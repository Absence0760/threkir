-- The platform owner's earnings read: application fees taken per calendar
-- month, and per host + club, net of the fees the refunds gave back. M7's
-- platform-fee half (instructor_business.md § M7, issue #1099, decisions
-- § 1817). The host-facing half is a separate read over the host's own orders.
--
-- Until now the only way to answer "what did the platform earn in September"
-- was the Stripe dashboard, or a hand-written query that had to rediscover
-- which statuses carry money and how a refund moves the fee. That knowledge is
-- spread over five migrations (20261229_001, 20270213_001, 20270620_001,
-- 20270624000001, 20270630000001); this states it once, in
-- `private.platform_fee_lines()`, and the two public reads aggregate it.
--
-- ── Who can read it ──────────────────────────────────────────────────────────
-- The `app_admins` allow-list (20270105_001) is the repo's one operator
-- privilege, and this reuses it rather than minting a second one. Both public
-- functions are SECURITY DEFINER and HARD-DENY (42501) a caller for whom
-- `private.is_admin(auth.uid())` is false, before reading a row — the shape
-- `fetch_pending_reports` set. The underlying ledgers stay exactly as closed as
-- they are: `payment_refunds` has no client grant, a host reads only their own
-- events' orders, and a donation's owner columns are revoked from clients.
-- The line function lives in `private` with EXECUTE withheld from every client
-- role, so it is not a PostgREST RPC and only the two gated readers (running as
-- the owner) can call it.
--
-- ── What counts as a fee, and when it was earned ─────────────────────────────
-- A fee is earned on a charge that took money: status `paid`,
-- `partially_refunded`, `refunded` or `refund_failed`. `pending`, `failed` and
-- `canceled` never charged a card. The row's `platform_fee_cents` is the
-- application fee Stripe actually took, recorded at checkout from
-- `platform_fees` (20270716000001), so it is read as-is and never recomputed
-- from today's rate.
--
-- The month is the UTC calendar month of `paid_at` (falling back to
-- `created_at` for a row that predates a `paid_at` write). UTC because the
-- reader is the operator reconciling against Stripe, whose balance reports and
-- payout schedules default to UTC; no host's timezone is meaningful for a
-- platform-wide sum, and a per-viewer zone would move a charge between months
-- depending on who looked. A refund's give-back is attributed to the month of
-- the SALE it reverses, not the month the refund happened: the figure is "what
-- did September's sales end up earning", which is stable once refunds settle,
-- rather than a cash-basis ledger in which a month can go negative.
--
-- ── How a refund moves the fee ───────────────────────────────────────────────
-- Every refund this repo creates goes through `buildRefundParams`
-- (events-cancel), which sends `refund_application_fee: true` with
-- `reverse_transfer: true` — Stripe returns the application fee in proportion
-- to the amount refunded. So:
--
--   * `refunded`: the whole fee is given back.
--   * `refund_failed`: the money is owed back to the buyer (§ 789) and the
--     operator's worklist will re-issue it, so the fee is not counted as
--     earned. It is surfaced as its own count so it is not invisible.
--   * `partially_refunded`, donations: the donation ledger carries
--     `refunded_cents` (20270620_001), less any reversal `payment_refunds`
--     records as failed/canceled, clamped — the same net-refunded figure
--     `fundraiser_totals` uses. The fee given back is that share of the fee.
--   * `partially_refunded`, event orders: `event_orders` carries no refunded
--     amount, so the share comes from the `payment_refunds` rows for the order
--     that did not fail. That set can be incomplete — a refund that settled
--     without a lifecycle event leaves no row (20270630000001's header) — and
--     an incomplete set UNDERSTATES the give-back, so the net fee is an upper
--     bound for these orders. `partially_refunded_count` says how many orders
--     that caveat touches, so the operator knows when to check Stripe.
--
-- The share is `round(fee * refunded / amount)`, clamped to `[0, fee]`.
-- Stripe's own application-fee refund object is the authority on the cent;
-- this is a reconciliation view, not an invoice.
--
-- A refund issued from the Stripe dashboard without "refund application fee"
-- leaves the fee with the platform and pays the buyer out of the platform
-- balance (§ 769). It is still recorded as a give-back here, because in that
-- case the platform's NET position on the charge is the same or worse; this
-- read never reports a refunded charge as fee income.
--
-- Amounts are summed per currency and never across currencies.
--
-- ── Lock impact (docs/backend/migration_locks.md) ────────────────────────────
-- Only CREATE FUNCTION, REVOKE and GRANT: catalogue rows in pg_proc, no lock on
-- any table, no scan, no rewrite. No index is added: the reads are operator
-- reads over the money ledgers, which are bounded by sales volume, and both
-- functions are a single pass over them.

create or replace function private.platform_fee_lines()
returns table (
  source               text,
  charge_id            uuid,
  month                date,
  currency             text,
  host_user_id         uuid,
  club_id              uuid,
  status               text,
  gross_fee_cents      bigint,
  reversed_fee_cents   bigint
)
language sql
stable
security definer
set search_path = public
as $$
  with event_lines as (
    select
      'event'::text as source,
      o.id as charge_id,
      (date_trunc('month', coalesce(o.paid_at, o.created_at) at time zone 'UTC'))::date as month,
      o.currency,
      o.host_user_id,
      e.club_id,
      o.status,
      o.platform_fee_cents::bigint as fee,
      o.amount_cents::bigint as amount,
      coalesce(r.refunded_cents, 0)::bigint as refunded
    from event_orders o
    join events e on e.id = o.event_id
    left join lateral (
      select sum(pr.amount_cents) as refunded_cents
      from payment_refunds pr
      where pr.event_order_id = o.id
        and pr.status not in ('failed', 'canceled')
    ) r on true
    where o.status in ('paid', 'partially_refunded', 'refunded', 'refund_failed')
  ),
  donation_lines as (
    select
      'donation'::text as source,
      d.id as charge_id,
      (date_trunc('month', coalesce(d.paid_at, d.created_at) at time zone 'UTC'))::date as month,
      d.currency,
      d.owner_user_id as host_user_id,
      ev.club_id,
      d.status,
      d.platform_fee_cents::bigint as fee,
      d.amount_cents::bigint as amount,
      (d.refunded_cents - least(coalesce(r.reversed_cents, 0), d.refunded_cents))::bigint as refunded
    from donations d
    join fundraisers f on f.id = d.fundraiser_id
    left join events ev on ev.id = f.event_id
    left join lateral (
      select sum(pr.amount_cents) as reversed_cents
      from payment_refunds pr
      where pr.donation_id = d.id
        and pr.status in ('failed', 'canceled')
    ) r on true
    where d.status in ('paid', 'partially_refunded', 'refunded', 'refund_failed')
  ),
  lines as (
    select * from event_lines
    union all
    select * from donation_lines
  )
  select
    l.source,
    l.charge_id,
    l.month,
    l.currency,
    l.host_user_id,
    l.club_id,
    l.status,
    l.fee as gross_fee_cents,
    case
      when l.status in ('refunded', 'refund_failed') then l.fee
      when l.status = 'partially_refunded' and l.amount > 0 then
        greatest(0, least(l.fee, round(l.fee::numeric * l.refunded / l.amount)::bigint))
      else 0
    end as reversed_fee_cents
  from lines l;
$$;

comment on function private.platform_fee_lines() is
  'One line per charge that took money on either Stripe Connect ledger '
  '(event_orders, donations): the application fee taken and the part of it '
  'refunds gave back, keyed to the UTC calendar month of the sale. The single '
  'statement of the fee-accounting rules; read only by the two app_admins-gated '
  'readers. decisions § 1817.';

revoke execute on function private.platform_fee_lines() from public, anon, authenticated;
grant execute on function private.platform_fee_lines() to service_role;

-- ─── admin_platform_fee_months: the monthly view ─────────────────────────────
create or replace function admin_platform_fee_months()
returns table (
  month                     date,
  currency                  text,
  source                    text,
  charge_count              bigint,
  gross_fee_cents           bigint,
  reversed_fee_cents        bigint,
  net_fee_cents             bigint,
  refunded_count            bigint,
  partially_refunded_count  bigint,
  refund_failed_count       bigint
)
language plpgsql
stable
security definer
set search_path = public, private
as $$
begin
  if not private.is_admin(auth.uid()) then
    raise exception 'admin_platform_fee_months: not authorized'
      using errcode = '42501';
  end if;

  return query
    select
      l.month,
      l.currency,
      l.source,
      count(*)::bigint,
      sum(l.gross_fee_cents)::bigint,
      sum(l.reversed_fee_cents)::bigint,
      sum(l.gross_fee_cents - l.reversed_fee_cents)::bigint,
      count(*) filter (where l.status = 'refunded')::bigint,
      count(*) filter (where l.status = 'partially_refunded')::bigint,
      count(*) filter (where l.status = 'refund_failed')::bigint
    from private.platform_fee_lines() l
    group by l.month, l.currency, l.source
    order by l.month desc, l.currency, l.source;
end;
$$;

comment on function admin_platform_fee_months() is
  'Operator-only (app_admins): platform application fees per UTC calendar month '
  'of sale, per currency and source (event | donation) — gross, given back by '
  'refunds, and net — plus the refund-status counts behind the give-back. '
  'Raises 42501 for anyone else. decisions § 1817.';

revoke execute on function admin_platform_fee_months() from public, anon;
grant execute on function admin_platform_fee_months() to authenticated, service_role;

-- ─── admin_platform_fees_by_host: one month, split by host + club ────────────
-- `p_month` is any day in the wanted month (normalised to its first day);
-- null means all time. The host's display name and the club's name + slug are
-- projected so the operator can tell lines apart without a second read.
create or replace function admin_platform_fees_by_host(p_month date default null)
returns table (
  host_user_id         uuid,
  host_display_name    text,
  club_id              uuid,
  club_name            text,
  club_slug            text,
  currency             text,
  charge_count         bigint,
  gross_fee_cents      bigint,
  reversed_fee_cents   bigint,
  net_fee_cents        bigint
)
language plpgsql
stable
security definer
set search_path = public, private
as $$
declare
  v_month date := date_trunc('month', p_month)::date;
begin
  if not private.is_admin(auth.uid()) then
    raise exception 'admin_platform_fees_by_host: not authorized'
      using errcode = '42501';
  end if;

  return query
    select
      l.host_user_id,
      up.display_name,
      l.club_id,
      c.name,
      c.slug,
      l.currency,
      count(*)::bigint,
      sum(l.gross_fee_cents)::bigint,
      sum(l.reversed_fee_cents)::bigint,
      sum(l.gross_fee_cents - l.reversed_fee_cents)::bigint as net
    from private.platform_fee_lines() l
    left join user_profiles up on up.id = l.host_user_id
    left join clubs c on c.id = l.club_id
    where v_month is null or l.month = v_month
    group by l.host_user_id, up.display_name, l.club_id, c.name, c.slug, l.currency
    order by net desc, l.currency, l.host_user_id, l.club_id;
end;
$$;

comment on function admin_platform_fees_by_host(date) is
  'Operator-only (app_admins): platform application fees for one UTC calendar '
  'month (any day in it; null = all time), one row per host + club + currency, '
  'net of refunds on the same rules as admin_platform_fee_months. Raises 42501 '
  'for anyone else. decisions § 1817.';

revoke execute on function admin_platform_fees_by_host(date) from public, anon;
grant execute on function admin_platform_fees_by_host(date) to authenticated, service_role;

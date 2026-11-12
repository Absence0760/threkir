-- M7 (docs/features/instructor_business.md): the host's earnings summary —
-- registrations and money per class instance, so an instructor can answer
-- "what did my classes earn this month?" without opening the Stripe dashboard.
--
-- ── Why a SECURITY DEFINER function and not a view over event_orders ─────────
-- Two reasons, either sufficient.
--   1. The scope is the PAYEE, not the organiser. event_orders' client SELECT
--      policy is "an organiser of the event's club" — the people who RUN the
--      class — while the money went to `event_orders.host_user_id`, stamped at
--      checkout as the connected account the destination charge paid. Those
--      differ: a host who stops being an organiser keeps every order they were
--      paid for, and a co-organiser who never hosted sees orders whose money
--      is not theirs. A summary of what someone was PAID is keyed on who was
--      paid, so the read is `host_user_id = auth.uid()`, which no existing
--      policy states.
--   2. The partial-refund amount lives in `payment_refunds`, which has no
--      client read path at all (20270630000001 revokes it from every client
--      role). An invoker view could not reach it.
-- The function returns aggregates only — no buyer id, no name, no Stripe id —
-- so widening the table's policy to the payee would expose strictly more than
-- this does.
--
-- ── What each figure means (the ledger's own vocabulary) ─────────────────────
--   paid                 money in; seat held.
--   partially_refunded   money in, part of it returned; still seat-bearing
--                        (20270522_001). The returned part is the order's
--                        `payment_refunds` children that did not fail or get
--                        cancelled — and only those: `charge.refunded` carries
--                        no refund id, so a partial refund the endpoint heard
--                        about only through it has no child row (§ 823). Such
--                        an order is COUNTED in `partial_refunds_unrecorded`
--                        rather than silently netted at zero, so the surface
--                        can say its refund total is a floor. The fee is the
--                        fee charged; a partial refund may have returned part
--                        of it, which no ledger column records, so net is
--                        understated rather than overstated.
--   refunded             the whole charge went back. events-cancel refunds with
--                        `reverse_transfer` + `refund_application_fee`
--                        (buildRefundParams, § 769), which nets the host AND the
--                        platform to zero, so the order contributes its gross
--                        and an equal refund and no fee.
--   refund_failed        a refund the bank sent back: the seat is gone and the
--                        money did NOT come back (§ 789). It is neither earned
--                        nor refunded, so it is excluded from every money sum
--                        and reported on its own as `unsettled_cents`, beside a
--                        count, for the host to see it is being resolved.
--   pending / failed / canceled — no money moved; excluded.
-- net_cents = gross_cents - refunded_cents - platform_fee_cents.
--
-- ── Which month an order belongs to, and in which timezone ───────────────────
-- An order belongs to the month of the CLASS it bought (instance_start), not of
-- the purchase: "my October classes" is the question an instructor asks, and a
-- November class pre-sold in October is November's revenue to them. The month
-- boundary is the event's own wall clock — `events.timezone`, the IANA zone the
-- event was created in (20270111_001), the same anchor search_public_events
-- uses for local hour — because a 19:00 class in Los Angeles on 31 October is
-- 02:00 UTC on 1 November, and a UTC boundary would file it in the wrong month
-- for the only person reading it. A legacy row with no zone, or a zone value
-- Postgres does not know (the column is length-capped, not validated, and
-- `at time zone 'Not/AZone'` raises), falls back to UTC rather than failing
-- the whole summary; the resolved zone is returned so the surface can say so.
--
-- Rows are per (class instance, currency). Amounts in different currencies are
-- never summed together here or on the client.
--
-- ── Online-safety (docs/backend/migration_locks.md) ──────────────────────────
-- CREATE FUNCTION only: no table lock, no scan, no rewrite. The read it defines
-- is served by `event_orders_host_user_id` (20270417_001) and
-- `payment_refunds_event_order_idx` (20270630000001).

create function public.host_earnings_summary()
returns table (
  event_id                   uuid,
  event_title                text,
  club_id                    uuid,
  instance_start             timestamptz,
  local_month                date,
  timezone                   text,
  currency                   text,
  registrations              integer,
  refunded_orders            integer,
  partially_refunded_orders  integer,
  partial_refunds_unrecorded integer,
  refund_failed_orders       integer,
  gross_cents                bigint,
  refunded_cents             bigint,
  platform_fee_cents         bigint,
  net_cents                  bigint,
  unsettled_cents            bigint
)
language sql
stable
security definer
set search_path = public
as $$
  with mine as (
    select o.id, o.event_id, o.instance_start, o.currency, o.status,
           o.amount_cents, o.platform_fee_cents
      from event_orders o
     where o.host_user_id = (select auth.uid())
       and o.status in ('paid', 'partially_refunded', 'refunded', 'refund_failed')
  ),
  partial as (
    select m.id,
           coalesce(sum(r.amount_cents) filter (where r.status not in ('failed', 'canceled')), 0) as returned,
           count(r.id) filter (where r.status not in ('failed', 'canceled')) as recorded
      from mine m
      left join payment_refunds r on r.event_order_id = m.id
     where m.status = 'partially_refunded'
     group by m.id
  ),
  zones as (
    select e.id as event_id, e.title, e.club_id,
           coalesce(
             (select tz.name from pg_timezone_names tz where tz.name = e.timezone limit 1),
             'UTC'
           ) as tz
      from events e
     where e.id in (select distinct event_id from mine)
  ),
  per_order as (
    select m.event_id, m.instance_start, m.currency, m.status,
           case when m.status = 'refund_failed' then 0 else m.amount_cents end as gross,
           case m.status
             when 'refunded' then m.amount_cents
             when 'partially_refunded' then least(p.returned, m.amount_cents)
             else 0
           end as refunded,
           case when m.status in ('paid', 'partially_refunded') then m.platform_fee_cents else 0 end as fee,
           case when m.status = 'refund_failed' then m.amount_cents else 0 end as unsettled,
           (m.status = 'partially_refunded' and coalesce(p.recorded, 0) = 0) as unrecorded
      from mine m
      left join partial p on p.id = m.id
  )
  select z.event_id,
         z.title,
         z.club_id,
         po.instance_start,
         date_trunc('month', po.instance_start at time zone z.tz)::date,
         z.tz,
         po.currency,
         count(*) filter (where po.status in ('paid', 'partially_refunded'))::int,
         count(*) filter (where po.status = 'refunded')::int,
         count(*) filter (where po.status = 'partially_refunded')::int,
         count(*) filter (where po.unrecorded)::int,
         count(*) filter (where po.status = 'refund_failed')::int,
         sum(po.gross)::bigint,
         sum(po.refunded)::bigint,
         sum(po.fee)::bigint,
         (sum(po.gross) - sum(po.refunded) - sum(po.fee))::bigint,
         sum(po.unsettled)::bigint
    from per_order po
    join zones z on z.event_id = po.event_id
   group by z.event_id, z.title, z.club_id, po.instance_start, z.tz, po.currency
   order by po.instance_start desc, z.title, po.currency;
$$;

comment on function public.host_earnings_summary() is
  'M7 host earnings: one row per (class instance, currency) of the CALLER''s '
  'paid-event orders — keyed on event_orders.host_user_id, the payee, not on '
  'organiser membership. local_month is the instance''s month in the event''s '
  'own IANA timezone (UTC fallback). net = gross - refunded - platform fee; '
  'refund_failed money is reported as unsettled, outside every other sum. '
  'Aggregates only, no buyer identity. instructor_business.md M7.';

revoke all on function public.host_earnings_summary() from public, anon;
grant execute on function public.host_earnings_summary() to authenticated, service_role;

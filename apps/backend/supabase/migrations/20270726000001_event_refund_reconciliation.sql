-- The M8 reconciliation sweep (club_events.md P2, decisions § 1839): a paid
-- order on an occurrence the host called off is owed a full refund, and every
-- path that issues it (events-cancel's occurrence scope, the webhook's
-- cancelled-occurrence arm) can fail and leave it owed with nothing retrying.
-- This migration gives the `events-refund-sweep` Edge Function its worklist and
-- pg_cron a way to call it.
--
-- Why an Edge Function and not a `jobs` row for the Go worker, which is where
-- every other periodic job in this tree runs: a refund is created through ONE
-- transport, `stripeRestRefundCreator` in events-cancel/refund.ts, under one
-- per-order idempotency key, with one stamp discipline (`refundOrder`). The
-- worker holds no Stripe key and no refund code; giving it some is a second
-- implementation of exactly what § 1818 and § 1839 collapsed to one.
--
-- Fail-closed twice. The schedule calls the function only when BOTH Vault
-- secrets exist (`event_refund_sweep_url`, `cron_secret`), so a project that has
-- not been set up sends nothing; and the function answers 503 without
-- STRIPE_SECRET_KEY before it reads a row.

create extension if not exists pg_net with schema extensions;

-- The worklist. "Owed" is exactly what the event page lists with a Refund now
-- (decisions § 1818): a `paid` / `partially_refunded` order on an occurrence
-- with an `event_exceptions` row and no `refund_initiated_at` stamp. Plus one
-- case the page cannot see: a stamp more than a day old on an order that is
-- still charged. A stamp means a refund was about to be created, and the
-- `charge.refunded` it produces moves the order out of `paid` within seconds;
-- a day later it is either a function that died between the stamp and the
-- Stripe call, or a refund whose webhook never arrived. Replaying `refundOrder`
-- resolves both: it creates the missing refund, or Stripe answers
-- `charge_already_refunded`, which reads as done.
--
-- `refund_failed` is deliberately not owed here: the bank returned the money
-- and the payer has been told (§ 825); Stripe's guidance is another route, not
-- a second attempt on the same card. Random order, so a refund Stripe refuses
-- every time (a host already paid out, followups.md) cannot hold the head of
-- the list and starve the rest of a capped run.
create or replace function public.event_orders_owed_refund(p_limit integer)
returns table (id uuid, status text, stripe_payment_intent_id text)
language sql
volatile
set search_path = public
as $$
  select o.id, o.status, o.stripe_payment_intent_id
  from public.event_orders o
  where o.status in ('paid', 'partially_refunded')
    and (o.refund_initiated_at is null
         or o.refund_initiated_at < now() - interval '1 day')
    and exists (
      select 1 from public.event_exceptions x
      where x.event_id = o.event_id
        and x.instance_start = o.instance_start
    )
  order by random()
  limit greatest(least(coalesce(p_limit, 0), 100), 0)
$$;

revoke execute on function public.event_orders_owed_refund(integer) from public, anon, authenticated;
grant execute on function public.event_orders_owed_refund(integer) to service_role;

comment on function public.event_orders_owed_refund(integer) is
  'The refund reconciliation worklist (decisions 1839): charged event orders on '
  'a host-cancelled occurrence with no refund stamp, or a stamp over a day old. '
  'Random order, capped at 100. Service-role only; events-refund-sweep reads it.';

-- What pg_cron runs. Posts to the sweep only when it is configured and only
-- when something is owed, so an idle hour costs no HTTP call. Returns the
-- pg_net request id, or null when it sent nothing.
create or replace function public.invoke_event_refund_sweep()
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_url text;
  v_secret text;
begin
  select decrypted_secret into v_url
  from vault.decrypted_secrets where name = 'event_refund_sweep_url';
  select decrypted_secret into v_secret
  from vault.decrypted_secrets where name = 'cron_secret';
  if v_url is null or v_secret is null then
    return null;
  end if;

  perform 1 from public.event_orders_owed_refund(1);
  if not found then
    return null;
  end if;

  return net.http_post(
    url := v_url,
    body := '{}'::jsonb,
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || v_secret,
      'Content-Type', 'application/json'
    ),
    timeout_milliseconds := 150000
  );
end;
$$;

revoke execute on function public.invoke_event_refund_sweep() from public, anon, authenticated;
grant execute on function public.invoke_event_refund_sweep() to service_role;

comment on function public.invoke_event_refund_sweep() is
  'Hourly pg_cron entry for the event refund reconciliation sweep (decisions '
  '1839). POSTs to events-refund-sweep with the cron bearer, only when the Vault '
  'secrets event_refund_sweep_url and cron_secret both exist and an order is '
  'owed. Service-role grant lets an operator run it by hand.';

select cron.schedule(
  'event-refund-sweep',
  '23 * * * *',
  $$select public.invoke_event_refund_sweep()$$
);

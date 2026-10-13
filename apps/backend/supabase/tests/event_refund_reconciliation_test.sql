-- Pins migration 20270726000001 (the M8 refund reconciliation sweep,
-- decisions § 1839):
--   * event_orders_owed_refund lists exactly the charged orders on a
--     host-cancelled occurrence with no refund stamp, or a stamp over a day old
--     -- never a recent stamp, a refund_failed / refunded order, or an order on
--     an occurrence still running;
--   * its limit is clamped to 0..100, and a null or negative one lists nothing;
--   * invoke_event_refund_sweep sends nothing until both Vault secrets exist,
--     queues one pg_net request when they do and an order is owed, and sends
--     nothing when nothing is;
--   * pg_cron schedules it hourly.

begin;
select plan(11);

delete from vault.secrets where name in ('event_refund_sweep_url', 'cron_secret');

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('aaaa7726-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'rs-host@evt.local', '', now(), now()),
  ('aaaa7726-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'rs-buyer@evt.local', '', now(), now());

insert into clubs (id, owner_id, name, slug, is_public)
values ('bbbb7726-0000-0000-0000-000000000001',
        'aaaa7726-0000-0000-0000-000000000001', 'Refund Sweep Studio', 'rs-studio', true);

insert into events (id, club_id, title, starts_at, author_id, host_user_id, category, recurrence_freq)
values ('cccc7726-0000-0000-0000-000000000001',
        'bbbb7726-0000-0000-0000-000000000001', 'Mat Pilates',
        '2026-07-01 18:00+00', 'aaaa7726-0000-0000-0000-000000000001',
        'aaaa7726-0000-0000-0000-000000000001', 'class', 'weekly');

-- 07-01 is cancelled and holds one order per state; 07-08 is running.
insert into event_orders (id, event_id, instance_start, buyer_user_id, host_user_id,
                          amount_cents, platform_fee_cents, status, paid_at,
                          refunded_at, refund_initiated_at, stripe_payment_intent_id)
values
  -- owed: paid, never stamped
  ('dddd7726-0000-0000-0000-000000000001', 'cccc7726-0000-0000-0000-000000000001', '2026-07-01 18:00+00',
   'aaaa7726-0000-0000-0000-000000000002', 'aaaa7726-0000-0000-0000-000000000001', 2200, 55,
   'paid', now(), null, null, 'pi_rs_1'),
  -- owed: partially refunded, never stamped (a goodwill refund, then the cancel)
  ('dddd7726-0000-0000-0000-000000000002', 'cccc7726-0000-0000-0000-000000000001', '2026-07-01 18:00+00',
   'aaaa7726-0000-0000-0000-000000000002', 'aaaa7726-0000-0000-0000-000000000001', 2200, 55,
   'partially_refunded', now(), null, null, 'pi_rs_2'),
  -- owed: stamped two days ago and still charged
  ('dddd7726-0000-0000-0000-000000000003', 'cccc7726-0000-0000-0000-000000000001', '2026-07-01 18:00+00',
   'aaaa7726-0000-0000-0000-000000000002', 'aaaa7726-0000-0000-0000-000000000001', 2200, 55,
   'paid', now(), null, now() - interval '2 days', 'pi_rs_3'),
  -- not owed: stamped an hour ago, its charge.refunded may be in flight
  ('dddd7726-0000-0000-0000-000000000004', 'cccc7726-0000-0000-0000-000000000001', '2026-07-01 18:00+00',
   'aaaa7726-0000-0000-0000-000000000002', 'aaaa7726-0000-0000-0000-000000000001', 2200, 55,
   'paid', now(), null, now() - interval '1 hour', 'pi_rs_4'),
  -- not owed: refunded
  ('dddd7726-0000-0000-0000-000000000005', 'cccc7726-0000-0000-0000-000000000001', '2026-07-01 18:00+00',
   'aaaa7726-0000-0000-0000-000000000002', 'aaaa7726-0000-0000-0000-000000000001', 2200, 55,
   'refunded', now(), now(), now() - interval '3 days', 'pi_rs_5'),
  -- not owed: the bank returned the refund and the payer was told (§ 825)
  ('dddd7726-0000-0000-0000-000000000006', 'cccc7726-0000-0000-0000-000000000001', '2026-07-01 18:00+00',
   'aaaa7726-0000-0000-0000-000000000002', 'aaaa7726-0000-0000-0000-000000000001', 2200, 55,
   'refund_failed', now(), now(), null, 'pi_rs_6'),
  -- not owed: paid on an occurrence that is still on
  ('dddd7726-0000-0000-0000-000000000007', 'cccc7726-0000-0000-0000-000000000001', '2026-07-08 18:00+00',
   'aaaa7726-0000-0000-0000-000000000002', 'aaaa7726-0000-0000-0000-000000000001', 2200, 55,
   'paid', now(), null, null, 'pi_rs_7');

insert into event_exceptions (event_id, instance_start, cancelled_by)
values ('cccc7726-0000-0000-0000-000000000001', '2026-07-01 18:00+00',
        'aaaa7726-0000-0000-0000-000000000001');

-- ── The worklist ──
select is(
  (select array_agg(id::text order by id)
   from public.event_orders_owed_refund(100)
   where id::text like 'dddd7726-%'),
  array['dddd7726-0000-0000-0000-000000000001',
        'dddd7726-0000-0000-0000-000000000002',
        'dddd7726-0000-0000-0000-000000000003'],
  'owed: charged, on a cancelled occurrence, and unstamped or stamped over a day ago');

select is(
  (select array_agg(status || ':' || stripe_payment_intent_id order by stripe_payment_intent_id)
   from public.event_orders_owed_refund(100)
   where id::text like 'dddd7726-%'),
  array['paid:pi_rs_1', 'partially_refunded:pi_rs_2', 'paid:pi_rs_3'],
  'each row carries the status refundOrder guards its stamp on, and the payment intent');

select is((select count(*)::int from public.event_orders_owed_refund(1)), 1,
  'a run takes no more than it asked for');
select is((select count(*)::int from public.event_orders_owed_refund(0)), 0,
  'a zero limit lists nothing');
select is((select count(*)::int from public.event_orders_owed_refund(-5)), 0,
  'a negative limit lists nothing rather than everything');
select is((select count(*)::int from public.event_orders_owed_refund(null)), 0,
  'a null limit lists nothing rather than everything');

-- ── The schedule's entry point ──
select is(public.invoke_event_refund_sweep(), null,
  'nothing is sent while the Vault secrets are absent');

do $$ begin
  perform vault.create_secret('https://example.invalid/functions/v1/events-refund-sweep',
                              'event_refund_sweep_url');
end $$;
select is(public.invoke_event_refund_sweep(), null,
  'one secret is not enough: the bearer is missing too');

do $$ begin perform vault.create_secret(repeat('c', 40), 'cron_secret'); end $$;
select isnt(public.invoke_event_refund_sweep(), null,
  'configured and owed: one pg_net request is queued');

-- Nothing owed anywhere this test can see once the occurrence is back on.
delete from event_exceptions where event_id = 'cccc7726-0000-0000-0000-000000000001';
select is(
  case when exists (select 1 from public.event_orders_owed_refund(1))
       then 'owed-elsewhere' else coalesce(public.invoke_event_refund_sweep()::text, 'null') end,
  'null',
  'configured but nothing owed: nothing is sent');

select is(
  (select schedule from cron.job where jobname = 'event-refund-sweep'),
  '23 * * * *',
  'pg_cron runs the sweep hourly');

select * from finish();
rollback;

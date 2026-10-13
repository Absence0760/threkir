-- The edges of event_orders_owed_refund (migration 20270726000001, decisions
-- § 1839) that event_refund_reconciliation_test.sql leaves open:
--   * the day-old-stamp boundary is strict: a stamp exactly 24 hours old is
--     still in flight, one second older is owed;
--   * a pending, failed or canceled order on a cancelled occurrence is never
--     owed (no money was taken). There is no `disputed` order status: the
--     event_orders CHECK does not admit one, which is pinned here too, so a
--     dispute cannot reach the worklist as a status;
--   * `authenticated` cannot execute it, by grant and in practice;
--   * a limit above 100 is clamped to 100.
--
-- now() is the transaction's, so the stamps below and the function's own
-- now() name the same instant and the boundary is exact.

begin;
select plan(9);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('aaaa7730-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'ow-host@evt.local', '', now(), now()),
  ('aaaa7730-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'ow-buyer@evt.local', '', now(), now());

insert into clubs (id, owner_id, name, slug, is_public)
values ('bbbb7730-0000-0000-0000-000000000001',
        'aaaa7730-0000-0000-0000-000000000001', 'Owed Edges Studio', 'ow-studio', true);

insert into events (id, club_id, title, starts_at, author_id, host_user_id, category, recurrence_freq)
values ('cccc7730-0000-0000-0000-000000000001',
        'bbbb7730-0000-0000-0000-000000000001', 'Hot Yoga',
        '2026-07-01 18:00+00', 'aaaa7730-0000-0000-0000-000000000001',
        'aaaa7730-0000-0000-0000-000000000001', 'class', 'weekly');

insert into event_orders (id, event_id, instance_start, buyer_user_id, host_user_id,
                          amount_cents, platform_fee_cents, status, paid_at,
                          refund_initiated_at, reserved_until, stripe_payment_intent_id)
values
  -- stamped exactly a day ago: not yet owed
  ('dddd7730-0000-0000-0000-000000000001', 'cccc7730-0000-0000-0000-000000000001', '2026-07-01 18:00+00',
   'aaaa7730-0000-0000-0000-000000000002', 'aaaa7730-0000-0000-0000-000000000001', 2200, 55,
   'paid', now(), now() - interval '1 day', null, 'pi_ow_1'),
  -- stamped a day and a second ago: owed
  ('dddd7730-0000-0000-0000-000000000002', 'cccc7730-0000-0000-0000-000000000001', '2026-07-01 18:00+00',
   'aaaa7730-0000-0000-0000-000000000002', 'aaaa7730-0000-0000-0000-000000000001', 2200, 55,
   'paid', now(), now() - interval '1 day 1 second', null, 'pi_ow_2'),
  -- no money taken
  ('dddd7730-0000-0000-0000-000000000003', 'cccc7730-0000-0000-0000-000000000001', '2026-07-01 18:00+00',
   'aaaa7730-0000-0000-0000-000000000002', 'aaaa7730-0000-0000-0000-000000000001', 2200, 55,
   'pending', null, null, now() + interval '10 minutes', null),
  ('dddd7730-0000-0000-0000-000000000004', 'cccc7730-0000-0000-0000-000000000001', '2026-07-01 18:00+00',
   'aaaa7730-0000-0000-0000-000000000002', 'aaaa7730-0000-0000-0000-000000000001', 2200, 55,
   'failed', null, null, null, 'pi_ow_4'),
  ('dddd7730-0000-0000-0000-000000000005', 'cccc7730-0000-0000-0000-000000000001', '2026-07-01 18:00+00',
   'aaaa7730-0000-0000-0000-000000000002', 'aaaa7730-0000-0000-0000-000000000001', 2200, 55,
   'canceled', null, null, null, null);

insert into event_exceptions (event_id, instance_start, cancelled_by)
values ('cccc7730-0000-0000-0000-000000000001', '2026-07-01 18:00+00',
        'aaaa7730-0000-0000-0000-000000000001');

-- ── the stamp boundary + the statuses (before the bulk rows below, so the
-- 100 cap cannot be what drops a row) ──
select is(
  (select count(*)::int from public.event_orders_owed_refund(100)
   where id = 'dddd7730-0000-0000-0000-000000000001'),
  0, 'a stamp exactly 24 hours old is still a refund in flight');

select is(
  (select count(*)::int from public.event_orders_owed_refund(100)
   where id = 'dddd7730-0000-0000-0000-000000000002'),
  1, 'a stamp one second past 24 hours is owed again');

select is(
  (select count(*)::int from public.event_orders_owed_refund(100)
   where id in ('dddd7730-0000-0000-0000-000000000003',
                'dddd7730-0000-0000-0000-000000000004',
                'dddd7730-0000-0000-0000-000000000005')),
  0, 'a pending, failed or canceled order took no money and is never owed');

select throws_ok(
  $$ update event_orders set status = 'disputed'
     where id = 'dddd7730-0000-0000-0000-000000000002' $$,
  '23514', null,
  'there is no disputed order status for the worklist to admit');

-- ── the caller boundary ──
select is(
  has_function_privilege('authenticated', 'public.event_orders_owed_refund(integer)', 'execute'),
  false, 'authenticated holds no EXECUTE on the worklist');

select is(
  has_function_privilege('service_role', 'public.event_orders_owed_refund(integer)', 'execute'),
  true, 'the service role the sweep runs as does');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"aaaa7730-0000-0000-0000-000000000002","role":"authenticated"}';
select throws_ok(
  $$ select * from public.event_orders_owed_refund(100) $$,
  '42501', null,
  'a signed-in buyer calling the worklist is refused');
reset role;
set local "request.jwt.claims" = '';

-- ── the cap ──
insert into event_orders (id, event_id, instance_start, buyer_user_id, host_user_id,
                          amount_cents, platform_fee_cents, status, paid_at, stripe_payment_intent_id)
select ('dddd7730-0000-0000-0001-' || lpad(to_hex(g), 12, '0'))::uuid,
       'cccc7730-0000-0000-0000-000000000001', '2026-07-01 18:00+00',
       'aaaa7730-0000-0000-0000-000000000002', 'aaaa7730-0000-0000-0000-000000000001',
       2200, 55, 'paid', now(), 'pi_ow_bulk_' || g
from generate_series(1, 101) g;

select ok(
  (select count(*) from event_orders o
   where o.status = 'paid' and o.refund_initiated_at is null
     and o.event_id = 'cccc7730-0000-0000-0000-000000000001') >= 101,
  'more than a hundred orders are owed');

select is(
  (select count(*)::int from public.event_orders_owed_refund(1000)),
  100, 'a limit above 100 is clamped to 100');

select * from finish();
rollback;

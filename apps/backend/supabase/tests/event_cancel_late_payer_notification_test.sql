-- Pins migration 20270729000001 (the cancel notification reaches a buyer whose
-- payment lands after the host called the occurrence off, decisions
-- § R6MONEY-1), and the recipient edges of notify_event_cancel it re-emits:
--   * the canceller and a declined attendee are not notified;
--   * a buyer holding two paid orders on the occurrence is notified once;
--   * a buyer holding a paid order and no attendee row (paid in the window
--     between the webhook's two cancellation reads) is notified, refunded;
--   * a buyer whose pending order turns paid on a cancelled occurrence gets
--     one refunded event_cancel row, however many late orders land;
--   * a waitlister told plainly at cancel time gets a second, refunded row
--     when their payment lands, and the plain one is left as it was;
--   * a payment on an occurrence that is still on announces nothing;
--   * the new trigger function is definer, path-pinned and not client-callable.

begin;
select plan(14);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('aaaa7729-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'lp-host@evt.local', '', now(), now()),
  ('aaaa7729-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'lp-declined@evt.local', '', now(), now()),
  ('aaaa7729-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'lp-twice@evt.local', '', now(), now()),
  ('aaaa7729-0000-0000-0000-000000000004', 'authenticated', 'authenticated', 'lp-unseated@evt.local', '', now(), now()),
  ('aaaa7729-0000-0000-0000-000000000005', 'authenticated', 'authenticated', 'lp-late@evt.local', '', now(), now()),
  ('aaaa7729-0000-0000-0000-000000000006', 'authenticated', 'authenticated', 'lp-waiter@evt.local', '', now(), now()),
  ('aaaa7729-0000-0000-0000-000000000007', 'authenticated', 'authenticated', 'lp-other@evt.local', '', now(), now());

insert into clubs (id, owner_id, name, slug, is_public)
values ('bbbb7729-0000-0000-0000-000000000001',
        'aaaa7729-0000-0000-0000-000000000001', 'Late Payer Studio', 'lp-studio', true);

insert into events (id, club_id, title, starts_at, author_id, host_user_id, category, recurrence_freq)
values ('cccc7729-0000-0000-0000-000000000001',
        'bbbb7729-0000-0000-0000-000000000001', 'Yin',
        '2026-07-01 18:00+00', 'aaaa7729-0000-0000-0000-000000000001',
        'aaaa7729-0000-0000-0000-000000000001', 'class', 'weekly');

insert into event_attendees (event_id, user_id, status, instance_start) values
  ('cccc7729-0000-0000-0000-000000000001', 'aaaa7729-0000-0000-0000-000000000001', 'going', '2026-07-01 18:00+00'),
  ('cccc7729-0000-0000-0000-000000000001', 'aaaa7729-0000-0000-0000-000000000002', 'declined', '2026-07-01 18:00+00'),
  ('cccc7729-0000-0000-0000-000000000001', 'aaaa7729-0000-0000-0000-000000000003', 'going', '2026-07-01 18:00+00'),
  ('cccc7729-0000-0000-0000-000000000001', 'aaaa7729-0000-0000-0000-000000000006', 'waitlisted', '2026-07-01 18:00+00');

insert into event_orders (id, event_id, instance_start, buyer_user_id, host_user_id,
                          amount_cents, platform_fee_cents, status, paid_at, reserved_until)
values
  -- two paid orders, one buyer
  ('dddd7729-0000-0000-0000-000000000001', 'cccc7729-0000-0000-0000-000000000001', '2026-07-01 18:00+00',
   'aaaa7729-0000-0000-0000-000000000003', 'aaaa7729-0000-0000-0000-000000000001', 2200, 55, 'paid', now(), null),
  ('dddd7729-0000-0000-0000-000000000002', 'cccc7729-0000-0000-0000-000000000001', '2026-07-01 18:00+00',
   'aaaa7729-0000-0000-0000-000000000003', 'aaaa7729-0000-0000-0000-000000000001', 2200, 55, 'paid', now(), null),
  -- paid, never seated
  ('dddd7729-0000-0000-0000-000000000003', 'cccc7729-0000-0000-0000-000000000001', '2026-07-01 18:00+00',
   'aaaa7729-0000-0000-0000-000000000004', 'aaaa7729-0000-0000-0000-000000000001', 2200, 55, 'paid', now(), null),
  -- still on Stripe's page when the cancel lands: two late orders, one buyer
  ('dddd7729-0000-0000-0000-000000000004', 'cccc7729-0000-0000-0000-000000000001', '2026-07-01 18:00+00',
   'aaaa7729-0000-0000-0000-000000000005', 'aaaa7729-0000-0000-0000-000000000001', 2200, 55, 'pending', null, now() + interval '10 minutes'),
  ('dddd7729-0000-0000-0000-000000000005', 'cccc7729-0000-0000-0000-000000000001', '2026-07-01 18:00+00',
   'aaaa7729-0000-0000-0000-000000000005', 'aaaa7729-0000-0000-0000-000000000001', 2200, 55, 'pending', null, now() + interval '10 minutes'),
  -- the waitlister, mid-checkout
  ('dddd7729-0000-0000-0000-000000000006', 'cccc7729-0000-0000-0000-000000000001', '2026-07-01 18:00+00',
   'aaaa7729-0000-0000-0000-000000000006', 'aaaa7729-0000-0000-0000-000000000001', 2200, 55, 'pending', null, now() + interval '10 minutes'),
  -- a buyer of the NEXT occurrence, which is still on
  ('dddd7729-0000-0000-0000-000000000007', 'cccc7729-0000-0000-0000-000000000001', '2026-07-08 18:00+00',
   'aaaa7729-0000-0000-0000-000000000007', 'aaaa7729-0000-0000-0000-000000000001', 2200, 55, 'pending', null, now() + interval '10 minutes');

-- Called off the way events-cancel does it.
set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';
insert into event_exceptions (event_id, instance_start, cancelled_by)
values ('cccc7729-0000-0000-0000-000000000001', '2026-07-01 18:00+00',
        'aaaa7729-0000-0000-0000-000000000001');
reset role;

-- ── the fan-out ──
select is(
  (select count(*)::int from notifications
   where kind = 'event_cancel' and user_id = 'aaaa7729-0000-0000-0000-000000000001'),
  0, 'the host who called it off is not notified, though they were going');

select is(
  (select count(*)::int from notifications
   where kind = 'event_cancel' and user_id = 'aaaa7729-0000-0000-0000-000000000002'),
  0, 'a declined attendee is not notified');

select is(
  (select array_agg(refunded) from notifications
   where kind = 'event_cancel' and user_id = 'aaaa7729-0000-0000-0000-000000000003'),
  array[true], 'two paid orders make one notification, and it says refunded');

select is(
  (select array_agg(refunded) from notifications
   where kind = 'event_cancel' and user_id = 'aaaa7729-0000-0000-0000-000000000004'),
  array[true], 'a paid buyer who was never seated is notified, refunded');

select is(
  (select array_agg(refunded) from notifications
   where kind = 'event_cancel' and user_id = 'aaaa7729-0000-0000-0000-000000000006'),
  array[false], 'a waitlister still paying is told plainly at cancel time');

select is(
  (select count(*)::int from notifications
   where kind = 'event_cancel' and user_id = 'aaaa7729-0000-0000-0000-000000000005'),
  0, 'a buyer with no seat and only a pending order is not on the fan-out');

-- ── the late payments: the webhook's pending -> paid CAS ──
update event_orders set status = 'paid', paid_at = now()
where id = 'dddd7729-0000-0000-0000-000000000004' and status = 'pending';

select is(
  (select array_agg(refunded) from notifications
   where kind = 'event_cancel' and user_id = 'aaaa7729-0000-0000-0000-000000000005'),
  array[true], 'a payment landing on a cancelled occurrence is told it is being refunded');

select is(
  (select actor_id from notifications
   where kind = 'event_cancel' and user_id = 'aaaa7729-0000-0000-0000-000000000005'),
  'aaaa7729-0000-0000-0000-000000000001'::uuid,
  'the late notification names the canceller as its actor, like the fan-out');

update event_orders set status = 'paid', paid_at = now()
where id = 'dddd7729-0000-0000-0000-000000000005' and status = 'pending';

select is(
  (select count(*)::int from notifications
   where kind = 'event_cancel' and user_id = 'aaaa7729-0000-0000-0000-000000000005'),
  1, 'a second late order for the same buyer adds no second notification');

update event_orders set status = 'paid', paid_at = now()
where id = 'dddd7729-0000-0000-0000-000000000006' and status = 'pending';

select is(
  (select array_agg(refunded order by refunded) from notifications
   where kind = 'event_cancel' and user_id = 'aaaa7729-0000-0000-0000-000000000006'
     and event_instance_start = '2026-07-01 18:00+00'),
  array[false, true], 'the waitlister keeps the plain row and gains a refunded one');

update event_orders set status = 'paid', paid_at = now()
where id = 'dddd7729-0000-0000-0000-000000000007' and status = 'pending';

select is(
  (select count(*)::int from notifications
   where kind = 'event_cancel' and user_id = 'aaaa7729-0000-0000-0000-000000000007'),
  0, 'a payment on an occurrence that is still on announces no cancel');

-- ── the boundary ──
select is(
  (select prosecdef from pg_proc where oid = 'public.notify_event_cancel_late_payer()'::regprocedure),
  true, 'notify_event_cancel_late_payer is SECURITY DEFINER');

select ok(
  (select 'search_path=public' = any(proconfig) from pg_proc
   where oid = 'public.notify_event_cancel_late_payer()'::regprocedure),
  'notify_event_cancel_late_payer pins search_path');

select is(
  has_function_privilege('authenticated', 'public.notify_event_cancel_late_payer()', 'execute'),
  false, 'a client role cannot execute notify_event_cancel_late_payer');

select * from finish();
rollback;

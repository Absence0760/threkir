-- Pins migration 20270725000002 (the cancel notification tells a paid
-- registrant they are being refunded):
--   * notify_event_cancel sets notifications.refunded for a recipient who held
--     a paid or partially refunded order on the cancelled occurrence;
--   * it leaves it false for a free attendee, for a buyer whose order on this
--     occurrence is already refunded, and for a buyer whose paid order is on a
--     DIFFERENT occurrence of the same series;
--   * the row now carries the occurrence (event_instance_start);
--   * the function is still SECURITY DEFINER with a pinned search_path and
--     still not executable by a client role.

begin;
select plan(11);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('aaaa7725-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'cn-owner@evt.local', '', now(), now()),
  ('aaaa7725-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'cn-paid@evt.local', '', now(), now()),
  ('aaaa7725-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'cn-partial@evt.local', '', now(), now()),
  ('aaaa7725-0000-0000-0000-000000000004', 'authenticated', 'authenticated', 'cn-free@evt.local', '', now(), now()),
  ('aaaa7725-0000-0000-0000-000000000005', 'authenticated', 'authenticated', 'cn-refunded@evt.local', '', now(), now()),
  ('aaaa7725-0000-0000-0000-000000000006', 'authenticated', 'authenticated', 'cn-other@evt.local', '', now(), now());

insert into clubs (id, owner_id, name, slug, is_public)
values ('bbbb7725-0000-0000-0000-000000000001',
        'aaaa7725-0000-0000-0000-000000000001', 'Cancel Note Studio', 'cn-studio', true);

insert into events (id, club_id, title, starts_at, author_id, host_user_id, category, recurrence_freq)
values ('cccc7725-0000-0000-0000-000000000001',
        'bbbb7725-0000-0000-0000-000000000001', 'Barre',
        '2026-07-01 18:00+00', 'aaaa7725-0000-0000-0000-000000000001',
        'aaaa7725-0000-0000-0000-000000000001', 'class', 'weekly');

insert into event_attendees (event_id, user_id, status, instance_start) values
  ('cccc7725-0000-0000-0000-000000000001', 'aaaa7725-0000-0000-0000-000000000002', 'going', '2026-07-01 18:00+00'),
  ('cccc7725-0000-0000-0000-000000000001', 'aaaa7725-0000-0000-0000-000000000003', 'going', '2026-07-01 18:00+00'),
  ('cccc7725-0000-0000-0000-000000000001', 'aaaa7725-0000-0000-0000-000000000004', 'maybe', '2026-07-01 18:00+00'),
  ('cccc7725-0000-0000-0000-000000000001', 'aaaa7725-0000-0000-0000-000000000005', 'waitlisted', '2026-07-01 18:00+00'),
  ('cccc7725-0000-0000-0000-000000000001', 'aaaa7725-0000-0000-0000-000000000006', 'going', '2026-07-01 18:00+00');

insert into event_orders (id, event_id, instance_start, buyer_user_id, host_user_id,
                          amount_cents, platform_fee_cents, status, paid_at)
values
  ('dddd7725-0000-0000-0000-000000000001', 'cccc7725-0000-0000-0000-000000000001', '2026-07-01 18:00+00',
   'aaaa7725-0000-0000-0000-000000000002', 'aaaa7725-0000-0000-0000-000000000001', 2200, 55, 'paid', now()),
  ('dddd7725-0000-0000-0000-000000000002', 'cccc7725-0000-0000-0000-000000000001', '2026-07-01 18:00+00',
   'aaaa7725-0000-0000-0000-000000000003', 'aaaa7725-0000-0000-0000-000000000001', 2200, 55, 'partially_refunded', now()),
  ('dddd7725-0000-0000-0000-000000000003', 'cccc7725-0000-0000-0000-000000000001', '2026-07-01 18:00+00',
   'aaaa7725-0000-0000-0000-000000000005', 'aaaa7725-0000-0000-0000-000000000001', 2200, 55, 'refunded', now()),
  ('dddd7725-0000-0000-0000-000000000004', 'cccc7725-0000-0000-0000-000000000001', '2026-07-08 18:00+00',
   'aaaa7725-0000-0000-0000-000000000006', 'aaaa7725-0000-0000-0000-000000000001', 2200, 55, 'paid', now());

-- Called off the way events-cancel does it: as the service role, which is the
-- only caller guard_paid_occurrence_cancel lets past a paid occurrence.
set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';
insert into event_exceptions (event_id, instance_start, cancelled_by)
values ('cccc7725-0000-0000-0000-000000000001', '2026-07-01 18:00+00',
        'aaaa7725-0000-0000-0000-000000000001');
reset role;

select is(
  (select refunded from notifications
   where kind = 'event_cancel' and user_id = 'aaaa7725-0000-0000-0000-000000000002'),
  true, 'a buyer holding a paid order on the occurrence is told they are being refunded');

select is(
  (select refunded from notifications
   where kind = 'event_cancel' and user_id = 'aaaa7725-0000-0000-0000-000000000003'),
  true, 'a buyer holding a partially refunded order is told the remainder is being refunded');

select is(
  (select refunded from notifications
   where kind = 'event_cancel' and user_id = 'aaaa7725-0000-0000-0000-000000000004'),
  false, 'a free attendee gets the plain cancel notification');

select is(
  (select refunded from notifications
   where kind = 'event_cancel' and user_id = 'aaaa7725-0000-0000-0000-000000000005'),
  false, 'a buyer whose order on this occurrence is already refunded is not told it again');

select is(
  (select refunded from notifications
   where kind = 'event_cancel' and user_id = 'aaaa7725-0000-0000-0000-000000000006'),
  false, 'a paid order on a different occurrence of the series does not mark this one');

select is(
  (select count(*)::int from notifications
   where kind = 'event_cancel' and event_id = 'cccc7725-0000-0000-0000-000000000001'),
  5, 'every going / maybe / waitlisted attendee is still notified exactly once');

select is(
  (select count(*)::int from notifications
   where kind = 'event_cancel' and event_id = 'cccc7725-0000-0000-0000-000000000001'
     and event_instance_start = '2026-07-01 18:00+00'),
  5, 'the notification carries the cancelled occurrence');

select col_not_null('public', 'notifications', 'refunded',
  'notifications.refunded is never null, so every other kind reads as no refund line');

select is(
  (select prosecdef from pg_proc where oid = 'public.notify_event_cancel()'::regprocedure),
  true, 'notify_event_cancel is still SECURITY DEFINER');

select ok(
  (select 'search_path=public' = any(proconfig) from pg_proc
   where oid = 'public.notify_event_cancel()'::regprocedure),
  'notify_event_cancel still pins search_path');

select is(
  has_function_privilege('authenticated', 'public.notify_event_cancel()', 'execute'),
  false, 'a client role still cannot execute notify_event_cancel');

select * from finish();
rollback;

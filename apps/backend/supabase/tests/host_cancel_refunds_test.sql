-- Pins migration 20270723000003 (M8, host cancel refunds every registrant):
--   * can_cancel_event_occurrence answers the event_exceptions insert policy's
--     organiser predicate for the CALLER -- true for an organiser, false for a
--     plain member and for a stranger, and not callable by anon;
--   * guard_paid_occurrence_cancel refuses a client insert into
--     event_exceptions over an occurrence holding a pending, paid or partially
--     refunded order, so a paid class cannot be called off with the money
--     still held;
--   * the guard leaves a free occurrence, and one whose orders are all
--     terminal, cancellable from the client exactly as before;
--   * the service role (the events-cancel EF, which refunds in the same
--     request) passes it.

begin;
select plan(13);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('aaaa7723-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'hc-owner@evt.local', '', now(), now()),
  ('aaaa7723-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'hc-org@evt.local', '', now(), now()),
  ('aaaa7723-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'hc-member@evt.local', '', now(), now()),
  ('aaaa7723-0000-0000-0000-000000000004', 'authenticated', 'authenticated', 'hc-stranger@evt.local', '', now(), now()),
  ('aaaa7723-0000-0000-0000-000000000005', 'authenticated', 'authenticated', 'hc-buyer@evt.local', '', now(), now());

insert into clubs (id, owner_id, name, slug, is_public)
values ('bbbb7723-0000-0000-0000-000000000001',
        'aaaa7723-0000-0000-0000-000000000001', 'Host Cancel Studio', 'hc-studio', true);

insert into club_members (club_id, user_id, role, status) values
  ('bbbb7723-0000-0000-0000-000000000001', 'aaaa7723-0000-0000-0000-000000000002', 'event_organiser', 'active'),
  ('bbbb7723-0000-0000-0000-000000000001', 'aaaa7723-0000-0000-0000-000000000003', 'member', 'active');

insert into events (id, club_id, title, starts_at, author_id, host_user_id, category, recurrence_freq)
values ('cccc7723-0000-0000-0000-000000000001',
        'bbbb7723-0000-0000-0000-000000000001', 'Reformer Pilates',
        '2026-07-01 18:00+00', 'aaaa7723-0000-0000-0000-000000000001',
        'aaaa7723-0000-0000-0000-000000000001', 'class', 'weekly');

-- One occurrence per order state. 07-01 paid, 07-08 pending, 07-15 partially
-- refunded, 07-22 refunded + canceled only, 07-29 no orders at all, 08-05 paid
-- (cancelled by the service role).
insert into event_orders (id, event_id, instance_start, buyer_user_id, host_user_id,
                          amount_cents, platform_fee_cents, status, paid_at)
values
  ('dddd7723-0000-0000-0000-000000000001', 'cccc7723-0000-0000-0000-000000000001', '2026-07-01 18:00+00',
   'aaaa7723-0000-0000-0000-000000000005', 'aaaa7723-0000-0000-0000-000000000001', 2200, 55, 'paid', now()),
  ('dddd7723-0000-0000-0000-000000000002', 'cccc7723-0000-0000-0000-000000000001', '2026-07-08 18:00+00',
   'aaaa7723-0000-0000-0000-000000000005', 'aaaa7723-0000-0000-0000-000000000001', 2200, 55, 'pending', null),
  ('dddd7723-0000-0000-0000-000000000003', 'cccc7723-0000-0000-0000-000000000001', '2026-07-15 18:00+00',
   'aaaa7723-0000-0000-0000-000000000005', 'aaaa7723-0000-0000-0000-000000000001', 2200, 55, 'partially_refunded', now()),
  ('dddd7723-0000-0000-0000-000000000004', 'cccc7723-0000-0000-0000-000000000001', '2026-07-22 18:00+00',
   'aaaa7723-0000-0000-0000-000000000005', 'aaaa7723-0000-0000-0000-000000000001', 2200, 55, 'refunded', now()),
  ('dddd7723-0000-0000-0000-000000000005', 'cccc7723-0000-0000-0000-000000000001', '2026-07-22 18:00+00',
   'aaaa7723-0000-0000-0000-000000000005', 'aaaa7723-0000-0000-0000-000000000001', 2200, 55, 'canceled', null),
  ('dddd7723-0000-0000-0000-000000000006', 'cccc7723-0000-0000-0000-000000000001', '2026-08-05 18:00+00',
   'aaaa7723-0000-0000-0000-000000000005', 'aaaa7723-0000-0000-0000-000000000001', 2200, 55, 'paid', now());

-- ── The organiser predicate, asked as each caller ──
set local role authenticated;

set local "request.jwt.claims" = '{"sub":"aaaa7723-0000-0000-0000-000000000002","role":"authenticated"}';
select is(public.can_cancel_event_occurrence('cccc7723-0000-0000-0000-000000000001'), true,
  'an event organiser may call off an occurrence');

set local "request.jwt.claims" = '{"sub":"aaaa7723-0000-0000-0000-000000000001","role":"authenticated"}';
select is(public.can_cancel_event_occurrence('cccc7723-0000-0000-0000-000000000001'), true,
  'the club owner may call off an occurrence');

set local "request.jwt.claims" = '{"sub":"aaaa7723-0000-0000-0000-000000000003","role":"authenticated"}';
select is(public.can_cancel_event_occurrence('cccc7723-0000-0000-0000-000000000001'), false,
  'a plain member may not call off an occurrence');

set local "request.jwt.claims" = '{"sub":"aaaa7723-0000-0000-0000-000000000004","role":"authenticated"}';
select is(public.can_cancel_event_occurrence('cccc7723-0000-0000-0000-000000000001'), false,
  'a stranger may not call off an occurrence');

-- ── The guard, as the organiser ──
set local "request.jwt.claims" = '{"sub":"aaaa7723-0000-0000-0000-000000000002","role":"authenticated"}';

select throws_ok(
  $$ insert into event_exceptions (event_id, instance_start, cancelled_by)
     values ('cccc7723-0000-0000-0000-000000000001', '2026-07-01 18:00+00',
             'aaaa7723-0000-0000-0000-000000000002') $$,
  'P0001', 'paid_occurrence_requires_refund',
  'a client cannot call off an occurrence holding a paid order');

select throws_ok(
  $$ insert into event_exceptions (event_id, instance_start, cancelled_by)
     values ('cccc7723-0000-0000-0000-000000000001', '2026-07-08 18:00+00',
             'aaaa7723-0000-0000-0000-000000000002') $$,
  'P0001', 'paid_occurrence_requires_refund',
  'a client cannot call off an occurrence holding a pending reservation');

select throws_ok(
  $$ insert into event_exceptions (event_id, instance_start, cancelled_by)
     values ('cccc7723-0000-0000-0000-000000000001', '2026-07-15 18:00+00',
             'aaaa7723-0000-0000-0000-000000000002') $$,
  'P0001', 'paid_occurrence_requires_refund',
  'a client cannot call off an occurrence holding a partially refunded order');

select lives_ok(
  $$ insert into event_exceptions (event_id, instance_start, cancelled_by)
     values ('cccc7723-0000-0000-0000-000000000001', '2026-07-22 18:00+00',
             'aaaa7723-0000-0000-0000-000000000002') $$,
  'an occurrence whose orders are all terminal is still cancellable from the client');

select lives_ok(
  $$ insert into event_exceptions (event_id, instance_start, cancelled_by)
     values ('cccc7723-0000-0000-0000-000000000001', '2026-07-29 18:00+00',
             'aaaa7723-0000-0000-0000-000000000002') $$,
  'an occurrence with no orders is still cancellable from the client');

-- ── As the service role (the events-cancel EF) ──
set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';

select lives_ok(
  $$ insert into event_exceptions (event_id, instance_start, cancelled_by)
     values ('cccc7723-0000-0000-0000-000000000001', '2026-08-05 18:00+00',
             'aaaa7723-0000-0000-0000-000000000002') $$,
  'the service role calls off a paid occurrence (it refunds in the same request)');

-- Read back as the owner: exactly the three permitted cancels landed, and none
-- of the three refused ones.
reset role;
select is(
  (select array_agg(to_char(instance_start at time zone 'UTC', 'MM-DD') order by instance_start)
   from event_exceptions where event_id = 'cccc7723-0000-0000-0000-000000000001'),
  array['07-22', '07-29', '08-05'],
  'only the permitted cancels were recorded');

select is(
  (select count(*)::int from event_orders
   where event_id = 'cccc7723-0000-0000-0000-000000000001'
     and status in ('pending', 'paid', 'partially_refunded')),
  4,
  'the guard refuses the cancel; it never touches the orders');

-- ── anon cannot ask ──
set local role anon;
set local "request.jwt.claims" = '{"role":"anon"}';
select throws_ok(
  $$ select public.can_cancel_event_occurrence('cccc7723-0000-0000-0000-000000000001') $$,
  '42501', null,
  'anon cannot execute can_cancel_event_occurrence');

select * from finish();
rollback;

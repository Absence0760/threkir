-- Pins migration 20270808000041 (decisions § 1921): a paid order must name a
-- real occurrence of its event. `event_occurrence_exists` is the door
-- events-checkout asks before it opens a Checkout Session; the
-- `event_orders_validate_occurrence` trigger refuses the write itself, so no
-- path can land an order for a session the series never produces.

begin;
select plan(12);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('aaaa1921-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'occ-host@pay.local', '', now(), now()),
  ('aaaa1921-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'occ-buyer@pay.local', '', now(), now());

insert into clubs (id, owner_id, name, slug, is_public)
values ('bbbb1921-0000-0000-0000-000000000001', 'aaaa1921-0000-0000-0000-000000000001',
        'Occurrence Studio', 'occ-studio', true);

-- A Saturday 09:00Z weekly class in UTC, and a one-off.
insert into events (id, club_id, title, starts_at, author_id, host_user_id, category,
                    recurrence_freq, recurrence_byday, timezone)
values
  ('cccc1921-0000-0000-0000-000000000001', 'bbbb1921-0000-0000-0000-000000000001', 'Saturday class',
   '2099-01-03 09:00+00', 'aaaa1921-0000-0000-0000-000000000001',
   'aaaa1921-0000-0000-0000-000000000001', 'class', 'weekly', array['SA'], 'UTC'),
  ('cccc1921-0000-0000-0000-000000000002', 'bbbb1921-0000-0000-0000-000000000001', 'One-off class',
   '2099-02-01 18:00+00', 'aaaa1921-0000-0000-0000-000000000001',
   'aaaa1921-0000-0000-0000-000000000001', 'class', null, null, 'UTC');

-- ── the RPC events-checkout asks ──
select ok(event_occurrence_exists('cccc1921-0000-0000-0000-000000000001', '2099-01-10 09:00+00'),
  'a later Saturday 09:00 is an occurrence of the weekly class');
select ok(not event_occurrence_exists('cccc1921-0000-0000-0000-000000000001', '2099-01-07 03:17+00'),
  'a Wednesday 03:17 is not');
select ok(not event_occurrence_exists('cccc1921-0000-0000-0000-000000000002', '2099-02-01 18:01+00'),
  'a minute after a one-off''s start is not an occurrence of it');

select ok(not has_function_privilege('authenticated', 'public.event_occurrence_exists(uuid, timestamptz)', 'execute'),
  'a signed-in account cannot call the occurrence door');
select ok(not has_function_privilege('anon', 'public.event_occurrence_exists(uuid, timestamptz)', 'execute'),
  'nor can anon');
select ok(has_function_privilege('service_role', 'public.event_occurrence_exists(uuid, timestamptz)', 'execute'),
  'the service role (events-checkout) can');

-- ── the write floor ──
select lives_ok(
  $$ insert into event_orders (id, event_id, instance_start, buyer_user_id, host_user_id,
                               amount_cents, platform_fee_cents, status)
     values ('dddd1921-0000-0000-0000-000000000001', 'cccc1921-0000-0000-0000-000000000001',
             '2099-01-10 09:00+00', 'aaaa1921-0000-0000-0000-000000000002',
             'aaaa1921-0000-0000-0000-000000000001', 2000, 100, 'pending') $$,
  'an order for a real occurrence of a series is written');

select is(
  (select count(*)::int from event_orders where id = 'dddd1921-0000-0000-0000-000000000001'),
  1, 'and the row is there, so the refusals below are the check and not a dead insert path');

select throws_ok(
  $$ insert into event_orders (id, event_id, instance_start, buyer_user_id, host_user_id,
                               amount_cents, platform_fee_cents, status)
     values ('dddd1921-0000-0000-0000-000000000002', 'cccc1921-0000-0000-0000-000000000001',
             '2099-01-07 03:17+00', 'aaaa1921-0000-0000-0000-000000000002',
             'aaaa1921-0000-0000-0000-000000000001', 2000, 100, 'pending') $$,
  '23514', 'event order instance_start is not an occurrence of its event',
  'an order for a fabricated session of a series is refused');

select lives_ok(
  $$ insert into event_orders (id, event_id, instance_start, buyer_user_id, host_user_id,
                               amount_cents, platform_fee_cents, status)
     values ('dddd1921-0000-0000-0000-000000000003', 'cccc1921-0000-0000-0000-000000000002',
             '2099-02-01 18:00+00', 'aaaa1921-0000-0000-0000-000000000002',
             'aaaa1921-0000-0000-0000-000000000001', 2000, 100, 'pending') $$,
  'an order for a one-off at its start is written');

select throws_ok(
  $$ insert into event_orders (id, event_id, instance_start, buyer_user_id, host_user_id,
                               amount_cents, platform_fee_cents, status)
     values ('dddd1921-0000-0000-0000-000000000004', 'cccc1921-0000-0000-0000-000000000002',
             '2099-02-08 18:00+00', 'aaaa1921-0000-0000-0000-000000000002',
             'aaaa1921-0000-0000-0000-000000000001', 2000, 100, 'pending') $$,
  '23514', 'event order instance_start is not an occurrence of its event',
  'an order for a one-off a week after it happened is refused');

select throws_ok(
  $$ update event_orders set instance_start = '2099-01-11 09:00+00'
      where id = 'dddd1921-0000-0000-0000-000000000001' $$,
  '23514', 'event order instance_start is not an occurrence of its event',
  'an existing order cannot be re-pointed at a session that is not an occurrence');

select * from finish();
rollback;

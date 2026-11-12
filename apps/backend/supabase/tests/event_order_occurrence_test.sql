-- Pins migration 20270808000041 (decisions § 1921): a paid order must name a
-- real occurrence of its event. `event_occurrence_exists` is the door
-- events-checkout asks before it opens a Checkout Session; the
-- `event_orders_validate_occurrence` trigger refuses the write itself, so no
-- path can land an order for a session the series never produces. Both are
-- strict about the § 1918 transition window: an instant only the old UTC
-- clock produces is refused for an order while the photo and RSVP paths
-- still take it.

begin;
select plan(19);

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
   'aaaa1921-0000-0000-0000-000000000001', 'class', null, null, 'UTC'),
  -- Wednesdays 21:30 in New York: the old UTC clock put it on Tuesdays.
  ('cccc1921-0000-0000-0000-000000000003', 'bbbb1921-0000-0000-0000-000000000001', 'Wednesday class',
   '2026-09-03 01:30+00', 'aaaa1921-0000-0000-0000-000000000001',
   'aaaa1921-0000-0000-0000-000000000001', 'class', 'weekly', array['WE'], 'America/New_York');

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

-- ── the transition window: strict for money, lenient elsewhere ──
select ok(private.recurrence_utc_clock_accepted(),
  'the § 1918 transition window is open');
select ok(not event_occurrence_exists('cccc1921-0000-0000-0000-000000000003', '2026-09-09 01:30+00'),
  'checkout refuses the UTC-clock-only instant (Tuesday 21:30 local) an old build mints, window or not');
select ok(event_occurrence_exists('cccc1921-0000-0000-0000-000000000003', '2026-09-10 01:30+00'),
  'and sells the wall-clock one (Wednesday 21:30 local)');

select throws_ok(
  $$ insert into event_orders (id, event_id, instance_start, buyer_user_id, host_user_id,
                               amount_cents, platform_fee_cents, status)
     values ('dddd1921-0000-0000-0000-000000000005', 'cccc1921-0000-0000-0000-000000000003',
             '2026-09-09 01:30+00', 'aaaa1921-0000-0000-0000-000000000002',
             'aaaa1921-0000-0000-0000-000000000001', 2000, 100, 'pending') $$,
  '23514', 'event order instance_start is not an occurrence of its event',
  'the order trigger refuses a UTC-clock-only instant inside the window');

select lives_ok(
  $$ insert into event_orders (id, event_id, instance_start, buyer_user_id, host_user_id,
                               amount_cents, platform_fee_cents, status)
     values ('dddd1921-0000-0000-0000-000000000006', 'cccc1921-0000-0000-0000-000000000003',
             '2026-09-10 01:30+00', 'aaaa1921-0000-0000-0000-000000000002',
             'aaaa1921-0000-0000-0000-000000000001', 2000, 100, 'pending') $$,
  'and writes an order on the wall-clock instant');

select lives_ok(
  $$ insert into run_photos (id, owner_id, storage_path, event_id, event_instance_start)
     values ('eeee1921-0000-0000-0000-000000000001', 'aaaa1921-0000-0000-0000-000000000001',
             'aaaa1921-0000-0000-0000-000000000001/old-clock.jpg',
             'cccc1921-0000-0000-0000-000000000003', '2026-09-09 01:30+00') $$,
  'a host photo on the same UTC-clock-only instant still passes the lenient occurrence check');

insert into event_attendees (event_id, user_id, instance_start, status)
values ('cccc1921-0000-0000-0000-000000000003', 'aaaa1921-0000-0000-0000-000000000002',
        '2026-09-09 01:30+00', 'going');
select ok(
  exists (select 1 from event_attendees
           where event_id = 'cccc1921-0000-0000-0000-000000000003'
             and user_id = 'aaaa1921-0000-0000-0000-000000000002'
             and instance_start = '2026-09-09 01:30+00'),
  'and an old build''s RSVP on it is still written');

select * from finish();
rollback;

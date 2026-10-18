-- Pins migration 20270924000002: race_listings.route_id names a race's course.
-- The public calendar view carries the course's summary only while the route
-- is itself public and not moderated away, so a listing pointed at a private
-- route shows no course to anon, to another runner or to the route's owner.
-- Only service_role writes route_id: a submitter's insert drops it and their
-- update keeps the stored value. Deleting the route nulls the link.

begin;
select plan(14);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('c1c1c1c1-0000-0000-0000-0000000c0001', 'authenticated', 'authenticated', 'rlc-owner@rlc.local', '', now(), now()),
  ('c1c1c1c1-0000-0000-0000-0000000c0002', 'authenticated', 'authenticated', 'rlc-other@rlc.local', '', now(), now())
on conflict (id) do nothing;

insert into routes (id, user_id, name, waypoints, distance_m, elevation_m, surface, is_public, shadow_hidden)
values
  ('c2c2c2c2-0000-0000-0000-0000000c0001', 'c1c1c1c1-0000-0000-0000-0000000c0001',
   'Richmond course', '[]'::jsonb, 42195, 180, 'road', true, false),
  ('c2c2c2c2-0000-0000-0000-0000000c0002', 'c1c1c1c1-0000-0000-0000-0000000c0001',
   'My secret loop', '[]'::jsonb, 21097, 310, 'trail', false, false),
  ('c2c2c2c2-0000-0000-0000-0000000c0003', 'c1c1c1c1-0000-0000-0000-0000000c0001',
   'Hidden course', '[]'::jsonb, 10000, 40, 'mixed', true, true);

set local role service_role;
insert into race_listings (id, provider, provider_race_id, name, race_date, distance_m, is_verified, route_id)
values
  ('c3c3c3c3-0000-0000-0000-0000000c0001', 'runsignup', 'rlc-1', 'Public Course Marathon', '2036-11-14', 42195, true,
   'c2c2c2c2-0000-0000-0000-0000000c0001'),
  ('c3c3c3c3-0000-0000-0000-0000000c0002', 'runsignup', 'rlc-2', 'Private Course Half', '2036-11-21', 21097, true,
   'c2c2c2c2-0000-0000-0000-0000000c0002'),
  ('c3c3c3c3-0000-0000-0000-0000000c0003', 'runsignup', 'rlc-3', 'Hidden Course 10K', '2036-11-28', 10000, true,
   'c2c2c2c2-0000-0000-0000-0000000c0003');
reset role;

-- 1. service_role links a course.
select is(
  (select route_id from race_listings where id = 'c3c3c3c3-0000-0000-0000-0000000c0001'),
  'c2c2c2c2-0000-0000-0000-0000000c0001'::uuid,
  'service_role sets race_listings.route_id'
);

-- ── anon ────────────────────────────────────────────────────────────────────
set local role anon;
set local "request.jwt.claims" = '';

-- 2. A public course reaches the calendar with its summary.
select results_eq(
  $$ select course_distance_m, course_elevation_m, course_surface
     from public_race_listings where id = 'c3c3c3c3-0000-0000-0000-0000000c0001' $$,
  $$ values (42195::numeric, 180::numeric, 'road'::text) $$,
  'anon reads a public course''s distance, climb and surface'
);

-- 3. The listing on a private route is still listed...
select is(
  (select name from public_race_listings where id = 'c3c3c3c3-0000-0000-0000-0000000c0002'),
  'Private Course Half',
  'the listing on a private route stays on the calendar'
);
-- 4. ...with no course.
select ok(
  (select course_distance_m is null and course_elevation_m is null and course_surface is null
   from public_race_listings where id = 'c3c3c3c3-0000-0000-0000-0000000c0002'),
  'a listing linked to a private route exposes no course to anon'
);

-- 5. A shadow-hidden route is not a course either.
select ok(
  (select course_distance_m is null and course_surface is null
   from public_race_listings where id = 'c3c3c3c3-0000-0000-0000-0000000c0003'),
  'a listing linked to a moderated-away route exposes no course to anon'
);
reset role;

-- ── another runner ─────────────────────────────────────────────────────────
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"c1c1c1c1-0000-0000-0000-0000000c0002","role":"authenticated"}';

select ok(
  (select course_distance_m is null and course_elevation_m is null and course_surface is null
   from public_race_listings where id = 'c3c3c3c3-0000-0000-0000-0000000c0002'),
  'a listing linked to a private route exposes no course to another runner'
);
select is(
  (select course_surface from public_race_listings where id = 'c3c3c3c3-0000-0000-0000-0000000c0001'),
  'road',
  'another runner reads the public course'
);
reset role;

-- ── the route's owner ──────────────────────────────────────────────────────
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"c1c1c1c1-0000-0000-0000-0000000c0001","role":"authenticated"}';

select ok(
  (select course_distance_m is null
   from public_race_listings where id = 'c3c3c3c3-0000-0000-0000-0000000c0002'),
  'the calendar shows the owner no course on their own private route either'
);

-- 6. A submitter cannot attach a course on insert.
insert into race_listings (id, provider, name, race_date, submitted_by, route_id)
values ('c3c3c3c3-0000-0000-0000-0000000c0004', 'manual', 'My Club 5K', '2036-12-05',
        'c1c1c1c1-0000-0000-0000-0000000c0001', 'c2c2c2c2-0000-0000-0000-0000000c0001');

-- 7. Nor on an update of their own unverified listing.
update race_listings set route_id = 'c2c2c2c2-0000-0000-0000-0000000c0001'
 where id = 'c3c3c3c3-0000-0000-0000-0000000c0004';
reset role;

select is(
  (select count(*)::int from race_listings where id = 'c3c3c3c3-0000-0000-0000-0000000c0004'),
  1,
  'the submitter''s listing was filed'
);
select is(
  (select route_id from race_listings where id = 'c3c3c3c3-0000-0000-0000-0000000c0004'),
  null::uuid,
  'a submitter''s insert and update leave route_id null'
);

-- 8. A submitter's update keeps a course the service role set.
set local role service_role;
update race_listings set route_id = 'c2c2c2c2-0000-0000-0000-0000000c0001', is_verified = false
 where id = 'c3c3c3c3-0000-0000-0000-0000000c0004';
reset role;
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"c1c1c1c1-0000-0000-0000-0000000c0001","role":"authenticated"}';
update race_listings set route_id = null, name = 'My Club 5K (renamed)'
 where id = 'c3c3c3c3-0000-0000-0000-0000000c0004';
reset role;
select is(
  (select name from race_listings where id = 'c3c3c3c3-0000-0000-0000-0000000c0004'),
  'My Club 5K (renamed)',
  'the submitter''s own edit lands'
);
select is(
  (select route_id from race_listings where id = 'c3c3c3c3-0000-0000-0000-0000000c0004'),
  'c2c2c2c2-0000-0000-0000-0000000c0001'::uuid,
  'a submitter''s update keeps the course the service role set'
);

-- 9. Deleting the route nulls the link and keeps the listing.
delete from routes where id = 'c2c2c2c2-0000-0000-0000-0000000c0001';
select is(
  (select route_id from race_listings where id = 'c3c3c3c3-0000-0000-0000-0000000c0001'),
  null::uuid,
  'deleting the route sets the listing''s route_id to null'
);
select is(
  (select name from race_listings where id = 'c3c3c3c3-0000-0000-0000-0000000c0001'),
  'Public Course Marathon',
  'deleting the route keeps the listing'
);

select * from finish();
rollback;

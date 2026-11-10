-- park_course_records (migration 20271129002436, issue #1352): this season's
-- record on every park course in one call, for the Races & courses page's
-- "Run any time" section. It wraps global_segment_leaderboard, so the
-- assertions here pin the wrapping (one row per course, the park's season,
-- the caller's RLS on the catalogue, no anon), not the board's own rules,
-- which its own suites cover.
--
-- Efforts are dated relative to now() because the season is "this year where
-- the park is", not a fixed year.

begin;

select plan(6);

-- ── Fixture ──
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-00000000a611', 'authenticated', 'authenticated',
   'rec-a@pcr.local', '', now(), now()),
  ('00000000-0000-0000-0000-00000000b612', 'authenticated', 'authenticated',
   'rec-b@pcr.local', '', now(), now()),
  ('00000000-0000-0000-0000-00000000c613', 'authenticated', 'authenticated',
   'rec-c@pcr.local', '', now(), now());

insert into user_profiles (id, display_name)
values
  ('00000000-0000-0000-0000-00000000a611', 'Record A'),
  ('00000000-0000-0000-0000-00000000b612', 'Record B'),
  ('00000000-0000-0000-0000-00000000c613', 'Record C');

select tests.confirm_consent();

insert into global_segments (id, name, waypoints, distance_m, is_active)
values
  ('a6a6a6a6-0000-0000-0000-0000000000d1', 'Record Loop',
   '[{"lat":36.0,"lng":-77.0},{"lat":36.004,"lng":-77.0}]', 450, true),
  ('a6a6a6a6-0000-0000-0000-0000000000d2', 'Quiet Loop',
   '[{"lat":36.1,"lng":-77.0},{"lat":36.104,"lng":-77.0}]', 450, true),
  ('a6a6a6a6-0000-0000-0000-0000000000d3', 'Pulled Loop',
   '[{"lat":36.2,"lng":-77.0},{"lat":36.204,"lng":-77.0}]', 450, true);

insert into parks (id, slug, name, agency, region_code, country_code, timezone, is_active)
values
  ('a6a6a6a6-0000-0000-0000-0000000000a1', 'record-park', 'Record Park',
   'state', 'US-VA', 'US', 'America/New_York', true),
  ('a6a6a6a6-0000-0000-0000-0000000000a2', 'record-pulled-park', 'Record Pulled Park',
   'state', 'US-VA', 'US', 'America/New_York', false);

insert into park_courses (id, park_id, global_segment_id, slug, course_shape, geometry_source)
values
  ('a6a6a6a6-0000-0000-0000-0000000000b1', 'a6a6a6a6-0000-0000-0000-0000000000a1',
   'a6a6a6a6-0000-0000-0000-0000000000d1', 'record-loop', 'loop', 'osm'),
  ('a6a6a6a6-0000-0000-0000-0000000000b2', 'a6a6a6a6-0000-0000-0000-0000000000a1',
   'a6a6a6a6-0000-0000-0000-0000000000d2', 'quiet-loop', 'loop', 'osm'),
  ('a6a6a6a6-0000-0000-0000-0000000000b3', 'a6a6a6a6-0000-0000-0000-0000000000a2',
   'a6a6a6a6-0000-0000-0000-0000000000d3', 'pulled-loop', 'loop', 'osm');

-- A: 400 s this season, and a faster 280 s more than a year ago.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000a611"}';
insert into runs (id, user_id, started_at, distance_m, duration_s, source, metadata, is_public)
values
  ('b6b6b6b6-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a611',
   now(), 5000, 1200, 'app', '{"activity_type":"run"}'::jsonb, true),
  ('b6b6b6b6-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-00000000a611',
   now() - interval '400 days', 5000, 1200, 'app', '{"activity_type":"run"}'::jsonb, true),
  ('b6b6b6b6-0000-0000-0000-0000000000a3', '00000000-0000-0000-0000-00000000a611',
   now(), 5000, 1200, 'app', '{"activity_type":"run"}'::jsonb, true);
insert into global_segment_efforts (global_segment_id, run_id, user_id, time_seconds, started_at)
values
  ('a6a6a6a6-0000-0000-0000-0000000000d1', 'b6b6b6b6-0000-0000-0000-0000000000a1',
   '00000000-0000-0000-0000-00000000a611', 400, now()),
  ('a6a6a6a6-0000-0000-0000-0000000000d1', 'b6b6b6b6-0000-0000-0000-0000000000a2',
   '00000000-0000-0000-0000-00000000a611', 280, now() - interval '400 days'),
  ('a6a6a6a6-0000-0000-0000-0000000000d3', 'b6b6b6b6-0000-0000-0000-0000000000a3',
   '00000000-0000-0000-0000-00000000a611', 300, now());

-- B: 390 s this season, on a PRIVATE run, so C must not see it.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000b612"}';
insert into runs (id, user_id, started_at, distance_m, duration_s, source, metadata, is_public)
values ('b6b6b6b6-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-00000000b612',
        now(), 5000, 1200, 'app', '{"activity_type":"run"}'::jsonb, false);
insert into global_segment_efforts (global_segment_id, run_id, user_id, time_seconds, started_at)
values ('a6a6a6a6-0000-0000-0000-0000000000d1', 'b6b6b6b6-0000-0000-0000-0000000000b1',
        '00000000-0000-0000-0000-00000000b612', 390, now());

-- ── Read by C ──
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000c613"}';

-- 1. This season's fastest visible effort, not the faster one from last year
--    and not B's private one.
select results_eq(
  $$ select user_id::text, display_name, time_seconds from park_course_records()
     where course_id = 'a6a6a6a6-0000-0000-0000-0000000000b1' $$,
  $$ values ('00000000-0000-0000-0000-00000000a611', 'Record A', 400) $$,
  'the record is this season''s fastest effort the caller may see'
);

-- 2. The season is the park's current year.
select is(
  (select season from park_course_records()
    where course_id = 'a6a6a6a6-0000-0000-0000-0000000000b1'),
  extract(year from (now() at time zone 'America/New_York'))::integer,
  'the season is the current calendar year in the park timezone'
);

-- 3. A course with no effort this season has no row.
select is_empty(
  $$ select 1 from park_course_records()
     where course_id = 'a6a6a6a6-0000-0000-0000-0000000000b2' $$,
  'a course with no effort this season has no record row'
);

-- 4. A pulled park's course is not listed, whatever its efforts.
select is_empty(
  $$ select 1 from park_course_records()
     where course_id = 'a6a6a6a6-0000-0000-0000-0000000000b3' $$,
  'a course in an inactive park is not listed'
);

-- 5. B sees their own private effort, as the board shows a runner their own.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000b612"}';
select is(
  (select time_seconds from park_course_records()
    where course_id = 'a6a6a6a6-0000-0000-0000-0000000000b1'),
  390,
  'the caller''s own private effort counts for the caller'
);

-- 6. An anonymous caller holds no EXECUTE.
set local role anon;
set local "request.jwt.claims" = '{}';
select throws_ok(
  $$ select * from park_course_records() $$,
  '42501',
  null,
  'anon cannot call park_course_records'
);

select * from finish();
rollback;

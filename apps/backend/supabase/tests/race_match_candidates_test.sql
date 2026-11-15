-- Pins migration 20271229100001 (issue #1389): race_match_candidates, the
-- "Is this your race?" read for one run.
--
--   1-3.  The date window is a day either side of the run's UTC start: the
--         Richmond Marathon on the run's day is returned, a race the next day
--         is returned (the scorer applies the exact window), and the Turkey
--         Trot twelve days later is not.
--   4-5.  With a start point, a listing over 50 km away is dropped and one
--         with no location is kept, after the located ones.
--   6-8.  A listing whose course is a public route carries the course's start
--         and finish lines, facing along the route, at the 15 m reach; a
--         listing on a private route carries none.
--   9.    The listing's location and course distance come back for the scorer.
--   10.   anon cannot call it.

begin;
select plan(10);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('a1389000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
   'rmc-owner@rmc.local', '', now(), now()),
  ('a1389000-0000-0000-0000-000000000002', 'authenticated', 'authenticated',
   'rmc-runner@rmc.local', '', now(), now());

-- Broad St start heading east, then south to a 5th & Byrd finish.
insert into routes (id, user_id, name, waypoints, distance_m, is_public)
values
  ('a1389000-0000-0000-0000-0000000000b1', 'a1389000-0000-0000-0000-000000000001',
   'Richmond Marathon course',
   '[{"lat":37.5480,"lng":-77.4600},{"lat":37.5480,"lng":-77.4500},{"lat":37.5400,"lng":-77.4440},{"lat":37.5365,"lng":-77.4440}]'::jsonb,
   42195, true),
  ('a1389000-0000-0000-0000-0000000000b2', 'a1389000-0000-0000-0000-000000000001',
   'Private loop',
   '[{"lat":37.55,"lng":-77.46},{"lat":37.56,"lng":-77.46}]'::jsonb,
   5000, false);

set local role service_role;
insert into race_listings (id, provider, provider_race_id, name, race_date, distance_m, is_verified, route_id, location_point)
values
  ('a1389000-0000-0000-0000-0000000000c1', 'runsignup', 'rmc-1', 'Richmond Marathon', '2026-11-14', 42195, true,
   'a1389000-0000-0000-0000-0000000000b1',
   ST_SetSRID(ST_MakePoint(-77.4360, 37.5407), 4326)::geography),
  ('a1389000-0000-0000-0000-0000000000c2', 'runsignup', 'rmc-2', 'TFC Turkey Trot', '2026-11-26', 5000, true,
   null, ST_SetSRID(ST_MakePoint(-77.4400, 37.5450), 4326)::geography),
  ('a1389000-0000-0000-0000-0000000000c3', 'runsignup', 'rmc-3', 'Sunday 10K', '2026-11-15', 10000, true,
   'a1389000-0000-0000-0000-0000000000b2',
   ST_SetSRID(ST_MakePoint(-77.4500, 37.5500), 4326)::geography),
  ('a1389000-0000-0000-0000-0000000000c4', 'runsignup', 'rmc-4', 'Virginia Beach 5K', '2026-11-14', 5000, true,
   null, ST_SetSRID(ST_MakePoint(-75.9780, 36.8529), 4326)::geography),
  ('a1389000-0000-0000-0000-0000000000c5', 'manual', null, 'Unplaced Saturday race', '2026-11-14', null, true,
   null, null);
reset role;

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"a1389000-0000-0000-0000-000000000002","role":"authenticated"}';

-- 1-3
select ok(
  exists (select 1 from race_match_candidates('2026-11-14 12:00+00', 37.5481, -77.4610)
          where id = 'a1389000-0000-0000-0000-0000000000c1'),
  'the race on the run''s day is a candidate'
);
select ok(
  exists (select 1 from race_match_candidates('2026-11-14 12:00+00', 37.5481, -77.4610)
          where id = 'a1389000-0000-0000-0000-0000000000c3'),
  'a race the next day is returned, for the scorer''s exact window'
);
select ok(
  not exists (select 1 from race_match_candidates('2026-11-14 12:00+00', 37.5481, -77.4610)
              where id = 'a1389000-0000-0000-0000-0000000000c2'),
  'a race twelve days later is not a candidate'
);

-- 4-5
select ok(
  not exists (select 1 from race_match_candidates('2026-11-14 12:00+00', 37.5481, -77.4610)
              where id = 'a1389000-0000-0000-0000-0000000000c4'),
  'a race over 50 km from the run''s start is dropped'
);
select is(
  (select array_agg(name) from race_match_candidates('2026-11-14 12:00+00', 37.5481, -77.4610)),
  array['Sunday 10K', 'Richmond Marathon', 'Unplaced Saturday race'],
  'nearest first, the listing with no location last'
);

-- 6-8
select ok(
  (select start_gate_lat = 37.548 and start_gate_lng = -77.46
          and finish_gate_lat = 37.5365 and finish_gate_lng = -77.444
          and gate_half_width_m = 15
   from race_match_candidates('2026-11-14 12:00+00', null, null)
   where id = 'a1389000-0000-0000-0000-0000000000c1'),
  'a public course carries its start and finish lines at the 15 m reach'
);
select ok(
  (select start_gate_bearing_deg between 89 and 91 and finish_gate_bearing_deg between 179 and 181
   from race_match_candidates('2026-11-14 12:00+00', null, null)
   where id = 'a1389000-0000-0000-0000-0000000000c1'),
  'the lines face along the route: east at the start, south at the finish'
);
select ok(
  (select start_gate_lat is null and finish_gate_lat is null and gate_half_width_m is null
   from race_match_candidates('2026-11-14 12:00+00', null, null)
   where id = 'a1389000-0000-0000-0000-0000000000c3'),
  'a listing on a private route carries no lines'
);

-- 9
select ok(
  (select round(location_lat::numeric, 4) = 37.5407 and round(location_lng::numeric, 4) = -77.4360
          and course_distance_m = 42195
   from race_match_candidates('2026-11-14 12:00+00', null, null)
   where id = 'a1389000-0000-0000-0000-0000000000c1'),
  'the listing''s location and course distance come back'
);

-- 10
set local role anon;
set local "request.jwt.claims" = '';
select throws_ok(
  $$ select * from race_match_candidates('2026-11-14 12:00+00', null, null) $$,
  '42501',
  null,
  'anon cannot call race_match_candidates'
);

select * from finish();
rollback;

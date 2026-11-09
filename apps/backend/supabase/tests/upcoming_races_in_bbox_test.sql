-- Pins 20271125002408: upcoming verified races as discovery-map pins (issue
-- #1190 § 4, decisions § 2408).
--
--   * only verified listings dated today .. today + p_days pin;
--   * the pin sits at a publicly shown course's start, else the listing's
--     location, and a private course neither moves the pin nor reads as a
--     course;
--   * official races (claimed by a verified, public, unhidden club) rank first,
--     then soonest, then id; the Official lens narrows to them;
--   * revoking the club's badge drops the rank at once;
--   * a logged-out caller can read it.
--
-- Everything sits in an empty patch of the southern Indian Ocean so seed data
-- and other suites' rows never enter the viewport.

begin;
select plan(13);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values ('0ab10000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'ur-owner@ur.local', '', now(), now())
on conflict (id) do nothing;

insert into clubs (id, owner_id, name, slug, is_public)
values ('0ab11111-0000-0000-0000-000000000001', '0ab10000-0000-0000-0000-000000000001', 'Race Org', 'ur-race-org', true);

set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';
update clubs set is_verified = true where id = '0ab11111-0000-0000-0000-000000000001';
reset role;

-- A public course starting at (80.20, -45.20) and a private one at (80.30, -45.30).
insert into routes (id, user_id, club_id, name, waypoints, distance_m, surface, is_public)
values
  ('0ab12222-0000-0000-0000-000000000001', '0ab10000-0000-0000-0000-000000000001', '0ab11111-0000-0000-0000-000000000001',
   'Public course', '[{"lat": -45.20, "lng": 80.20}, {"lat": -45.21, "lng": 80.21}]'::jsonb, 10000, 'road', true),
  ('0ab12222-0000-0000-0000-000000000002', '0ab10000-0000-0000-0000-000000000001', null,
   'Private course', '[{"lat": -45.30, "lng": 80.30}, {"lat": -45.31, "lng": 80.31}]'::jsonb, 10000, 'road', false);

insert into race_listings (id, provider, provider_race_id, name, race_date, distance_m, location_label,
                           location_point, is_verified, organiser_club_id, route_id)
values
  -- Official (claimed by the verified club), with its public course, in 60 days.
  ('0ab13333-0000-0000-0000-000000000001', 'manual', null, 'Official Marathon', current_date + 60, 42195, 'Somewhere',
   ST_SetSRID(ST_MakePoint(80.10, -45.10), 4326)::geography, true, '0ab11111-0000-0000-0000-000000000001',
   '0ab12222-0000-0000-0000-000000000001'),
  -- A provider-verified community race, sooner, linked to a private route.
  ('0ab13333-0000-0000-0000-000000000002', 'runsignup', 'ur-2', 'Synced 10K', current_date + 10, 10000, 'Somewhere',
   ST_SetSRID(ST_MakePoint(80.40, -45.40), 4326)::geography, true, null, '0ab12222-0000-0000-0000-000000000002'),
  -- Unverified (a fan's copy).
  ('0ab13333-0000-0000-0000-000000000003', 'manual', null, 'Fan copy', current_date + 60, 42195, 'Somewhere',
   ST_SetSRID(ST_MakePoint(80.11, -45.11), 4326)::geography, false, null, null),
  -- Already run.
  ('0ab13333-0000-0000-0000-000000000004', 'runsignup', 'ur-4', 'Last month', current_date - 30, 5000, 'Somewhere',
   ST_SetSRID(ST_MakePoint(80.12, -45.12), 4326)::geography, true, null, null),
  -- Beyond the default six months.
  ('0ab13333-0000-0000-0000-000000000005', 'runsignup', 'ur-5', 'Next autumn', current_date + 250, 5000, 'Somewhere',
   ST_SetSRID(ST_MakePoint(80.13, -45.13), 4326)::geography, true, null, null),
  -- Verified, today, but nowhere to pin.
  ('0ab13333-0000-0000-0000-000000000006', 'runsignup', 'ur-6', 'Nowhere', current_date, 5000, null,
   null, true, null, null),
  -- More than a year out.
  ('0ab13333-0000-0000-0000-000000000007', 'runsignup', 'ur-7', 'Far off', current_date + 400, 5000, 'Somewhere',
   ST_SetSRID(ST_MakePoint(80.14, -45.14), 4326)::geography, true, null, null);

-- 1. Only the verified, upcoming, pinnable races, official first.
select results_eq(
  $$ select id from upcoming_races_in_bbox(80.0, -45.5, 80.5, -45.0) $$,
  $$ values ('0ab13333-0000-0000-0000-000000000001'::uuid), ('0ab13333-0000-0000-0000-000000000002'::uuid) $$,
  'verified upcoming races pin, official first even when a community race is sooner'
);

-- 2. The official race reads as official.
select ok(
  (select is_official from upcoming_races_in_bbox(80.0, -45.5, 80.5, -45.0)
    where id = '0ab13333-0000-0000-0000-000000000001'),
  'a race claimed by a verified club is official'
);

-- 3. The public course moves the pin to its start.
select results_eq(
  $$ select round(lng::numeric, 4), round(lat::numeric, 4), has_course from upcoming_races_in_bbox(80.0, -45.5, 80.5, -45.0)
      where id = '0ab13333-0000-0000-0000-000000000001' $$,
  $$ values (80.2000::numeric, -45.2000::numeric, true) $$,
  'a public course pins the race at its start'
);

-- 4. A private course neither moves the pin nor reads as a course.
select results_eq(
  $$ select round(lng::numeric, 4), round(lat::numeric, 4), has_course from upcoming_races_in_bbox(80.0, -45.5, 80.5, -45.0)
      where id = '0ab13333-0000-0000-0000-000000000002' $$,
  $$ values (80.4000::numeric, -45.4000::numeric, false) $$,
  'a private course leaves the pin on the listing location'
);

-- 5. The box is the pin point's: a box around only the course start finds the
--    official race, though its listing location is outside it.
select results_eq(
  $$ select id from upcoming_races_in_bbox(80.15, -45.25, 80.25, -45.15) $$,
  $$ values ('0ab13333-0000-0000-0000-000000000001'::uuid) $$,
  'the bbox tests the resolved pin point'
);

-- 6. p_days widens the window.
select ok(
  exists (select 1 from upcoming_races_in_bbox(80.0, -45.5, 80.5, -45.0, 100, 366)
          where id = '0ab13333-0000-0000-0000-000000000005'),
  'a wider p_days reaches a race past six months'
);

-- 7. p_days is clamped to a year.
select ok(
  not exists (select 1 from upcoming_races_in_bbox(80.0, -45.5, 80.5, -45.0, 100, 100000)
              where id = '0ab13333-0000-0000-0000-000000000007'),
  'p_days is clamped to 366, so a race in 400 days never pins'
);

-- 8. p_limit keeps the official race when it cuts.
select results_eq(
  $$ select id from upcoming_races_in_bbox(80.0, -45.5, 80.5, -45.0, 1) $$,
  $$ values ('0ab13333-0000-0000-0000-000000000001'::uuid) $$,
  'a limit of one keeps the official race'
);

-- 9. The Official lens holds only official races.
select results_eq(
  $$ select id from upcoming_races_in_bbox(80.0, -45.5, 80.5, -45.0, 100, 183, true) $$,
  $$ values ('0ab13333-0000-0000-0000-000000000001'::uuid) $$,
  'p_official_only narrows to official races'
);

-- 10. A course made private stops moving the pin.
update routes set is_public = false where id = '0ab12222-0000-0000-0000-000000000001';
select results_eq(
  $$ select round(lng::numeric, 4), round(lat::numeric, 4), has_course from upcoming_races_in_bbox(80.0, -45.5, 80.5, -45.0)
      where id = '0ab13333-0000-0000-0000-000000000001' $$,
  $$ values (80.1000::numeric, -45.1000::numeric, false) $$,
  'a course made private returns the pin to the listing location'
);

-- 11. Revoking the club's badge drops the rank at once.
set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';
update clubs set is_verified = false where id = '0ab11111-0000-0000-0000-000000000001';
reset role;
select results_eq(
  $$ select id, is_official from upcoming_races_in_bbox(80.0, -45.5, 80.5, -45.0) $$,
  $$ values ('0ab13333-0000-0000-0000-000000000002'::uuid, false), ('0ab13333-0000-0000-0000-000000000001'::uuid, false) $$,
  'an unverified organiser no longer ranks first'
);

-- 12–13. A logged-out caller reads the pins.
set local role anon;
set local "request.jwt.claims" = '{"role":"anon"}';
select lives_ok(
  $$ select * from upcoming_races_in_bbox(80.0, -45.5, 80.5, -45.0) $$,
  'anon can execute upcoming_races_in_bbox'
);
select is(
  (select count(*)::int from upcoming_races_in_bbox(80.0, -45.5, 80.5, -45.0)),
  2,
  'anon sees the same verified races'
);
reset role;

select * from finish();
rollback;

-- Pins 20271108000010: routes.official_distance_m (issue #1291).
--
-- The column is nullable and the CHECK holds it to (0, 1,000 km]. The owner
-- sets and clears it. public_routes and shared_routes carry it, the race
-- calendar's course_distance_m and the explore map's bbox RPC return it in
-- place of the traced length. Linking a race listing to a route with no
-- official distance prefills it from the listing, only within 10% of the
-- traced length, and never over a value the owner already set.

begin;
select plan(14);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('0d150000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'rod-owner@rod.local', '', now(), now()),
  ('0d150000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'rod-other@rod.local', '', now(), now())
on conflict (id) do nothing;

insert into routes (id, user_id, name, waypoints, distance_m, surface, is_public)
values
  ('0d152222-0000-0000-0000-000000000001', '0d150000-0000-0000-0000-000000000001',
   'Traced marathon', '[{"lat": 37.54, "lng": -77.44}]'::jsonb, 42670, 'road', true),
  ('0d152222-0000-0000-0000-000000000002', '0d150000-0000-0000-0000-000000000001',
   'Traced half', '[]'::jsonb, 21300, 'road', true),
  ('0d152222-0000-0000-0000-000000000003', '0d150000-0000-0000-0000-000000000001',
   'Owner-set 10K', '[]'::jsonb, 10120, 'road', true),
  ('0d152222-0000-0000-0000-000000000004', '0d150000-0000-0000-0000-000000000001',
   'Wrong course', '[]'::jsonb, 42670, 'road', true);

-- 1-2. The CHECK refuses zero and a value past 1,000 km.
select throws_ok(
  $$ update routes set official_distance_m = 0 where id = '0d152222-0000-0000-0000-000000000001' $$,
  '23514', null,
  'official_distance_m must be positive'
);
select throws_ok(
  $$ update routes set official_distance_m = 1000001 where id = '0d152222-0000-0000-0000-000000000001' $$,
  '23514', null,
  'official_distance_m is at most 1,000 km'
);

-- ── the owner sets and clears it ───────────────────────────────────────────
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"0d150000-0000-0000-0000-000000000001","role":"authenticated"}';

update routes set official_distance_m = 42195 where id = '0d152222-0000-0000-0000-000000000001';
-- 3.
select is(
  (select official_distance_m from routes where id = '0d152222-0000-0000-0000-000000000001'),
  42195::numeric,
  'the owner sets the official distance'
);

update routes set official_distance_m = 10050 where id = '0d152222-0000-0000-0000-000000000003';
update routes set official_distance_m = null where id = '0d152222-0000-0000-0000-000000000001';
-- 4.
select is(
  (select official_distance_m from routes where id = '0d152222-0000-0000-0000-000000000001'),
  null::numeric,
  'the owner clears the official distance'
);
update routes set official_distance_m = 42195 where id = '0d152222-0000-0000-0000-000000000001';

-- ── another runner cannot write it ─────────────────────────────────────────
set local "request.jwt.claims" = '{"sub":"0d150000-0000-0000-0000-000000000002","role":"authenticated"}';
update routes set official_distance_m = 40000 where id = '0d152222-0000-0000-0000-000000000001';
reset role;
-- 5.
select is(
  (select official_distance_m from routes where id = '0d152222-0000-0000-0000-000000000001'),
  42195::numeric,
  'a non-owner update writes nothing'
);

-- ── public reads ───────────────────────────────────────────────────────────
set local role anon;
set local "request.jwt.claims" = '';
-- 6.
select is(
  (select official_distance_m from public_routes where id = '0d152222-0000-0000-0000-000000000001'),
  42195::numeric,
  'anon reads the official distance through public_routes'
);
-- 7. The traced length is still there beside it.
select is(
  (select distance_m from public_routes where id = '0d152222-0000-0000-0000-000000000001'),
  42670::numeric,
  'public_routes keeps the measured distance'
);
-- 8. The explore map's pins carry the shown distance.
select is(
  (select distance_m from discoverable_routes_in_bbox(-78, 37, -77, 38, 100, 'hidden_gems', null, null)
    where id = '0d152222-0000-0000-0000-000000000001'),
  42195::numeric,
  'discoverable_routes_in_bbox returns the official distance as the shown distance'
);
-- 9. The marathon band admits it on the official figure.
select ok(
  exists (select 1 from discoverable_routes_in_bbox(-78, 37, -77, 38, 100, 'hidden_gems', array[42000]::numeric[], array[42400]::numeric[])
    where id = '0d152222-0000-0000-0000-000000000001'),
  'the distance band filters on the shown distance'
);
reset role;

-- ── race link prefill ──────────────────────────────────────────────────────
set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';
insert into race_listings (id, provider, provider_race_id, name, race_date, distance_m, is_verified, route_id)
values
  ('0d153333-0000-0000-0000-000000000001', 'runsignup', 'od-1', 'Half', '2036-11-14', 21097, true,
   '0d152222-0000-0000-0000-000000000002'),
  ('0d153333-0000-0000-0000-000000000002', 'runsignup', 'od-2', '10K', '2036-11-15', 10000, true,
   '0d152222-0000-0000-0000-000000000003'),
  ('0d153333-0000-0000-0000-000000000003', 'runsignup', 'od-3', '50K', '2036-11-16', 50000, true,
   '0d152222-0000-0000-0000-000000000004');
reset role;

-- 10.
select is(
  (select official_distance_m from routes where id = '0d152222-0000-0000-0000-000000000002'),
  21097::numeric,
  'linking a race listing prefills the route''s official distance'
);
-- 11.
select is(
  (select official_distance_m from routes where id = '0d152222-0000-0000-0000-000000000003'),
  10050::numeric,
  'the prefill never overwrites a value the owner set'
);
-- 12.
select is(
  (select official_distance_m from routes where id = '0d152222-0000-0000-0000-000000000004'),
  null::numeric,
  'a listing more than 10% off the traced length prefills nothing'
);

-- 13. Relinking a listing prefills the newly linked route.
set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';
update race_listings set route_id = null where id = '0d153333-0000-0000-0000-000000000003';
update race_listings set route_id = '0d152222-0000-0000-0000-000000000004', distance_m = 42195
where id = '0d153333-0000-0000-0000-000000000003';
reset role;
select is(
  (select official_distance_m from routes where id = '0d152222-0000-0000-0000-000000000004'),
  42195::numeric,
  'relinking a listing prefills the route it now names'
);

-- 14. The race calendar shows the course's official distance.
set local role anon;
set local "request.jwt.claims" = '';
select is(
  (select course_distance_m from public_race_listings where id = '0d153333-0000-0000-0000-000000000001'),
  21097::numeric,
  'public_race_listings.course_distance_m is the official distance'
);
reset role;

select * from finish();
rollback;

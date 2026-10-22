-- Pins 20271021000031: discovery ranks official content and verified clubs
-- first (issue #1190 § 4, decisions § 2228).
--
--   * an official route qualifies for a pin with no runs and no editorial pick;
--   * official routes rank first, at most a quarter of p_limit of them ahead
--     of the community outside the `official` lens; the rest rank after the
--     community and backfill empty slots, so they never crowd it out and
--     never vanish from a sparse viewport;
--   * the `official` lens is uncapped and holds only official routes;
--   * `hidden_gems` never offers an official route;
--   * clubs_in_bbox ranks a verified club above a bigger unverified one.
--
-- Everything sits in an empty patch of the Southern Ocean so seed data and
-- other suites' rows never enter the viewport.

begin;
select plan(10);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('0fd10000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'od-owner@od.local', '', now(), now()),
  ('0fd10000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'od-runner@od.local', '', now(), now())
on conflict (id) do nothing;

insert into clubs (id, owner_id, name, slug, is_public, location_point)
values
  ('0fd11111-0000-0000-0000-000000000001', '0fd10000-0000-0000-0000-000000000001', 'Official Org', 'od-official', true,
   ST_SetSRID(ST_MakePoint(150.15, -40.15), 4326)::geography),
  ('0fd11111-0000-0000-0000-000000000002', '0fd10000-0000-0000-0000-000000000002', 'Big Fan Club', 'od-fan', true,
   ST_SetSRID(ST_MakePoint(150.16, -40.16), 4326)::geography);

set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';
update clubs set is_verified = true where id = '0fd11111-0000-0000-0000-000000000001';
reset role;
-- member_count is trigger-maintained; the fan club is the bigger one.
update clubs set member_count = 500 where id = '0fd11111-0000-0000-0000-000000000002';

-- Six official courses with no runs, four community routes people run, one
-- un-run community gem, all inside the box.
insert into routes (id, user_id, club_id, name, waypoints, distance_m, surface, is_public, run_count)
select
  ('0fd12222-0000-0000-0000-00000000000' || g)::uuid,
  '0fd10000-0000-0000-0000-000000000001',
  '0fd11111-0000-0000-0000-000000000001',
  'Official course ' || g,
  jsonb_build_array(jsonb_build_object('lat', -40.15, 'lng', 150.10 + g * 0.01)),
  5000 + g, 'road', true, 0
from generate_series(1, 6) g;

insert into routes (id, user_id, name, waypoints, distance_m, surface, is_public, run_count)
select
  ('0fd13333-0000-0000-0000-00000000000' || g)::uuid,
  '0fd10000-0000-0000-0000-000000000002',
  'Community loop ' || g,
  jsonb_build_array(jsonb_build_object('lat', -40.12, 'lng', 150.10 + g * 0.01)),
  5000 + g, 'road', true, 10 - g
from generate_series(1, 4) g;

insert into routes (id, user_id, name, waypoints, distance_m, surface, is_public, run_count)
values ('0fd13333-0000-0000-0000-000000000009', '0fd10000-0000-0000-0000-000000000002', 'Quiet gem',
        '[{"lat": -40.13, "lng": 150.18}]'::jsonb, 3000, 'trail', true, 0);

-- 1. Every official route qualifies for a pin under the official lens.
select is(
  (select count(*)::int from discoverable_routes_in_bbox(150.0, -40.3, 150.3, -40.0, 100, 'official')),
  6,
  'the official lens returns every official route in view, uncapped'
);

-- 2. ...and only official routes.
select ok(
  (select bool_and(is_official) from discoverable_routes_in_bbox(150.0, -40.3, 150.3, -40.0, 100, 'official')),
  'the official lens holds only official routes'
);

-- 3. Under the default lens an un-run official route still pins.
select ok(
  exists (select 1 from discoverable_routes_in_bbox(150.0, -40.3, 150.3, -40.0, 100, 'popular') d
          where d.id = '0fd12222-0000-0000-0000-000000000001'),
  'an official route with no runs qualifies for a popular pin'
);

-- 4. The cap: p_limit 8 lets 8 / 4 = 2 official pins rank first...
select results_eq(
  $$ select is_official from discoverable_routes_in_bbox(150.0, -40.3, 150.3, -40.0, 8, 'popular') limit 2 $$,
  $$ values (true), (true) $$,
  'at most a quarter of p_limit official pins rank ahead of the community'
);

-- 5. ...then every community route in view, before any further official one.
select results_eq(
  $$ select id from discoverable_routes_in_bbox(150.0, -40.3, 150.3, -40.0, 8, 'popular') offset 2 limit 4 $$,
  $$ values ('0fd13333-0000-0000-0000-000000000001'::uuid), ('0fd13333-0000-0000-0000-000000000002'::uuid),
            ('0fd13333-0000-0000-0000-000000000003'::uuid), ('0fd13333-0000-0000-0000-000000000004'::uuid) $$,
  'the cap keeps community routes their slots, ranked by run count'
);

-- 6. The cap is a tier, not a filter: official routes past it fill the slots
--    the community leaves empty.
select is(
  (select count(*)::int from discoverable_routes_in_bbox(150.0, -40.3, 150.3, -40.0, 8, 'popular') where is_official),
  4,
  'official routes past the cap backfill the unused slots'
);

-- 7. With room to spare, the cap scales with p_limit (100 / 4 = 25 > 6).
select is(
  (select count(*)::int from discoverable_routes_in_bbox(150.0, -40.3, 150.3, -40.0, 100, 'popular') where is_official),
  6,
  'below the cap every official route pins'
);

-- 8. Hidden gems offers the un-run community route, never an official one.
select results_eq(
  $$ select id from discoverable_routes_in_bbox(150.0, -40.3, 150.3, -40.0, 100, 'hidden_gems') $$,
  $$ values ('0fd13333-0000-0000-0000-000000000009'::uuid) $$,
  'hidden_gems offers un-run community routes, not official ones'
);

-- 9. A verified club outranks a bigger unverified one.
select results_eq(
  $$ select id from clubs_in_bbox(150.0, -40.3, 150.3, -40.0, 100) $$,
  $$ values ('0fd11111-0000-0000-0000-000000000001'::uuid), ('0fd11111-0000-0000-0000-000000000002'::uuid) $$,
  'clubs_in_bbox ranks verified clubs above unverified ones'
);

-- 10. ...and returns the flag for the pin's badge, to a logged-out visitor.
set local role anon;
set local "request.jwt.claims" = '';
select results_eq(
  $$ select is_verified from clubs_in_bbox(150.0, -40.3, 150.3, -40.0, 100) $$,
  $$ values (true), (false) $$,
  'clubs_in_bbox returns is_verified to anon'
);
reset role;

select * from finish();
rollback;

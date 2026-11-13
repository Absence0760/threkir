-- pgtap: a privacy zone covers at least 100 m (migration
-- 20271226001374_privacy_zone_radius_floor, issue #1374 round 3).
--
-- The phone once saved zones from 50 m. Every server-side zone test goes
-- through privacy_in_any_zone, which now reads a smaller radius as 100 m, so
-- clip_track_for_user trims a fix 80 m from a 50 m zone's centre.
-- At 47.37 deg N one degree of longitude is about 75 356 m, so 0.00106 deg
-- east is about 80 m and 0.00146 deg about 110 m.

begin;

select plan(6);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values ('00000000-0000-0000-0000-00000000f101', 'authenticated', 'authenticated',
        'floor@clip.local', '', now(), now());

insert into user_settings (user_id, prefs)
values (
  '00000000-0000-0000-0000-00000000f101',
  jsonb_build_object('privacy_zones', jsonb_build_array(
    jsonb_build_object('lat', 47.37, 'lng', 8.54, 'radius_m', 50)
  ))
);

-- 1. 80 m from a 50 m zone is inside the 100 m floor.
select ok(
  privacy_in_any_zone(47.37, 8.54106,
    '[{"lat": 47.37, "lng": 8.54, "radius_m": 50}]'::jsonb),
  'a 50 m zone covers a point 80 m from its centre'
);

-- 2. 110 m is outside the floor.
select ok(
  not privacy_in_any_zone(47.37, 8.54146,
    '[{"lat": 47.37, "lng": 8.54, "radius_m": 50}]'::jsonb),
  'a 50 m zone does not cover a point 110 m away'
);

-- 3. A radius above the floor is kept as stored.
select ok(
  privacy_in_any_zone(47.37, 8.5423,
    '[{"lat": 47.37, "lng": 8.54, "radius_m": 300}]'::jsonb),
  'a 300 m zone still covers a point about 170 m away'
);

-- 4. A zone with no radius reads as the floor, not as no zone.
select ok(
  privacy_in_any_zone(47.37, 8.54106, '[{"lat": 47.37, "lng": 8.54}]'::jsonb),
  'a zone missing radius_m covers 100 m'
);

-- 5. clip_track_for_user trims the leading fix 80 m from a 50 m zone.
select is(
  jsonb_array_length(clip_track_for_user(
    '00000000-0000-0000-0000-00000000f101',
    '[{"lat": 47.37, "lng": 8.54106}, {"lat": 47.37, "lng": 8.545}, {"lat": 47.37, "lng": 8.55}]'::jsonb
  )),
  2,
  'the clip trims a fix inside the floor of a zone stored at 50 m'
);

-- 6. The helper stays ungranted to client roles (20260711_001).
select ok(
  not has_function_privilege('authenticated',
    'privacy_in_any_zone(double precision, double precision, jsonb)', 'execute'),
  'privacy_in_any_zone is not executable by authenticated'
);

select * from finish();
rollback;

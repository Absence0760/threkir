-- pgtap: a privacy-zone change reaches the points already stored
-- (migrations 20271226021374 / 20271226021375, issue #1374 round 4).
--
-- The runner's pings and the frozen copies of their race course are stored
-- before they add a zone. Adding it (a 50 m zone, read as the 100 m floor)
-- must delete the precise pings inside it, keep a coarse last-seen point,
-- refreeze a race that has not started, clear the derived gate of a race that
-- has, and leave an organiser's gate alone. A later widening reaches what the
-- first zone did not cover.
--
-- At 40 deg N, 0.0005 deg of latitude is about 56 m and 0.005 deg about 556 m.

begin;

select plan(9);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values ('00000000-0000-0000-0000-00000000f201', 'authenticated', 'authenticated',
        'strip@zone.local', '', now(), now());

insert into clubs (id, owner_id, name, slug, is_public)
values ('00000000-0000-0000-0000-00000000f2c1',
        '00000000-0000-0000-0000-00000000f201', 'Strip Club', 'strip-zone-club', true);

insert into events (id, club_id, title, starts_at, author_id, is_public)
values ('00000000-0000-0000-0000-00000000f2e1', '00000000-0000-0000-0000-00000000f2c1',
        'Strip race', '2026-09-01 08:00+00', '00000000-0000-0000-0000-00000000f201', true);

insert into routes (id, user_id, name, waypoints, distance_m, is_public)
values ('00000000-0000-0000-0000-00000000f2b1', '00000000-0000-0000-0000-00000000f201',
        'From home',
        '[{"lat":40.0,"lng":-75.0},{"lat":40.005,"lng":-75.0},{"lat":40.01,"lng":-75.0}]'::jsonb,
        1112, true);

-- Two courses on the route; the second's start line is the organiser's own.
insert into event_courses (id, event_id, name, distance_m, sort_order, route_id)
values
  ('00000000-0000-0000-0000-00000000f2a1', '00000000-0000-0000-0000-00000000f2e1',
   'Derived', 1112, 0, '00000000-0000-0000-0000-00000000f2b1'),
  ('00000000-0000-0000-0000-00000000f2a2', '00000000-0000-0000-0000-00000000f2e1',
   'Placed', 1112, 1, '00000000-0000-0000-0000-00000000f2b1');
update event_courses
   set start_gate_source = 'organiser', start_gate_lat = 40.0001, start_gate_lng = -75.0,
       start_gate_bearing_deg = 0, start_gate_half_width_m = 20
 where id = '00000000-0000-0000-0000-00000000f2a2';

-- One race not started yet, one under way. Each freezes its copy on insert.
insert into race_sessions (event_id, instance_start, status)
values ('00000000-0000-0000-0000-00000000f2e1', '2026-09-01 08:00+00', 'armed');
insert into race_sessions (event_id, instance_start, status, started_at)
values ('00000000-0000-0000-0000-00000000f2e1', '2026-09-08 08:00+00', 'running', now());

insert into runs (id, user_id, started_at, distance_m, duration_s, source, is_public, metadata)
values ('00000000-0000-0000-0000-00000000f2d1', '00000000-0000-0000-0000-00000000f201',
        now(), 1000, 600, 'app', true, '{"activity_type":"run"}');

-- No zone yet, so every ping lands at full precision.
insert into live_run_pings (run_id, user_id, lat, lng)
values
  ('00000000-0000-0000-0000-00000000f2d1', '00000000-0000-0000-0000-00000000f201', 40.0005, -75.0),
  ('00000000-0000-0000-0000-00000000f2d1', '00000000-0000-0000-0000-00000000f201', 40.0015, -75.0),
  ('00000000-0000-0000-0000-00000000f2d1', '00000000-0000-0000-0000-00000000f201', 40.005, -75.0);
insert into race_pings (event_id, instance_start, user_id, at, lat, lng, coarse)
values
  ('00000000-0000-0000-0000-00000000f2e1', '2026-09-08 08:00+00',
   '00000000-0000-0000-0000-00000000f201', now(), 40.0005, -75.0, false),
  ('00000000-0000-0000-0000-00000000f2e1', '2026-09-08 08:00+00',
   '00000000-0000-0000-0000-00000000f201', now(), 40.0, -75.0, true);

select is(
  (select count(*)::int from race_session_courses
    where course_id = '00000000-0000-0000-0000-00000000f2a1'
      and start_gate_lat = 40.0),
  2,
  'both frozen copies start with the derived start line on the route''s first point'
);

-- The runner adds a 50 m zone round the start, read as 100 m.
insert into user_settings (user_id, prefs)
values ('00000000-0000-0000-0000-00000000f201',
        '{"privacy_zones":[{"lat":40.0,"lng":-75.0,"radius_m":50}]}'::jsonb);

select is(
  (select array_agg(lat order by lat) from live_run_pings
    where user_id = '00000000-0000-0000-0000-00000000f201'),
  array[40.0015, 40.005]::double precision[],
  'the precise live ping 56 m from the zone centre is deleted; those outside stay'
);

select is(
  (select array_agg(coarse order by coarse) from race_pings
    where user_id = '00000000-0000-0000-0000-00000000f201'),
  array[true],
  'the precise race ping inside the zone is deleted; the coarse last-seen stays'
);

select is(
  (select start_gate_lat from race_session_courses
    where course_id = '00000000-0000-0000-0000-00000000f2a1'
      and instance_start = '2026-09-01 08:00+00'),
  null,
  'the race not yet started is frozen again, without the start line the zone now covers'
);

select is(
  (select coalesce(start_gate_lat::text, 'none') || '|' || finish_gate_lat
     from race_session_courses
    where course_id = '00000000-0000-0000-0000-00000000f2a1'
      and instance_start = '2026-09-08 08:00+00'),
  'none|40.01',
  'the race under way loses only its derived start line inside the zone'
);

select is(
  (select start_gate_lat from race_session_courses
    where course_id = '00000000-0000-0000-0000-00000000f2a2'
      and instance_start = '2026-09-08 08:00+00'),
  40.0001::double precision,
  'an organiser''s start line in the race under way is kept'
);

select is(
  (select count(*)::int from race_session_courses
    where course_id = '00000000-0000-0000-0000-00000000f2a1'
      and instance_start = '2026-09-08 08:00+00'
      and start_gate_bearing_deg is null and start_gate_half_width_m is null),
  1,
  'the cleared start line is cleared whole'
);

-- Widening the zone to 300 m reaches the ping 167 m out.
update user_settings
   set prefs = '{"privacy_zones":[{"lat":40.0,"lng":-75.0,"radius_m":300}]}'::jsonb
 where user_id = '00000000-0000-0000-0000-00000000f201';

select is(
  (select array_agg(lat order by lat) from live_run_pings
    where user_id = '00000000-0000-0000-0000-00000000f201'),
  array[40.005]::double precision[],
  'widening the zone deletes the stored ping it now covers'
);

select ok(
  not has_function_privilege('authenticated',
    'private.strip_stored_in_zone_points(uuid)', 'execute'),
  'strip_stored_in_zone_points is not executable by authenticated'
);

select * from finish();
rollback;

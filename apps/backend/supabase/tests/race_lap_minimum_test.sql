-- Pins migration 20271222002472 (a lap course's minimum covered distance,
-- #1304, decisions § 2472).
--
--   1-3.  A route drawn as one closed lap and raced k times: D - G / 2, never
--         under 60 % of D; an open route raced the same way has none.
--   4-5.  A route drawn with its laps: the last two finish crossings' spacing,
--         scaled to the course distance; with no distance, the drawn length.
--   6-9.  No minimum: a single loop, a straight route, no route, no line.
--   10-11. Arm freezes it per course: the lap course's minimum, and null for
--         a routeless course.
--   12.   The CHECK refuses a non-positive minimum.

begin;
select plan(12);

-- The drawn length the function measures: gate_plane_xy between neighbours.
create function pg_temp.geom_len(p jsonb) returns double precision
language sql immutable as $$
  select coalesce(sum(sqrt(g.x ^ 2 + g.y ^ 2)), 0)
    from generate_series(1, jsonb_array_length(p) - 1) i,
         lateral private.gate_plane_xy((p -> (i - 1) ->> 0)::float8, (p -> (i - 1) ->> 1)::float8,
                                       (p -> i ->> 0)::float8, (p -> i ->> 1)::float8) g
$$;

-- One square lap: east, north, west, south back to the start, arriving
-- heading south onto a finish line at the start point.
create temp table lap_geom as
select '[[41.0,-75.0],[41.0,-74.99],[41.01,-74.99],[41.01,-75.0],[41.0,-75.0]]'::jsonb as one,
       '[[41.0,-75.0],[41.0,-74.99],[41.01,-74.99],[41.01,-75.0],[41.0,-75.0],
         [41.0,-74.99],[41.01,-74.99],[41.01,-75.0],[41.0,-75.0],
         [41.0,-74.99],[41.01,-74.99],[41.01,-75.0],[41.0,-75.0]]'::jsonb as three,
       '[[40.0,-75.0],[40.005,-75.0],[40.01,-75.0]]'::jsonb as straight,
       -- The same square entered 1 km south of it: open, so not one lap.
       '[[40.991,-75.0],[41.0,-75.0],[41.0,-74.99],[41.01,-74.99],[41.01,-75.0],[41.0,-75.0]]'::jsonb as open;

-- ── 1-3: one lap drawn ──────────────────────────────────────────────────────

select is(
  (select round(private.course_finish_min_coverage_m(one, 41.0, -75.0, 180, 15, 3 * pg_temp.geom_len(one))::numeric, 6)
     from lap_geom),
  (select round((3 * pg_temp.geom_len(one) - pg_temp.geom_len(one) / 2)::numeric, 6) from lap_geom),
  '1: a closed lap raced three times needs the distance less half a lap');

select is(
  (select round(private.course_finish_min_coverage_m(one, 41.0, -75.0, 180, 15, 2 * pg_temp.geom_len(one))::numeric, 6)
     from lap_geom),
  (select round((1.5 * pg_temp.geom_len(one))::numeric, 6) from lap_geom),
  '2: two laps need one and a half, above the 60 % share');

select is(
  (select private.course_finish_min_coverage_m(open, 41.0, -75.0, 180, 15, 3 * pg_temp.geom_len(open))
     from lap_geom),
  null,
  '3: an open route raced past its drawn length is not a lap: no minimum');

-- ── 4-5: laps drawn ─────────────────────────────────────────────────────────

select is(
  (select round(private.course_finish_min_coverage_m(three, 41.0, -75.0, 180, 15, 11400)::numeric, 6)
     from lap_geom),
  9500.000000::numeric,
  '4: three laps drawn: a lap is a third of 11400, so 11400 - 1900');

select is(
  (select round(private.course_finish_min_coverage_m(three, 41.0, -75.0, 180, 15, null)::numeric, 6)
     from lap_geom),
  (select round((pg_temp.geom_len(three) * 5 / 6)::numeric, 6) from lap_geom),
  '5: with no course distance the drawn length stands in for it');

-- ── 6-9: none ───────────────────────────────────────────────────────────────

select is(
  (select private.course_finish_min_coverage_m(one, 41.0, -75.0, 180, 15, pg_temp.geom_len(one))
     from lap_geom),
  null,
  '6: a single loop crosses its finish once: no minimum');

select is(
  (select private.course_finish_min_coverage_m(straight, 40.01, -75.0, 0, 15, 1112) from lap_geom),
  null,
  '7: a straight route has no minimum');

select is(
  private.course_finish_min_coverage_m('[]'::jsonb, 41.0, -75.0, 180, 15, 3000),
  null,
  '8: no route, no minimum (the detectors measure the lap)');

select is(
  (select private.course_finish_min_coverage_m(three, null, null, null, null, 11400) from lap_geom),
  null,
  '9: no finish line, no minimum');

-- ── 10-11: frozen at Arm ────────────────────────────────────────────────────

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values ('e2472000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
        'lap-organiser@evt.local', '', now(), now());

set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';

insert into clubs (id, owner_id, name, slug, is_public)
values ('e2472000-0000-0000-0000-0000000000c1',
        'e2472000-0000-0000-0000-000000000001', 'Lap Club', 'lap-minimum-c', true);

insert into events (id, club_id, title, starts_at, author_id, is_public)
values ('e2472000-0000-0000-0000-0000000000e1', 'e2472000-0000-0000-0000-0000000000c1',
        'Three laps of the park', '2026-09-01 08:00+00',
        'e2472000-0000-0000-0000-000000000001', true);

insert into routes (id, user_id, name, waypoints, distance_m, is_public)
values ('e2472000-0000-0000-0000-0000000000b1', 'e2472000-0000-0000-0000-000000000001',
        'One lap',
        '[{"lat":41.0,"lng":-75.0},{"lat":41.0,"lng":-74.99},{"lat":41.01,"lng":-74.99},
          {"lat":41.01,"lng":-75.0},{"lat":41.0,"lng":-75.0}]'::jsonb,
        3800, false);

insert into event_courses (id, event_id, name, distance_m, sort_order, route_id)
values
  ('e2472000-0000-0000-0000-0000000000a1', 'e2472000-0000-0000-0000-0000000000e1',
   'Three laps', 11400, 0, 'e2472000-0000-0000-0000-0000000000b1'),
  ('e2472000-0000-0000-0000-0000000000a2', 'e2472000-0000-0000-0000-0000000000e1',
   'Routeless', 3000, 1, null);

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"e2472000-0000-0000-0000-000000000001","role":"authenticated"}';

insert into race_sessions (event_id, instance_start, status)
values ('e2472000-0000-0000-0000-0000000000e1', '2026-09-01 08:00+00', 'armed');

reset role;

select is(
  (select round(s.finish_min_coverage_m::numeric, 6)
     from race_session_courses s
    where s.course_id = 'e2472000-0000-0000-0000-0000000000a1'),
  (select round((11400 - pg_temp.geom_len(one) / 2)::numeric, 6) from lap_geom),
  '10: Arm freezes the lap course''s minimum: 11400 less half the drawn lap');

select is(
  (select finish_min_coverage_m from race_session_courses
    where course_id = 'e2472000-0000-0000-0000-0000000000a2'),
  null,
  '11: a routeless course freezes no minimum');

-- ── 12: the CHECK ───────────────────────────────────────────────────────────

set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';
select throws_ok(
  $$ update race_session_courses set finish_min_coverage_m = 0
      where course_id = 'e2472000-0000-0000-0000-0000000000a1' $$,
  '23514', null,
  '12: the lap-minimum CHECK refuses a non-positive minimum');
reset role;

select * from finish();
rollback;

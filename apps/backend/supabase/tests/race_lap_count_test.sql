-- Pins migration 20271222002472 (a lap course's lap count, #1304, decisions
-- § 2472).
--
--   1-4.   A route drawn as one closed lap and raced round(D / G) times: 3
--          and 2 laps; an open route raced past its drawn length, and a route
--          whose last point does not come back to its first, have none.
--   5-6.   A route drawn with its laps: its passes, with or without a
--          distance.
--   7-11.  No count: a single loop, a straight route, no route, no finish
--          line, a lap under 50 m.
--   12-13. Arm freezes it per course: the lap course's count, and null for a
--          routeless course.
--   14.    The CHECK refuses a count under 2.

begin;
select plan(14);

-- The drawn length the function measures: gate_plane_xy between neighbours.
create function pg_temp.geom_len(p jsonb) returns double precision
language sql immutable as $$
  select coalesce(sum(sqrt(g.x ^ 2 + g.y ^ 2)), 0)
    from generate_series(1, jsonb_array_length(p) - 1) i,
         lateral private.gate_plane_xy((p -> (i - 1) ->> 0)::float8, (p -> (i - 1) ->> 1)::float8,
                                       (p -> i ->> 0)::float8, (p -> i ->> 1)::float8) g
$$;

-- One square lap (about 3.9 km): east, north, west, south back to the start,
-- arriving heading south onto a finish line at the start point.
create temp table lap_geom as
select '[[41.0,-75.0],[41.0,-74.99],[41.01,-74.99],[41.01,-75.0],[41.0,-75.0]]'::jsonb as one,
       '[[41.0,-75.0],[41.0,-74.99],[41.01,-74.99],[41.01,-75.0],[41.0,-75.0],
         [41.0,-74.99],[41.01,-74.99],[41.01,-75.0],[41.0,-75.0],
         [41.0,-74.99],[41.01,-74.99],[41.01,-75.0],[41.0,-75.0]]'::jsonb as three,
       '[[40.0,-75.0],[40.005,-75.0],[40.01,-75.0]]'::jsonb as straight,
       -- The same square entered 1 km south of it: open, so not one lap.
       '[[40.991,-75.0],[41.0,-75.0],[41.0,-74.99],[41.01,-74.99],[41.01,-75.0],[41.0,-75.0]]'::jsonb as open,
       -- Starts on the line, but runs on 556 m south past it at the end.
       '[[41.0,-75.0],[41.0,-74.99],[41.01,-74.99],[41.01,-75.0],[40.995,-75.0]]'::jsonb as runs_on,
       -- A square about 11 m by 8 m.
       '[[41.0,-75.0],[41.0,-74.9999],[41.0001,-74.9999],[41.0001,-75.0],[41.0,-75.0]]'::jsonb as tiny;

-- ── 1-4: one lap drawn ──────────────────────────────────────────────────────

select is(
  (select private.course_finish_lap_count(one, 41.0, -75.0, 180, 15, 41.0, -75.0, 3 * pg_temp.geom_len(one))
     from lap_geom),
  3,
  '1: a closed lap raced three times passes its finish three times');

select is(
  (select private.course_finish_lap_count(one, 41.0, -75.0, 180, 15, 41.0, -75.0, 2.4 * pg_temp.geom_len(one))
     from lap_geom),
  2,
  '2: 2.4 drawn laps of distance round to 2 laps');

select is(
  (select private.course_finish_lap_count(open, 41.0, -75.0, 180, 15, 40.991, -75.0, 3 * pg_temp.geom_len(open))
     from lap_geom),
  null,
  '3: an open route raced past its drawn length is not a lap: no count');

select is(
  (select private.course_finish_lap_count(runs_on, 41.0, -75.0, 180, 15, 41.0, -75.0, 3 * pg_temp.geom_len(runs_on))
     from lap_geom),
  null,
  '4: a route starting on the line but ending 556 m from its start is not closed: no count');

-- ── 5-6: laps drawn ─────────────────────────────────────────────────────────

select is(
  (select private.course_finish_lap_count(three, 41.0, -75.0, 180, 15, 41.0, -75.0, 11400) from lap_geom),
  3,
  '5: three laps drawn pass the finish three times');

select is(
  (select private.course_finish_lap_count(three, 41.0, -75.0, 180, 15, 41.0, -75.0, null) from lap_geom),
  3,
  '6: counting needs no course distance');

-- ── 7-11: none ──────────────────────────────────────────────────────────────

select is(
  (select private.course_finish_lap_count(one, 41.0, -75.0, 180, 15, 41.0, -75.0, pg_temp.geom_len(one))
     from lap_geom),
  null,
  '7: a single loop passes its finish once: no count');

select is(
  (select private.course_finish_lap_count(straight, 40.01, -75.0, 0, 15, 40.0, -75.0, 1112) from lap_geom),
  null,
  '8: a straight route has no count');

select is(
  private.course_finish_lap_count('[]'::jsonb, 41.0, -75.0, 180, 15, 41.0, -75.0, 3000),
  null,
  '9: no route, no count (the detectors measure the lap)');

select is(
  (select private.course_finish_lap_count(three, null, null, null, null, 41.0, -75.0, 11400) from lap_geom),
  null,
  '10: no finish line, no count');

select is(
  (select private.course_finish_lap_count(tiny, 41.0, -75.0, 180, 15, 41.0, -75.0, 400) from lap_geom),
  null,
  '11: a lap under 50 m is no lap, however many times the distance asks for it');

-- ── 12-13: frozen at Arm ────────────────────────────────────────────────────

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values ('e2472000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
        'lap-organiser@evt.local', '', now(), now());

set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';

insert into clubs (id, owner_id, name, slug, is_public)
values ('e2472000-0000-0000-0000-0000000000c1',
        'e2472000-0000-0000-0000-000000000001', 'Lap Club', 'lap-count-c', true);

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
  (select finish_lap_count from race_session_courses
    where course_id = 'e2472000-0000-0000-0000-0000000000a1'),
  3,
  '12: Arm freezes the lap course''s count: the 3.9 km lap raced round(11400 / G) = 3 times');

select is(
  (select finish_lap_count from race_session_courses
    where course_id = 'e2472000-0000-0000-0000-0000000000a2'),
  null,
  '13: a routeless course freezes no count');

-- ── 14: the CHECK ───────────────────────────────────────────────────────────

set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';
select throws_ok(
  $$ update race_session_courses set finish_lap_count = 1
      where course_id = 'e2472000-0000-0000-0000-0000000000a1' $$,
  '23514', null,
  '14: the lap-count CHECK refuses a count under 2');
reset role;

select * from finish();
rollback;

-- Pins migration 20271116002390 (timing lines phase 2, #1305, decisions § 2390).
--
--   1-6.   Derived lines from the clipped route: a straight route, a loop, and
--          a route whose start the owner's zone clipped (no start line, a
--          finish line), each at the default 15 m half-width.
--   7-8.   finish_line_self_cross: off on a single loop, on for three laps.
--   9-12.  The organiser RPCs: only an organiser, no privacy-zone check, a
--          routeless course takes both lines, anon cannot call.
--   13-15. A waypoint edit recomputes a derived line and leaves an organiser's
--          alone; reset returns a line to the route, or to none.
--   16.    A client writing the line columns directly changes nothing.
--   17-21. The CHECKs: the RPC's own refusal of an out-of-range width, then
--          half-width, bearing and all-or-none on an organiser line, and the
--          source allowlist, validated.
--   22-25. The snapshot: taken at Arm, holding the lines of the moment, not
--          moved by a later route edit, linked from race_sessions_redacted.
--   26.    A client cannot clear courses_frozen_at.
--   27-29. Reads follow the event: anon reads a public event's lines and
--          frozen copy, and not a private club's.

begin;
select plan(29);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('e2390000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
   'tl-organiser@evt.local', '', now(), now()),
  ('e2390000-0000-0000-0000-000000000002', 'authenticated', 'authenticated',
   'tl-stranger@evt.local', '', now(), now()),
  ('e2390000-0000-0000-0000-000000000003', 'authenticated', 'authenticated',
   'tl-member@evt.local', '', now(), now());

set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';

insert into clubs (id, owner_id, name, slug, is_public)
values
  ('e2390000-0000-0000-0000-0000000000c1',
   'e2390000-0000-0000-0000-000000000001', 'Line Club', 'timing-lines-c', true),
  ('e2390000-0000-0000-0000-0000000000c2',
   'e2390000-0000-0000-0000-000000000001', 'Private Line Club', 'timing-lines-p', false);

insert into club_members (club_id, user_id, role, status)
values ('e2390000-0000-0000-0000-0000000000c1',
        'e2390000-0000-0000-0000-000000000003', 'member', 'active');

insert into events (id, club_id, title, starts_at, author_id, is_public)
values
  ('e2390000-0000-0000-0000-0000000000e1', 'e2390000-0000-0000-0000-0000000000c1',
   'Line race', '2026-09-01 08:00+00', 'e2390000-0000-0000-0000-000000000001', true),
  ('e2390000-0000-0000-0000-0000000000e2', 'e2390000-0000-0000-0000-0000000000c2',
   'Private line race', '2026-09-01 08:00+00', 'e2390000-0000-0000-0000-000000000001', false);

-- The stranger's zone covers (42.0, -75.0), the first point of their route.
insert into user_settings (user_id, prefs)
values ('e2390000-0000-0000-0000-000000000002',
        '{"privacy_zones":[{"lat":42.0,"lng":-75.0,"radius_m":200}]}'::jsonb);

insert into routes (id, user_id, name, waypoints, distance_m, is_public)
values
  -- Due north, 1.1 km.
  ('e2390000-0000-0000-0000-0000000000b1', 'e2390000-0000-0000-0000-000000000001',
   'Straight',
   '[{"lat":40.0,"lng":-75.0},{"lat":40.005,"lng":-75.0},{"lat":40.01,"lng":-75.0}]'::jsonb,
   1112, false),
  -- One square lap: east, north, west, south back to the start.
  ('e2390000-0000-0000-0000-0000000000b2', 'e2390000-0000-0000-0000-000000000001',
   'Loop',
   '[{"lat":41.0,"lng":-75.0},{"lat":41.0,"lng":-74.99},{"lat":41.01,"lng":-74.99},
     {"lat":41.01,"lng":-75.0},{"lat":41.0,"lng":-75.0}]'::jsonb,
   3800, false),
  -- The same square three times.
  ('e2390000-0000-0000-0000-0000000000b3', 'e2390000-0000-0000-0000-000000000001',
   'Three laps',
   '[{"lat":41.0,"lng":-75.0},{"lat":41.0,"lng":-74.99},{"lat":41.01,"lng":-74.99},
     {"lat":41.01,"lng":-75.0},{"lat":41.0,"lng":-75.0},
     {"lat":41.0,"lng":-74.99},{"lat":41.01,"lng":-74.99},
     {"lat":41.01,"lng":-75.0},{"lat":41.0,"lng":-75.0},
     {"lat":41.0,"lng":-74.99},{"lat":41.01,"lng":-74.99},
     {"lat":41.01,"lng":-75.0},{"lat":41.0,"lng":-75.0}]'::jsonb,
   11400, false),
  -- The stranger's public route, starting inside their zone.
  ('e2390000-0000-0000-0000-0000000000b4', 'e2390000-0000-0000-0000-000000000002',
   'Starts at home',
   '[{"lat":42.0,"lng":-75.0},{"lat":42.005,"lng":-75.0},{"lat":42.01,"lng":-75.0}]'::jsonb,
   1112, true);

insert into event_courses (id, event_id, name, distance_m, sort_order)
values
  ('e2390000-0000-0000-0000-0000000000a1', 'e2390000-0000-0000-0000-0000000000e1', 'Straight', 1112, 0),
  ('e2390000-0000-0000-0000-0000000000a2', 'e2390000-0000-0000-0000-0000000000e1', 'Loop', 3800, 1),
  ('e2390000-0000-0000-0000-0000000000a3', 'e2390000-0000-0000-0000-0000000000e1', 'Laps', 11400, 2),
  ('e2390000-0000-0000-0000-0000000000a4', 'e2390000-0000-0000-0000-0000000000e1', 'Clipped', 1112, 3),
  ('e2390000-0000-0000-0000-0000000000a5', 'e2390000-0000-0000-0000-0000000000e1', 'Routeless', null, 4),
  ('e2390000-0000-0000-0000-0000000000a6', 'e2390000-0000-0000-0000-0000000000e2', 'Private', 1112, 0);

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"e2390000-0000-0000-0000-000000000001","role":"authenticated"}';

update event_courses set route_id = 'e2390000-0000-0000-0000-0000000000b1'
 where id in ('e2390000-0000-0000-0000-0000000000a1', 'e2390000-0000-0000-0000-0000000000a6');
update event_courses set route_id = 'e2390000-0000-0000-0000-0000000000b2'
 where id = 'e2390000-0000-0000-0000-0000000000a2';
update event_courses set route_id = 'e2390000-0000-0000-0000-0000000000b3'
 where id = 'e2390000-0000-0000-0000-0000000000a3';
update event_courses set route_id = 'e2390000-0000-0000-0000-0000000000b4'
 where id = 'e2390000-0000-0000-0000-0000000000a4';

-- ── 1-6: derived lines ──────────────────────────────────────────────────────
-- Bearings are rounded to 0.1 degree: 25 m along a due-north line is 0 up to
-- floating-point residue, which can land a hair under 360.

select is(
  (select start_gate_source || '|' || start_gate_lat || ',' || start_gate_lng || '|'
          || (round(start_gate_bearing_deg::numeric, 1) % 360) || '|' || start_gate_half_width_m
     from event_courses where id = 'e2390000-0000-0000-0000-0000000000a1'),
  'derived|40,-75|0.0|15',
  '1: a straight route''s start line sits on its first point, facing along it, 15 m wide');

select is(
  (select finish_gate_source || '|' || finish_gate_lat || ',' || finish_gate_lng || '|'
          || (round(finish_gate_bearing_deg::numeric, 1) % 360)
     from event_courses where id = 'e2390000-0000-0000-0000-0000000000a1'),
  'derived|40.01,-75|0.0',
  '2: its finish line sits on its last point, facing the way it arrives');

select is(
  (select round(start_gate_bearing_deg::numeric, 1) || '|' || round(finish_gate_bearing_deg::numeric, 1)
     from event_courses where id = 'e2390000-0000-0000-0000-0000000000a2'),
  '90.0|180.0',
  '3: a loop leaves east and arrives heading south');

select is(
  (select num_nulls(start_gate_lat, start_gate_lng, start_gate_bearing_deg,
                    start_gate_half_width_m, start_gate_source)
     from event_courses where id = 'e2390000-0000-0000-0000-0000000000a4'),
  5,
  '4: an end the owner''s zone clipped has no line');

select is(
  (select finish_gate_source || '|' || finish_gate_lat || ',' || finish_gate_lng
     from event_courses where id = 'e2390000-0000-0000-0000-0000000000a4'),
  'derived|42.01,-75',
  '5: the end the clip left whole keeps its line');

select is(
  (select num_nulls(start_gate_source, finish_gate_source)
     from event_courses where id = 'e2390000-0000-0000-0000-0000000000a5'),
  2,
  '6: a routeless course has no derived line');

-- ── 7-8: self-crossing ─────────────────────────────────────────────────────

select is(
  (select finish_line_self_cross from event_courses where id = 'e2390000-0000-0000-0000-0000000000a2'),
  false,
  '7: a single loop crosses its finish line once, at the end');

select is(
  (select finish_line_self_cross from event_courses where id = 'e2390000-0000-0000-0000-0000000000a3'),
  true,
  '8: three laps cross the finish line two thirds of the way round');

-- ── 9-12: the organiser RPCs ───────────────────────────────────────────────

set local "request.jwt.claims" = '{"sub":"e2390000-0000-0000-0000-000000000003","role":"authenticated"}';
select throws_ok(
  $$ select set_event_course_gate('e2390000-0000-0000-0000-0000000000a1', 'finish',
                                  40.009, -75.0, 0, 20) $$,
  '42501', null,
  '9: a plain member cannot place a line');

set local role anon;
set local "request.jwt.claims" = '{"role":"anon"}';
select throws_ok(
  $$ select set_event_course_gate('e2390000-0000-0000-0000-0000000000a1', 'finish',
                                  40.009, -75.0, 0, 20) $$,
  '42501', null,
  '10: anon cannot call the RPC at all');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"e2390000-0000-0000-0000-000000000001","role":"authenticated"}';

-- Inside the stranger's zone, on the course that uses their route.
select lives_ok(
  $$ select set_event_course_gate('e2390000-0000-0000-0000-0000000000a4', 'start',
                                  42.0, -75.0, 360, 20) $$,
  '11: an organiser line is not checked against anyone''s privacy zone');

select set_event_course_gate('e2390000-0000-0000-0000-0000000000a5', 'start', 43.0, -75.0, -90, 10);
select set_event_course_gate('e2390000-0000-0000-0000-0000000000a5', 'finish', 43.001, -75.0, 450, 12);
select is(
  (select start_gate_source || '|' || start_gate_bearing_deg || '|' || start_gate_half_width_m
          || '|' || finish_gate_source || '|' || finish_gate_bearing_deg
     from event_courses where id = 'e2390000-0000-0000-0000-0000000000a5'),
  'organiser|270|10|organiser|90',
  '12: a routeless course takes both lines, the direction normalised into [0, 360)');

-- ── 13-15: recompute, and reset ────────────────────────────────────────────

select set_event_course_gate('e2390000-0000-0000-0000-0000000000a1', 'finish', 40.009, -75.0, 0, 20);

set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';
-- The route now runs due east.
update routes
   set waypoints = '[{"lat":40.0,"lng":-75.0},{"lat":40.0,"lng":-74.995},{"lat":40.0,"lng":-74.99}]'::jsonb
 where id = 'e2390000-0000-0000-0000-0000000000b1';
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"e2390000-0000-0000-0000-000000000001","role":"authenticated"}';

select is(
  (select start_gate_source || '|' || round(start_gate_bearing_deg::numeric, 1)
     from event_courses where id = 'e2390000-0000-0000-0000-0000000000a1'),
  'derived|90.0',
  '13: a waypoint edit turns the derived start line with the route');

select is(
  (select finish_gate_source || '|' || finish_gate_lat || ',' || finish_gate_lng || '|'
          || finish_gate_bearing_deg || '|' || finish_gate_half_width_m
     from event_courses where id = 'e2390000-0000-0000-0000-0000000000a1'),
  'organiser|40.009,-75|0|20',
  '14: the organiser''s finish line survives the recompute');

select reset_event_course_gate('e2390000-0000-0000-0000-0000000000a1', 'finish');
select reset_event_course_gate('e2390000-0000-0000-0000-0000000000a5', 'finish');
select is(
  (select c1.finish_gate_source || '|' || c1.finish_gate_lat || ',' || c1.finish_gate_lng
          || '|' || round(c1.finish_gate_bearing_deg::numeric, 1)
          || '|' || num_nulls(c5.finish_gate_lat, c5.finish_gate_source)
     from event_courses c1, event_courses c5
    where c1.id = 'e2390000-0000-0000-0000-0000000000a1'
      and c5.id = 'e2390000-0000-0000-0000-0000000000a5'),
  'derived|40,-74.99|90.0|2',
  '15: reset returns a line to the route''s, or to none on a routeless course');

-- ── 16: no direct client write ─────────────────────────────────────────────

update event_courses
   set start_gate_lat = 0, start_gate_lng = 0, start_gate_bearing_deg = 45,
       start_gate_half_width_m = 99, start_gate_source = 'organiser',
       finish_line_self_cross = true
 where id = 'e2390000-0000-0000-0000-0000000000a2';
select is(
  (select start_gate_source || '|' || start_gate_lat || '|' || round(start_gate_bearing_deg::numeric, 1)
          || '|' || finish_line_self_cross
     from event_courses where id = 'e2390000-0000-0000-0000-0000000000a2'),
  'derived|41|90.0|false',
  '16: a client update of the line columns is ignored');

-- ── 17-21: CHECKs ──────────────────────────────────────────────────────────

select throws_ok(
  $$ select set_event_course_gate('e2390000-0000-0000-0000-0000000000a5', 'finish',
                                  43.0, -75.0, 0, 3) $$,
  '22023', null,
  '17: the RPC refuses a half-width under 5 m');

set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';

select throws_ok(
  $$ update event_courses set start_gate_half_width_m = 101
      where id = 'e2390000-0000-0000-0000-0000000000a5' $$,
  '23514', null,
  '18: the half-width CHECK refuses over 100 m');

select throws_ok(
  $$ update event_courses set start_gate_bearing_deg = 360
      where id = 'e2390000-0000-0000-0000-0000000000a4' $$,
  '23514', null,
  '19: the bearing CHECK refuses 360');

select throws_ok(
  $$ update event_courses set start_gate_bearing_deg = null
      where id = 'e2390000-0000-0000-0000-0000000000a5' $$,
  '23514', null,
  '20: an organiser line missing its direction fails the all-or-none CHECK');

-- An unknown source never reaches the CHECK through a write (the derivation
-- takes any end that is not the organiser's), so the constraint itself is read:
-- both ends' allowlists, validated by 20271116002391.
select is(
  (select string_agg(conname || '=' || convalidated
                     || '=' || (pg_get_constraintdef(oid) like '%''derived''%''organiser''%'),
                     ',' order by conname)
     from pg_constraint
    where conrelid = 'public.event_courses'::regclass
      and conname in ('event_courses_start_gate_source_check', 'event_courses_finish_gate_source_check')),
  'event_courses_finish_gate_source_check=true=true,event_courses_start_gate_source_check=true=true',
  '21: both source CHECKs allow only derived and organiser, and are validated');

-- ── 22-25: the snapshot at Arm ─────────────────────────────────────────────

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"e2390000-0000-0000-0000-000000000001","role":"authenticated"}';

insert into race_sessions (event_id, instance_start, status)
values ('e2390000-0000-0000-0000-0000000000e1', '2026-09-01 08:00+00', 'armed');

select is(
  (select count(*)::int from race_session_courses
    where event_id = 'e2390000-0000-0000-0000-0000000000e1'
      and instance_start = '2026-09-01 08:00+00'),
  5,
  '22: arming freezes every course of the event');

select is(
  (select s.start_gate_lat || ',' || s.start_gate_lng || '|' || round(s.start_gate_bearing_deg::numeric, 1)
          || '|' || s.finish_lat || ',' || s.finish_lng || '|' || s.distance_m
     from race_session_courses s
    where s.course_id = 'e2390000-0000-0000-0000-0000000000a1'),
  '40,-75|90.0|40,-74.99|1112',
  '23: the frozen copy holds the lines, finish point and distance of the moment');

set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';
update routes
   set waypoints = '[{"lat":40.0,"lng":-75.0},{"lat":40.005,"lng":-75.0},{"lat":40.01,"lng":-75.0}]'::jsonb
 where id = 'e2390000-0000-0000-0000-0000000000b1';
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"e2390000-0000-0000-0000-000000000001","role":"authenticated"}';

select is(
  (select round(s.start_gate_bearing_deg::numeric, 1) || '|'
          || round(c.start_gate_bearing_deg::numeric, 1) % 360
     from race_session_courses s
     join event_courses c on c.id = s.course_id
    where s.course_id = 'e2390000-0000-0000-0000-0000000000a1'),
  '90.0|0.0',
  '24: a route edit after Arm moves the course, not the frozen copy');

select isnt(
  (select courses_frozen_at from race_sessions_redacted
    where event_id = 'e2390000-0000-0000-0000-0000000000e1'
      and instance_start = '2026-09-01 08:00+00'),
  null,
  '25: race_sessions_redacted links the frozen copy');

-- ── 26: courses_frozen_at is the server's ──────────────────────────────────

update race_sessions set courses_frozen_at = null
 where event_id = 'e2390000-0000-0000-0000-0000000000e1'
   and instance_start = '2026-09-01 08:00+00';
select isnt(
  (select courses_frozen_at from race_sessions
    where event_id = 'e2390000-0000-0000-0000-0000000000e1'
      and instance_start = '2026-09-01 08:00+00'),
  null,
  '26: a client cannot clear courses_frozen_at');

-- ── 27-29: reads follow the event ──────────────────────────────────────────

insert into race_sessions (event_id, instance_start, status)
values ('e2390000-0000-0000-0000-0000000000e2', '2026-09-01 08:00+00', 'armed');

-- Positive control: the private event's frozen copy exists for its organiser.
select isnt_empty(
  $$ select 1 from race_session_courses
      where event_id = 'e2390000-0000-0000-0000-0000000000e2' $$,
  '27: the organiser reads the private event''s frozen copy');

set local role anon;
set local "request.jwt.claims" = '{"role":"anon"}';

select is(
  (select (select count(*) from race_session_courses
            where event_id = 'e2390000-0000-0000-0000-0000000000e1')
          || '|' || (select finish_gate_source from event_courses
                      where id = 'e2390000-0000-0000-0000-0000000000a4')),
  '5|derived',
  '28: anon reads a public event''s lines and frozen copy');

select is_empty(
  $$ select 1 from race_session_courses
      where event_id = 'e2390000-0000-0000-0000-0000000000e2' $$,
  '29: anon cannot read a private club''s frozen copy');

select * from finish();
rollback;

-- Pins migration 20270727000001 (multi-course races, gun time, host DNF on
-- race end; clubs.md § Live race mode, decisions § 1842).
--
--   1-5.   event_courses RLS: read follows the event, write is the organiser.
--   6-9.   event_attendees.course_id: must belong to the event, and is required
--          on a self-RSVP to a multi-course event (but not a single-course one).
--   10-13. The result write window and course defaulting: refused before GO,
--          lands while running and takes the racer's RSVP'd course.
--   14.    recompute_event_ranks partitions by course.
--   15.    An organiser's edit of someone else's time stamps finish_method host.
--   16-17. race_pending_dnf_count: the director's count, NULL for anyone else.
--   18-19. Ending the race files a host DNF for the pinged attendee with no
--          result, and nothing for anyone else.
--   20-21. The window stays open 24 h after the finish, then closes.
--   22.    A result on a single-course event with no RSVP'd course takes that
--          course.
--   23-24. A course's finish point is copied from its route's last waypoint,
--          and only from a route the organiser can see.
--   25.    GO stamps started_at with server time, not the client's value.

begin;
select plan(25);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('e7270000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
   'rc-owner@evt.local', '', now(), now()),
  ('e7270000-0000-0000-0000-000000000002', 'authenticated', 'authenticated',
   'rc-racer-a@evt.local', '', now(), now()),
  ('e7270000-0000-0000-0000-000000000003', 'authenticated', 'authenticated',
   'rc-racer-b@evt.local', '', now(), now()),
  ('e7270000-0000-0000-0000-000000000004', 'authenticated', 'authenticated',
   'rc-outsider@evt.local', '', now(), now()),
  ('e7270000-0000-0000-0000-000000000005', 'authenticated', 'authenticated',
   'rc-member@evt.local', '', now(), now());

set local role service_role;

insert into clubs (id, owner_id, name, slug, is_public)
values ('e7270000-0000-0000-0000-0000000000c1',
        'e7270000-0000-0000-0000-000000000001', 'Course Club', 'race-courses-c', true);

-- enroll_club_owner_trigger seats the owner; the rest are plain members.
insert into club_members (club_id, user_id, role, status)
values
  ('e7270000-0000-0000-0000-0000000000c1', 'e7270000-0000-0000-0000-000000000002', 'member', 'active'),
  ('e7270000-0000-0000-0000-0000000000c1', 'e7270000-0000-0000-0000-000000000003', 'member', 'active'),
  ('e7270000-0000-0000-0000-0000000000c1', 'e7270000-0000-0000-0000-000000000005', 'member', 'active');

insert into events (id, club_id, title, starts_at, author_id, is_public)
values
  ('e7270000-0000-0000-0000-0000000000e1', 'e7270000-0000-0000-0000-0000000000c1',
   'Two-course race', '2026-08-01 08:00+00', 'e7270000-0000-0000-0000-000000000001', true),
  ('e7270000-0000-0000-0000-0000000000e2', 'e7270000-0000-0000-0000-0000000000c1',
   'Members-only race', '2026-08-02 08:00+00', 'e7270000-0000-0000-0000-000000000001', false),
  ('e7270000-0000-0000-0000-0000000000e3', 'e7270000-0000-0000-0000-0000000000c1',
   'One-course run', '2026-08-03 08:00+00', 'e7270000-0000-0000-0000-000000000001', true);

-- The owner's private route, and the outsider's private route.
insert into routes (id, user_id, name, waypoints, distance_m, is_public)
values
  ('e7270000-0000-0000-0000-0000000000b1', 'e7270000-0000-0000-0000-000000000001',
   'Club 10K', '[{"lat":-37.8136,"lng":144.9631},{"lat":-37.8096,"lng":144.9690}]'::jsonb,
   10000, false),
  ('e7270000-0000-0000-0000-0000000000b2', 'e7270000-0000-0000-0000-000000000004',
   'Home loop', '[{"lat":51.5,"lng":-0.1},{"lat":51.51,"lng":-0.11}]'::jsonb,
   5000, false);

insert into event_courses (id, event_id, name, distance_m, sort_order)
values
  ('e7270000-0000-0000-0000-0000000000a1', 'e7270000-0000-0000-0000-0000000000e1', '10K', 10000, 0),
  ('e7270000-0000-0000-0000-0000000000a2', 'e7270000-0000-0000-0000-0000000000e1', '5K', 5000, 1),
  ('e7270000-0000-0000-0000-0000000000a3', 'e7270000-0000-0000-0000-0000000000e2', 'Members loop', 8000, 0),
  ('e7270000-0000-0000-0000-0000000000a4', 'e7270000-0000-0000-0000-0000000000e3', 'Only course', 5000, 0);

-- ── 1-5: event_courses RLS ──────────────────────────────────────────────────
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"e7270000-0000-0000-0000-000000000004","role":"authenticated"}';

select is(
  (select count(*)::int from event_courses
    where event_id = 'e7270000-0000-0000-0000-0000000000e1'),
  2,
  'a non-member reads the courses of a public event'
);

select is(
  (select count(*)::int from event_courses
    where event_id = 'e7270000-0000-0000-0000-0000000000e2'),
  0,
  'a non-member cannot read the courses of a members-only event'
);

set local "request.jwt.claims" = '{"sub":"e7270000-0000-0000-0000-000000000005","role":"authenticated"}';

select is(
  (select count(*)::int from event_courses
    where event_id = 'e7270000-0000-0000-0000-0000000000e2'),
  1,
  'a club member reads the courses of a members-only event'
);

select throws_ok(
  $$ insert into event_courses (event_id, name)
     values ('e7270000-0000-0000-0000-0000000000e2', 'Sneaky loop') $$,
  '42501',
  null,
  'a plain member cannot add a course'
);

set local "request.jwt.claims" = '{"sub":"e7270000-0000-0000-0000-000000000001","role":"authenticated"}';

select lives_ok(
  $$ insert into event_courses (event_id, name, sort_order)
     values ('e7270000-0000-0000-0000-0000000000e2', 'Short loop', 1) $$,
  'the club owner adds a course'
);

-- ── 6-9: the RSVP course ────────────────────────────────────────────────────
set local "request.jwt.claims" = '{"sub":"e7270000-0000-0000-0000-000000000002","role":"authenticated"}';

select throws_ok(
  $$ insert into event_attendees (event_id, user_id, status, instance_start)
     values ('e7270000-0000-0000-0000-0000000000e1',
             'e7270000-0000-0000-0000-000000000002', 'going', '2026-08-01 08:00+00') $$,
  '23514',
  null,
  'a going RSVP to a two-course event must name a course'
);

select throws_ok(
  $$ insert into event_attendees (event_id, user_id, status, instance_start, course_id)
     values ('e7270000-0000-0000-0000-0000000000e1',
             'e7270000-0000-0000-0000-000000000002', 'going', '2026-08-01 08:00+00',
             'e7270000-0000-0000-0000-0000000000a4') $$,
  '23514',
  null,
  'an RSVP cannot name another event''s course'
);

insert into event_attendees (event_id, user_id, status, instance_start, course_id)
values ('e7270000-0000-0000-0000-0000000000e1',
        'e7270000-0000-0000-0000-000000000002', 'going', '2026-08-01 08:00+00',
        'e7270000-0000-0000-0000-0000000000a1');

select is(
  (select course_id from event_attendees
    where event_id = 'e7270000-0000-0000-0000-0000000000e1'
      and user_id = 'e7270000-0000-0000-0000-000000000002'),
  'e7270000-0000-0000-0000-0000000000a1'::uuid,
  'a going RSVP naming one of the event''s courses lands with it'
);

insert into event_attendees (event_id, user_id, status, instance_start)
values ('e7270000-0000-0000-0000-0000000000e3',
        'e7270000-0000-0000-0000-000000000002', 'going', '2026-08-03 08:00+00');

select is(
  (select status || '/' || coalesce(course_id::text, 'none') from event_attendees
    where event_id = 'e7270000-0000-0000-0000-0000000000e3'
      and user_id = 'e7270000-0000-0000-0000-000000000002'),
  'going/none',
  'a single-course event still takes an RSVP with no course'
);

-- The other racers, filed by the server.
set local role service_role;
insert into event_attendees (event_id, user_id, status, instance_start, course_id)
values
  ('e7270000-0000-0000-0000-0000000000e1', 'e7270000-0000-0000-0000-000000000003',
   'going', '2026-08-01 08:00+00', 'e7270000-0000-0000-0000-0000000000a2'),
  ('e7270000-0000-0000-0000-0000000000e1', 'e7270000-0000-0000-0000-000000000005',
   'going', '2026-08-01 08:00+00', 'e7270000-0000-0000-0000-0000000000a2');

insert into race_sessions (event_id, instance_start, status)
values ('e7270000-0000-0000-0000-0000000000e1', '2026-08-01 08:00+00', 'armed');

-- ── 23-24: the course finish point ──────────────────────────────────────────
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"e7270000-0000-0000-0000-000000000001","role":"authenticated"}';

update event_courses set route_id = 'e7270000-0000-0000-0000-0000000000b1'
 where id = 'e7270000-0000-0000-0000-0000000000a1';

select is(
  (select finish_lat::text || ',' || finish_lng::text from event_courses
    where id = 'e7270000-0000-0000-0000-0000000000a1'),
  '-37.8096,144.969',
  'a course given a route takes the route''s last waypoint as its finish'
);

select throws_ok(
  $$ update event_courses set route_id = 'e7270000-0000-0000-0000-0000000000b2'
      where id = 'e7270000-0000-0000-0000-0000000000a2' $$,
  '42501',
  null,
  'an organiser cannot publish the finish of a route they cannot see'
);

set local role service_role;

-- ── 10-13: the write window, before and after GO ────────────────────────────
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"e7270000-0000-0000-0000-000000000002","role":"authenticated"}';

select throws_ok(
  $$ insert into event_results (event_id, instance_start, user_id, duration_s, distance_m)
     values ('e7270000-0000-0000-0000-0000000000e1', '2026-08-01 08:00+00',
             'e7270000-0000-0000-0000-000000000002', 2400, 10000) $$,
  '23514',
  null,
  'a result cannot be written while the race is only armed'
);

set local "request.jwt.claims" = '{"sub":"e7270000-0000-0000-0000-000000000001","role":"authenticated"}';
update race_sessions
   set status = 'running', started_at = '2000-01-01 00:00+00'
 where event_id = 'e7270000-0000-0000-0000-0000000000e1';

-- ── 25: GO is server time ───────────────────────────────────────────────────
select is(
  (select started_at from race_sessions
    where event_id = 'e7270000-0000-0000-0000-0000000000e1'),
  now(),
  'GO stamps started_at with the server clock, not the host device''s value'
);

set local role service_role;

insert into race_pings (event_id, instance_start, user_id, lat, lng, distance_m, elapsed_s)
values
  ('e7270000-0000-0000-0000-0000000000e1', '2026-08-01 08:00+00',
   'e7270000-0000-0000-0000-000000000002', 51.5, -0.1, 9000, 2100),
  ('e7270000-0000-0000-0000-0000000000e1', '2026-08-01 08:00+00',
   'e7270000-0000-0000-0000-000000000005', 51.5, -0.1, 3100, 1300);

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"e7270000-0000-0000-0000-000000000002","role":"authenticated"}';

insert into event_results (event_id, instance_start, user_id, duration_s, gun_time_s,
                           chip_time_s, distance_m, finish_method)
values ('e7270000-0000-0000-0000-0000000000e1', '2026-08-01 08:00+00',
        'e7270000-0000-0000-0000-000000000002', 2400, 2400, 2390, 10000, 'auto');

select is(
  (select course_id from event_results
    where event_id = 'e7270000-0000-0000-0000-0000000000e1'
      and user_id = 'e7270000-0000-0000-0000-000000000002'),
  'e7270000-0000-0000-0000-0000000000a1'::uuid,
  'a result written with no course takes the racer''s RSVP''d course'
);

select is(
  (select gun_time_s || '/' || chip_time_s || '/' || finish_method from event_results
    where event_id = 'e7270000-0000-0000-0000-0000000000e1'
      and user_id = 'e7270000-0000-0000-0000-000000000002'),
  '2400/2390/auto',
  'a result written while the race is running keeps its gun time, chip time and method'
);

select throws_ok(
  $$ update event_results set course_id = 'e7270000-0000-0000-0000-0000000000a4'
      where event_id = 'e7270000-0000-0000-0000-0000000000e1'
        and user_id = 'e7270000-0000-0000-0000-000000000002' $$,
  '23514',
  null,
  'a result cannot move to another event''s course'
);

set local "request.jwt.claims" = '{"sub":"e7270000-0000-0000-0000-000000000003","role":"authenticated"}';

insert into event_results (event_id, instance_start, user_id, duration_s, gun_time_s,
                           distance_m, finish_method, course_id)
values ('e7270000-0000-0000-0000-0000000000e1', '2026-08-01 08:00+00',
        'e7270000-0000-0000-0000-000000000003', 1500, 1500, 5000, 'auto',
        'e7270000-0000-0000-0000-0000000000a2');

-- ── 14: ranks partition by course ───────────────────────────────────────────
select is(
  (select rank from event_results
    where event_id = 'e7270000-0000-0000-0000-0000000000e1'
      and user_id = 'e7270000-0000-0000-0000-000000000002'),
  1,
  'the 10K winner ranks 1 although a 5K finisher was faster'
);

-- ── 15: an organiser's edit is a host result ────────────────────────────────
set local "request.jwt.claims" = '{"sub":"e7270000-0000-0000-0000-000000000001","role":"authenticated"}';

update event_results set duration_s = 2450, gun_time_s = 2450
 where event_id = 'e7270000-0000-0000-0000-0000000000e1'
   and user_id = 'e7270000-0000-0000-0000-000000000002';

select is(
  (select duration_s || '/' || finish_method from event_results
    where event_id = 'e7270000-0000-0000-0000-0000000000e1'
      and user_id = 'e7270000-0000-0000-0000-000000000002'),
  '2450/host',
  'an organiser editing a racer''s time lands it and stamps finish_method host'
);

-- ── 16-17: what End will do ─────────────────────────────────────────────────
select is(
  race_pending_dnf_count('e7270000-0000-0000-0000-0000000000e1', '2026-08-01 08:00+00'),
  1,
  'the race director sees one racer End would mark DNF (pinged, no result)'
);

set local "request.jwt.claims" = '{"sub":"e7270000-0000-0000-0000-000000000005","role":"authenticated"}';

select is(
  race_pending_dnf_count('e7270000-0000-0000-0000-0000000000e1', '2026-08-01 08:00+00'),
  null::int,
  'a racer who is not a race director gets no count'
);

-- ── 18-19: End files the host DNF ───────────────────────────────────────────
set local "request.jwt.claims" = '{"sub":"e7270000-0000-0000-0000-000000000001","role":"authenticated"}';

update race_sessions set status = 'finished', finished_at = now()
 where event_id = 'e7270000-0000-0000-0000-0000000000e1'
   and instance_start = '2026-08-01 08:00+00';

select is(
  (select finisher_status || '/' || finish_method || '/' || course_id::text || '/' || duration_s
     from event_results
    where event_id = 'e7270000-0000-0000-0000-0000000000e1'
      and user_id = 'e7270000-0000-0000-0000-000000000005'),
  'dnf/host/e7270000-0000-0000-0000-0000000000a2/1300',
  'ending the race files a host DNF on the racer''s course from their last ping'
);

select is(
  (select count(*)::int from event_results
    where event_id = 'e7270000-0000-0000-0000-0000000000e1'),
  3,
  'ending the race leaves the two finishers alone and adds only the one DNF'
);

-- ── 20-21: the window after the finish ──────────────────────────────────────
set local "request.jwt.claims" = '{"sub":"e7270000-0000-0000-0000-000000000003","role":"authenticated"}';

update event_results set duration_s = 1490, chip_time_s = 1490
 where event_id = 'e7270000-0000-0000-0000-0000000000e1'
   and user_id = 'e7270000-0000-0000-0000-000000000003';

select is(
  (select duration_s from event_results
    where event_id = 'e7270000-0000-0000-0000-0000000000e1'
      and user_id = 'e7270000-0000-0000-0000-000000000003'),
  1490,
  'a racer''s queued result still lands just after the race finished'
);

set local role service_role;
update race_sessions set finished_at = now() - interval '25 hours'
 where event_id = 'e7270000-0000-0000-0000-0000000000e1'
   and instance_start = '2026-08-01 08:00+00';

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"e7270000-0000-0000-0000-000000000003","role":"authenticated"}';

select throws_ok(
  $$ update event_results set duration_s = 1480
      where event_id = 'e7270000-0000-0000-0000-0000000000e1'
        and user_id = 'e7270000-0000-0000-0000-000000000003' $$,
  '23514',
  null,
  'a racer cannot change their time more than 24 h after the race finished'
);

-- ── 22: the only course of a single-course event ────────────────────────────
set local "request.jwt.claims" = '{"sub":"e7270000-0000-0000-0000-000000000002","role":"authenticated"}';

insert into event_results (event_id, instance_start, user_id, duration_s, distance_m)
values ('e7270000-0000-0000-0000-0000000000e3', '2026-08-03 08:00+00',
        'e7270000-0000-0000-0000-000000000002', 1600, 5000);

select is(
  (select course_id from event_results
    where event_id = 'e7270000-0000-0000-0000-0000000000e3'
      and user_id = 'e7270000-0000-0000-0000-000000000002'),
  'e7270000-0000-0000-0000-0000000000a4'::uuid,
  'a result on a single-course event takes that course when the RSVP named none'
);

select * from finish();
rollback;

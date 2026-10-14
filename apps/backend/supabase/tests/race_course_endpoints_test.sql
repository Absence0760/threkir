-- Pins migration 20270728000001 (decisions § 1848) and the event_courses
-- table contract from 20270727000001.
--
--   1-4.   A course's start and finish are the route owner's privacy-clipped
--          endpoints: an endpoint inside the owner's zone is NULL, never the
--          nearest surviving point — for someone else's public route and for
--          the organiser's own.
--   5-8.   The endpoints follow the route: a waypoint edit, a new zone and a
--          removed zone each recompute them, and a client write to them is
--          recomputed rather than stored.
--   9-11.  The attach-time visibility check: a rename after the route went
--          private still lands, and attaching a route the organiser cannot see
--          raises event_course_route_not_visible.
--   12-14. Column CHECKs: blank name, distance 0, distance over 1,000,000.
--   15-17. RLS: a plain member cannot rename or delete a course, anon reads a
--          public event's courses.
--   18-20. Clearing the route, an empty route and a route whose waypoints have
--          no position all give no endpoints. (An out-of-range coordinate cannot
--          reach routes at all: the routes geometry triggers cast the waypoints
--          to geography, which refuses it.)
--   21-22. Deleting a course nulls the RSVP's and the result's course.

begin;
select plan(22);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('e7280000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
   'ce-organiser@evt.local', '', now(), now()),
  ('e7280000-0000-0000-0000-000000000002', 'authenticated', 'authenticated',
   'ce-stranger@evt.local', '', now(), now()),
  ('e7280000-0000-0000-0000-000000000003', 'authenticated', 'authenticated',
   'ce-member@evt.local', '', now(), now());

set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';

insert into clubs (id, owner_id, name, slug, is_public)
values ('e7280000-0000-0000-0000-0000000000c1',
        'e7280000-0000-0000-0000-000000000001', 'Endpoint Club', 'course-endpoints-c', true);

insert into club_members (club_id, user_id, role, status)
values ('e7280000-0000-0000-0000-0000000000c1',
        'e7280000-0000-0000-0000-000000000003', 'member', 'active');

insert into events (id, club_id, title, starts_at, author_id, is_public)
values ('e7280000-0000-0000-0000-0000000000e1', 'e7280000-0000-0000-0000-0000000000c1',
        'Endpoint race', '2026-09-01 08:00+00', 'e7280000-0000-0000-0000-000000000001', true);

-- The stranger's zone covers (10.02, 10.02); the organiser's covers (20.02, 20.02).
insert into user_settings (user_id, prefs)
values
  ('e7280000-0000-0000-0000-000000000002',
   '{"privacy_zones":[{"lat":10.02,"lng":10.02,"radius_m":200}]}'::jsonb),
  ('e7280000-0000-0000-0000-000000000001',
   '{"privacy_zones":[{"lat":20.02,"lng":20.02,"radius_m":200}]}'::jsonb);

insert into routes (id, user_id, name, waypoints, distance_m, is_public)
values
  ('e7280000-0000-0000-0000-0000000000b1', 'e7280000-0000-0000-0000-000000000002',
   'Ends at home',
   '[{"lat":10.0,"lng":10.0},{"lat":10.01,"lng":10.01},{"lat":10.02,"lng":10.02}]'::jsonb,
   3000, true),
  ('e7280000-0000-0000-0000-0000000000b2', 'e7280000-0000-0000-0000-000000000002',
   'Starts at home',
   '[{"lat":10.02,"lng":10.02},{"lat":10.01,"lng":10.01},{"lat":10.0,"lng":10.0}]'::jsonb,
   3000, true),
  ('e7280000-0000-0000-0000-0000000000b3', 'e7280000-0000-0000-0000-000000000001',
   'Organiser home finish',
   '[{"lat":20.0,"lng":20.0},{"lat":20.02,"lng":20.02}]'::jsonb,
   3000, false),
  ('e7280000-0000-0000-0000-0000000000b4', 'e7280000-0000-0000-0000-000000000001',
   'Organiser park loop',
   '[{"lat":30.0,"lng":30.0},{"lat":30.01,"lng":30.01}]'::jsonb,
   2000, false),
  ('e7280000-0000-0000-0000-0000000000b5', 'e7280000-0000-0000-0000-000000000001',
   'Empty', '[]'::jsonb, 1000, false),
  ('e7280000-0000-0000-0000-0000000000b6', 'e7280000-0000-0000-0000-000000000001',
   'Unplaced', '[{"note":"no fix"},{"note":"no fix"}]'::jsonb, 1000, false);

insert into event_courses (id, event_id, name, distance_m, sort_order)
values
  ('e7280000-0000-0000-0000-0000000000a1', 'e7280000-0000-0000-0000-0000000000e1', 'A', 3000, 0),
  ('e7280000-0000-0000-0000-0000000000a2', 'e7280000-0000-0000-0000-0000000000e1', 'B', 3000, 1),
  ('e7280000-0000-0000-0000-0000000000a3', 'e7280000-0000-0000-0000-0000000000e1', 'C', 3000, 2),
  ('e7280000-0000-0000-0000-0000000000a4', 'e7280000-0000-0000-0000-0000000000e1', 'D', 2000, 3),
  ('e7280000-0000-0000-0000-0000000000a5', 'e7280000-0000-0000-0000-0000000000e1', 'E', 1000, 4),
  ('e7280000-0000-0000-0000-0000000000a6', 'e7280000-0000-0000-0000-0000000000e1', 'F', 1000, 5);

-- ── 1-4: endpoints are clipped for every caller ─────────────────────────────
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"e7280000-0000-0000-0000-000000000001","role":"authenticated"}';

update event_courses set route_id = 'e7280000-0000-0000-0000-0000000000b1'
 where id = 'e7280000-0000-0000-0000-0000000000a1';
update event_courses set route_id = 'e7280000-0000-0000-0000-0000000000b2'
 where id = 'e7280000-0000-0000-0000-0000000000a2';
update event_courses set route_id = 'e7280000-0000-0000-0000-0000000000b3'
 where id = 'e7280000-0000-0000-0000-0000000000a3';

select is(
  (select coalesce(finish_lat::text, 'null') || ',' || coalesce(finish_lng::text, 'null')
     from event_courses where id = 'e7280000-0000-0000-0000-0000000000a1'),
  'null,null',
  'someone else''s public route whose finish is in their privacy zone publishes no finish'
);

select is(
  (select start_lat::text || ',' || start_lng::text
     from event_courses where id = 'e7280000-0000-0000-0000-0000000000a1'),
  '10,10',
  'the same route''s start, outside the zone, is published unchanged'
);

select is(
  (select coalesce(start_lat::text, 'null') || ',' || coalesce(start_lng::text, 'null')
          || '|' || finish_lat::text || ',' || finish_lng::text
     from event_courses where id = 'e7280000-0000-0000-0000-0000000000a2'),
  'null,null|10,10',
  'a route that starts in the owner''s zone publishes no start and keeps its finish'
);

select is(
  (select start_lat::text || ',' || start_lng::text
          || '|' || coalesce(finish_lat::text, 'null') || ',' || coalesce(finish_lng::text, 'null')
     from event_courses where id = 'e7280000-0000-0000-0000-0000000000a3'),
  '20,20|null,null',
  'the organiser''s own route is clipped too: the course row is a non-owner surface'
);

-- ── 5-8: the endpoints follow the route and the zones ───────────────────────
update event_courses set route_id = 'e7280000-0000-0000-0000-0000000000b4'
 where id = 'e7280000-0000-0000-0000-0000000000a4';

update routes
   set waypoints = '[{"lat":30.0,"lng":30.0},{"lat":30.05,"lng":30.05}]'::jsonb
 where id = 'e7280000-0000-0000-0000-0000000000b4';

select is(
  (select finish_lat::text || ',' || finish_lng::text
     from event_courses where id = 'e7280000-0000-0000-0000-0000000000a4'),
  '30.05,30.05',
  'editing the route''s waypoints moves the course finish with it'
);

set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';

update user_settings
   set prefs = '{"privacy_zones":[{"lat":20.02,"lng":20.02,"radius_m":200},{"lat":30.05,"lng":30.05,"radius_m":200}]}'::jsonb
 where user_id = 'e7280000-0000-0000-0000-000000000001';

select is(
  (select coalesce(finish_lat::text, 'null') || ',' || coalesce(finish_lng::text, 'null')
     from event_courses where id = 'e7280000-0000-0000-0000-0000000000a4'),
  'null,null',
  'a privacy zone added over the finish withdraws the published finish'
);

update user_settings
   set prefs = '{"privacy_zones":[{"lat":20.02,"lng":20.02,"radius_m":200}]}'::jsonb
 where user_id = 'e7280000-0000-0000-0000-000000000001';

select is(
  (select finish_lat::text || ',' || finish_lng::text
     from event_courses where id = 'e7280000-0000-0000-0000-0000000000a4'),
  '30.05,30.05',
  'removing that zone publishes the finish again'
);

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"e7280000-0000-0000-0000-000000000001","role":"authenticated"}';

update event_courses set finish_lat = 0, finish_lng = 0, start_lat = 1
 where id = 'e7280000-0000-0000-0000-0000000000a4';

select is(
  (select start_lat::text || ',' || start_lng::text || '|' || finish_lat::text || ',' || finish_lng::text
     from event_courses where id = 'e7280000-0000-0000-0000-0000000000a4'),
  '30,30|30.05,30.05',
  'a client write to the endpoints (even half a pair) is recomputed from the route'
);

-- ── 9-11: the attach-time visibility check ──────────────────────────────────
set local "request.jwt.claims" = '{"sub":"e7280000-0000-0000-0000-000000000002","role":"authenticated"}';
update routes set is_public = false where id = 'e7280000-0000-0000-0000-0000000000b1';

set local "request.jwt.claims" = '{"sub":"e7280000-0000-0000-0000-000000000001","role":"authenticated"}';

select lives_ok(
  $$ update event_courses set name = 'A renamed'
      where id = 'e7280000-0000-0000-0000-0000000000a1' $$,
  'renaming a course whose route has since gone private is not refused'
);

select is(
  (select start_lat::text || ',' || start_lng::text
     from event_courses where id = 'e7280000-0000-0000-0000-0000000000a1'),
  '10,10',
  'and the rename leaves the published endpoints as they were'
);

select throws_ok(
  $$ update event_courses set route_id = 'e7280000-0000-0000-0000-0000000000b1'
      where id = 'e7280000-0000-0000-0000-0000000000a5' $$,
  '42501',
  'event_course_route_not_visible: route e7280000-0000-0000-0000-0000000000b1 is not visible to you',
  'attaching a route the organiser cannot see raises event_course_route_not_visible'
);

-- ── 12-14: column CHECKs ────────────────────────────────────────────────────
select throws_ok(
  $$ insert into event_courses (event_id, name)
     values ('e7280000-0000-0000-0000-0000000000e1', '   ') $$,
  '23514',
  null,
  'a blank course name is refused'
);

select throws_ok(
  $$ insert into event_courses (event_id, name, distance_m)
     values ('e7280000-0000-0000-0000-0000000000e1', 'Zero', 0) $$,
  '23514',
  null,
  'a course distance of 0 is refused'
);

select throws_ok(
  $$ insert into event_courses (event_id, name, distance_m)
     values ('e7280000-0000-0000-0000-0000000000e1', 'Too far', 1000001) $$,
  '23514',
  null,
  'a course distance over 1,000,000 m is refused'
);

-- ── 15-17: RLS ──────────────────────────────────────────────────────────────
set local "request.jwt.claims" = '{"sub":"e7280000-0000-0000-0000-000000000003","role":"authenticated"}';

update event_courses set name = 'Hijacked'
 where id = 'e7280000-0000-0000-0000-0000000000a4';
delete from event_courses where id = 'e7280000-0000-0000-0000-0000000000a6';

select is(
  (select name from event_courses where id = 'e7280000-0000-0000-0000-0000000000a4'),
  'D',
  'a plain member cannot rename a course'
);

select is(
  (select count(*)::int from event_courses where id = 'e7280000-0000-0000-0000-0000000000a6'),
  1,
  'a plain member cannot delete a course'
);

set local role anon;
set local "request.jwt.claims" = '{"role":"anon"}';

select is(
  (select count(*)::int from event_courses
    where event_id = 'e7280000-0000-0000-0000-0000000000e1'),
  6,
  'anon reads the courses of a public event'
);

-- ── 18-20: no endpoints ─────────────────────────────────────────────────────
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"e7280000-0000-0000-0000-000000000001","role":"authenticated"}';

update event_courses set route_id = null
 where id = 'e7280000-0000-0000-0000-0000000000a4';

select is(
  (select num_nulls(start_lat, start_lng, finish_lat, finish_lng)
     from event_courses where id = 'e7280000-0000-0000-0000-0000000000a4'),
  4,
  'clearing the route clears both endpoints'
);

update event_courses set route_id = 'e7280000-0000-0000-0000-0000000000b5'
 where id = 'e7280000-0000-0000-0000-0000000000a5';

select is(
  (select num_nulls(start_lat, start_lng, finish_lat, finish_lng)
     from event_courses where id = 'e7280000-0000-0000-0000-0000000000a5'),
  4,
  'a route with no waypoints gives no endpoints'
);

update event_courses set route_id = 'e7280000-0000-0000-0000-0000000000b6'
 where id = 'e7280000-0000-0000-0000-0000000000a6';

select is(
  (select num_nulls(start_lat, start_lng, finish_lat, finish_lng)
     from event_courses where id = 'e7280000-0000-0000-0000-0000000000a6'),
  4,
  'waypoints with no position give no endpoints'
);

-- ── 21-22: deleting a course ────────────────────────────────────────────────
set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';

insert into event_attendees (event_id, user_id, status, instance_start, course_id)
values ('e7280000-0000-0000-0000-0000000000e1', 'e7280000-0000-0000-0000-000000000003',
        'going', '2026-09-01 08:00+00', 'e7280000-0000-0000-0000-0000000000a6');

insert into event_results (event_id, instance_start, user_id, duration_s, distance_m, course_id)
values ('e7280000-0000-0000-0000-0000000000e1', '2026-09-01 08:00+00',
        'e7280000-0000-0000-0000-000000000003', 600, 1000,
        'e7280000-0000-0000-0000-0000000000a6');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"e7280000-0000-0000-0000-000000000001","role":"authenticated"}';

delete from event_courses where id = 'e7280000-0000-0000-0000-0000000000a6';

set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';

select is(
  (select coalesce(course_id::text, 'none') from event_attendees
    where event_id = 'e7280000-0000-0000-0000-0000000000e1'
      and user_id = 'e7280000-0000-0000-0000-000000000003'),
  'none',
  'deleting a course drops it from the RSVPs that named it'
);

select is(
  (select coalesce(course_id::text, 'none') from event_results
    where event_id = 'e7280000-0000-0000-0000-0000000000e1'
      and user_id = 'e7280000-0000-0000-0000-000000000003'),
  'none',
  'deleting a course moves its results to the course-less bucket'
);

select * from finish();
rollback;

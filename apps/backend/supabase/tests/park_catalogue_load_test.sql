-- The operator load of a park catalogue (migration 20271126002423, issue
-- #1342, decisions § 2423): private.load_park_catalogue creates a park, its
-- courses' catalogue segments, park_courses rows and official routes; a
-- re-run updates them in place, so ids and efforts survive; it refuses an
-- author who is not an official publisher, and no client role can call it.

begin;

select plan(31);

-- ── Fixture ──
-- O owns the verified public club; X belongs to no club; U owns a public club
-- that was never verified.
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000000c1a01', 'authenticated', 'authenticated', 'pcl-owner@pcl.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000c1a02', 'authenticated', 'authenticated', 'pcl-outsider@pcl.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000c1a03', 'authenticated', 'authenticated', 'pcl-unverified@pcl.local', '', now(), now());

select tests.confirm_consent();

insert into clubs (id, owner_id, name, slug, is_public)
values
  ('00000000-0000-0000-0000-0000000c1b01', '00000000-0000-0000-0000-0000000c1a01', 'PCL Official', 'pcl-official', true),
  ('00000000-0000-0000-0000-0000000c1b02', '00000000-0000-0000-0000-0000000c1a03', 'PCL Unverified', 'pcl-unverified', true);

set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';
update clubs set is_verified = true where id = '00000000-0000-0000-0000-0000000c1b01';
reset role;
set local "request.jwt.claims" = '{}';

-- v1: a loop and a "race" course (a lead-in, one lap, the lead-in back).
-- v2: the loop starts somewhere else on the same square and measures longer.
create temp table manifests (k text primary key, j jsonb not null);
insert into manifests (k, j) values
('v1', $json${
  "park": {"slug": "pcl-test-park", "name": "PCL Test Park", "agency": "state", "region_code": "US-VA",
           "country_code": "US", "timezone": "America/New_York", "website_url": "https://example.org/pcl"},
  "region": "PCL Test Park, Virginia",
  "attribution": "© OpenStreetMap contributors (ODbL); elevation: USGS 3DEP",
  "courses": [
    {"slug": "pcl-loop", "name": "PCL Loop", "course_shape": "loop", "surface": "trail", "difficulty": "easy",
     "geometry_source": "osm", "source_ref": "way/1,way/2", "source_checked_at": "2026-11-09",
     "distance_m": 1990, "elevation_m": 4, "official_distance_m": null, "description": "Run it clockwise.",
     "checkpoints": [{"lat": 10.0045, "lng": 20.0045}],
     "waypoints": [{"lat": 10.0, "lng": 20.0, "ele": 10}, {"lat": 10.0045, "lng": 20.0, "ele": 12},
                   {"lat": 10.0045, "lng": 20.0045, "ele": 14}, {"lat": 10.0, "lng": 20.0045, "ele": 12},
                   {"lat": 10.0, "lng": 20.0, "ele": 10}]},
    {"slug": "pcl-5k", "name": "PCL 5K", "course_shape": "loop", "surface": "trail", "difficulty": null,
     "geometry_source": "osm", "source_ref": "way/3", "source_checked_at": "2026-11-09",
     "distance_m": 2200, "elevation_m": 0, "official_distance_m": 2200, "description": null,
     "checkpoints": [{"lat": 10.0145, "lng": 20.001}, {"lat": 10.0145, "lng": 20.0055}],
     "waypoints": [{"lat": 10.01, "lng": 20.0}, {"lat": 10.01, "lng": 20.001}, {"lat": 10.0145, "lng": 20.001},
                   {"lat": 10.0145, "lng": 20.0055}, {"lat": 10.01, "lng": 20.0055}, {"lat": 10.01, "lng": 20.001},
                   {"lat": 10.01, "lng": 20.0}]}
  ]
}$json$::jsonb);
insert into manifests (k, j)
select 'v2', jsonb_set(
  jsonb_set(j, '{courses,0,waypoints}',
    '[{"lat": 10.0, "lng": 20.002}, {"lat": 10.0, "lng": 20.0045}, {"lat": 10.0045, "lng": 20.0045},
      {"lat": 10.0045, "lng": 20.0}, {"lat": 10.0, "lng": 20.0}, {"lat": 10.0, "lng": 20.002}]'::jsonb),
  '{courses,0,distance_m}', '2000'::jsonb)
from manifests where k = 'v1';
grant select on manifests to service_role;

-- ── First load ──
set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';
create temp table load1 as
  select * from private.load_park_catalogue(
    (select j from manifests where k = 'v1'),
    '00000000-0000-0000-0000-0000000c1b01', '00000000-0000-0000-0000-0000000c1a01');
reset role;
set local "request.jwt.claims" = '{}';

select is(
  (select array_agg(course_slug || ':' || action order by course_slug) from load1),
  array['pcl-5k:created', 'pcl-loop:created'],
  'the first load creates both courses');
select is(
  (select array_agg(pc.slug order by pc.slug)
     from park_courses pc join parks p on p.id = pc.park_id where p.slug = 'pcl-test-park'),
  array['pcl-5k', 'pcl-loop'],
  'the park holds both courses');
select is(
  (select array[bbox_min_lat, bbox_min_lng, bbox_max_lat, bbox_max_lng, centroid_lat, centroid_lng]::numeric[]
     from parks where slug = 'pcl-test-park'),
  array[10.0, 20.0, 10.0145, 20.0055, 10.00725, 20.00275]::numeric[],
  'the park''s bounding box and centroid come from every course line');
select ok(
  (select bool_and(pc.global_segment_id = l.global_segment_id and pc.route_id = l.route_id)
     from load1 l join park_courses pc on pc.id = l.park_course_id),
  'each course row links the segment and route the load reports');
select is(
  (select array_agg(r.user_id::text || '|' || r.club_id::text || '|' || r.is_public::text order by l.course_slug)
     from load1 l join routes r on r.id = l.route_id),
  array['00000000-0000-0000-0000-0000000c1a01|00000000-0000-0000-0000-0000000c1b01|true',
        '00000000-0000-0000-0000-0000000c1a01|00000000-0000-0000-0000-0000000c1b01|true'],
  'each route is public, owned by the author and carries the club');
select ok(
  (select bool_and(is_official(r)) from load1 l join routes r on r.id = l.route_id),
  'each route is official');
select is(
  (select r.official_distance_m from load1 l join routes r on r.id = l.route_id where l.course_slug = 'pcl-5k'),
  2200::numeric,
  'the race course''s route carries its official distance');
select is(
  (select gs.description from load1 l join global_segments gs on gs.id = l.global_segment_id
    where l.course_slug = 'pcl-loop'),
  E'Run it clockwise.\n\n© OpenStreetMap contributors (ODbL); elevation: USGS 3DEP',
  'the segment description ends with the attribution');
select is(
  (select r.description from load1 l join routes r on r.id = l.route_id where l.course_slug = 'pcl-5k'),
  '© OpenStreetMap contributors (ODbL); elevation: USGS 3DEP',
  'a course with no description of its own still carries the attribution');
select is(
  (select array[gs.start_gate_source, gs.end_gate_source]
     from load1 l join global_segments gs on gs.id = l.global_segment_id where l.course_slug = 'pcl-loop'),
  array['derived', 'derived'],
  'the loop segment has derived start and end lines');
select is(
  (select array[gs.start_gate_lat, gs.start_gate_lng, gs.end_gate_lat, gs.end_gate_lng]
     from load1 l join global_segments gs on gs.id = l.global_segment_id where l.course_slug = 'pcl-5k'),
  array[10.01, 20.0, 10.01, 20.0]::float8[],
  'a start-finish course puts both lines on its one start point');
select is(
  (select array[round(gs.start_gate_bearing_deg)::int, round(gs.end_gate_bearing_deg)::int]
     from load1 l join global_segments gs on gs.id = l.global_segment_id where l.course_slug = 'pcl-5k'),
  array[90, 270],
  'its start line faces out along the lead-in and its end line faces back in');
select is(
  (select pc.checkpoints from load1 l join park_courses pc on pc.id = l.park_course_id where l.course_slug = 'pcl-5k'),
  '[{"lat": 10.0145, "lng": 20.001}, {"lat": 10.0145, "lng": 20.0055}]'::jsonb,
  'the checkpoints are stored in order');
select is(
  (select array[pc.course_shape, pc.geometry_source, pc.source_ref, pc.difficulty, pc.status]
     from load1 l join park_courses pc on pc.id = l.park_course_id where l.course_slug = 'pcl-loop'),
  array['loop', 'osm', 'way/1,way/2', 'easy', 'open'],
  'the course row carries shape, source and difficulty, and opens');
select is(
  (select gs.waypoints -> 1 from load1 l join global_segments gs on gs.id = l.global_segment_id
    where l.course_slug = 'pcl-loop'),
  '{"lat": 10.0045, "lng": 20.0, "ele": 12}'::jsonb,
  'the line keeps the payload''s order and elevation');

-- An effort on the loop, and a curator-closed race course: neither may be
-- touched by a re-run.
insert into runs (id, user_id, started_at, distance_m, duration_s, source, metadata, is_public)
values ('00000000-0000-0000-0000-0000000c1c01', '00000000-0000-0000-0000-0000000c1a01',
        '2026-06-01T12:00:00Z', 2000, 600, 'app', '{"activity_type":"run"}'::jsonb, true);
insert into global_segment_efforts (global_segment_id, run_id, user_id, time_seconds, started_at)
select l.global_segment_id, '00000000-0000-0000-0000-0000000c1c01', '00000000-0000-0000-0000-0000000c1a01',
       540, '2026-06-01T12:00:00Z'
  from load1 l where l.course_slug = 'pcl-loop';
update park_courses set status = 'closed', status_note = 'Bridge out'
 where id = (select park_course_id from load1 where course_slug = 'pcl-5k');

-- ── Second load, same payload ──
set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';
create temp table load2 as
  select * from private.load_park_catalogue(
    (select j from manifests where k = 'v1'),
    '00000000-0000-0000-0000-0000000c1b01', '00000000-0000-0000-0000-0000000c1a01');
reset role;
set local "request.jwt.claims" = '{}';

select is(
  (select array_agg(course_slug || ':' || action order by course_slug) from load2),
  array['pcl-5k:updated', 'pcl-loop:updated'],
  'a second load updates both courses');
select ok(
  (select bool_and(a.park_course_id = b.park_course_id and a.global_segment_id = b.global_segment_id
                   and a.route_id = b.route_id)
     from load1 a join load2 b using (course_slug)),
  'a second load keeps every id');
select is(
  (select array[
     (select count(*) from parks where slug = 'pcl-test-park'),
     (select count(*) from park_courses pc join parks p on p.id = pc.park_id where p.slug = 'pcl-test-park'),
     (select count(*) from global_segments where created_by = '00000000-0000-0000-0000-0000000c1a01'),
     (select count(*) from routes where user_id = '00000000-0000-0000-0000-0000000c1a01')]),
  array[1, 2, 2, 2]::bigint[],
  'a second load duplicates nothing');
select is(
  (select array[pc.status, pc.status_note] from load2 l join park_courses pc on pc.id = l.park_course_id
    where l.course_slug = 'pcl-5k'),
  array['closed', 'Bridge out'],
  'a re-run leaves a course''s status alone');

-- ── Changed geometry ──
set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';
create temp table load3 as
  select * from private.load_park_catalogue(
    (select j from manifests where k = 'v2'),
    '00000000-0000-0000-0000-0000000c1b01', '00000000-0000-0000-0000-0000000c1a01');
reset role;
set local "request.jwt.claims" = '{}';

select ok(
  (select bool_and(a.park_course_id = b.park_course_id and a.global_segment_id = b.global_segment_id
                   and a.route_id = b.route_id)
     from load1 a join load3 b using (course_slug)),
  'changed geometry keeps every id');
select is(
  (select array[gs.distance_m, jsonb_array_length(gs.waypoints)::numeric, gs.start_gate_lng::numeric]
     from load3 l join global_segments gs on gs.id = l.global_segment_id where l.course_slug = 'pcl-loop'),
  array[2000, 6, 20.002]::numeric[],
  'changed geometry rewrites the segment line in place and re-derives its start line');
select is(
  (select array[r.distance_m, jsonb_array_length(r.waypoints)::numeric]
     from load3 l join routes r on r.id = l.route_id where l.course_slug = 'pcl-loop'),
  array[2000, 6]::numeric[],
  'changed geometry rewrites the route in place');
select is(
  (select array_agg(e.time_seconds::int) from global_segment_efforts e
     join load3 l on l.global_segment_id = e.global_segment_id where l.course_slug = 'pcl-loop'),
  array[540],
  'an effort on the course survives the new geometry');

-- ── A deleted route is recreated ──
delete from routes where id = (select route_id from load1 where course_slug = 'pcl-5k');
set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';
create temp table load4 as
  select * from private.load_park_catalogue(
    (select j from manifests where k = 'v1'),
    '00000000-0000-0000-0000-0000000c1b01', '00000000-0000-0000-0000-0000000c1a01', true);
reset role;
set local "request.jwt.claims" = '{}';

select ok(
  (select l.route_id is not null and l.route_id <> (select route_id from load1 where course_slug = 'pcl-5k')
          and pc.route_id = l.route_id
     from load4 l join park_courses pc on pc.id = l.park_course_id where l.course_slug = 'pcl-5k'),
  'a course whose route was deleted gets a new route, linked');
select is(
  (select array_agg(j.payload ->> 'segment_id' order by j.payload ->> 'segment_id')
     from load4 l join jobs j on j.id = l.backfill_job_id
    where j.kind = 'segment_match'),
  (select array_agg(global_segment_id::text order by global_segment_id::text) from load4),
  'the backfill flag queues one segment_match backfill per course');

-- ── Refusals ──
select throws_ok(
  $$ select * from private.load_park_catalogue(
       (select j from manifests where k = 'v1'),
       '00000000-0000-0000-0000-0000000c1b01', '00000000-0000-0000-0000-0000000c1a02') $$,
  '42501',
  'load_park_catalogue: 00000000-0000-0000-0000-0000000c1a02 is not an active owner or admin of the verified public club 00000000-0000-0000-0000-0000000c1b01',
  'an author outside the club is refused');
select throws_ok(
  $$ select * from private.load_park_catalogue(
       (select j from manifests where k = 'v1'),
       '00000000-0000-0000-0000-0000000c1b02', '00000000-0000-0000-0000-0000000c1a03') $$,
  '42501',
  'load_park_catalogue: 00000000-0000-0000-0000-0000000c1a03 is not an active owner or admin of the verified public club 00000000-0000-0000-0000-0000000c1b02',
  'the owner of an unverified club is refused');
select throws_ok(
  $$ select * from private.load_park_catalogue(
       jsonb_set((select j from manifests where k = 'v1'), '{courses,1,waypoints,2,lat}', '91'),
       '00000000-0000-0000-0000-0000000c1b01', '00000000-0000-0000-0000-0000000c1a01') $$,
  '22023',
  'load_park_catalogue: course pcl-5k needs at least two waypoints, each a lat and lng in range',
  'a waypoint out of range is refused');

set local role anon;
select throws_ok(
  $$ select * from private.load_park_catalogue('{}'::jsonb, null, null) $$,
  '42501', 'permission denied for function load_park_catalogue',
  'anon cannot call the load');
reset role;

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000c1a01","role":"authenticated"}';
select throws_ok(
  $$ select * from private.load_park_catalogue('{}'::jsonb, null, null) $$,
  '42501', 'permission denied for function load_park_catalogue',
  'a signed-in account, even the official publisher, cannot call the load');
reset role;
set local "request.jwt.claims" = '{}';

select is(
  (select count(*) from park_courses pc join parks p on p.id = pc.park_id where p.slug = 'pcl-test-park'),
  2::bigint,
  'the refused calls wrote nothing');

select * from finish();
rollback;

-- park_courses.laps and park_courses.attribution (migration 20271130002438,
-- issue #1352, decisions § 2438): private.load_park_catalogue writes each
-- course's laps and the manifest's credit into their own columns and no longer
-- appends the credit to the catalogue segment's or the official route's
-- description; a course loaded by the previous body (credit in the
-- description, both columns null) re-loads as `updated` with no backfill,
-- because no line moved; the CHECKs refuse a lap count under 1 and a blank
-- credit; the load refuses a manifest whose laps or credit the columns could
-- not hold.

begin;

select plan(16);

-- ── Fixture ──
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values ('00000000-0000-0000-0000-0000000c3a01', 'authenticated', 'authenticated', 'pla-owner@pla.local', '', now(), now());

select tests.confirm_consent();

insert into clubs (id, owner_id, name, slug, is_public)
values ('00000000-0000-0000-0000-0000000c3b01', '00000000-0000-0000-0000-0000000c3a01', 'PLA Official', 'pla-official', true);

set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';
update clubs set is_verified = true where id = '00000000-0000-0000-0000-0000000c3b01';
reset role;
set local "request.jwt.claims" = '{}';

-- A plain trail loop (laps 1), a two-lap race course and a point-to-point
-- course, for which laps say nothing (null).
create temp table manifests (k text primary key, j jsonb not null);
insert into manifests (k, j) values
('base', $json${
  "park": {"slug": "pla-test-park", "name": "PLA Test Park", "agency": "state", "region_code": "US-VA",
           "country_code": "US", "timezone": "America/New_York", "website_url": "https://example.org/pla"},
  "region": "PLA Test Park, Virginia",
  "attribution": "© OpenStreetMap contributors (ODbL); elevation: USGS 3DEP",
  "courses": [
    {"slug": "pla-loop", "name": "PLA Loop", "course_shape": "loop", "surface": "trail", "difficulty": "easy",
     "geometry_source": "osm", "source_ref": "way/1", "source_checked_at": "2026-11-09",
     "distance_m": 1990, "elevation_m": 4, "official_distance_m": null, "description": "Run it clockwise.",
     "laps": 1, "checkpoints": [],
     "waypoints": [{"lat": 10.0, "lng": 20.0}, {"lat": 10.0045, "lng": 20.0}, {"lat": 10.0045, "lng": 20.0045},
                   {"lat": 10.0, "lng": 20.0045}, {"lat": 10.0, "lng": 20.0}]},
    {"slug": "pla-10k", "name": "PLA 10K", "course_shape": "loop", "surface": "trail", "difficulty": null,
     "geometry_source": "osm", "source_ref": "way/2", "source_checked_at": "2026-11-09",
     "distance_m": 2200, "elevation_m": 0, "official_distance_m": 2200,
     "description": "Measures exactly 10 km: 2 laps of the loop.", "laps": 2, "checkpoints": [],
     "waypoints": [{"lat": 10.01, "lng": 20.0}, {"lat": 10.01, "lng": 20.001}, {"lat": 10.0145, "lng": 20.001},
                   {"lat": 10.0145, "lng": 20.0055}, {"lat": 10.01, "lng": 20.0055}, {"lat": 10.01, "lng": 20.001},
                   {"lat": 10.01, "lng": 20.0}]},
    {"slug": "pla-line", "name": "PLA Line", "course_shape": "point_to_point", "surface": "road", "difficulty": null,
     "geometry_source": "osm", "source_ref": "way/3", "source_checked_at": "2026-11-09",
     "distance_m": 500, "elevation_m": null, "official_distance_m": null, "description": null,
     "laps": null, "checkpoints": [],
     "waypoints": [{"lat": 10.02, "lng": 20.0}, {"lat": 10.0245, "lng": 20.0}]}
  ]
}$json$::jsonb);

create temp table loads (n int, course_slug text, park_course_id uuid, global_segment_id uuid, route_id uuid,
                         action text, backfill_job_id bigint);

create function pg_temp.load(p_n int, p_j jsonb) returns void language sql as $$
  insert into loads
  select p_n, l.* from private.load_park_catalogue(
    p_j, '00000000-0000-0000-0000-0000000c3b01', '00000000-0000-0000-0000-0000000c3a01', true) l;
  update jobs set status = 'done'
   where kind = 'segment_match' and status = 'queued'
     and id in (select backfill_job_id from loads where n = p_n);
$$;

create function pg_temp.actions(p_n int) returns text[] language sql as $$
  select array_agg(course_slug || ':' || action || ':' || (backfill_job_id is not null)::text
                   order by course_slug)
    from loads where n = p_n;
$$;

-- ── Columns ──
select col_type_is('public', 'park_courses', 'laps', 'integer', 'park_courses.laps is an integer');
select col_is_null('public', 'park_courses', 'laps', 'park_courses.laps is nullable');
select col_type_is('public', 'park_courses', 'attribution', 'text', 'park_courses.attribution is text');
select col_is_null('public', 'park_courses', 'attribution', 'park_courses.attribution is nullable');

-- ── 1. A load writes both columns and leaves the credit out of the descriptions ──
select pg_temp.load(1, (select j from manifests where k = 'base'));

select is(
  (select array_agg(pc.slug || ':' || coalesce(pc.laps::text, '<null>') order by pc.slug)
     from park_courses pc join parks p on p.id = pc.park_id where p.slug = 'pla-test-park'),
  array['pla-10k:2', 'pla-line:<null>', 'pla-loop:1'],
  'each course stores the manifest''s laps: a lapped race its count, a loop 1, a line null');
select ok(
  (select bool_and(pc.attribution = '© OpenStreetMap contributors (ODbL); elevation: USGS 3DEP')
     from park_courses pc join parks p on p.id = pc.park_id where p.slug = 'pla-test-park'),
  'each course stores the manifest attribution in park_courses.attribution');
select is(
  (select array_agg(coalesce(gs.description, '<null>') || ' | ' || coalesce(r.description, '<null>')
                    order by pc.slug)
     from park_courses pc join parks p on p.id = pc.park_id
     join global_segments gs on gs.id = pc.global_segment_id join routes r on r.id = pc.route_id
    where p.slug = 'pla-test-park'),
  array['Measures exactly 10 km: 2 laps of the loop. | Measures exactly 10 km: 2 laps of the loop.',
        '<null> | <null>',
        'Run it clockwise. | Run it clockwise.'],
  'the segment and route descriptions are the course''s own text, with no credit appended');

-- ── 2. A second identical load writes nothing ──
select pg_temp.load(2, (select j from manifests where k = 'base'));
select is(
  pg_temp.actions(2),
  array['pla-10k:unchanged:false', 'pla-line:unchanged:false', 'pla-loop:unchanged:false'],
  'an identical re-load reports every course unchanged');

-- ── 3. A course loaded by the previous body is rewritten, without a backfill ──
-- What 20271127002429 left behind: the credit appended to both descriptions,
-- and neither column written.
update global_segments gs
   set description = concat_ws(E'\n\n', gs.description, '© OpenStreetMap contributors (ODbL); elevation: USGS 3DEP')
  from park_courses pc join parks p on p.id = pc.park_id
 where gs.id = pc.global_segment_id and p.slug = 'pla-test-park';
update routes r
   set description = concat_ws(E'\n\n', r.description, '© OpenStreetMap contributors (ODbL); elevation: USGS 3DEP')
  from park_courses pc join parks p on p.id = pc.park_id
 where r.id = pc.route_id and p.slug = 'pla-test-park';
update park_courses pc set laps = null, attribution = null
  from parks p where p.id = pc.park_id and p.slug = 'pla-test-park';

select pg_temp.load(3, (select j from manifests where k = 'base'));
select is(
  pg_temp.actions(3),
  array['pla-10k:updated:false', 'pla-line:updated:false', 'pla-loop:updated:false'],
  'an old-style course re-loads as updated and queues no backfill');
select is(
  (select array_agg(coalesce(gs.description, '<null>') || ' | ' || coalesce(pc.laps::text, '<null>')
                    || ' | ' || coalesce(pc.attribution, '<null>') order by pc.slug)
     from park_courses pc join parks p on p.id = pc.park_id
     join global_segments gs on gs.id = pc.global_segment_id
    where p.slug = 'pla-test-park'),
  array['Measures exactly 10 km: 2 laps of the loop. | 2 | © OpenStreetMap contributors (ODbL); elevation: USGS 3DEP',
        '<null> | <null> | © OpenStreetMap contributors (ODbL); elevation: USGS 3DEP',
        'Run it clockwise. | 1 | © OpenStreetMap contributors (ODbL); elevation: USGS 3DEP'],
  'the re-load strips the credit from the description and writes laps and attribution');
select ok(
  (select bool_and(r.description is not distinct from gs.description)
     from park_courses pc join parks p on p.id = pc.park_id
     join global_segments gs on gs.id = pc.global_segment_id join routes r on r.id = pc.route_id
    where p.slug = 'pla-test-park'),
  'the re-load strips the credit from the route description too');

-- ── 4. The CHECKs ──
select throws_ok(
  $$ update park_courses pc set laps = 0 from parks p where p.id = pc.park_id and p.slug = 'pla-test-park' $$,
  '23514', null,
  'park_courses refuses a lap count under 1');
select throws_ok(
  $$ update park_courses pc set attribution = '  ' from parks p where p.id = pc.park_id and p.slug = 'pla-test-park' $$,
  '23514', null,
  'park_courses refuses a blank attribution');

-- ── 5. The load refuses what the columns cannot hold ──
select throws_ok(
  $$ select pg_temp.load(4, jsonb_set((select j from manifests where k = 'base'), '{courses,1,laps}', '0')) $$,
  '22023',
  'load_park_catalogue: course pla-10k has laps that is not a whole number from 1 to 1000',
  'the load refuses a lap count under 1');
select throws_ok(
  $$ select pg_temp.load(4, jsonb_set((select j from manifests where k = 'base'), '{courses,1,laps}', '"2"')) $$,
  '22023',
  'load_park_catalogue: course pla-10k has laps that is not a whole number from 1 to 1000',
  'the load refuses a lap count that is not a JSON number');
select throws_ok(
  $$ select pg_temp.load(4, jsonb_set((select j from manifests where k = 'base'), '{attribution}',
                                      to_jsonb(repeat('x', 301)))) $$,
  '22023',
  'load_park_catalogue: the attribution is longer than 300 characters',
  'the load refuses an attribution longer than the column holds');

select * from finish();
rollback;

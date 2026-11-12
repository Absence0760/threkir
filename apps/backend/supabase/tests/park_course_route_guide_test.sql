-- park_courses.route_guide and park_courses.route_guide_checked_at
-- (migration 20271212001344, issue #1344, decisions § 2448): the shape CHECK
-- (private.park_course_route_guide_ok) holds a guide to its step vocabulary
-- and order; private.load_park_catalogue writes the guide and its ground-check
-- date, reports a course whose guide changed `updated` with no backfill, and
-- refuses a guide or a date the columns could not hold.

begin;

select plan(20);

-- ── Fixture ──
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values ('00000000-0000-0000-0000-0000000c4a01', 'authenticated', 'authenticated', 'prg-owner@pla.local', '', now(), now());

select tests.confirm_consent();

insert into clubs (id, owner_id, name, slug, is_public)
values ('00000000-0000-0000-0000-0000000c4b01', '00000000-0000-0000-0000-0000000c4a01', 'PRG Official', 'prg-official', true);

set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';
update clubs set is_verified = true where id = '00000000-0000-0000-0000-0000000c4b01';
reset role;
set local "request.jwt.claims" = '{}';

-- A plain trail loop (laps 1), a two-lap race course and a point-to-point
-- course, for which laps say nothing (null).
create temp table manifests (k text primary key, j jsonb not null);
insert into manifests (k, j) values
('base', $json${
  "park": {"slug": "prg-test-park", "name": "PRG Test Park", "agency": "state", "region_code": "US-VA",
           "country_code": "US", "timezone": "America/New_York", "website_url": "https://example.org/prg"},
  "region": "PRG Test Park, Virginia",
  "attribution": "© OpenStreetMap contributors (ODbL); elevation: USGS 3DEP",
  "courses": [
    {"slug": "prg-loop", "name": "PRG Loop", "course_shape": "loop", "surface": "trail", "difficulty": "easy",
     "geometry_source": "osm", "source_ref": "way/1", "source_checked_at": "2026-11-09",
     "distance_m": 1990, "elevation_m": 4, "official_distance_m": null, "description": "Run it clockwise.",
     "laps": 1, "checkpoints": [],
     "waypoints": [{"lat": 10.0, "lng": 20.0}, {"lat": 10.0045, "lng": 20.0}, {"lat": 10.0045, "lng": 20.0045},
                   {"lat": 10.0, "lng": 20.0045}, {"lat": 10.0, "lng": 20.0}]},
    {"slug": "prg-10k", "name": "PRG 10K", "course_shape": "loop", "surface": "trail", "difficulty": null,
     "geometry_source": "osm", "source_ref": "way/2", "source_checked_at": "2026-11-09",
     "distance_m": 2200, "elevation_m": 0, "official_distance_m": 2200,
     "description": "Measures exactly 10 km: 2 laps of the loop.", "laps": 2, "checkpoints": [],
     "waypoints": [{"lat": 10.01, "lng": 20.0}, {"lat": 10.01, "lng": 20.001}, {"lat": 10.0145, "lng": 20.001},
                   {"lat": 10.0145, "lng": 20.0055}, {"lat": 10.01, "lng": 20.0055}, {"lat": 10.01, "lng": 20.001},
                   {"lat": 10.01, "lng": 20.0}]},
    {"slug": "prg-line", "name": "PRG Line", "course_shape": "point_to_point", "surface": "road", "difficulty": null,
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
    p_j, '00000000-0000-0000-0000-0000000c4b01', '00000000-0000-0000-0000-0000000c4a01', true) l;
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
select col_type_is('public', 'park_courses', 'route_guide', 'jsonb', 'park_courses.route_guide is jsonb');
select col_is_null('public', 'park_courses', 'route_guide', 'park_courses.route_guide is nullable');
select col_type_is('public', 'park_courses', 'route_guide_checked_at', 'date', 'park_courses.route_guide_checked_at is a date');

-- ── 1. The shape predicate ──
create temp table guides (k text primary key, j jsonb not null);
insert into guides (k, j) values ('ok', $json${"version": 1, "lang": "en", "getting_there": "Park by the boathouse.",
                     "steps": [{"kind": "start", "at_m": 0, "name": "Lake Trail"},
                               {"kind": "direction", "at_m": 0, "rotation": "clockwise"},
                               {"kind": "junction", "at_m": 400, "turn": "left", "name": "Ridge Trail"},
                               {"kind": "crossing", "at_m": 600, "crossing": "bridge"},
                               {"kind": "surface", "at_m": 700, "surface": "gravel"},
                               {"kind": "climb", "at_m": 800, "gain_m": 14, "length_m": 300},
                               {"kind": "checkpoint", "at_m": 995, "order": 1, "of": 1},
                               {"kind": "junction", "at_m": 1500, "turn": "right", "way": "fire_road"},
                               {"kind": "finish", "at_m": 1990}]}$json$::jsonb);

select ok(private.park_course_route_guide_ok((select j from guides where k = 'ok')), 'a well-formed guide passes');
select ok(
  private.park_course_route_guide_ok('{"version": 1, "lang": "en", "steps": [{"kind": "start", "at_m": 0, "way": "path"},
    {"kind": "direction", "at_m": 0, "rotation": "counterclockwise", "keep_on": "left", "landmark": "Mill Pond"},
    {"kind": "lap", "at_m": 500, "lap": 2, "of": 2}, {"kind": "finish", "at_m": 1000}]}'::jsonb),
  'a guide with a landmark, a lap and no getting_there passes');
select is(
  (select array_agg(k order by k) from (values
     ('kind', jsonb_set((select j from guides where k = 'ok'), '{steps,2,kind}', '"waypoint"')),
     ('turn', jsonb_set((select j from guides where k = 'ok'), '{steps,2,turn}', '"uturn"')),
     ('extra_key', jsonb_set((select j from guides where k = 'ok'), '{steps,3,name}', '"Old Bridge"')),
     ('name_and_way', jsonb_set((select j from guides where k = 'ok'), '{steps,2,way}', '"path"')),
     ('no_target', (select j #- '{steps,2,name}' from guides where k = 'ok')),
     ('order', jsonb_set((select j from guides where k = 'ok'), '{steps,3,at_m}', '100')),
     ('fraction', jsonb_set((select j from guides where k = 'ok'), '{steps,3,at_m}', '600.5')),
     ('start_late', jsonb_set((select j from guides where k = 'ok'), '{steps,0,at_m}', '5')),
     ('no_finish', (select j #- '{steps,8}' from guides where k = 'ok')),
     ('surface', jsonb_set((select j from guides where k = 'ok'), '{steps,4,surface}', '"lava"')),
     ('climb', jsonb_set((select j from guides where k = 'ok'), '{steps,5,gain_m}', '"14"')),
     ('checkpoint', jsonb_set((select j from guides where k = 'ok'), '{steps,6,order}', '2')),
     ('landmark_alone', jsonb_set((select j from guides where k = 'ok'), '{steps,1,landmark}', '"Lake"')),
     ('version', jsonb_set((select j from guides where k = 'ok'), '{version}', '2')),
     ('lang', jsonb_set((select j from guides where k = 'ok'), '{lang}', '"English"')),
     ('getting_there', jsonb_set((select j from guides where k = 'ok'), '{getting_there}', to_jsonb(repeat('x', 501)))),
     ('top_key', jsonb_set((select j from guides where k = 'ok'), '{notes}', '"x"')),
     ('steps', jsonb_set((select j from guides where k = 'ok'), '{steps}', '{}'))
   ) as bad(k, j)
   where not coalesce(private.park_course_route_guide_ok(j), false)),
  array['checkpoint', 'climb', 'extra_key', 'fraction', 'getting_there', 'kind', 'landmark_alone', 'lang',
        'name_and_way', 'no_finish', 'no_target', 'order', 'start_late', 'steps', 'surface', 'top_key', 'turn',
        'version'],
  'the predicate refuses every malformed guide');
select ok(not private.park_course_route_guide_ok('[]'::jsonb), 'a guide that is not an object fails');

-- ── 2. A load writes the guide and its date ──
create temp table loaded (k text primary key, j jsonb not null);
insert into loaded (k, j)
select 'guided',
       jsonb_set(jsonb_set(j, '{courses,0,route_guide}', (select g.j from guides g where g.k = 'ok')),
                 '{courses,0,route_guide_checked_at}', 'null')
  from manifests where k = 'base';

select pg_temp.load(1, (select j from manifests where k = 'base'));
select is(
  (select array_agg(pc.slug || ':' || coalesce(pc.route_guide::text, '<null>') order by pc.slug)
     from park_courses pc join parks p on p.id = pc.park_id where p.slug = 'prg-test-park'),
  array['prg-10k:<null>', 'prg-line:<null>', 'prg-loop:<null>'],
  'a manifest with no guide leaves the column null');

select pg_temp.load(2, (select j from loaded where k = 'guided'));
select is(
  pg_temp.actions(2),
  array['prg-10k:unchanged:false', 'prg-line:unchanged:false', 'prg-loop:updated:false'],
  'adding a guide reports the course updated and queues no backfill');
select is(
  (select pc.route_guide from park_courses pc join parks p on p.id = pc.park_id
    where p.slug = 'prg-test-park' and pc.slug = 'prg-loop'),
  (select j from guides where k = 'ok'),
  'the guide is stored verbatim');
select is(
  (select pc.route_guide_checked_at from park_courses pc join parks p on p.id = pc.park_id
    where p.slug = 'prg-test-park' and pc.slug = 'prg-loop'),
  null::date,
  'a guide not yet checked on the ground stores no date');

select pg_temp.load(3, (select j from loaded where k = 'guided'));
select is(
  pg_temp.actions(3),
  array['prg-10k:unchanged:false', 'prg-line:unchanged:false', 'prg-loop:unchanged:false'],
  'an identical re-load reports every course unchanged');

select pg_temp.load(4, jsonb_set((select j from loaded where k = 'guided'), '{courses,0,route_guide_checked_at}', '"2026-12-01"'));
select is(
  pg_temp.actions(4),
  array['prg-10k:unchanged:false', 'prg-line:unchanged:false', 'prg-loop:updated:false'],
  'setting the ground-check date reports the course updated and queues no backfill');
select is(
  (select pc.route_guide_checked_at from park_courses pc join parks p on p.id = pc.park_id
    where p.slug = 'prg-test-park' and pc.slug = 'prg-loop'),
  '2026-12-01'::date,
  'the ground-check date is stored');

select pg_temp.load(5, (select j from loaded where k = 'guided'));
select is(
  (select pc.route_guide_checked_at from park_courses pc join parks p on p.id = pc.park_id
    where p.slug = 'prg-test-park' and pc.slug = 'prg-loop'),
  null::date,
  'a manifest that drops the date clears it');

-- ── 3. The CHECKs ──
select throws_ok(
  $$ update park_courses pc set route_guide = '{"version": 1, "lang": "en", "steps": []}'
       from parks p where p.id = pc.park_id and p.slug = 'prg-test-park' $$,
  '23514', null,
  'park_courses refuses a malformed route guide');
select throws_ok(
  $$ update park_courses pc set route_guide_checked_at = '2026-12-01'
       from parks p where p.id = pc.park_id and p.slug = 'prg-test-park' and pc.slug = 'prg-line' $$,
  '23514', null,
  'park_courses refuses a ground-check date on a course with no guide');

-- ── 4. The load refuses what the columns cannot hold ──
select throws_ok(
  $$ select pg_temp.load(6, jsonb_set((select j from loaded where k = 'guided'), '{courses,0,route_guide,steps,2,turn}', '"back"')) $$,
  '22023',
  'load_park_catalogue: course prg-loop has a route_guide that is not a valid step list',
  'the load refuses a malformed guide');
select throws_ok(
  $$ select pg_temp.load(6, jsonb_set((select j from manifests where k = 'base'), '{courses,0,route_guide_checked_at}', '"2026-12-01"')) $$,
  '22023',
  'load_park_catalogue: course prg-loop has a route_guide_checked_at that is not a date of a guide',
  'the load refuses a ground-check date with no guide');
select throws_ok(
  $$ select pg_temp.load(6, jsonb_set((select j from loaded where k = 'guided'), '{courses,0,route_guide_checked_at}', '"1 Dec"')) $$,
  '22023',
  'load_park_catalogue: course prg-loop has a route_guide_checked_at that is not a date of a guide',
  'the load refuses a ground-check date that is not YYYY-MM-DD');

select * from finish();
rollback;

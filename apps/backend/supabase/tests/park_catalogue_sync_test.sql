-- The park catalogue sync contract (migration 20271127002429, issue #1349,
-- decisions § 2429): private.load_park_catalogue is safe to run on every
-- backend release. A second identical load reports every course `unchanged`,
-- writes no row and queues no backfill; the backfill flag queues a backfill
-- for a created course and for changed matching geometry (line, curated line,
-- checkpoints), never for a metadata-only change; a course the manifest drops
-- is closed, not deleted, keeps its efforts, is reported once, and reopens
-- when the manifest names it again; an operator's closure is never touched;
-- an author outside the club is still refused.

begin;

select plan(29);

-- ── Fixture ──
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000000c2a01', 'authenticated', 'authenticated', 'pcs-owner@pcs.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000c2a02', 'authenticated', 'authenticated', 'pcs-outsider@pcs.local', '', now(), now());

select tests.confirm_consent();

insert into clubs (id, owner_id, name, slug, is_public)
values ('00000000-0000-0000-0000-0000000c2b01', '00000000-0000-0000-0000-0000000c2a01', 'PCS Official', 'pcs-official', true);

set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';
update clubs set is_verified = true where id = '00000000-0000-0000-0000-0000000c2b01';
reset role;
set local "request.jwt.claims" = '{}';

-- base: three courses. Each later manifest is base with one change.
create temp table manifests (k text primary key, j jsonb not null);
insert into manifests (k, j) values
('base', $json${
  "park": {"slug": "pcs-test-park", "name": "PCS Test Park", "agency": "state", "region_code": "US-VA",
           "country_code": "US", "timezone": "America/New_York", "website_url": "https://example.org/pcs"},
  "region": "PCS Test Park, Virginia",
  "attribution": "© OpenStreetMap contributors (ODbL)",
  "courses": [
    {"slug": "pcs-a", "name": "PCS A", "course_shape": "loop", "surface": "trail", "difficulty": "easy",
     "geometry_source": "osm", "source_ref": "way/1", "source_checked_at": "2026-11-09",
     "distance_m": 1990, "elevation_m": 4, "official_distance_m": null, "description": "Run it clockwise.",
     "checkpoints": [{"lat": 10.0045, "lng": 20.0045}],
     "waypoints": [{"lat": 10.0, "lng": 20.0}, {"lat": 10.0045, "lng": 20.0}, {"lat": 10.0045, "lng": 20.0045},
                   {"lat": 10.0, "lng": 20.0045}, {"lat": 10.0, "lng": 20.0}]},
    {"slug": "pcs-b", "name": "PCS B", "course_shape": "loop", "surface": "trail", "difficulty": null,
     "geometry_source": "osm", "source_ref": "way/2", "source_checked_at": "2026-11-09",
     "distance_m": 2200, "elevation_m": 0, "official_distance_m": 2200, "description": null,
     "checkpoints": [],
     "start_gate": {"lat": 10.01, "lng": 20.0, "bearing_deg": 80, "half_width_m": 20},
     "waypoints": [{"lat": 10.01, "lng": 20.0}, {"lat": 10.01, "lng": 20.001}, {"lat": 10.0145, "lng": 20.001},
                   {"lat": 10.0145, "lng": 20.0055}, {"lat": 10.01, "lng": 20.0055}, {"lat": 10.01, "lng": 20.001},
                   {"lat": 10.01, "lng": 20.0}]},
    {"slug": "pcs-c", "name": "PCS C", "course_shape": "loop", "surface": "road", "difficulty": "hard",
     "geometry_source": "osm", "source_ref": "way/3", "source_checked_at": "2026-11-09",
     "distance_m": 1990, "elevation_m": 2, "official_distance_m": null, "description": null,
     "checkpoints": [],
     "waypoints": [{"lat": 10.02, "lng": 20.0}, {"lat": 10.0245, "lng": 20.0}, {"lat": 10.0245, "lng": 20.0045},
                   {"lat": 10.02, "lng": 20.0045}, {"lat": 10.02, "lng": 20.0}]}
  ]
}$json$::jsonb);
insert into manifests (k, j)
select 'rename_a', jsonb_set(j, '{courses,0,name}', '"PCS A (renamed)"') from manifests where k = 'base'
union all
select 'redraw_a', jsonb_set(jsonb_set(j, '{courses,0,waypoints,1}', '{"lat": 10.0046, "lng": 20.0}'),
                             '{courses,0,name}', '"PCS A (renamed)"') from manifests where k = 'base'
union all
select 'turn_b', jsonb_set(j, '{courses,1,start_gate,bearing_deg}', '85') from manifests where k = 'base'
union all
select 'checkpoint_c', jsonb_set(j, '{courses,2,checkpoints}', '[{"lat": 10.0245, "lng": 20.0045}]')
  from manifests where k = 'base'
union all
select 'drop_c', j #- '{courses,2}' from manifests where k = 'base';
grant select on manifests to service_role;

create temp table loads (n int, course_slug text, park_course_id uuid, global_segment_id uuid, route_id uuid,
                         action text, backfill_job_id bigint);
grant select, insert on loads to service_role;

-- enqueue_segment_backfill hands back a segment's job while it is still
-- queued, so each load's jobs are finished straight after it, as the worker
-- would: a later load that asked for a backfill then shows as a new job.
create function pg_temp.load(p_n int, p_k text) returns void language sql as $$
  insert into loads
  select p_n, l.* from private.load_park_catalogue(
    (select j from manifests where k = p_k),
    '00000000-0000-0000-0000-0000000c2b01', '00000000-0000-0000-0000-0000000c2a01', true) l;
  update jobs set status = 'done'
   where kind = 'segment_match' and status = 'queued'
     and id in (select backfill_job_id from loads where n = p_n);
$$;

-- Every row the load can write, with the transaction id that last wrote it.
create function pg_temp.row_versions() returns text[] language sql as $$
  select array_agg(v order by v) from (
    select 'park:' || p.xmin::text as v from parks p where p.slug = 'pcs-test-park'
    union all
    select 'course:' || pc.slug || ':' || pc.xmin::text from park_courses pc
      join parks p on p.id = pc.park_id where p.slug = 'pcs-test-park'
    union all
    select 'segment:' || pc.slug || ':' || gs.xmin::text from park_courses pc
      join parks p on p.id = pc.park_id join global_segments gs on gs.id = pc.global_segment_id
     where p.slug = 'pcs-test-park'
    union all
    select 'route:' || pc.slug || ':' || r.xmin::text from park_courses pc
      join parks p on p.id = pc.park_id join routes r on r.id = pc.route_id
     where p.slug = 'pcs-test-park') s;
$$;

create function pg_temp.backfill_jobs() returns bigint language sql as $$
  select count(*) from jobs j
   where j.kind = 'segment_match'
     and (j.payload ->> 'segment_id')::uuid in (
       select pc.global_segment_id from park_courses pc join parks p on p.id = pc.park_id
        where p.slug = 'pcs-test-park');
$$;

create function pg_temp.actions(p_n int) returns text[] language sql as $$
  select array_agg(course_slug || ':' || action || ':' || (backfill_job_id is not null)::text
                   order by course_slug)
    from loads where n = p_n;
$$;

-- ── 1. Created ──
set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';
select pg_temp.load(1, 'base');
reset role;
set local "request.jwt.claims" = '{}';

select is(pg_temp.actions(1),
  array['pcs-a:created:true', 'pcs-b:created:true', 'pcs-c:created:true'],
  'a first load creates every course and queues a backfill for each');
select is(pg_temp.backfill_jobs(), 3::bigint, 'three backfill jobs are queued');

-- Each load below runs in its own subtransaction, so a row it rewrites takes
-- a new xmin that the comparison can see.
insert into runs (id, user_id, started_at, distance_m, duration_s, source, metadata, is_public)
values ('00000000-0000-0000-0000-0000000c2c01', '00000000-0000-0000-0000-0000000c2a01',
        '2026-06-01T12:00:00Z', 2000, 600, 'app', '{"activity_type":"run"}'::jsonb, true);
insert into global_segment_efforts (global_segment_id, run_id, user_id, time_seconds, started_at)
select global_segment_id, '00000000-0000-0000-0000-0000000c2c01', '00000000-0000-0000-0000-0000000c2a01',
       540, '2026-06-01T12:00:00Z'
  from loads where n = 1 and course_slug = 'pcs-c';

create temp table versions (n int primary key, v text[]);
insert into versions values (1, pg_temp.row_versions());

-- ── 2. Unchanged ──
savepoint load2;
set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';
select pg_temp.load(2, 'base');
reset role;
set local "request.jwt.claims" = '{}';
release savepoint load2;

select is(pg_temp.actions(2),
  array['pcs-a:unchanged:false', 'pcs-b:unchanged:false', 'pcs-c:unchanged:false'],
  'a second identical load reports every course unchanged and queues no backfill');
select is(pg_temp.row_versions(), (select v from versions where n = 1),
  'a second identical load rewrites no park, course, segment or route row');
select is(pg_temp.backfill_jobs(), 3::bigint, 'a second identical load queues no job');
select is(array_length((select v from versions where n = 1), 1), 10,
  'the version census reads the park and three rows per course');
select ok(
  (select bool_and(a.park_course_id = b.park_course_id and a.global_segment_id = b.global_segment_id
                   and a.route_id = b.route_id)
     from loads a join loads b using (course_slug) where a.n = 1 and b.n = 2),
  'an unchanged load reports the same ids');

-- ── 3. Metadata only ──
savepoint load3;
set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';
select pg_temp.load(3, 'rename_a');
reset role;
set local "request.jwt.claims" = '{}';
release savepoint load3;

select isnt(pg_temp.row_versions(), (select v from versions where n = 1),
  'a load that rewrites a row moves the version census (the positive control for the unchanged checks)');

select is(pg_temp.actions(3),
  array['pcs-a:updated:false', 'pcs-b:unchanged:false', 'pcs-c:unchanged:false'],
  'a renamed course is updated without a backfill, and the rest are unchanged');
select is(
  (select array[gs.name, r.name] from loads l join global_segments gs on gs.id = l.global_segment_id
     join routes r on r.id = l.route_id where l.n = 3 and l.course_slug = 'pcs-a'),
  array['PCS A (renamed)', 'PCS A (renamed)'],
  'the rename reaches the segment and the route');
select is(pg_temp.backfill_jobs(), 3::bigint, 'a metadata-only change queues no job');

-- ── 4. Changed line ──
set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';
select pg_temp.load(4, 'redraw_a');
reset role;
set local "request.jwt.claims" = '{}';

select is(pg_temp.actions(4),
  array['pcs-a:updated:true', 'pcs-b:unchanged:false', 'pcs-c:unchanged:false'],
  'a redrawn line is updated and queues a backfill');
select is(
  (select j.payload ->> 'segment_id' from loads l join jobs j on j.id = l.backfill_job_id
    where l.n = 4 and l.course_slug = 'pcs-a'),
  (select global_segment_id::text from loads where n = 4 and course_slug = 'pcs-a'),
  'the backfill is a segment_match job for that course''s segment');
select is(
  (select gs.waypoints -> 1 ->> 'lat' from loads l join global_segments gs on gs.id = l.global_segment_id
    where l.n = 4 and l.course_slug = 'pcs-a'),
  '10.0046',
  'the redrawn line is stored');

-- ── 5. Changed curated line ──
set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';
select pg_temp.load(5, 'turn_b');
reset role;
set local "request.jwt.claims" = '{}';

select is(
  (select array_agg(course_slug || ':' || action || ':' || (backfill_job_id is not null)::text order by course_slug)
     from loads where n = 5 and course_slug = 'pcs-b'),
  array['pcs-b:updated:true'],
  'a turned curated start line is a geometry change: updated, with a backfill');
select is(
  (select gs.start_gate_bearing_deg from loads l join global_segments gs on gs.id = l.global_segment_id
    where l.n = 5 and l.course_slug = 'pcs-b'),
  85::float8,
  'the turned line is stored');

-- ── 6. Changed checkpoints ──
set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';
select pg_temp.load(6, 'checkpoint_c');
reset role;
set local "request.jwt.claims" = '{}';

select is(
  (select array_agg(course_slug || ':' || action || ':' || (backfill_job_id is not null)::text order by course_slug)
     from loads where n = 6 and course_slug = 'pcs-c'),
  array['pcs-c:updated:true'],
  'a new checkpoint changes what the matcher scores: updated, with a backfill');

-- ── 7. Removed ──
set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';
select pg_temp.load(7, 'drop_c');
reset role;
set local "request.jwt.claims" = '{}';

select is(
  (select array_agg(course_slug || ':' || action order by course_slug) from loads where n = 7),
  array['pcs-a:unchanged', 'pcs-b:unchanged', 'pcs-c:closed'],
  'a course the manifest no longer names is reported closed');
select is(
  (select array[pc.status, pc.status_note] from park_courses pc where pc.id =
     (select park_course_id from loads where n = 1 and course_slug = 'pcs-c')),
  array['closed', 'Removed from the park catalogue.'],
  'the dropped course is closed with the catalogue note');
select is(
  (select count(*) from global_segment_efforts e
    where e.global_segment_id = (select global_segment_id from loads where n = 1 and course_slug = 'pcs-c')),
  1::bigint,
  'the closed course keeps its segment and its effort');
select ok(
  (select backfill_job_id is null from loads where n = 7 and course_slug = 'pcs-c'),
  'closing queues no backfill');

savepoint load8;
insert into versions values (7, pg_temp.row_versions());
set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';
select pg_temp.load(8, 'drop_c');
reset role;
set local "request.jwt.claims" = '{}';
release savepoint load8;

select is(
  (select array_agg(course_slug || ':' || action order by course_slug) from loads where n = 8),
  array['pcs-a:unchanged', 'pcs-b:unchanged'],
  'a course already closed is not reported again');
select is(pg_temp.row_versions(), (select v from versions where n = 7),
  'and the repeat load writes nothing, the closed course included');

-- ── 8. Re-added ──
set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';
select pg_temp.load(9, 'checkpoint_c');
reset role;
set local "request.jwt.claims" = '{}';

select is(
  (select array[l.action, pc.status, coalesce(pc.status_note, '<null>')]
     from loads l join park_courses pc on pc.id = l.park_course_id where l.n = 9 and l.course_slug = 'pcs-c'),
  array['updated', 'open', '<null>'],
  'a course the catalogue closed reopens when the manifest names it again');

-- ── 9. An operator's closure ──
update park_courses set status = 'closed', status_note = 'Bridge out'
 where id = (select park_course_id from loads where n = 1 and course_slug = 'pcs-c');

set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';
select pg_temp.load(10, 'checkpoint_c');
select pg_temp.load(11, 'drop_c');
reset role;
set local "request.jwt.claims" = '{}';

select is(
  (select action from loads where n = 10 and course_slug = 'pcs-c'),
  'unchanged',
  'an operator-closed course the manifest names is unchanged');
select is(
  (select count(*) from loads where n = 11 and course_slug = 'pcs-c'),
  0::bigint,
  'an operator-closed course the manifest drops is not reported');
select is(
  (select array[pc.status, pc.status_note] from park_courses pc where pc.id =
     (select park_course_id from loads where n = 1 and course_slug = 'pcs-c')),
  array['closed', 'Bridge out'],
  'neither load touches an operator''s closure');

-- ── 10. Refusal ──
set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';
select throws_ok(
  $$ select * from private.load_park_catalogue(
       (select j from manifests where k = 'base'),
       '00000000-0000-0000-0000-0000000c2b01', '00000000-0000-0000-0000-0000000c2a02', true) $$,
  '42501',
  'load_park_catalogue: 00000000-0000-0000-0000-0000000c2a02 is not an active owner or admin of the verified public club 00000000-0000-0000-0000-0000000c2b01',
  'an author outside the club is refused');
reset role;
set local "request.jwt.claims" = '{}';

select is(
  (select array[(select count(*) from park_courses pc join parks p on p.id = pc.park_id
                   where p.slug = 'pcs-test-park'),
                pg_temp.backfill_jobs()]),
  array[3, 8]::bigint[],
  'the refused call wrote nothing and queued nothing');

select * from finish();
rollback;

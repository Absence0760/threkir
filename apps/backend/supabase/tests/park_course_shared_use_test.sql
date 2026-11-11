-- park_courses.shared_use (migration 20271215120001, issue #1345, decisions
-- § 2455): a vocabulary key the clients render as a give-way note naming no
-- one. private.load_park_catalogue writes it, reports a course whose value
-- changed `updated` with no backfill and an unchanged one `unchanged`, and the
-- CHECK refuses free text.

begin;

select plan(8);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values ('00000000-0000-0000-0000-0000000c5a01', 'authenticated', 'authenticated', 'psu-owner@pla.local', '', now(), now());

select tests.confirm_consent();

insert into clubs (id, owner_id, name, slug, is_public)
values ('00000000-0000-0000-0000-0000000c5b01', '00000000-0000-0000-0000-0000000c5a01', 'PSU Official', 'psu-official', true);

set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';
update clubs set is_verified = true where id = '00000000-0000-0000-0000-0000000c5b01';
reset role;
set local "request.jwt.claims" = '{}';

create temp table manifests (k text primary key, j jsonb not null);
insert into manifests (k, j) values
('base', $json${
  "park": {"slug": "psu-test-park", "name": "PSU Test Park", "agency": "county", "region_code": "US-VA",
           "country_code": "US", "timezone": "America/New_York", "website_url": "https://example.org/psu"},
  "region": "PSU Test Park, Virginia",
  "attribution": "© OpenStreetMap contributors (ODbL); elevation: USGS 3DEP",
  "courses": [
    {"slug": "psu-loop", "name": "PSU Loop", "course_shape": "loop", "surface": "road", "difficulty": null,
     "geometry_source": "osm", "source_ref": "way/1", "source_checked_at": "2026-11-10",
     "distance_m": 1990, "elevation_m": 4, "official_distance_m": null, "description": null,
     "laps": 1, "checkpoints": [], "shared_use": null,
     "waypoints": [{"lat": 11.0, "lng": 21.0}, {"lat": 11.0045, "lng": 21.0}, {"lat": 11.0045, "lng": 21.0045},
                   {"lat": 11.0, "lng": 21.0045}, {"lat": 11.0, "lng": 21.0}]}
  ]
}$json$::jsonb);
insert into manifests (k, j)
select 'shared', jsonb_set(j, '{courses,0,shared_use}', '"saturday_morning_group"') from manifests where k = 'base';
insert into manifests (k, j)
select 'free_text', jsonb_set(j, '{courses,0,shared_use}', '"Deep Run group, Saturdays 8am"') from manifests where k = 'base';

create temp table loads (n int, course_slug text, park_course_id uuid, global_segment_id uuid, route_id uuid,
                         action text, backfill_job_id bigint);

create function pg_temp.load(p_n int, p_j jsonb) returns void language sql as $$
  insert into loads
  select p_n, l.* from private.load_park_catalogue(
    p_j, '00000000-0000-0000-0000-0000000c5b01', '00000000-0000-0000-0000-0000000c5a01', true) l;
  update jobs set status = 'done'
   where kind = 'segment_match' and status = 'queued'
     and id in (select backfill_job_id from loads where n = p_n);
$$;

create function pg_temp.shared_use() returns text language sql as $$
  select coalesce(pc.shared_use, '<null>') from park_courses pc join parks p on p.id = pc.park_id
   where p.slug = 'psu-test-park' and pc.slug = 'psu-loop';
$$;

select col_is_null('public', 'park_courses', 'shared_use', 'park_courses.shared_use is nullable');

select pg_temp.load(1, (select j from manifests where k = 'base'));
select is(pg_temp.shared_use(), '<null>', 'a course with no shared use loads null');

select pg_temp.load(2, (select j from manifests where k = 'shared'));
select is(
  (select action || ':' || (backfill_job_id is not null)::text from loads where n = 2),
  'updated:false',
  'setting the shared use reports the course updated and queues no backfill');
select is(pg_temp.shared_use(), 'saturday_morning_group', 'the load writes the shared use');

select pg_temp.load(3, (select j from manifests where k = 'shared'));
select is((select action from loads where n = 3), 'unchanged', 'the same manifest again writes nothing');

select pg_temp.load(4, (select j from manifests where k = 'base'));
select is(pg_temp.shared_use(), '<null>', 'a manifest that drops the shared use clears it');

select throws_ok(
  $$select pg_temp.load(5, (select j from manifests where k = 'free_text'))$$,
  '23514', null,
  'free text, which could name the group, is refused');

select throws_ok(
  $$update park_courses set shared_use = 'sunday' where slug = 'psu-loop'$$,
  '23514', null,
  'the CHECK holds the column to its vocabulary');

select * from finish();
rollback;

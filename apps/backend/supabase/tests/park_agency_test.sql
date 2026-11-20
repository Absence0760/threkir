-- parks.agency takes usfs and usfws (migrations 20280103001431 and
-- 20280103011431, issue #1431, decisions § 2593): a national forest or a
-- wildlife refuge loads with its own agency, takes no NPS park code, and the
-- CHECK still refuses a value outside the vocabulary.

begin;

select plan(7);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values ('00000000-0000-0000-0000-0000000c7a01', 'authenticated', 'authenticated', 'pag-owner@pla.local', '', now(), now());

select tests.confirm_consent();

insert into clubs (id, owner_id, name, slug, is_public)
values ('00000000-0000-0000-0000-0000000c7b01', '00000000-0000-0000-0000-0000000c7a01', 'PAG Official', 'pag-official', true);

set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';
update clubs set is_verified = true where id = '00000000-0000-0000-0000-0000000c7b01';
reset role;
set local "request.jwt.claims" = '{}';

create temp table manifests (k text primary key, j jsonb not null);
insert into manifests (k, j) values
('base', $json${
  "park": {"slug": "pag-test-forest", "name": "PAG Test Forest", "kind": "park", "agency": "usfs", "region_code": "US-VA",
           "country_code": "US", "timezone": "America/New_York", "website_url": "https://example.org/pag"},
  "region": "PAG Test Forest, Virginia",
  "attribution": "© OpenStreetMap contributors (ODbL); elevation: USGS 3DEP",
  "courses": [
    {"slug": "pag-loop", "name": "PAG Loop", "course_shape": "loop", "surface": "road", "difficulty": null,
     "geometry_source": "osm", "source_ref": "way/1", "source_checked_at": "2026-11-10",
     "distance_m": 1990, "elevation_m": 4, "official_distance_m": null, "description": null,
     "laps": 1, "checkpoints": [], "shared_use": null,
     "waypoints": [{"lat": 11.0, "lng": 21.0}, {"lat": 11.0045, "lng": 21.0}, {"lat": 11.0045, "lng": 21.0045},
                   {"lat": 11.0, "lng": 21.0045}, {"lat": 11.0, "lng": 21.0}]}
  ]
}$json$::jsonb);
insert into manifests (k, j)
select 'usfws', jsonb_set(j, '{park,agency}', '"usfws"') from manifests where k = 'base';
insert into manifests (k, j)
select 'blm', jsonb_set(j, '{park,agency}', '"blm"') from manifests where k = 'base';
insert into manifests (k, j)
select 'usfs_code', jsonb_set(j, '{park}', (j -> 'park') || '{"nps_park_code": "gwje"}') from manifests where k = 'base';

create function pg_temp.load(p_j jsonb) returns void language sql as $$
  select count(*) from private.load_park_catalogue(
    p_j, '00000000-0000-0000-0000-0000000c7b01', '00000000-0000-0000-0000-0000000c7a01', false);
  select null::void;
$$;

create function pg_temp.agency() returns text language sql as $$
  select agency from parks where slug = 'pag-test-forest';
$$;

select is(
  (select convalidated from pg_constraint where conname = 'parks_agency_check' and conrelid = 'public.parks'::regclass),
  true,
  'the widened CHECK is validated');

select pg_temp.load((select j from manifests where k = 'base'));
select is(pg_temp.agency(), 'usfs', 'a national forest loads as usfs');

select pg_temp.load((select j from manifests where k = 'usfws'));
select is(pg_temp.agency(), 'usfws', 'a wildlife refuge loads as usfws');

select is(
  (select nps_park_code from parks where slug = 'pag-test-forest'),
  null,
  'a usfs or usfws park carries no NPS park code');

select throws_ok(
  $$select pg_temp.load((select j from manifests where k = 'usfs_code'))$$,
  '23514', null,
  'an NPS park code on a national forest is refused');

select throws_ok(
  $$select pg_temp.load((select j from manifests where k = 'blm'))$$,
  '23514', null,
  'an agency outside the vocabulary is refused');

select throws_ok(
  $$update parks set agency = 'blm' where slug = 'pag-test-forest'$$,
  '23514', null,
  'the CHECK holds the column to its vocabulary');

select * from finish();
rollback;

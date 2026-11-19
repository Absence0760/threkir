-- parks.kind (migration 20280101001431, issues #1431 #1432, decisions § 2581):
-- a catalogue entry is a park or a trail. private.load_park_catalogue writes
-- it from the payload, rewrites it when the manifest changes it, and the
-- column refuses a missing or unknown value.

begin;

select plan(7);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values ('00000000-0000-0000-0000-0000000c6a01', 'authenticated', 'authenticated', 'pki-owner@pla.local', '', now(), now());

select tests.confirm_consent();

insert into clubs (id, owner_id, name, slug, is_public)
values ('00000000-0000-0000-0000-0000000c6b01', '00000000-0000-0000-0000-0000000c6a01', 'PKI Official', 'pki-official', true);

set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';
update clubs set is_verified = true where id = '00000000-0000-0000-0000-0000000c6b01';
reset role;
set local "request.jwt.claims" = '{}';

create temp table manifests (k text primary key, j jsonb not null);
insert into manifests (k, j) values
('base', $json${
  "park": {"slug": "pki-test-trail", "name": "PKI Test Trail", "kind": "trail", "agency": "county", "region_code": "US-VA",
           "country_code": "US", "timezone": "America/New_York", "website_url": "https://example.org/pki"},
  "region": "PKI Test Trail, Virginia",
  "attribution": "© OpenStreetMap contributors (ODbL); elevation: USGS 3DEP",
  "courses": [
    {"slug": "pki-loop", "name": "PKI Loop", "course_shape": "loop", "surface": "road", "difficulty": null,
     "geometry_source": "osm", "source_ref": "way/1", "source_checked_at": "2026-11-10",
     "distance_m": 1990, "elevation_m": 4, "official_distance_m": null, "description": null,
     "laps": 1, "checkpoints": [], "shared_use": null,
     "waypoints": [{"lat": 11.0, "lng": 21.0}, {"lat": 11.0045, "lng": 21.0}, {"lat": 11.0045, "lng": 21.0045},
                   {"lat": 11.0, "lng": 21.0045}, {"lat": 11.0, "lng": 21.0}]}
  ]
}$json$::jsonb);
insert into manifests (k, j)
select 'park', jsonb_set(j, '{park,kind}', '"park"') from manifests where k = 'base';
insert into manifests (k, j)
select 'forest', jsonb_set(j, '{park,kind}', '"forest"') from manifests where k = 'base';
insert into manifests (k, j)
select 'missing', j #- '{park,kind}' from manifests where k = 'base';

create function pg_temp.load(p_j jsonb) returns void language sql as $$
  select count(*) from private.load_park_catalogue(
    p_j, '00000000-0000-0000-0000-0000000c6b01', '00000000-0000-0000-0000-0000000c6a01', false);
  select null::void;
$$;

create function pg_temp.kind() returns text language sql as $$
  select kind from parks where slug = 'pki-test-trail';
$$;

select col_not_null('public', 'parks', 'kind', 'parks.kind is not null');
select col_default_is('public', 'parks', 'kind', 'park'::text, 'an existing park reads as a park');

select pg_temp.load((select j from manifests where k = 'base'));
select is(pg_temp.kind(), 'trail', 'the load writes a trail as a trail');

select pg_temp.load((select j from manifests where k = 'park'));
select is(pg_temp.kind(), 'park', 'a manifest that changes the kind rewrites it');

select throws_ok(
  $$select pg_temp.load((select j from manifests where k = 'forest'))$$,
  '23514', null,
  'a kind outside the vocabulary is refused');

select throws_ok(
  $$select pg_temp.load((select j from manifests where k = 'missing'))$$,
  '23502', null,
  'a payload without a kind is refused, not defaulted');

select throws_ok(
  $$update parks set kind = 'forest' where slug = 'pki-test-trail'$$,
  '23514', null,
  'the CHECK holds the column to its vocabulary');

select * from finish();
rollback;

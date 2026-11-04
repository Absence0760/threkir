-- pgtap suite for the NYC Marathon catalogue segments
-- (20271105000001_nyc_marathon_bridge_segments, issue #1274).
--
-- Pins that the six curated rows exist with the location fields the issue
-- asks for, that a logged-out reader sees them (the catalogue is public),
-- and that each stored distance_m is the length of its own line, since the
-- matcher compares a run's covered distance against it.

begin;

create extension if not exists pgtap with schema public;

select plan(7);

create temp table nyc_ids (id uuid primary key, name text) on commit drop;
insert into nyc_ids values
  ('00000000-0000-4000-8000-0000000c0127', 'Verrazzano-Narrows Bridge (NYC Marathon)'),
  ('00000000-0000-4000-8000-0000000c0128', 'Pulaski Bridge (NYC Marathon)'),
  ('00000000-0000-4000-8000-0000000c0129', 'Queensboro Bridge (NYC Marathon)'),
  ('00000000-0000-4000-8000-0000000c012a', 'Willis Avenue Bridge (NYC Marathon)'),
  ('00000000-0000-4000-8000-0000000c012b', 'Madison Avenue Bridge (NYC Marathon)'),
  ('00000000-0000-4000-8000-0000000c012c', 'Fifth Avenue climb (NYC Marathon)');
grant select on nyc_ids to anon;

select set_eq(
  $$ select g.id, g.name from global_segments g join nyc_ids n using (id) $$,
  $$ select id, name from nyc_ids $$,
  'all six NYC Marathon segments exist under their fixed ids and names'
);

select is(
  (select count(*)::int from global_segments g join nyc_ids n using (id)
    where g.is_active
      and g.surface = 'road'
      and g.region = 'New York, NY'
      and g.country_code = 'US'
      and g.created_by is null),
  6,
  'each is an active road segment in New York, NY, US with no curator account'
);

select is(
  (select count(*)::int from global_segments g join nyc_ids n using (id)
    where g.description like '%OpenStreetMap contributors, ODbL%'),
  6,
  'each description carries the OpenStreetMap ODbL attribution'
);

-- Haversine on the 6371 km sphere, the same formula the matcher uses.
create temp view nyc_lengths as
with pts as (
  select g.id, p.ord,
         (p.pt->>'lat')::float8 as lat, (p.pt->>'lng')::float8 as lng
  from global_segments g
  join nyc_ids n using (id)
  cross join lateral jsonb_array_elements(g.waypoints) with ordinality as p(pt, ord)
), legs as (
  select id, ord, lat, lng,
         lag(lat) over (partition by id order by ord) as plat,
         lag(lng) over (partition by id order by ord) as plng
  from pts
)
select id,
       count(*) as n_points,
       coalesce(sum(
         2 * 6371000 * asin(sqrt(
           sin(radians(lat - plat) / 2) ^ 2
           + cos(radians(plat)) * cos(radians(lat)) * sin(radians(lng - plng) / 2) ^ 2
         ))
       ) filter (where plat is not null), 0) as length_m
from legs
group by id;

select is(
  (select count(*)::int from nyc_lengths l join global_segments g using (id)
    where abs(l.length_m - g.distance_m) <= 1),
  6,
  'each distance_m is the length of its own waypoint line, to the metre'
);

select is(
  (select count(*)::int from nyc_lengths where n_points >= 2),
  6,
  'each line has at least two points'
);

select set_eq(
  $$ select g.id, g.elevation_m::int from global_segments g join nyc_ids n using (id) $$,
  $$ values
       ('00000000-0000-4000-8000-0000000c0127'::uuid, null::int),
       ('00000000-0000-4000-8000-0000000c0128', null),
       ('00000000-0000-4000-8000-0000000c0129', null),
       ('00000000-0000-4000-8000-0000000c012a', null),
       ('00000000-0000-4000-8000-0000000c012b', null),
       ('00000000-0000-4000-8000-0000000c012c', 29) $$,
  'the Fifth Avenue climb carries its 29 m rise; the bridges carry none'
);

set local role anon;

select is(
  (select count(*)::int from global_segments g join nyc_ids n using (id)),
  6,
  'a logged-out reader sees all six'
);

select * from finish();
rollback;

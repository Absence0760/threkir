-- An official park_courses board carries its region (issue #1313, migration
-- 20271214131301): private.load_official_catalogue writes
-- challenges.park_region_code from the item, a second identical load is
-- `unchanged`, a board not yet started takes a changed region, a started one
-- keeps it, and an item whose region and metric disagree is refused.

begin;

select plan(12);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values ('00000000-0000-0000-0000-0000000d1301', 'authenticated', 'authenticated', 'pr-owner@pr.local', '', now(), now());

select tests.confirm_consent();

insert into clubs (id, owner_id, name, slug, is_public)
values ('00000000-0000-0000-0000-0000000d1311', '00000000-0000-0000-0000-0000000d1301', 'PR Official', 'pr-official', true);

set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';
update clubs set is_verified = true where id = '00000000-0000-0000-0000-0000000d1311';

create temp table catalogues (k text primary key, j jsonb not null);
insert into catalogues (k, j) values
('base', $json${
  "plans": [], "gym_routines": [], "race_courses": [],
  "challenges": [
    {"slug": "pr-passport", "recurrence": "yearly", "title": "Run 10 Virginia park courses in {period}",
     "description": "Fixture passport.", "metric": "park_courses", "goal_value": 10, "activity_type": "run",
     "park_region_code": "US-VA"}
  ]
}$json$::jsonb);
insert into catalogues (k, j)
select 'other_region', jsonb_set(j, '{challenges,0,park_region_code}', '"US-NC"') from catalogues where k = 'base'
union all
select 'no_region', j #- '{challenges,0,park_region_code}' from catalogues where k = 'base'
union all
select 'region_on_distance', jsonb_set(jsonb_set(j, '{challenges,0,metric}', '"distance"'), '{challenges,0,goal_value}', '50000')
  from catalogues where k = 'base'
union all
select 'bad_region', jsonb_set(j, '{challenges,0,park_region_code}', '"virginia"') from catalogues where k = 'base';

create temp table loads (n int, kind text, slug text, target_id uuid, action text);

create function pg_temp.load(p_n int, p_k text, p_now timestamptz)
returns void language sql as $$
  insert into loads
  select p_n, l.* from private.load_official_catalogue(
    (select j from catalogues where k = p_k),
    '00000000-0000-0000-0000-0000000d1311', '00000000-0000-0000-0000-0000000d1301', p_now) l;
$$;

create function pg_temp.actions(p_n int) returns text language sql as $$
  select string_agg(slug || '=' || action, ', ' order by slug) from loads where n = p_n;
$$;

-- Late November: the current year's board is more than half over, so only the
-- next year's (inside the 45-day lookahead) is opened, and it has not started.
select pg_temp.load(1, 'base', '2027-11-25 12:00+00');
select is(pg_temp.actions(1), 'pr-passport@2028=created', 'the next year''s passport board is created');
select is(
  (select park_region_code from challenges where id = (select target_id from loads where n = 1)),
  'US-VA', 'the board carries the item''s region');
select is(
  (select metric from challenges where id = (select target_id from loads where n = 1)),
  'park_courses', 'the board counts park courses');

select pg_temp.load(2, 'base', '2027-11-25 12:00+00');
select is(pg_temp.actions(2), 'pr-passport@2028=unchanged', 'a second identical load is unchanged');

select pg_temp.load(3, 'other_region', '2027-11-25 12:00+00');
select is(pg_temp.actions(3), 'pr-passport@2028=updated', 'a board not yet started takes a changed region');
select is(
  (select park_region_code from challenges where id = (select target_id from loads where n = 3)),
  'US-NC', 'the new region is written');

select pg_temp.load(4, 'base', '2028-01-05 12:00+00');
select is(pg_temp.actions(4), 'pr-passport@2028=unchanged', 'a started board keeps its terms');
select is(
  (select park_region_code from challenges where id = (select target_id from loads where n = 4)),
  'US-NC', 'a started board keeps the region it opened with');

select throws_ok(
  $$ select pg_temp.load(5, 'no_region', '2027-11-25 12:00+00') $$,
  '22023', null, 'a park_courses item without a region is refused');
select throws_ok(
  $$ select pg_temp.load(6, 'region_on_distance', '2027-11-25 12:00+00') $$,
  '22023', null, 'a region on any other metric is refused');
select throws_ok(
  $$ select pg_temp.load(7, 'bad_region', '2027-11-25 12:00+00') $$,
  '23514', null, 'a region that is not ISO 3166-2 is refused by the CHECK');
select is((select count(*)::int from loads where n >= 5), 0, 'a refused load writes nothing');

select * from finish();
rollback;

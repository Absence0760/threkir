-- Park course badges, the park_courses challenge metric and the run's park
-- course times (migration 20271123002404, issue #1313 phase 5, decisions
-- § 2404 / § 2405).
--
-- Fixture regions US-ZZ and US-ZY are fictional so the seed's Fixture State
-- Park (US-VA) never enters a passport count.
--   US-ZZ: P1 (c1, c2), P2 (c3, plus c4 closed), P3 (c5)
--   US-ZY: P4 (c6, c7, c8)

begin;

select plan(22);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000000ba001', 'authenticated', 'authenticated', 'a@pcb.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000ba002', 'authenticated', 'authenticated', 'b@pcb.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000ba003', 'authenticated', 'authenticated', 'c@pcb.local', '', now(), now());

insert into user_profiles (id, display_name)
values
  ('00000000-0000-0000-0000-0000000ba001', 'Badge A'),
  ('00000000-0000-0000-0000-0000000ba002', 'Badge B'),
  ('00000000-0000-0000-0000-0000000ba003', 'Badge C')
on conflict (id) do nothing;

select tests.confirm_consent();

insert into global_segments (id, name, waypoints, distance_m, is_active)
select ('bab0bab0-0000-0000-0000-0000000000d' || n)::uuid, 'Badge Course ' || n,
       '[{"lat":36.0,"lng":-78.0},{"lat":36.004,"lng":-78.0}]', 450, true
from generate_series(1, 8) n;

insert into parks (id, slug, name, agency, region_code, country_code, timezone)
values
  ('bab0bab0-0000-0000-0000-0000000000a1', 'badge-park-one', 'Badge Park One', 'state', 'US-ZZ', 'US', 'America/New_York'),
  ('bab0bab0-0000-0000-0000-0000000000a2', 'badge-park-two', 'Badge Park Two', 'state', 'US-ZZ', 'US', 'America/New_York'),
  ('bab0bab0-0000-0000-0000-0000000000a3', 'badge-park-three', 'Badge Park Three', 'nps', 'US-ZZ', 'US', 'America/New_York'),
  ('bab0bab0-0000-0000-0000-0000000000a4', 'badge-park-four', 'Badge Park Four', 'state', 'US-ZY', 'US', 'America/Chicago');

insert into park_courses (id, park_id, global_segment_id, slug, course_shape, status, geometry_source)
values
  ('bab0bab0-0000-0000-0000-0000000000c1', 'bab0bab0-0000-0000-0000-0000000000a1', 'bab0bab0-0000-0000-0000-0000000000d1', 'one', 'loop', 'open', 'osm'),
  ('bab0bab0-0000-0000-0000-0000000000c2', 'bab0bab0-0000-0000-0000-0000000000a1', 'bab0bab0-0000-0000-0000-0000000000d2', 'two', 'loop', 'seasonal', 'osm'),
  ('bab0bab0-0000-0000-0000-0000000000c3', 'bab0bab0-0000-0000-0000-0000000000a2', 'bab0bab0-0000-0000-0000-0000000000d3', 'three', 'loop', 'open', 'osm'),
  ('bab0bab0-0000-0000-0000-0000000000c4', 'bab0bab0-0000-0000-0000-0000000000a2', 'bab0bab0-0000-0000-0000-0000000000d4', 'four', 'loop', 'closed', 'osm'),
  ('bab0bab0-0000-0000-0000-0000000000c5', 'bab0bab0-0000-0000-0000-0000000000a3', 'bab0bab0-0000-0000-0000-0000000000d5', 'five', 'loop', 'open', 'osm'),
  ('bab0bab0-0000-0000-0000-0000000000c6', 'bab0bab0-0000-0000-0000-0000000000a4', 'bab0bab0-0000-0000-0000-0000000000d6', 'six', 'loop', 'open', 'osm'),
  ('bab0bab0-0000-0000-0000-0000000000c7', 'bab0bab0-0000-0000-0000-0000000000a4', 'bab0bab0-0000-0000-0000-0000000000d7', 'seven', 'loop', 'open', 'osm'),
  ('bab0bab0-0000-0000-0000-0000000000c8', 'bab0bab0-0000-0000-0000-0000000000a4', 'bab0bab0-0000-0000-0000-0000000000d8', 'eight', 'loop', 'open', 'osm');

-- The yearly passport: four US-ZZ courses inside the window. A joins first, so
-- the effort trigger is what completes it.
insert into challenges (id, creator_id, title, metric, scope, goal_value, starts_at, ends_at, is_public, park_region_code)
values ('bab0bab0-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000ba001',
        'ZZ passport', 'park_courses', 'individual', 4,
        now() - interval '30 days', now() + interval '30 days', true, 'US-ZZ');
insert into challenge_participants (challenge_id, user_id)
values ('bab0bab0-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000ba001'),
       ('bab0bab0-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000ba002');

-- One run per course for A, B on P4, C on a DNF run. Efforts are written the
-- way the owner fallback writes them (as the owner, under the owner RLS); the
-- server matcher's insert fires the same statement trigger.
create temporary table badge_runs (n int, user_id uuid, run_id uuid, segment_id uuid, dnf boolean);
insert into badge_runs values
  (1, '00000000-0000-0000-0000-0000000ba001', 'bab0bab0-0000-0000-0000-0000000001a1', 'bab0bab0-0000-0000-0000-0000000000d1', false),
  (2, '00000000-0000-0000-0000-0000000ba001', 'bab0bab0-0000-0000-0000-0000000001a2', 'bab0bab0-0000-0000-0000-0000000000d2', false),
  (3, '00000000-0000-0000-0000-0000000ba001', 'bab0bab0-0000-0000-0000-0000000001a3', 'bab0bab0-0000-0000-0000-0000000000d3', false),
  (4, '00000000-0000-0000-0000-0000000ba001', 'bab0bab0-0000-0000-0000-0000000001a5', 'bab0bab0-0000-0000-0000-0000000000d5', false),
  (5, '00000000-0000-0000-0000-0000000ba002', 'bab0bab0-0000-0000-0000-0000000001b6', 'bab0bab0-0000-0000-0000-0000000000d6', false),
  (6, '00000000-0000-0000-0000-0000000ba002', 'bab0bab0-0000-0000-0000-0000000001b7', 'bab0bab0-0000-0000-0000-0000000000d7', false),
  (7, '00000000-0000-0000-0000-0000000ba003', 'bab0bab0-0000-0000-0000-0000000001c1', 'bab0bab0-0000-0000-0000-0000000000d1', true);
grant select on badge_runs to authenticated;

insert into runs (id, user_id, started_at, distance_m, duration_s, source, metadata, is_public, is_dnf)
select b.run_id, b.user_id, now() - interval '2 days' + b.n * interval '1 hour', 5000, 1500, 'app',
       '{"activity_type":"run"}'::jsonb, true, b.dnf
from badge_runs b;

create or replace function pg_temp.run_course(p_n int) returns void
language plpgsql as $$
declare
  r record;
begin
  select * into r from badge_runs where n = p_n;
  perform set_config('request.jwt.claims', json_build_object('sub', r.user_id)::text, true);
  set local role authenticated;
  insert into global_segment_efforts (global_segment_id, run_id, user_id, time_seconds, started_at)
  values (r.segment_id, r.run_id, r.user_id, 600 + p_n, now() - interval '2 days' + p_n * interval '1 hour');
  reset role;
  perform set_config('request.jwt.claims', '', true);
end;
$$;

create or replace function pg_temp.tiers(p_user uuid, p_key text) returns text
language sql as $$
  select coalesce(string_agg(tier, ',' order by tier), '') from achievements
  where user_id = p_user and badge_key = p_key;
$$;

-- ── park_courses: the first course ──
select pg_temp.run_course(1);
select is(pg_temp.tiers('00000000-0000-0000-0000-0000000ba001', 'park_courses'), 'bronze',
  'a first park course effort awards park_courses bronze from the effort trigger');
select is(
  (select source_kind || ':' || coalesce(source_id::text, 'null') from achievements
   where user_id = '00000000-0000-0000-0000-0000000ba001' and badge_key = 'park_courses'),
  'segment:null', 'the award is a segment-kind count that names no course');
select is(pg_temp.tiers('00000000-0000-0000-0000-0000000ba001', 'park_complete'), '',
  'one of two courses does not complete the park');

-- ── park_complete: both courses of P1 (a seasonal course counts) ──
select pg_temp.run_course(2);
select is(pg_temp.tiers('00000000-0000-0000-0000-0000000ba001', 'park_complete'), 'bronze',
  'every course of a two-course park awards park_complete bronze');

-- ── P2 has one course not closed: it can never be a park_complete park ──
select pg_temp.run_course(3);
select is(
  (select value_num::int from achievement_tiers_met('00000000-0000-0000-0000-0000000ba001')
   where badge_key = 'park_complete'),
  1, 'a park left with one course after its closed one is not counted complete');
select is(pg_temp.tiers('00000000-0000-0000-0000-0000000ba001', 'park_passport'), '',
  'no passport while P3 has no completion');

-- ── park_passport: a course in every US-ZZ park ──
select pg_temp.run_course(4);
select is(pg_temp.tiers('00000000-0000-0000-0000-0000000ba001', 'park_passport'), 'bronze',
  'a course in each of the three US-ZZ parks awards park_passport bronze');
select is(
  (select value_num::int from achievement_tiers_met('00000000-0000-0000-0000-0000000ba001')
   where badge_key = 'park_courses' order by rank desc limit 1),
  4, 'four distinct courses counted');
select is(
  (select count(*)::int from notifications n join achievements a on a.id = n.achievement_id
   where a.user_id = '00000000-0000-0000-0000-0000000ba001' and a.badge_key like 'park_%'),
  3, 'each new park badge raises one achievement notification');

-- ── challenge metric ──
select is(
  (select count(*)::int from challenge_badges
   where challenge_id = 'bab0bab0-0000-0000-0000-0000000000e1' and user_id = '00000000-0000-0000-0000-0000000ba001'),
  1, 'the fourth course completes the passport challenge from the effort trigger');

-- B: two P4 courses, outside the challenge's region.
select pg_temp.run_course(5);
select pg_temp.run_course(6);

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000ba001"}';
select results_eq(
  $$ select user_id, value::int from challenge_leaderboard('bab0bab0-0000-0000-0000-0000000000e1', false)
     order by rank, user_id $$,
  $$ values ('00000000-0000-0000-0000-0000000ba001'::uuid, 4),
            ('00000000-0000-0000-0000-0000000ba002'::uuid, 0) $$,
  'the board counts distinct US-ZZ courses; courses in another region count 0');
select is(
  (select value::int from challenge_leaderboard('bab0bab0-0000-0000-0000-0000000000e1', true)),
  4, 'the team board counts distinct courses across the team');
reset role;

update challenges set park_region_code = null where id = 'bab0bab0-0000-0000-0000-0000000000e1';
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000ba002"}';
select is(
  (select value::int from challenge_leaderboard('bab0bab0-0000-0000-0000-0000000000e1', false)
   where user_id = '00000000-0000-0000-0000-0000000ba002'),
  2, 'without a region every park counts');
reset role;

select throws_ok(
  $$ insert into challenges (creator_id, title, metric, scope, goal_value, starts_at, ends_at, park_region_code)
     values ('00000000-0000-0000-0000-0000000ba001', 'bad', 'distance', 'individual', 1000,
             now(), now() + interval '1 day', 'US-ZZ') $$,
  '23514', null, 'a region on any other metric is refused');
select throws_ok(
  $$ insert into challenges (creator_id, title, metric, scope, goal_value, starts_at, ends_at, park_region_code)
     values ('00000000-0000-0000-0000-0000000ba001', 'bad', 'park_courses', 'individual', 2,
             now(), now() + interval '1 day', 'virginia') $$,
  '23514', null, 'a region that is not ISO 3166-2 is refused');

-- ── closing a course completes a park for runners already there ──
select is(pg_temp.tiers('00000000-0000-0000-0000-0000000ba002', 'park_complete'), '',
  'two of three open P4 courses is not complete');
update park_courses set status = 'closed' where id = 'bab0bab0-0000-0000-0000-0000000000c8';
select is(pg_temp.tiers('00000000-0000-0000-0000-0000000ba002', 'park_complete'), 'bronze',
  'closing the course B has not run completes P4 for B through the park_courses trigger');

-- ── a DNF run earns nothing ──
select pg_temp.run_course(7);
select is(pg_temp.tiers('00000000-0000-0000-0000-0000000ba003', 'park_courses'), '',
  'an effort on a DNF run does not count');

-- ── run_park_course_times ──
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000ba001"}';
select results_eq(
  $$ select course_name, park_name, region_code, time_seconds, season_rank
     from run_park_course_times('bab0bab0-0000-0000-0000-0000000001a1') $$,
  $$ values ('Badge Course 1'::text, 'Badge Park One'::text, 'US-ZZ'::text, 601, 1) $$,
  'the owner reads the course, its park, the time and the season rank');
select is(
  (select season from run_park_course_times('bab0bab0-0000-0000-0000-0000000001a1')),
  extract(year from ((now() - interval '2 days' + interval '1 hour') at time zone 'America/New_York'))::int,
  'the season is the calendar year in the park''s timezone');

set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000ba002"}';
select is(
  (select count(*)::int from run_park_course_times('bab0bab0-0000-0000-0000-0000000001a1')),
  0, 'another runner gets no rows for a run that is not theirs, public or not');
reset role;

select ok(
  not has_function_privilege('anon', 'public.run_park_course_times(uuid)', 'execute'),
  'anon cannot call run_park_course_times');

select * from finish();
rollback;

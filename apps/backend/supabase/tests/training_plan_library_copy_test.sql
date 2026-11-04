-- Pins migration 20271107000001 (decisions § 2337).
--
-- A: a plan links its own library copy through library_copy_id, which only
-- publish_plan_to_library writes, which no template carries, and which goes
-- null when the copy is deleted.
-- B: a library copy keeps the plan's design and none of the publisher's data:
-- no real dates (moved onto the week of 2001-01-01, weekday kept), no
-- absolute pace, no goal time, no notes, no race name, no duration that
-- pairs with a distance. The field rules hold for every writer; only the
-- publish RPC may create a public template from a client role.

begin;
select plan(27);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('c1c1c1c1-0000-0000-0000-0000000e0001', 'authenticated', 'authenticated', 'lcp-owner@lcp.local', '', now(), now()),
  ('c1c1c1c1-0000-0000-0000-0000000e0002', 'authenticated', 'authenticated', 'lcp-reader@lcp.local', '', now(), now())
on conflict (id) do nothing;
insert into user_profiles (id, display_name)
values
  ('c1c1c1c1-0000-0000-0000-0000000e0001', 'LCP Owner'),
  ('c1c1c1c1-0000-0000-0000-0000000e0002', 'LCP Reader')
on conflict (id) do nothing;

-- The source: a Wednesday start, a goal time, notes everywhere, an interval
-- session with paces inside and outside `structure`, and a B race.
insert into training_plans (id, user_id, name, goal_event, goal_distance_m, goal_time_seconds,
  start_date, end_date, days_per_week, status, notes, vdot, rules)
values ('c2c2c2c2-0000-0000-0000-0000000e0001', 'c1c1c1c1-0000-0000-0000-0000000e0001', 'Spring 10K',
  'distance_10k', 10000, 2700, '2036-03-05', '2036-03-18', 4, 'completed', 'left knee', 50,
  '["80% easy"]'::jsonb);
insert into plan_weeks (id, plan_id, week_index, phase, target_volume_m, notes)
values ('c3c3c3c3-0000-0000-0000-0000000e0001', 'c2c2c2c2-0000-0000-0000-0000000e0001', 0, 'build', 30000, 'travel week');
insert into plan_workouts (week_id, scheduled_date, kind, target_distance_m, target_duration_seconds,
  target_pace_sec_per_km, target_pace_end_sec_per_km, target_pace_tolerance_sec, pace_zone, structure,
  notes, target_rpe_min, target_rpe_max, race_name, race_priority)
values
  ('c3c3c3c3-0000-0000-0000-0000000e0001', '2036-03-07', 'interval', 8000, 2400, 270, 260, 5, 'interval',
   '{"warmup": {"distance_m": 2000, "pace": "easy"},
     "repeats": {"count": 5, "distance_m": 1000, "duration_s": 240, "pace_sec_per_km": 240,
                 "recovery_distance_m": 400, "recovery_duration_s": 150, "recovery_pace": "jog"}}'::jsonb,
   '5x1k at 4:00', 7, 8, null, null),
  ('c3c3c3c3-0000-0000-0000-0000000e0001', '2036-03-12', 'race', 5000, 1260, 252, null, null, null, null,
   null, null, null, 'Parkrun PB attempt', 'B'),
  ('c3c3c3c3-0000-0000-0000-0000000e0001', '2036-03-14', 'easy', null, 2700, null, null, null, 'easy', null,
   null, 3, 4, null, null);

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"c1c1c1c1-0000-0000-0000-0000000e0001","role":"authenticated"}';
create temp table lcp_copy on commit drop as
  select publish_plan_to_library('c2c2c2c2-0000-0000-0000-0000000e0001') as id;
reset role;

-- ── A. The link ─────────────────────────────────────────────────────────────

select is(
  (select library_copy_id from training_plans where id = 'c2c2c2c2-0000-0000-0000-0000000e0001'),
  (select id from lcp_copy),
  'publishing links the source plan to its library copy');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"c1c1c1c1-0000-0000-0000-0000000e0001","role":"authenticated"}';
select is(
  publish_plan_to_library('c2c2c2c2-0000-0000-0000-0000000e0001'),
  (select id from lcp_copy),
  'a second publish returns the existing copy');
update training_plans set library_copy_id = null where id = 'c2c2c2c2-0000-0000-0000-0000000e0001';
reset role;

select is(
  (select count(*)::int from training_plans
    where user_id = 'c1c1c1c1-0000-0000-0000-0000000e0001' and is_public_template),
  1,
  'a second publish makes no second copy');
select is(
  (select library_copy_id from training_plans where id = 'c2c2c2c2-0000-0000-0000-0000000e0001'),
  (select id from lcp_copy),
  'a client cannot clear or rewrite library_copy_id');
select is(
  (select library_copy_id from training_plans where id = (select id from lcp_copy)),
  null::uuid,
  'the copy itself carries no link');
select hasnt_column('public', 'training_plans', 'published_from_plan_id',
  'the copy no longer names the plan it came from');

-- Another signed-in user reads the copy and never the source.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"c1c1c1c1-0000-0000-0000-0000000e0002","role":"authenticated"}';
select is(
  (select count(*)::int from training_plans where id = (select id from lcp_copy)),
  1,
  'a library reader sees the copy');
select is(
  (select count(*)::int from training_plans where library_copy_id is not null),
  0,
  'a library reader cannot read any library_copy_id');
select throws_ok(
  $$ select publish_plan_to_library('c2c2c2c2-0000-0000-0000-0000000e0001') $$,
  'P0002', 'publish_plan_to_library: plan not found',
  'nobody but the owner can publish a plan');
reset role;

-- ── B. What the copy keeps ──────────────────────────────────────────────────

select is(
  (select array[start_date, end_date] from training_plans where id = (select id from lcp_copy)),
  array[date '2001-01-03', date '2001-01-16'],
  'the copy''s dates move onto the reference week, keeping the start weekday and the length');
select is(
  (select coalesce(goal_time_seconds::text, 'null') || '/' || coalesce(notes, 'null') || '/' || coalesce(vdot::text, 'null')
     from training_plans where id = (select id from lcp_copy)),
  'null/null/null',
  'the copy carries no goal time, notes or VDOT');
select is(
  (select rules from training_plans where id = (select id from lcp_copy)),
  '["80% easy"]'::jsonb,
  'the plan-wide rules are design and are kept');
select is(
  (select notes from plan_weeks where plan_id = (select id from lcp_copy)),
  null::text,
  'week notes are dropped');

create temp table lcp_wo on commit drop as
  select wo.* , wo.scheduled_date - p.start_date as day
    from plan_workouts wo
    join plan_weeks w on w.id = wo.week_id
    join training_plans p on p.id = w.plan_id
   where p.id = (select id from lcp_copy);

select is(
  (select array_agg(day order by day) from lcp_wo),
  array[2, 7, 9],
  'every workout keeps its day within the plan');
select is(
  (select count(*)::int from lcp_wo
    where target_pace_sec_per_km is not null or target_pace_end_sec_per_km is not null
       or target_pace_tolerance_sec is not null),
  0,
  'no absolute pace survives on any workout');
select is(
  (select count(*)::int from lcp_wo where notes is not null or race_name is not null),
  0,
  'workout notes and race names are dropped');
select is(
  (select structure from lcp_wo where kind = 'interval'),
  '{"warmup": {"distance_m": 2000, "pace": "easy"},
    "repeats": {"count": 5, "distance_m": 1000, "recovery_distance_m": 400, "recovery_pace": "jog"}}'::jsonb,
  'structure keeps reps, distances and effort labels, and loses every pace and paired duration');
select is(
  (select array[target_distance_m::int, target_rpe_min, target_rpe_max]::int[] from lcp_wo where kind = 'interval'),
  array[8000, 7, 8],
  'distance and RPE range are kept');
select is(
  (select pace_zone from lcp_wo where kind = 'interval'),
  'interval',
  'the named pace zone is kept');
select is(
  (select coalesce(target_duration_seconds::text, 'null') from lcp_wo where kind = 'interval'),
  'null',
  'a duration set beside a distance is dropped: together they are a pace');
select is(
  (select coalesce(target_duration_seconds::text, 'null') || '/' || race_priority from lcp_wo where kind = 'race'),
  'null/B',
  'a race keeps its priority and drops its target time');
select is(
  (select target_duration_seconds from lcp_wo where kind = 'easy'),
  2700,
  'a time-only session keeps its duration');

-- ── Every writer, and the only door ─────────────────────────────────────────

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"c1c1c1c1-0000-0000-0000-0000000e0001","role":"authenticated"}';
select throws_ok(
  $$ insert into training_plans (user_id, name, goal_event, goal_distance_m, start_date, end_date,
       days_per_week, status, is_template, is_public_template)
     values ('c1c1c1c1-0000-0000-0000-0000000e0001', 'Direct', 'distance_10k', 10000, '2036-01-01',
       '2036-01-07', 4, 'completed', true, true) $$,
  '42501', 'training_plans: publish to the library with publish_plan_to_library',
  'a client cannot insert a public template directly');
select throws_ok(
  $$ update training_plans set is_template = true, is_public_template = true
      where id = 'c2c2c2c2-0000-0000-0000-0000000e0001' $$,
  '42501', 'training_plans: publish to the library with publish_plan_to_library',
  'a client cannot flip a plan public');
reset role;

-- A non-client writer flipping a template public (a restore) redacts what
-- the plan already holds.
insert into training_plans (id, user_id, name, goal_event, goal_distance_m, start_date, end_date,
  days_per_week, status, is_template)
values ('c2c2c2c2-0000-0000-0000-0000000e0009', 'c1c1c1c1-0000-0000-0000-0000000e0001', 'Restored',
  'distance_10k', 10000, '2036-04-01', '2036-04-07', 4, 'completed', true);
insert into plan_weeks (id, plan_id, week_index, phase, target_volume_m, notes)
values ('c3c3c3c3-0000-0000-0000-0000000e0009', 'c2c2c2c2-0000-0000-0000-0000000e0009', 0, 'base', 20000, 'mine');
insert into plan_workouts (week_id, scheduled_date, kind, target_distance_m, target_pace_sec_per_km, notes)
values ('c3c3c3c3-0000-0000-0000-0000000e0009', '2036-04-02', 'easy', 6000, 330, 'mine');
update training_plans set is_public_template = true where id = 'c2c2c2c2-0000-0000-0000-0000000e0009';
select is(
  (select coalesce(wo.target_pace_sec_per_km::text, 'null') || '/' || coalesce(wo.notes, 'null') || '/' || coalesce(w.notes, 'null')
     from plan_workouts wo join plan_weeks w on w.id = wo.week_id
    where w.plan_id = 'c2c2c2c2-0000-0000-0000-0000000e0009'),
  'null/null/null',
  'a template flipped public by a non-client writer is redacted too');

-- Unpublish: deleting the copy clears the link and keeps the source.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"c1c1c1c1-0000-0000-0000-0000000e0001","role":"authenticated"}';
delete from training_plans where id = (select id from lcp_copy);
reset role;
select is(
  (select coalesce(library_copy_id::text, 'null') from training_plans where id = 'c2c2c2c2-0000-0000-0000-0000000e0001'),
  'null',
  'deleting the copy clears the source''s link and keeps the source');

select ok(
  not has_function_privilege('anon', 'public.publish_plan_to_library(uuid)', 'execute'),
  'anon cannot publish');

select * from finish();
rollback;

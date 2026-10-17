-- Pins migration 20270830000004 (decisions § 2050): create_training_plan
-- resolves overlapping active plans and writes the new plan, weeks and
-- workouts in one transaction, and the clone RPCs take the same p_overlap.

begin;
select plan(25);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('abababab-0000-0000-0000-0000000a0001', 'authenticated', 'authenticated', 'apc-runner@apc.local', '', now(), now()),
  ('abababab-0000-0000-0000-0000000a0002', 'authenticated', 'authenticated', 'apc-other@apc.local', '', now(), now())
on conflict (id) do nothing;
insert into user_profiles (id, display_name) values
  ('abababab-0000-0000-0000-0000000a0001', 'APC Runner'),
  ('abababab-0000-0000-0000-0000000a0002', 'APC Other')
on conflict (id) do nothing;

-- The runner's current block, 2031-03-02 .. 2031-04-26, with one workout in
-- its last week, plus a personal template to clone.
insert into training_plans (id, user_id, name, goal_event, goal_distance_m, start_date, end_date, days_per_week, status, is_template, is_public_template)
values
  ('acacacac-0000-0000-0000-0000000b0001', 'abababab-0000-0000-0000-0000000a0001', 'Spring block', 'distance_half', 21097, '2031-03-02', '2031-04-26', 4, 'active', false, false),
  ('acacacac-0000-0000-0000-0000000b0009', 'abababab-0000-0000-0000-0000000a0001', 'Two-week template', 'distance_10k', 10000, '2030-01-05', '2030-01-18', 4, 'completed', true, true);
insert into plan_weeks (id, plan_id, week_index, phase, target_volume_m) values
  ('adadadad-0000-0000-0000-0000000b0001', 'acacacac-0000-0000-0000-0000000b0001', 7, 'taper', 10000),
  ('adadadad-0000-0000-0000-0000000b0009', 'acacacac-0000-0000-0000-0000000b0009', 0, 'base', 10000);
insert into plan_workouts (week_id, scheduled_date, kind, target_distance_m) values
  ('adadadad-0000-0000-0000-0000000b0001', '2031-04-25', 'easy', 6000),
  ('adadadad-0000-0000-0000-0000000b0009', '2030-01-07', 'easy', 6000);

create temp table apc_args (label text primary key, plan jsonb, weeks jsonb);
grant select on apc_args to authenticated;
insert into apc_args values
  ('overlapping',
   '{"name":"Autumn half","goal_event":"distance_half","goal_distance_m":21097.5,"goal_time_seconds":6300,"start_date":"2031-04-12","end_date":"2031-05-09","days_per_week":4,"vdot":45.2,"current_5k_seconds":1320,"notes":"  "}',
   '[{"week_index":0,"phase":"base","target_volume_m":30000,"notes":null,"workouts":[{"scheduled_date":"2031-04-13","kind":"easy","target_distance_m":8000,"target_duration_seconds":null,"target_pace_sec_per_km":330,"target_pace_tolerance_sec":10,"structure":null,"notes":"Easy","race_name":null,"race_priority":null}]},{"week_index":3,"phase":"race","target_volume_m":21097.5,"notes":null,"workouts":[{"scheduled_date":"2031-05-09","kind":"race","target_distance_m":21097.5,"target_duration_seconds":6300,"race_name":"Autumn Half","race_priority":"A"}]}]'),
  ('bad_kind',
   '{"name":"Broken","goal_event":"distance_10k","goal_distance_m":10000,"start_date":"2031-04-12","end_date":"2031-05-09","days_per_week":4}',
   '[{"week_index":0,"phase":"base","target_volume_m":10000,"workouts":[{"scheduled_date":"2031-04-13","kind":"sprintz","target_distance_m":5000}]}]'),
  ('starts_before',
   '{"name":"Winter base","goal_event":"distance_10k","goal_distance_m":10000,"start_date":"2031-02-16","end_date":"2031-03-08","days_per_week":4}',
   '[{"week_index":0,"phase":"base","target_volume_m":10000,"workouts":[{"scheduled_date":"2031-02-17","kind":"easy","target_distance_m":5000}]}]'),
  ('free',
   '{"name":"Summer 10k","user_id":"abababab-0000-0000-0000-0000000a0002","goal_event":"distance_10k","goal_distance_m":10000,"start_date":"2031-07-06","end_date":"2031-07-19","days_per_week":3}',
   '[{"week_index":0,"phase":"base","target_volume_m":10000,"workouts":[{"scheduled_date":"2031-07-07","kind":"easy","target_distance_m":5000}]}]'),
  ('no_weeks',
   '{"name":"Empty","goal_event":"distance_10k","goal_distance_m":10000,"start_date":"2031-08-03","end_date":"2031-08-16","days_per_week":4}',
   '[]'),
  ('two_days',
   '{"name":"Too few days","goal_event":"distance_10k","goal_distance_m":10000,"start_date":"2031-08-03","end_date":"2031-08-16","days_per_week":2}',
   '[{"week_index":0,"phase":"base","target_volume_m":10000,"workouts":[]}]');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"abababab-0000-0000-0000-0000000a0001","role":"authenticated"}';

-- 1. refuse is the default and changes nothing.
select throws_ok(
  $$ select create_training_plan(plan, weeks) from apc_args where label = 'overlapping' $$,
  '23P01', 'create_training_plan: these dates overlap an active training plan',
  'an overlapping create is refused by default'
);
reset role;
select is(
  (select row(status, end_date)::text from training_plans where id = 'acacacac-0000-0000-0000-0000000b0001'),
  row('active', '2031-04-26'::date)::text,
  'a refused create leaves the overlapped plan as it was'
);

-- 2. Atomicity: a failure after the resolve rolls the resolve back.
set local role authenticated;
select throws_ok(
  $$ select create_training_plan(plan, weeks, 'replace') from apc_args where label = 'bad_kind' $$,
  '22P02', null,
  'a create whose workout kind is invalid fails'
);
select throws_ok(
  $$ select create_training_plan(plan, weeks, 'trim') from apc_args where label = 'bad_kind' $$,
  '22P02', null,
  'a trimming create whose workout kind is invalid fails'
);
reset role;
select is(
  (select row(status, end_date)::text from training_plans where id = 'acacacac-0000-0000-0000-0000000b0001'),
  row('active', '2031-04-26'::date)::text,
  'a create that failed after resolving neither completed nor trimmed the overlapped plan'
);
select is(
  (select count(*)::int from plan_workouts where week_id = 'adadadad-0000-0000-0000-0000000b0001'),
  1,
  'the failed trimming create deleted none of the overlapped plan''s workouts'
);

-- 3. Server-side validation.
set local role authenticated;
select throws_ok(
  $$ select create_training_plan(plan, weeks) from apc_args where label = 'no_weeks' $$,
  '22023', 'create_training_plan: the plan has no weeks',
  'a plan with no weeks is refused'
);
select throws_ok(
  $$ select create_training_plan(plan, weeks) from apc_args where label = 'two_days' $$,
  '22023', 'create_training_plan: days per week must be between 3 and 7',
  'two days a week is refused'
);
select throws_ok(
  $$ select create_training_plan(plan, weeks, 'merge') from apc_args where label = 'free' $$,
  '22023', 'create_training_plan: overlap must be refuse, replace or trim',
  'an unknown overlap choice is refused'
);

-- 4. trim refuses when an overlapping plan starts on or after the new start.
select throws_ok(
  $$ select create_training_plan(plan, weeks, 'trim') from apc_args where label = 'starts_before' $$,
  '23P01', 'create_training_plan: an overlapping plan starts on or after the new start date, so it cannot be ended early',
  'a plan that starts after the new one cannot be trimmed out of the way'
);

-- 5. trim ends the overlapped plan the day before and writes everything.
select lives_ok(
  $$ select create_training_plan(plan, weeks, 'trim') from apc_args where label = 'overlapping' $$,
  'an overlapping create with trim succeeds'
);
reset role;
select is(
  (select row(status, end_date)::text from training_plans where id = 'acacacac-0000-0000-0000-0000000b0001'),
  row('active', '2031-04-11'::date)::text,
  'trim ends the overlapped plan the day before the new start and keeps it active'
);
select is(
  (select row(user_id, status, source, goal_event, notes, vdot, current_5k_seconds, end_date)::text
   from training_plans where name = 'Autumn half'),
  row('abababab-0000-0000-0000-0000000a0001'::uuid, 'active', 'generated', 'distance_half'::goal_event, null::text, 45.20::numeric(5,2), 1320, '2031-05-09'::date)::text,
  'the new plan is the caller''s, active, generated, for its goal, with blank notes collapsed to null'
);
select is(
  (select array_agg(row(w.week_index, wo.kind, wo.race_name, wo.race_priority)::text order by w.week_index)
   from training_plans p join plan_weeks w on w.plan_id = p.id join plan_workouts wo on wo.week_id = w.id
   where p.name = 'Autumn half'),
  array[row(0, 'easy'::workout_kind, null::text, null::text)::text,
        row(3, 'race'::workout_kind, 'Autumn Half', 'A')::text],
  'its weeks and workouts, race fields included, were written'
);

-- 6. replace retires the overlapped plan as abandoned, not completed: the
-- runner dropped it, they did not finish it (20270903000001).
delete from training_plans where name = 'Autumn half';
set local role authenticated;
select lives_ok(
  $$ select create_training_plan(plan, weeks, 'replace') from apc_args where label = 'starts_before' $$,
  'an overlapping create with replace succeeds'
);
reset role;
select is(
  (select status from training_plans where id = 'acacacac-0000-0000-0000-0000000b0001'),
  'abandoned',
  'replace retires the overlapped plan as abandoned'
);

-- 7. user_id is always the caller, whatever p_plan says.
set local role authenticated;
select lives_ok(
  $$ select create_training_plan(plan, weeks) from apc_args where label = 'free' $$,
  'a create into free dates needs no overlap choice'
);
reset role;
select is(
  (select user_id from training_plans where name = 'Summer 10k'),
  'abababab-0000-0000-0000-0000000a0001'::uuid,
  'a user_id smuggled into p_plan is ignored: the plan belongs to the caller'
);

-- 8. The clone RPCs refuse on request.
set local role authenticated;
select throws_ok(
  $$ select clone_plan_template('acacacac-0000-0000-0000-0000000b0009', '2031-07-13', 'refuse') $$,
  '23P01', 'clone_plan_template: these dates overlap an active training plan',
  'clone_plan_template with refuse will not clone over an active plan'
);
select throws_ok(
  $$ select clone_public_plan('acacacac-0000-0000-0000-0000000b0009', '2031-07-13', 'refuse') $$,
  '23P01', 'clone_public_plan: these dates overlap an active training plan',
  'clone_public_plan with refuse will not clone over an active plan'
);
reset role;

-- 9. The clone RPCs' replace retires as abandoned too.
create temp table apc_overlapped as
  select id from training_plans
  where user_id = 'abababab-0000-0000-0000-0000000a0001' and status = 'active'
    and daterange(start_date, end_date, '[]') && daterange('2031-07-13', '2031-07-26', '[]');
select ok((select count(*) from apc_overlapped) > 0, 'the clone dates overlap an active plan');
set local role authenticated;
select lives_ok(
  $$ select clone_plan_template('acacacac-0000-0000-0000-0000000b0009', '2031-07-13', 'replace') $$,
  'clone_plan_template with replace succeeds over an active plan'
);
reset role;
select is(
  (select array_agg(distinct status) from training_plans where id in (select id from apc_overlapped)),
  array['abandoned'],
  'clone_plan_template replace retires the overlapped plans as abandoned'
);
truncate apc_overlapped;
insert into apc_overlapped
  select id from training_plans
  where user_id = 'abababab-0000-0000-0000-0000000a0001' and status = 'active'
    and daterange(start_date, end_date, '[]') && daterange('2031-07-13', '2031-07-26', '[]');
set local role authenticated;
select lives_ok(
  $$ select clone_public_plan('acacacac-0000-0000-0000-0000000b0009', '2031-07-13', 'replace') $$,
  'clone_public_plan with replace succeeds over the clone it overlaps'
);
reset role;
select is(
  (select array_agg(distinct status) from training_plans where id in (select id from apc_overlapped)),
  array['abandoned'],
  'clone_public_plan replace retires the overlapped plan as abandoned'
);

select * from finish();
rollback;

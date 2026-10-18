-- Pins the guards around restart_training_plan (20270920000001): who may call
-- it, the runner's "today" with and without a stored time zone, the heart-rate
-- prescription gate on the copied bpm targets, and the hourly rate limit.

begin;
select plan(16);

insert into private.feature_flags (name, enabled) values ('hr_prescription', true)
  on conflict (name) do update set enabled = true;

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('b7b7b7b7-0000-0000-0000-0000000f0001', 'authenticated', 'authenticated', 'rsg-hr@rsg.local', '', now(), now()),
  ('b7b7b7b7-0000-0000-0000-0000000f0002', 'authenticated', 'authenticated', 'rsg-tz@rsg.local', '', now(), now()),
  ('b7b7b7b7-0000-0000-0000-0000000f0003', 'authenticated', 'authenticated', 'rsg-rate@rsg.local', '', now(), now())
on conflict (id) do nothing;
insert into user_profiles (id, display_name, health_data_consent_at) values
  ('b7b7b7b7-0000-0000-0000-0000000f0001', 'RSG HR', now()),
  ('b7b7b7b7-0000-0000-0000-0000000f0002', 'RSG TZ', null),
  ('b7b7b7b7-0000-0000-0000-0000000f0003', 'RSG Rate', null)
on conflict (id) do nothing;
insert into user_settings (user_id, prefs) values
  ('b7b7b7b7-0000-0000-0000-0000000f0002', '{"time_zone": "UTC"}'::jsonb);

insert into training_plans (id, user_id, name, goal_event, goal_distance_m, start_date, end_date, days_per_week, status)
values
  ('b8b8b8b8-0000-0000-0000-0000000f0001', 'b7b7b7b7-0000-0000-0000-0000000f0001', 'HR plan', 'distance_10k', 10000,
   current_date - 30, current_date - 10, 4, 'completed'),
  ('b8b8b8b8-0000-0000-0000-0000000f0002', 'b7b7b7b7-0000-0000-0000-0000000f0002', 'TZ plan', 'distance_10k', 10000,
   current_date - 30, current_date - 10, 4, 'completed'),
  ('b8b8b8b8-0000-0000-0000-0000000f0003', 'b7b7b7b7-0000-0000-0000-0000000f0003', 'Rate plan', 'distance_10k', 10000,
   current_date - 30, current_date - 10, 4, 'completed');
insert into plan_weeks (id, plan_id, week_index, phase) values
  ('b9b9b9b9-0000-0000-0000-0000000f0001', 'b8b8b8b8-0000-0000-0000-0000000f0001', 0, 'base');
insert into plan_workouts (week_id, scheduled_date, kind, target_distance_m, target_hr_min_bpm, target_hr_max_bpm)
values ('b9b9b9b9-0000-0000-0000-0000000f0001', current_date - 28, 'easy', 5000, 120, 145);

create temporary table copies (label text, id uuid);
grant all on copies to authenticated;

-- Who may call it.
select ok(
  not has_function_privilege('anon', 'public.restart_training_plan(uuid, date)', 'execute'),
  'anon cannot execute restart_training_plan');

set local role authenticated;
set local "request.jwt.claims" = '';
select throws_ok(
  $$select restart_training_plan('b8b8b8b8-0000-0000-0000-0000000f0001', current_date + 7)$$,
  'P0001', 'restart_training_plan: not authenticated', 'an unauthenticated caller is refused');

-- The heart-rate gate on the copied bpm targets.
set local "request.jwt.claims" = '{"sub":"b7b7b7b7-0000-0000-0000-0000000f0001","role":"authenticated"}';
insert into copies
  select 'open', restart_training_plan('b8b8b8b8-0000-0000-0000-0000000f0001', current_date + 7);
select is(
  (select row(pwo.target_hr_min_bpm, pwo.target_hr_max_bpm)::text
   from plan_workouts pwo join plan_weeks pw on pw.id = pwo.week_id
   where pw.plan_id = (select id from copies where label = 'open')),
  '(120,145)', 'with the gate open and consent on record the bpm targets carry');

reset role;
update private.feature_flags set enabled = false where name = 'hr_prescription';
set local role authenticated;
select lives_ok(
  $$insert into copies select 'shut', restart_training_plan('b8b8b8b8-0000-0000-0000-0000000f0001', current_date + 7)$$,
  'with the gate shut the restart still succeeds');
select is(
  (select row(pwo.target_hr_min_bpm, pwo.target_hr_max_bpm)::text
   from plan_workouts pwo join plan_weeks pw on pw.id = pwo.week_id
   where pw.plan_id = (select id from copies where label = 'shut')),
  '(,)', 'and the copy holds no bpm target');

reset role;
update private.feature_flags set enabled = true where name = 'hr_prescription';
update user_profiles set health_data_consent_at = null where id = 'b7b7b7b7-0000-0000-0000-0000000f0001';
set local role authenticated;
select lives_ok(
  $$insert into copies select 'unconsented', restart_training_plan('b8b8b8b8-0000-0000-0000-0000000f0001', current_date + 7)$$,
  'without consent the restart still succeeds');
select is(
  (select row(pwo.target_hr_min_bpm, pwo.target_hr_max_bpm)::text
   from plan_workouts pwo join plan_weeks pw on pw.id = pwo.week_id
   where pw.plan_id = (select id from copies where label = 'unconsented')),
  '(,)', 'and the copy holds no bpm target');
select is(
  (select row(pwo.target_hr_min_bpm, pwo.target_hr_max_bpm)::text
   from plan_workouts pwo join plan_weeks pw on pw.id = pwo.week_id
   where pw.plan_id = 'b8b8b8b8-0000-0000-0000-0000000f0001'),
  '(120,145)', 'the source keeps its bpm targets throughout');

-- "Today" with no stored time zone: the UTC date less one day.
select lives_ok(
  $$select restart_training_plan('b8b8b8b8-0000-0000-0000-0000000f0001', current_date)$$,
  'with no time zone a start of today is accepted');
select lives_ok(
  $$select restart_training_plan('b8b8b8b8-0000-0000-0000-0000000f0001', current_date - 1)$$,
  'and so is the UTC yesterday, which a device west of UTC calls today');
select throws_ok(
  $$select restart_training_plan('b8b8b8b8-0000-0000-0000-0000000f0001', current_date - 2)$$,
  'RR002', 'restart_training_plan: the new start date is before today',
  'but not the day before that');

-- "Today" with a stored time zone: that zone's date, no slack.
set local "request.jwt.claims" = '{"sub":"b7b7b7b7-0000-0000-0000-0000000f0002","role":"authenticated"}';
select throws_ok(
  $$select restart_training_plan('b8b8b8b8-0000-0000-0000-0000000f0002', current_date - 1)$$,
  'RR002', 'restart_training_plan: the new start date is before today',
  'with a time zone the day before its today is refused');
select lives_ok(
  $$select restart_training_plan('b8b8b8b8-0000-0000-0000-0000000f0002', current_date)$$,
  'and its today is accepted');

-- Another runner's plan is refused before any budget is spent.
select throws_ok(
  $$select restart_training_plan('b8b8b8b8-0000-0000-0000-0000000f0003', current_date + 7)$$,
  'P0001', null, 'another runner''s plan is refused');

-- The hourly cap.
set local "request.jwt.claims" = '{"sub":"b7b7b7b7-0000-0000-0000-0000000f0003","role":"authenticated"}';
select lives_ok(
  $$ do $d$ begin
       for i in 1..20 loop perform public.restart_training_plan('b8b8b8b8-0000-0000-0000-0000000f0003', current_date + 7); end loop;
     end $d$ $$,
  'twenty restarts in an hour are allowed');
select throws_like(
  $$select restart_training_plan('b8b8b8b8-0000-0000-0000-0000000f0003', current_date + 7)$$,
  'rate limit exceeded for restart_training_plan%',
  'the twenty-first is refused');

select * from finish();
rollback;

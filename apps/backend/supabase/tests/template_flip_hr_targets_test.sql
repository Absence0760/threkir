-- Pins 20270915000005 (decisions § 2096) and 20270917000003 (§ 2107): flipping a plan to a (public)
-- template nulls its workouts' bpm targets, and a week carrying one cannot
-- move into a template plan. RPE targets are not Art 9 and survive the flip.
begin;
select plan(7);

insert into private.feature_flags (name, enabled) values ('hr_prescription', true)
  on conflict (name) do update set enabled = true;

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at) values
  ('2096aaaa-0000-0000-0000-0000000000a1', 'authenticated', 'authenticated', 'owner@tflip.local', '', now(), now())
on conflict (id) do nothing;
insert into user_profiles (id, display_name, health_data_consent_at) values
  ('2096aaaa-0000-0000-0000-0000000000a1', 'Flip Owner', now())
on conflict (id) do nothing;
insert into training_plans (id, user_id, name, goal_event, goal_distance_m, start_date, end_date, days_per_week, status) values
  ('2096bbbb-0000-0000-0000-0000000000a1', '2096aaaa-0000-0000-0000-0000000000a1', 'Mine', 'distance_10k', 10000, date '2031-03-03', date '2031-03-16', 4, 'active'),
  ('2096bbbb-0000-0000-0000-0000000000a2', '2096aaaa-0000-0000-0000-0000000000a1', 'Other', 'distance_10k', 10000, date '2031-05-04', date '2031-05-10', 4, 'active'),
  ('2096bbbb-0000-0000-0000-0000000000f1', '2096aaaa-0000-0000-0000-0000000000a1', 'Tmpl', 'distance_10k', 10000, date '2031-03-03', date '2031-03-09', 4, 'completed');
update training_plans set is_template = true where id = '2096bbbb-0000-0000-0000-0000000000f1';
insert into plan_weeks (id, plan_id, week_index, phase, target_volume_m) values
  ('2096cccc-0000-0000-0000-0000000000a1', '2096bbbb-0000-0000-0000-0000000000a1', 0, 'build', 20000),
  ('2096cccc-0000-0000-0000-0000000000a2', '2096bbbb-0000-0000-0000-0000000000a2', 0, 'build', 20000);
insert into plan_workouts (id, week_id, scheduled_date, kind, target_distance_m, target_rpe_min, target_rpe_max, target_hr_max_bpm) values
  ('2096dddd-0000-0000-0000-0000000000a1', '2096cccc-0000-0000-0000-0000000000a1', date '2031-03-04', 'easy', 8000, 3, 4, 125),
  ('2096dddd-0000-0000-0000-0000000000a2', '2096cccc-0000-0000-0000-0000000000a2', date '2031-05-05', 'easy', 8000, 3, 4, 130);

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"2096aaaa-0000-0000-0000-0000000000a1","role":"authenticated"}';

select lives_ok(
  $$ update training_plans set is_template = true, is_public_template = true, status = 'completed'
     where id = '2096bbbb-0000-0000-0000-0000000000a1' $$,
  'the owner may still publish the plan row itself');
select is(
  (select target_hr_max_bpm from plan_workouts where id = '2096dddd-0000-0000-0000-0000000000a1'),
  null::smallint,
  'the flip nulls the bpm target on the plan''s workouts');
select is(
  (select array[target_rpe_min, target_rpe_max] from plan_workouts where id = '2096dddd-0000-0000-0000-0000000000a1'),
  array[3, 4]::smallint[],
  'the RPE range survives the flip');
select throws_ok(
  $$ update plan_weeks set plan_id = '2096bbbb-0000-0000-0000-0000000000f1'
     where id = '2096cccc-0000-0000-0000-0000000000a2' $$,
  '23514',
  'plan_weeks: a week carrying a heart-rate target cannot move into a template plan',
  'a week with a bpm target cannot move into a template');
select is(
  (select target_hr_max_bpm from plan_workouts where id = '2096dddd-0000-0000-0000-0000000000a2'),
  130::smallint,
  'the refused move leaves the target on its own plan');
update plan_workouts set target_hr_max_bpm = null where id = '2096dddd-0000-0000-0000-0000000000a2';
select lives_ok(
  $$ update plan_weeks set plan_id = '2096bbbb-0000-0000-0000-0000000000f1'
     where id = '2096cccc-0000-0000-0000-0000000000a2' $$,
  'a week with no bpm target moves into a template');
reset role;

-- 20270917000003: the workout check reads the plan row FOR SHARE, so a flip
-- and a concurrent bpm write on the same plan serialise.
select ok(
  pg_get_functiondef('private.check_plan_workout_hr_target()'::regprocedure) ~* 'for share of tp',
  'the bpm target check locks the plan row it reads');

select * from finish();
rollback;

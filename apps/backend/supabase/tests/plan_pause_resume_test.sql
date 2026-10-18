-- Pins migration 20270918000004: pausing stamps paused_at and leaving pause
-- clears it; resume_training_plan reactivates the owner's paused plan and can
-- push the weeks from a given index back by whole weeks, keeping earlier weeks
-- (and their history) where they are.

begin;
select plan(14);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('f0f0f0f0-0000-0000-0000-0000000c0001', 'authenticated', 'authenticated', 'ppr-owner@ppr.local', '', now(), now()),
  ('f0f0f0f0-0000-0000-0000-0000000c0002', 'authenticated', 'authenticated', 'ppr-other@ppr.local', '', now(), now())
on conflict (id) do nothing;
insert into user_profiles (id, display_name) values
  ('f0f0f0f0-0000-0000-0000-0000000c0001', 'PPR Owner'),
  ('f0f0f0f0-0000-0000-0000-0000000c0002', 'PPR Other')
on conflict (id) do nothing;

-- Three weeks from 2035-01-01 (week 0 done in part), plus another runner's plan.
insert into training_plans (id, user_id, name, goal_event, goal_distance_m, start_date, end_date, days_per_week, status)
values
  ('f1f1f1f1-0000-0000-0000-0000000c0001', 'f0f0f0f0-0000-0000-0000-0000000c0001', 'Paused', 'distance_10k', 10000, '2035-01-01', '2035-01-21', 4, 'active'),
  ('f1f1f1f1-0000-0000-0000-0000000c0002', 'f0f0f0f0-0000-0000-0000-0000000c0002', 'Theirs', 'distance_10k', 10000, '2035-01-01', '2035-01-21', 4, 'paused');
insert into plan_weeks (id, plan_id, week_index, phase, target_volume_m) values
  ('f2f2f2f2-0000-0000-0000-0000000c0010', 'f1f1f1f1-0000-0000-0000-0000000c0001', 0, 'base', 10000),
  ('f2f2f2f2-0000-0000-0000-0000000c0011', 'f1f1f1f1-0000-0000-0000-0000000c0001', 1, 'build', 12000),
  ('f2f2f2f2-0000-0000-0000-0000000c0012', 'f1f1f1f1-0000-0000-0000-0000000c0001', 2, 'taper', 8000);
insert into plan_workouts (id, week_id, scheduled_date, kind, target_distance_m) values
  ('f3f3f3f3-0000-0000-0000-0000000c0100', 'f2f2f2f2-0000-0000-0000-0000000c0010', '2035-01-02', 'easy', 5000),
  ('f3f3f3f3-0000-0000-0000-0000000c0110', 'f2f2f2f2-0000-0000-0000-0000000c0011', '2035-01-09', 'tempo', 8000),
  ('f3f3f3f3-0000-0000-0000-0000000c0120', 'f2f2f2f2-0000-0000-0000-0000000c0012', '2035-01-21', 'race', 10000);

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"f0f0f0f0-0000-0000-0000-0000000c0001","role":"authenticated"}';

update training_plans set status = 'paused' where id = 'f1f1f1f1-0000-0000-0000-0000000c0001';
select isnt((select paused_at from training_plans where id = 'f1f1f1f1-0000-0000-0000-0000000c0001'),
  null, 'pausing stamps paused_at');

select throws_ok(
  $$select resume_training_plan('f1f1f1f1-0000-0000-0000-0000000c0001', 0, 1)$$,
  '22023', 'resume_training_plan: a shift needs the first week to move, after week 0',
  'week 0 never moves: it holds the start date');
select throws_ok(
  $$select resume_training_plan('f1f1f1f1-0000-0000-0000-0000000c0002', null, 0)$$,
  'P0001', 'resume_training_plan: plan f1f1f1f1-0000-0000-0000-0000000c0002 not found',
  'another runner''s plan is refused');

select lives_ok(
  $$select resume_training_plan('f1f1f1f1-0000-0000-0000-0000000c0001', 1, 2)$$,
  'the owner resumes, pushing weeks 1 on back two weeks');
select is((select status from training_plans where id = 'f1f1f1f1-0000-0000-0000-0000000c0001'),
  'active', 'the plan is active again');
select is((select paused_at from training_plans where id = 'f1f1f1f1-0000-0000-0000-0000000c0001'),
  null, 'leaving pause clears paused_at');
select is((select end_date from training_plans where id = 'f1f1f1f1-0000-0000-0000-0000000c0001'),
  '2035-02-04'::date, 'the end date moves 14 days');
select is((select start_date from training_plans where id = 'f1f1f1f1-0000-0000-0000-0000000c0001'),
  '2035-01-01'::date, 'the start date stays');
select is((select week_index::int from plan_weeks where id = 'f2f2f2f2-0000-0000-0000-0000000c0010'),
  0, 'the paused week keeps its index');
select is((select scheduled_date from plan_workouts where id = 'f3f3f3f3-0000-0000-0000-0000000c0100'),
  '2035-01-02'::date, 'and its workouts keep their dates');
select is((select week_index::int from plan_weeks where id = 'f2f2f2f2-0000-0000-0000-0000000c0011'),
  3, 'a later week moves two indexes');
select is((select scheduled_date from plan_workouts where id = 'f3f3f3f3-0000-0000-0000-0000000c0110'),
  '2035-01-23'::date, 'and its workouts 14 days, inside its new week');
select is((select scheduled_date from plan_workouts where id = 'f3f3f3f3-0000-0000-0000-0000000c0120'),
  '2035-02-04'::date, 'the race lands on the new end date');

select throws_ok(
  $$select resume_training_plan('f1f1f1f1-0000-0000-0000-0000000c0001', null, 0)$$,
  '22023', 'resume_training_plan: plan is not paused', 'an active plan cannot be resumed');

select * from finish();
rollback;

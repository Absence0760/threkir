-- Pins answer_missed_workouts and plan_workouts.missed_ack_at
-- (20270921000001): who may answer, which workouts count as missed, that a
-- make-up and its answer land together or not at all, that every refusal
-- writes nothing, that a moved workout loses its answer, and that copies
-- start with none.

begin;
select plan(34);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('c1c1c1c1-0000-0000-0000-0000000a0001', 'authenticated', 'authenticated', 'mak-owner@mak.local', '', now(), now()),
  ('c1c1c1c1-0000-0000-0000-0000000a0002', 'authenticated', 'authenticated', 'mak-other@mak.local', '', now(), now())
on conflict (id) do nothing;
insert into user_profiles (id, display_name) values
  ('c1c1c1c1-0000-0000-0000-0000000a0001', 'MAK Owner'),
  ('c1c1c1c1-0000-0000-0000-0000000a0002', 'MAK Other')
on conflict (id) do nothing;

insert into training_plans (id, user_id, name, goal_event, goal_distance_m, start_date, end_date, days_per_week, status, is_template)
values
  ('c2c2c2c2-0000-0000-0000-0000000a0001', 'c1c1c1c1-0000-0000-0000-0000000a0001', 'Active', 'distance_half', 21097,
   current_date - 14, current_date + 41, 4, 'active', false),
  ('c2c2c2c2-0000-0000-0000-0000000a0002', 'c1c1c1c1-0000-0000-0000-0000000a0001', 'Paused', 'distance_10k', 10000,
   current_date - 100, current_date - 60, 4, 'paused', false),
  ('c2c2c2c2-0000-0000-0000-0000000a0003', 'c1c1c1c1-0000-0000-0000-0000000a0001', 'Template', 'distance_10k', 10000,
   current_date - 200, current_date - 160, 4, 'completed', true);
insert into plan_weeks (id, plan_id, week_index, phase, target_volume_m) values
  ('c3c3c3c3-0000-0000-0000-0000000a0001', 'c2c2c2c2-0000-0000-0000-0000000a0001', 0, 'base', 30000),
  ('c3c3c3c3-0000-0000-0000-0000000a0002', 'c2c2c2c2-0000-0000-0000-0000000a0001', 1, 'base', 32000),
  ('c3c3c3c3-0000-0000-0000-0000000a0003', 'c2c2c2c2-0000-0000-0000-0000000a0001', 2, 'build', 34000),
  ('c3c3c3c3-0000-0000-0000-0000000a0004', 'c2c2c2c2-0000-0000-0000-0000000a0002', 0, 'base', 20000),
  ('c3c3c3c3-0000-0000-0000-0000000a0005', 'c2c2c2c2-0000-0000-0000-0000000a0003', 0, 'base', 20000);
insert into plan_workouts (id, week_id, scheduled_date, kind, target_distance_m, manually_completed, skipped_at)
values
  -- the missed long run and a missed easy run
  ('c4c4c4c4-0000-0000-0000-0000000a0001', 'c3c3c3c3-0000-0000-0000-0000000a0002', current_date - 3, 'long', 18000, false, null),
  ('c4c4c4c4-0000-0000-0000-0000000a0002', 'c3c3c3c3-0000-0000-0000-0000000a0002', current_date - 5, 'easy', 6000, false, null),
  -- not missed: rest, done, skipped, still to come
  ('c4c4c4c4-0000-0000-0000-0000000a0003', 'c3c3c3c3-0000-0000-0000-0000000a0002', current_date - 4, 'rest', null, false, null),
  ('c4c4c4c4-0000-0000-0000-0000000a0004', 'c3c3c3c3-0000-0000-0000-0000000a0002', current_date - 6, 'tempo', 8000, true, null),
  ('c4c4c4c4-0000-0000-0000-0000000a0005', 'c3c3c3c3-0000-0000-0000-0000000a0002', current_date - 2, 'interval', 7000, false, now()),
  ('c4c4c4c4-0000-0000-0000-0000000a0006', 'c3c3c3c3-0000-0000-0000-0000000a0003', current_date + 4, 'long', 16000, false, null),
  ('c4c4c4c4-0000-0000-0000-0000000a0007', 'c3c3c3c3-0000-0000-0000-0000000a0003', current_date + 2, 'easy', 6000, false, null),
  -- a missed run in each of the paused plan and the template
  ('c4c4c4c4-0000-0000-0000-0000000a0008', 'c3c3c3c3-0000-0000-0000-0000000a0004', current_date - 70, 'easy', 5000, false, null),
  ('c4c4c4c4-0000-0000-0000-0000000a0009', 'c3c3c3c3-0000-0000-0000-0000000a0005', current_date - 170, 'easy', 5000, false, null),
  -- a missed run in week 0 for the copy checks
  ('c4c4c4c4-0000-0000-0000-0000000a0010', 'c3c3c3c3-0000-0000-0000-0000000a0001', current_date - 12, 'easy', 5000, false, null);

-- Who may call it.
select ok(
  not has_function_privilege('anon', 'public.answer_missed_workouts(uuid, uuid[], jsonb)', 'execute'),
  'anon cannot execute answer_missed_workouts');
select ok(
  has_function_privilege('authenticated', 'public.answer_missed_workouts(uuid, uuid[], jsonb)', 'execute'),
  'authenticated can execute answer_missed_workouts');
select is(
  (select prosecdef from pg_proc where oid = 'public.answer_missed_workouts(uuid, uuid[], jsonb)'::regprocedure),
  false, 'answer_missed_workouts is SECURITY INVOKER');

set local role authenticated;
set local "request.jwt.claims" = '';
select throws_ok(
  $$select answer_missed_workouts('c2c2c2c2-0000-0000-0000-0000000a0001', array['c4c4c4c4-0000-0000-0000-0000000a0001']::uuid[])$$,
  'P0001', 'answer_missed_workouts: not authenticated', 'an unauthenticated caller is refused');

-- Another runner cannot answer for the owner.
set local "request.jwt.claims" = '{"sub":"c1c1c1c1-0000-0000-0000-0000000a0002","role":"authenticated"}';
select throws_ok(
  $$select answer_missed_workouts('c2c2c2c2-0000-0000-0000-0000000a0001', array['c4c4c4c4-0000-0000-0000-0000000a0001']::uuid[])$$,
  'P0001', null, 'another runner is refused');

-- The owner's refusals.
set local "request.jwt.claims" = '{"sub":"c1c1c1c1-0000-0000-0000-0000000a0001","role":"authenticated"}';
select throws_ok(
  $$select answer_missed_workouts('c2c2c2c2-0000-0000-0000-0000000a0001', array[]::uuid[])$$,
  '22023', 'answer_missed_workouts: name at least one workout', 'an empty list is refused');
select throws_ok(
  $$select answer_missed_workouts('c2c2c2c2-0000-0000-0000-0000000a0001', null)$$,
  '22023', 'answer_missed_workouts: name at least one workout', 'a null list is refused');
select throws_ok(
  $$select answer_missed_workouts('c2c2c2c2-0000-0000-0000-0000000a0002', array['c4c4c4c4-0000-0000-0000-0000000a0008']::uuid[])$$,
  '55000', 'answer_missed_workouts: the plan is not active', 'a paused plan is refused');
select throws_ok(
  $$select answer_missed_workouts('c2c2c2c2-0000-0000-0000-0000000a0003', array['c4c4c4c4-0000-0000-0000-0000000a0009']::uuid[])$$,
  '55000', 'answer_missed_workouts: the plan is not active', 'a template is refused');
select throws_ok(
  $$select answer_missed_workouts('c2c2c2c2-0000-0000-0000-0000000a0001', array['c4c4c4c4-0000-0000-0000-0000000a0003']::uuid[])$$,
  '55000', 'answer_missed_workouts: a workout is not a missed workout of this plan', 'a rest day is refused');
select throws_ok(
  $$select answer_missed_workouts('c2c2c2c2-0000-0000-0000-0000000a0001', array['c4c4c4c4-0000-0000-0000-0000000a0004']::uuid[])$$,
  '55000', 'answer_missed_workouts: a workout is not a missed workout of this plan', 'a done workout is refused');
select throws_ok(
  $$select answer_missed_workouts('c2c2c2c2-0000-0000-0000-0000000a0001', array['c4c4c4c4-0000-0000-0000-0000000a0005']::uuid[])$$,
  '55000', 'answer_missed_workouts: a workout is not a missed workout of this plan', 'a skipped workout is refused');
select throws_ok(
  $$select answer_missed_workouts('c2c2c2c2-0000-0000-0000-0000000a0001', array['c4c4c4c4-0000-0000-0000-0000000a0007']::uuid[])$$,
  '55000', 'answer_missed_workouts: a workout is not a missed workout of this plan', 'a workout still to come is refused');
select throws_ok(
  $$select answer_missed_workouts('c2c2c2c2-0000-0000-0000-0000000a0001', array['c4c4c4c4-0000-0000-0000-0000000a0008']::uuid[])$$,
  '55000', 'answer_missed_workouts: a workout is not a missed workout of this plan', 'a workout of another plan is refused');
select throws_ok(
  $$select answer_missed_workouts('c2c2c2c2-0000-0000-0000-0000000a0001',
      array['c4c4c4c4-0000-0000-0000-0000000a0002', 'c4c4c4c4-0000-0000-0000-0000000a0003']::uuid[])$$,
  '55000', 'answer_missed_workouts: a workout is not a missed workout of this plan',
  'one workout that is not missed refuses the whole list');
select throws_ok(
  $$select answer_missed_workouts('c2c2c2c2-0000-0000-0000-0000000a0001', array['c4c4c4c4-0000-0000-0000-0000000a0001']::uuid[],
      '{"id": "c4c4c4c4-0000-0000-0000-0000000a0006"}'::jsonb)$$,
  '22023', 'answer_missed_workouts: changes must be a list', 'changes that are not a list are refused');
select throws_ok(
  $$select answer_missed_workouts('c2c2c2c2-0000-0000-0000-0000000a0001', array['c4c4c4c4-0000-0000-0000-0000000a0001']::uuid[],
      '[{"id": "c4c4c4c4-0000-0000-0000-0000000a0006", "completed_run_id": null}]'::jsonb)$$,
  '22023', 'apply_workout_adjustments: a change names a column it cannot write',
  'a make-up the adjustment path refuses is refused');

select is(
  (select count(*)::int from plan_workouts where missed_ack_at is not null),
  0, 'no refusal recorded an answer');
select is(
  (select target_distance_m::int from plan_workouts where id = 'c4c4c4c4-0000-0000-0000-0000000a0006'),
  16000, 'and no refusal changed the next long run');

-- "Let it go": the answer and nothing else.
select lives_ok(
  $$select answer_missed_workouts('c2c2c2c2-0000-0000-0000-0000000a0001', array['c4c4c4c4-0000-0000-0000-0000000a0002']::uuid[])$$,
  'the owner lets a missed easy run go');
select ok(
  (select missed_ack_at is not null from plan_workouts where id = 'c4c4c4c4-0000-0000-0000-0000000a0002'),
  'the easy run is answered');
select is(
  (select count(*)::int from plan_workouts where missed_ack_at is not null),
  1, 'and only it');

-- Answering again keeps the first answer.
reset role;
update plan_workouts set missed_ack_at = '2020-01-01T00:00:00Z' where id = 'c4c4c4c4-0000-0000-0000-0000000a0002';
set local role authenticated;
select lives_ok(
  $$select answer_missed_workouts('c2c2c2c2-0000-0000-0000-0000000a0001', array['c4c4c4c4-0000-0000-0000-0000000a0002']::uuid[])$$,
  'answering twice is allowed');
select is(
  (select missed_ack_at from plan_workouts where id = 'c4c4c4c4-0000-0000-0000-0000000a0002'),
  '2020-01-01T00:00:00Z'::timestamptz, 'and keeps the first answer');

-- "Make it up": the stretched long run and the answer land together.
select lives_ok(
  $$select answer_missed_workouts('c2c2c2c2-0000-0000-0000-0000000a0001', array['c4c4c4c4-0000-0000-0000-0000000a0001']::uuid[],
      '[{"id": "c4c4c4c4-0000-0000-0000-0000000a0006", "target_distance_m": 18000}]'::jsonb)$$,
  'the owner makes up a missed long run');
select is(
  (select target_distance_m::int from plan_workouts where id = 'c4c4c4c4-0000-0000-0000-0000000a0006'),
  18000, 'the next long run is stretched');
select is(
  (select target_volume_m::int from plan_weeks where id = 'c3c3c3c3-0000-0000-0000-0000000a0003'),
  24000, 'its week''s volume is restated');
select ok(
  (select missed_ack_at is not null from plan_workouts where id = 'c4c4c4c4-0000-0000-0000-0000000a0001'),
  'the missed long run is answered');

-- A moved workout loses its answer; any other edit keeps it.
update plan_workouts set notes = 'kept' where id = 'c4c4c4c4-0000-0000-0000-0000000a0001';
select ok(
  (select missed_ack_at is not null from plan_workouts where id = 'c4c4c4c4-0000-0000-0000-0000000a0001'),
  'an edit that does not move the workout keeps its answer');
update plan_workouts set scheduled_date = current_date - 1 where id = 'c4c4c4c4-0000-0000-0000-0000000a0001';
select is(
  (select missed_ack_at from plan_workouts where id = 'c4c4c4c4-0000-0000-0000-0000000a0001'),
  null, 'moving the workout to another date clears its answer');

-- Copies start with no answers.
select lives_ok(
  $$select answer_missed_workouts('c2c2c2c2-0000-0000-0000-0000000a0001', array['c4c4c4c4-0000-0000-0000-0000000a0010']::uuid[])$$,
  'the owner lets a week-0 run go');
create temporary table copies (label text, id uuid);
grant all on copies to authenticated;
insert into copies select 'week', duplicate_plan_week('c2c2c2c2-0000-0000-0000-0000000a0001', 0);
select is(
  (select count(*)::int from plan_workouts
   where week_id = (select id from copies where label = 'week') and missed_ack_at is not null),
  0, 'a duplicated week carries no answer');
select ok(
  (select missed_ack_at is not null from plan_workouts where id = 'c4c4c4c4-0000-0000-0000-0000000a0010'),
  'while the week it copied keeps its own');
insert into copies select 'plan', restart_training_plan('c2c2c2c2-0000-0000-0000-0000000a0001', current_date + 7);
select is(
  (select count(*)::int from plan_workouts wo join plan_weeks w on w.id = wo.week_id
   where w.plan_id = (select id from copies where label = 'plan') and wo.missed_ack_at is not null),
  0, 'a restarted plan starts with no answers');

select * from finish();
rollback;

-- Pins migration 20270902000001 (issue #1186, decisions § 2073): a planned
-- workout moves to another day of its week on a dense, generated-shape week
-- (seven rows, rest days included), trading days with whatever row is there;
-- several dates change in one transaction; the plan shifts by a
-- non-multiple of seven; and the per-day uniqueness is still immediate for
-- every other writer.

begin;
select plan(24);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('a1a1a1a1-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'move-owner@pmw.local', '', now(), now()),
  ('a1a1a1a1-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'move-coach@pmw.local', '', now(), now()),
  ('a1a1a1a1-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'move-stranger@pmw.local', '', now(), now())
on conflict (id) do nothing;
insert into user_profiles (id, display_name) values
  ('a1a1a1a1-0000-0000-0000-000000000001', 'Mover'),
  ('a1a1a1a1-0000-0000-0000-000000000002', 'Move Coach'),
  ('a1a1a1a1-0000-0000-0000-000000000003', 'Stranger')
on conflict (id) do nothing;
insert into coach_athletes (coach_id, athlete_id, status, invite_token, accepted_at) values
  ('a1a1a1a1-0000-0000-0000-000000000002', 'a1a1a1a1-0000-0000-0000-000000000001', 'active', 'pmw-tok', now());

-- A two-week plan starting Monday 2031-03-03, both weeks dense the way the
-- generator writes them, plus a public template owned by the same runner.
insert into training_plans (id, user_id, name, goal_event, goal_distance_m, start_date, end_date, days_per_week, status, is_template, is_public_template)
values
  ('b2b2b2b2-0000-0000-0000-000000000001', 'a1a1a1a1-0000-0000-0000-000000000001', 'Dense', 'distance_10k', 10000, '2031-03-03', '2031-03-16', 4, 'active', false, false),
  ('b2b2b2b2-0000-0000-0000-000000000002', 'a1a1a1a1-0000-0000-0000-000000000001', 'Shared', 'distance_10k', 10000, '2032-03-01', '2032-03-07', 4, 'completed', true, true);
insert into plan_weeks (id, plan_id, week_index, phase, target_volume_m) values
  ('c3c3c3c3-0000-0000-0000-000000000000', 'b2b2b2b2-0000-0000-0000-000000000001', 0, 'base', 30000),
  ('c3c3c3c3-0000-0000-0000-000000000001', 'b2b2b2b2-0000-0000-0000-000000000001', 1, 'base', 30000),
  ('c3c3c3c3-0000-0000-0000-000000000002', 'b2b2b2b2-0000-0000-0000-000000000002', 0, 'base', 8000);

insert into plan_workouts (id, week_id, scheduled_date, kind, target_distance_m) values
  ('d4d4d4d4-0000-0000-0000-000000000001', 'c3c3c3c3-0000-0000-0000-000000000000', '2031-03-03', 'rest', null),
  ('d4d4d4d4-0000-0000-0000-000000000002', 'c3c3c3c3-0000-0000-0000-000000000000', '2031-03-04', 'tempo', 8000),
  ('d4d4d4d4-0000-0000-0000-000000000003', 'c3c3c3c3-0000-0000-0000-000000000000', '2031-03-05', 'easy', 6000),
  ('d4d4d4d4-0000-0000-0000-000000000004', 'c3c3c3c3-0000-0000-0000-000000000000', '2031-03-06', 'rest', null),
  ('d4d4d4d4-0000-0000-0000-000000000005', 'c3c3c3c3-0000-0000-0000-000000000000', '2031-03-07', 'easy', 6000),
  ('d4d4d4d4-0000-0000-0000-000000000006', 'c3c3c3c3-0000-0000-0000-000000000000', '2031-03-08', 'rest', null),
  ('d4d4d4d4-0000-0000-0000-000000000007', 'c3c3c3c3-0000-0000-0000-000000000000', '2031-03-09', 'long', 10000),
  ('d4d4d4d4-0000-0000-0000-000000000011', 'c3c3c3c3-0000-0000-0000-000000000001', '2031-03-10', 'rest', null),
  ('d4d4d4d4-0000-0000-0000-000000000012', 'c3c3c3c3-0000-0000-0000-000000000001', '2031-03-11', 'tempo', 8000),
  ('d4d4d4d4-0000-0000-0000-000000000013', 'c3c3c3c3-0000-0000-0000-000000000001', '2031-03-12', 'easy', 6000),
  ('d4d4d4d4-0000-0000-0000-000000000014', 'c3c3c3c3-0000-0000-0000-000000000001', '2031-03-13', 'rest', null),
  ('d4d4d4d4-0000-0000-0000-000000000015', 'c3c3c3c3-0000-0000-0000-000000000001', '2031-03-14', 'easy', 6000),
  ('d4d4d4d4-0000-0000-0000-000000000016', 'c3c3c3c3-0000-0000-0000-000000000001', '2031-03-15', 'rest', null),
  ('d4d4d4d4-0000-0000-0000-000000000017', 'c3c3c3c3-0000-0000-0000-000000000001', '2031-03-16', 'long', 12000),
  ('d4d4d4d4-0000-0000-0000-000000000021', 'c3c3c3c3-0000-0000-0000-000000000002', '2032-03-02', 'easy', 8000);

select ok(
  (select condeferrable and not condeferred from pg_constraint where conname = 'plan_workouts_one_per_day'),
  'the per-day uniqueness is deferrable but initially immediate'
);

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"a1a1a1a1-0000-0000-0000-000000000001","role":"authenticated"}';

-- A plain update that lands on an occupied day is still refused at once.
select throws_ok(
  $$ update plan_workouts set scheduled_date = '2031-03-05'
     where id = 'd4d4d4d4-0000-0000-0000-000000000002' $$,
  '23505', null,
  'a direct date update onto an occupied day still fails immediately'
);

-- Move Tuesday's tempo onto Thursday's rest day: they trade days.
select is(
  move_plan_workout('d4d4d4d4-0000-0000-0000-000000000002', '2031-03-06'),
  'd4d4d4d4-0000-0000-0000-000000000004'::uuid,
  'moving onto an occupied day returns the workout it swapped with'
);
select is(
  (select scheduled_date from plan_workouts where id = 'd4d4d4d4-0000-0000-0000-000000000002'),
  '2031-03-06'::date,
  'the moved workout is on its new day'
);
select is(
  (select scheduled_date from plan_workouts where id = 'd4d4d4d4-0000-0000-0000-000000000004'),
  '2031-03-04'::date,
  'the rest day took the moved workout''s old day'
);
select is(
  (select count(*)::int from plan_workouts where week_id = 'c3c3c3c3-0000-0000-0000-000000000000'),
  7,
  'the week still has exactly seven rows'
);

-- Swap two occupied days (the AI adjust's swap_days) in one call.
select lives_ok(
  $$ select reschedule_plan_workouts('b2b2b2b2-0000-0000-0000-000000000001', jsonb_build_array(
       jsonb_build_object('id', 'd4d4d4d4-0000-0000-0000-000000000003', 'date', '2031-03-09'),
       jsonb_build_object('id', 'd4d4d4d4-0000-0000-0000-000000000007', 'date', '2031-03-05'))) $$,
  'two occupied days swap in one call'
);
select is(
  (select array_agg(kind::text order by scheduled_date) from plan_workouts
   where week_id = 'c3c3c3c3-0000-0000-0000-000000000000'),
  array['rest', 'rest', 'long', 'tempo', 'easy', 'rest', 'easy'],
  'the week reads in its new order'
);

select is(
  move_plan_workout('d4d4d4d4-0000-0000-0000-000000000005', '2031-03-07'),
  null::uuid,
  'moving onto its own day is a no-op'
);

select throws_ok(
  $$ select reschedule_plan_workouts('b2b2b2b2-0000-0000-0000-000000000001', jsonb_build_array(
       jsonb_build_object('id', 'd4d4d4d4-0000-0000-0000-000000000005', 'date', '2031-03-08'))) $$,
  '23505', null,
  'a batch that leaves two rows on one day is refused'
);
select is(
  (select scheduled_date from plan_workouts where id = 'd4d4d4d4-0000-0000-0000-000000000005'),
  '2031-03-07'::date,
  'and nothing it named moved'
);

select throws_ok(
  $$ select move_plan_workout('d4d4d4d4-0000-0000-0000-000000000005', '2031-03-10') $$,
  '22023', null,
  'a workout cannot move out of its plan week'
);
select throws_ok(
  $$ select move_plan_workout('d4d4d4d4-0000-0000-0000-000000000017', '2031-03-17') $$,
  '22023', null,
  'nor past the plan''s end'
);
select throws_ok(
  $$ select reschedule_plan_workouts('b2b2b2b2-0000-0000-0000-000000000001', jsonb_build_array(
       jsonb_build_object('id', 'd4d4d4d4-0000-0000-0000-000000000005', 'date', '2031-03-08'),
       jsonb_build_object('id', 'd4d4d4d4-0000-0000-0000-000000000005', 'date', '2031-03-03'))) $$,
  '22023', null,
  'a batch may not name a workout twice'
);
reset role;

update plan_workouts set manually_completed = true, completed_at = now()
where id = 'd4d4d4d4-0000-0000-0000-000000000012';

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"a1a1a1a1-0000-0000-0000-000000000001","role":"authenticated"}';
select throws_ok(
  $$ select move_plan_workout('d4d4d4d4-0000-0000-0000-000000000012', '2031-03-13') $$,
  '22023', null,
  'a completed workout keeps its day'
);
select throws_ok(
  $$ select move_plan_workout('d4d4d4d4-0000-0000-0000-000000000013', '2031-03-11') $$,
  '22023', null,
  'and is never displaced by a swap'
);

-- The coach of this runner can move their workouts.
set local "request.jwt.claims" = '{"sub":"a1a1a1a1-0000-0000-0000-000000000002","role":"authenticated"}';
select is(
  move_plan_workout('d4d4d4d4-0000-0000-0000-000000000013', '2031-03-14'),
  'd4d4d4d4-0000-0000-0000-000000000015'::uuid,
  'an active coach moves an athlete''s workout'
);

-- A stranger sees neither plan nor workout.
set local "request.jwt.claims" = '{"sub":"a1a1a1a1-0000-0000-0000-000000000003","role":"authenticated"}';
select throws_ok(
  $$ select move_plan_workout('d4d4d4d4-0000-0000-0000-000000000015', '2031-03-12') $$,
  'P0002', null,
  'a stranger cannot reach another runner''s workout'
);
select throws_ok(
  $$ select reschedule_plan_workouts('b2b2b2b2-0000-0000-0000-000000000001', jsonb_build_array(
       jsonb_build_object('id', 'd4d4d4d4-0000-0000-0000-000000000015', 'date', '2031-03-12'))) $$,
  'P0002', null,
  'nor reschedule that plan'
);
-- A public template is readable by anyone, and editable by its owner only.
select throws_ok(
  $$ select move_plan_workout('d4d4d4d4-0000-0000-0000-000000000021', '2032-03-04') $$,
  '42501', null,
  'a reader of a public template cannot move its workouts'
);
reset role;

select is(
  (select scheduled_date from plan_workouts where id = 'd4d4d4d4-0000-0000-0000-000000000021'),
  '2032-03-02'::date,
  'the refused move changed nothing'
);

-- Shifting a dense plan by one day used to meet the next day's row.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"a1a1a1a1-0000-0000-0000-000000000001","role":"authenticated"}';
select lives_ok(
  $$ select shift_training_plan('b2b2b2b2-0000-0000-0000-000000000001', 1) $$,
  'a dense plan shifts by a single day'
);
select lives_ok(
  $$ select shift_training_plan('b2b2b2b2-0000-0000-0000-000000000001', -3) $$,
  'and back by three'
);
reset role;

select is(
  (select row(min(wo.scheduled_date), max(wo.scheduled_date), count(*))::text
   from plan_workouts wo join plan_weeks w on w.id = wo.week_id
   where w.plan_id = 'b2b2b2b2-0000-0000-0000-000000000001'),
  row('2031-03-01'::date, '2031-03-14'::date, 14::bigint)::text,
  'every row moved two days earlier and none was lost'
);

select * from finish();
rollback;

-- Pins migration 20270920000001: restart_training_plan copies one of the
-- caller's plans to a new start date with no history, retires the overlapped
-- active plans and the source (when live) as abandoned in the same
-- transaction, and refuses templates, other runners' plans, past starts and a
-- plan whose race is still ahead.

begin;
select plan(33);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('a7a7a7a7-0000-0000-0000-0000000e0001', 'authenticated', 'authenticated', 'rst-owner@rst.local', '', now(), now()),
  ('a7a7a7a7-0000-0000-0000-0000000e0002', 'authenticated', 'authenticated', 'rst-other@rst.local', '', now(), now()),
  ('a7a7a7a7-0000-0000-0000-0000000e0003', 'authenticated', 'authenticated', 'rst-coach@rst.local', '', now(), now())
on conflict (id) do nothing;
insert into user_profiles (id, display_name) values
  ('a7a7a7a7-0000-0000-0000-0000000e0001', 'RST Owner'),
  ('a7a7a7a7-0000-0000-0000-0000000e0002', 'RST Other'),
  ('a7a7a7a7-0000-0000-0000-0000000e0003', 'RST Coach')
on conflict (id) do nothing;

-- Source: an active plan that started 14 days ago, coach-assigned, with a
-- completed, a skipped and a run-linked workout, and a race that is behind it.
insert into training_plans (id, user_id, name, goal_event, goal_distance_m, goal_time_seconds,
  start_date, end_date, days_per_week, vdot, status, notes, assigned_by_coach_id, rules)
values
  ('a8a8a8a8-0000-0000-0000-0000000e0001', 'a7a7a7a7-0000-0000-0000-0000000e0001', 'Ten K', 'distance_10k', 10000, 3000,
   current_date - 14, current_date + 6, 4, 45.5, 'active', 'my notes', 'a7a7a7a7-0000-0000-0000-0000000e0003',
   '{"long_run_day": 0}'::jsonb),
  ('a8a8a8a8-0000-0000-0000-0000000e0002', 'a7a7a7a7-0000-0000-0000-0000000e0002', 'Theirs', 'distance_10k', 10000, null,
   current_date - 14, current_date + 6, 4, null, 'completed', null, null, null),
  ('a8a8a8a8-0000-0000-0000-0000000e0003', 'a7a7a7a7-0000-0000-0000-0000000e0001', 'Template', 'distance_10k', 10000, null,
   '2035-01-07', '2035-01-27', 4, null, 'completed', null, null, null),
  ('a8a8a8a8-0000-0000-0000-0000000e0004', 'a7a7a7a7-0000-0000-0000-0000000e0001', 'Race ahead', 'distance_5k', 5000, null,
   current_date - 60, current_date - 40, 4, null, 'abandoned', null, null, null);
update training_plans set is_template = true where id = 'a8a8a8a8-0000-0000-0000-0000000e0003';

insert into plan_weeks (id, plan_id, week_index, phase, target_volume_m, notes) values
  ('a9a9a9a9-0000-0000-0000-0000000e0010', 'a8a8a8a8-0000-0000-0000-0000000e0001', 0, 'base', 10000, 'week one'),
  ('a9a9a9a9-0000-0000-0000-0000000e0011', 'a8a8a8a8-0000-0000-0000-0000000e0001', 1, 'build', 12000, null),
  ('a9a9a9a9-0000-0000-0000-0000000e0012', 'a8a8a8a8-0000-0000-0000-0000000e0001', 2, 'taper', 8000, null),
  ('a9a9a9a9-0000-0000-0000-0000000e0040', 'a8a8a8a8-0000-0000-0000-0000000e0004', 0, 'race', 5000, null);

insert into plan_workouts (id, week_id, scheduled_date, kind, target_distance_m,
  target_pace_sec_per_km, target_rpe_min, target_rpe_max, structure, notes, manually_completed, skipped_at,
  race_name, race_priority)
values
  ('aaaaaaaa-0000-0000-0000-0000000e0100', 'a9a9a9a9-0000-0000-0000-0000000e0010', current_date - 14, 'easy', 5000,
   360, 3, 4, '{"warmup_m": 1000}'::jsonb, 'go easy', true, null, null, null),
  ('aaaaaaaa-0000-0000-0000-0000000e0101', 'a9a9a9a9-0000-0000-0000-0000000e0010', current_date - 12, 'race', 5000,
   300, null, null, null, null, false, null, 'Parkrun', 'C'),
  ('aaaaaaaa-0000-0000-0000-0000000e0110', 'a9a9a9a9-0000-0000-0000-0000000e0011', current_date - 6, 'tempo', 8000,
   320, null, null, null, null, false, now(), null, null),
  ('aaaaaaaa-0000-0000-0000-0000000e0120', 'a9a9a9a9-0000-0000-0000-0000000e0012', current_date + 2, 'long', 12000,
   380, null, null, null, null, false, null, null, null),
  ('aaaaaaaa-0000-0000-0000-0000000e0400', 'a9a9a9a9-0000-0000-0000-0000000e0040', current_date + 3, 'race', 5000,
   null, null, null, null, null, false, null, 'Ahead', 'A');

-- A plan queued after the source that the new window will overlap, one queued
-- well after it that the window does not reach, and another runner's active
-- plan over the same dates.
insert into training_plans (id, user_id, name, goal_event, goal_distance_m, start_date, end_date, days_per_week, status)
values
  ('a8a8a8a8-0000-0000-0000-0000000e0005', 'a7a7a7a7-0000-0000-0000-0000000e0001', 'Queued', 'distance_5k', 5000,
   current_date + 20, current_date + 40, 4, 'active'),
  ('a8a8a8a8-0000-0000-0000-0000000e0006', 'a7a7a7a7-0000-0000-0000-0000000e0001', 'Far queued', 'distance_5k', 5000,
   current_date + 200, current_date + 220, 4, 'active'),
  ('a8a8a8a8-0000-0000-0000-0000000e0007', 'a7a7a7a7-0000-0000-0000-0000000e0002', 'Their active', 'distance_5k', 5000,
   current_date + 7, current_date + 27, 4, 'active');

insert into runs (id, user_id, started_at, duration_s, distance_m, source, activity_type)
values ('abababab-0000-0000-0000-0000000e0001', 'a7a7a7a7-0000-0000-0000-0000000e0001', '2020-01-01 07:00+00', 3600, 12000, 'app', 'run');
update plan_workouts set completed_run_id = 'abababab-0000-0000-0000-0000000e0001'
where id = 'aaaaaaaa-0000-0000-0000-0000000e0120';

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"a7a7a7a7-0000-0000-0000-0000000e0001","role":"authenticated"}';

select throws_ok(
  $$select restart_training_plan('a8a8a8a8-0000-0000-0000-0000000e0002', current_date + 7)$$,
  'P0001', null, 'another runner''s plan is refused');
select throws_ok(
  $$select restart_training_plan('a8a8a8a8-0000-0000-0000-0000000e0003', current_date + 7)$$,
  '22023', 'restart_training_plan: a template cannot be restarted', 'a template is refused');
select throws_ok(
  $$select restart_training_plan('a8a8a8a8-0000-0000-0000-0000000e0001', current_date - 3)$$,
  'RR002', 'restart_training_plan: the new start date is before today', 'a start before today is refused');
select throws_ok(
  $$select restart_training_plan('a8a8a8a8-0000-0000-0000-0000000e0004', current_date + 7)$$,
  'RR001', 'restart_training_plan: this plan has a race still ahead',
  'a plan whose race is still ahead is refused');
select is((select status from training_plans where id = 'a8a8a8a8-0000-0000-0000-0000000e0004'),
  'abandoned', 'and a refused restart changes nothing');

create temporary table restarted (id uuid);
grant all on restarted to authenticated;
insert into restarted
  select restart_training_plan('a8a8a8a8-0000-0000-0000-0000000e0001', current_date + 7);

select is((select status from training_plans where id = (select id from restarted)),
  'active', 'the copy is active');
select is((select start_date from training_plans where id = (select id from restarted)),
  current_date + 7, 'the copy starts on the picked date');
select is((select end_date from training_plans where id = (select id from restarted)),
  current_date + 27, 'the end date moves by the same offset');
select is(
  (select row(name, goal_event::text, goal_distance_m, goal_time_seconds, days_per_week, vdot, notes, rules::text)::text
   from training_plans where id = (select id from restarted)),
  (select row(name, goal_event::text, goal_distance_m, goal_time_seconds, days_per_week, vdot, notes, rules::text)::text
   from training_plans where id = 'a8a8a8a8-0000-0000-0000-0000000e0001'),
  'the goal, rules and notes carry over');
select is((select assigned_by_coach_id from training_plans where id = (select id from restarted)),
  null, 'the coach attribution does not carry over');
select is((select status from training_plans where id = 'a8a8a8a8-0000-0000-0000-0000000e0001'),
  'abandoned', 'the source is retired as abandoned');
select is((select status from training_plans where id = 'a8a8a8a8-0000-0000-0000-0000000e0005'),
  'abandoned', 'an active plan the new window overlaps is retired as abandoned');

select is((select status from training_plans where id = 'a8a8a8a8-0000-0000-0000-0000000e0006'),
  'active', 'a later active plan the new window does not reach stays active');
reset role;
select is((select status from training_plans where id = 'a8a8a8a8-0000-0000-0000-0000000e0007'),
  'active', 'another runner''s active plan is untouched');
set local role authenticated;
select is((select count(*)::int from plan_weeks where plan_id = (select id from restarted)),
  3, 'every week is copied');
select is((select notes from plan_weeks where plan_id = (select id from restarted) and week_index = 0),
  'week one', 'with its notes');
select is(
  (select count(*)::int from plan_workouts pwo join plan_weeks pw on pw.id = pwo.week_id
   where pw.plan_id = (select id from restarted)),
  4, 'every workout is copied');
select is(
  (select count(*)::int from plan_workouts pwo join plan_weeks pw on pw.id = pwo.week_id
   where pw.plan_id = (select id from restarted)
     and (pwo.manually_completed or pwo.completed_run_id is not null
          or pwo.completed_at is not null or pwo.skipped_at is not null)),
  0, 'no completion, skip or run link carries over');
select is(
  (select pwo.scheduled_date from plan_workouts pwo join plan_weeks pw on pw.id = pwo.week_id
   where pw.plan_id = (select id from restarted) and pwo.kind = 'easy'),
  current_date + 7, 'a workout moves by the start offset');
select is(
  (select row(pwo.target_distance_m, pwo.target_pace_sec_per_km, pwo.target_rpe_min, pwo.target_rpe_max,
              pwo.structure::text, pwo.notes)::text
   from plan_workouts pwo join plan_weeks pw on pw.id = pwo.week_id
   where pw.plan_id = (select id from restarted) and pwo.kind = 'easy'),
  '(5000.00,360,3,4,"{""warmup_m"": 1000}","go easy")', 'its targets, structure and notes carry over');
select is(
  (select row(pwo.scheduled_date, pwo.race_name, pwo.race_priority)::text
   from plan_workouts pwo join plan_weeks pw on pw.id = pwo.week_id
   where pw.plan_id = (select id from restarted) and pwo.kind = 'race'),
  row(current_date + 9, 'Parkrun', 'C')::text, 'a race behind the plan moves with it');

select is((select manually_completed from plan_workouts where id = 'aaaaaaaa-0000-0000-0000-0000000e0100'),
  true, 'the source keeps its completions');
select isnt((select skipped_at from plan_workouts where id = 'aaaaaaaa-0000-0000-0000-0000000e0110'),
  null, 'and its skips');
select is((select completed_run_id from plan_workouts where id = 'aaaaaaaa-0000-0000-0000-0000000e0120'),
  'abababab-0000-0000-0000-0000000e0001'::uuid, 'and its run links');
select is(
  (select scheduled_date from plan_workouts where id = 'aaaaaaaa-0000-0000-0000-0000000e0100'),
  current_date - 14, 'and its dates');
select is((select count(*)::int from plan_weeks where plan_id = 'a8a8a8a8-0000-0000-0000-0000000e0001'),
  3, 'and its weeks');

-- A paused source is retired as abandoned too.
reset role;
update training_plans set status = 'paused' where id = 'a8a8a8a8-0000-0000-0000-0000000e0001';
set local role authenticated;
select lives_ok(
  $$select restart_training_plan('a8a8a8a8-0000-0000-0000-0000000e0001', current_date + 7)$$,
  'a paused plan can be restarted');
select is((select status from training_plans where id = 'a8a8a8a8-0000-0000-0000-0000000e0001'),
  'abandoned', 'and the paused source is retired as abandoned');
select is((select status from training_plans where id = (select id from restarted)),
  'abandoned', 'and the earlier copy the new window overlaps is retired too');

-- A completed source is restarted without its status changing.
reset role;
update training_plans set status = 'completed' where id = 'a8a8a8a8-0000-0000-0000-0000000e0001';
set local role authenticated;
select lives_ok(
  $$select restart_training_plan('a8a8a8a8-0000-0000-0000-0000000e0001', current_date + 7)$$,
  'a completed plan can be restarted');
select is((select status from training_plans where id = 'a8a8a8a8-0000-0000-0000-0000000e0001'),
  'completed', 'and stays completed');

reset role;
update training_plans set status = 'abandoned' where id = 'a8a8a8a8-0000-0000-0000-0000000e0001';
set local role authenticated;
select lives_ok(
  $$select restart_training_plan('a8a8a8a8-0000-0000-0000-0000000e0001', current_date + 7)$$,
  'an abandoned plan can be restarted');
select is(
  (select count(*)::int from training_plans
   where user_id = 'a7a7a7a7-0000-0000-0000-0000000e0001' and status = 'active'
     and id <> 'a8a8a8a8-0000-0000-0000-0000000e0006'),
  1, 'leaving exactly one active plan over those dates, the newest copy');

select * from finish();
rollback;

-- Pins migration 20270918000003: set_plan_goal_time writes a plan's goal time,
-- its VDOT and the re-derived workout paces in one transaction, refuses a
-- plan the caller does not own, and rolls the goal back when a workout patch
-- is refused.

begin;
select plan(9);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('f0f0f0f0-0000-0000-0000-0000000b0001', 'authenticated', 'authenticated', 'spg-owner@spg.local', '', now(), now()),
  ('f0f0f0f0-0000-0000-0000-0000000b0002', 'authenticated', 'authenticated', 'spg-other@spg.local', '', now(), now())
on conflict (id) do nothing;
insert into user_profiles (id, display_name) values
  ('f0f0f0f0-0000-0000-0000-0000000b0001', 'SPG Owner'),
  ('f0f0f0f0-0000-0000-0000-0000000b0002', 'SPG Other')
on conflict (id) do nothing;

insert into training_plans (id, user_id, name, goal_event, goal_distance_m, goal_time_seconds, vdot, start_date, end_date, days_per_week, status)
values
  ('f1f1f1f1-0000-0000-0000-0000000b0001', 'f0f0f0f0-0000-0000-0000-0000000b0001', 'Mine', 'distance_half', 21097, 7200, 45.00, '2034-01-01', '2034-01-14', 4, 'active'),
  ('f1f1f1f1-0000-0000-0000-0000000b0002', 'f0f0f0f0-0000-0000-0000-0000000b0002', 'Theirs', 'distance_half', 21097, 7200, 45.00, '2034-01-01', '2034-01-14', 4, 'active');
insert into plan_weeks (id, plan_id, week_index, phase, target_volume_m) values
  ('f2f2f2f2-0000-0000-0000-0000000b0010', 'f1f1f1f1-0000-0000-0000-0000000b0001', 0, 'base', 18000);
insert into plan_workouts (id, week_id, scheduled_date, kind, target_distance_m, target_pace_sec_per_km, structure) values
  ('f3f3f3f3-0000-0000-0000-0000000b0101', 'f2f2f2f2-0000-0000-0000-0000000b0010', '2034-01-03', 'tempo', 8000, 330, null),
  ('f3f3f3f3-0000-0000-0000-0000000b0102', 'f2f2f2f2-0000-0000-0000-0000000b0010', '2034-01-05', 'interval', 10000, 300,
   '{"repeats":{"count":5,"distance_m":1000,"pace_sec_per_km":300,"recovery_pace":"jog"}}');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"f0f0f0f0-0000-0000-0000-0000000b0001","role":"authenticated"}';

select lives_ok(
  $$select set_plan_goal_time('f1f1f1f1-0000-0000-0000-0000000b0001', 6480, 49.5,
      '[{"id":"f3f3f3f3-0000-0000-0000-0000000b0101","target_pace_sec_per_km":297},
        {"id":"f3f3f3f3-0000-0000-0000-0000000b0102","target_pace_sec_per_km":270,
         "structure":{"repeats":{"count":5,"distance_m":1000,"pace_sec_per_km":270,"recovery_pace":"jog"}}}]')$$,
  'the owner sets a new goal time with its re-derived paces');
select is((select goal_time_seconds from training_plans where id = 'f1f1f1f1-0000-0000-0000-0000000b0001'),
  6480, 'the goal time is written');
select is((select vdot from training_plans where id = 'f1f1f1f1-0000-0000-0000-0000000b0001'),
  49.50::numeric, 'the VDOT is written');
select is((select target_pace_sec_per_km from plan_workouts where id = 'f3f3f3f3-0000-0000-0000-0000000b0101'),
  297, 'a workout pace is written in the same call');
select is((select structure->'repeats'->>'pace_sec_per_km' from plan_workouts where id = 'f3f3f3f3-0000-0000-0000-0000000b0102'),
  '270', 'a pace inside the structure is written in the same call');

select throws_ok(
  $$select set_plan_goal_time('f1f1f1f1-0000-0000-0000-0000000b0001', 6000, null,
      '[{"id":"f3f3f3f3-0000-0000-0000-0000000b0101","completed_run_id":"00000000-0000-0000-0000-000000000000"}]')$$,
  null, 'a refused workout patch fails the whole call');
select is((select goal_time_seconds from training_plans where id = 'f1f1f1f1-0000-0000-0000-0000000b0001'),
  6480, 'and the goal time is not changed by it');

select throws_ok(
  $$select set_plan_goal_time('f1f1f1f1-0000-0000-0000-0000000b0002', 6000, null, '[]')$$,
  null, 'another runner''s plan is refused');
select throws_ok(
  $$select set_plan_goal_time('f1f1f1f1-0000-0000-0000-0000000b0001', 0, null, '[]')$$,
  '22023', 'set_plan_goal_time: goal time must be positive', 'a zero goal time is refused');

select * from finish();
rollback;

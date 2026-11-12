-- Pins migration 20270915000001: a walk-run plan may train two days a week,
-- every other plan still needs three, and the table CHECK floor is 2. And
-- 20270917000002: the walk-run-only rule holds on the direct write paths too.

begin;
select plan(10);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values ('c7c7c7c7-0000-0000-0000-0000000b0002', 'authenticated', 'authenticated', 'wr2-owner@wr2.local', '', now(), now())
on conflict (id) do nothing;
insert into user_profiles (id, display_name)
values ('c7c7c7c7-0000-0000-0000-0000000b0002', 'WR2 Owner')
on conflict (id) do nothing;

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"c7c7c7c7-0000-0000-0000-0000000b0002","role":"authenticated"}';

select lives_ok(
  $$ select create_training_plan(
       '{"name":"Two-day walk-run","goal_event":"distance_5k","goal_distance_m":5000,"start_date":"2036-05-04","end_date":"2036-05-10","days_per_week":2}',
       '[{"week_index":0,"phase":"build","target_volume_m":6000,"workouts":[
          {"scheduled_date":"2036-05-04","kind":"walk_run","target_duration_seconds":1800},
          {"scheduled_date":"2036-05-05","kind":"rest"},
          {"scheduled_date":"2036-05-06","kind":"walk_run","target_duration_seconds":1800}
        ]}]') $$,
  'a two-day walk-run plan saves'
);

select throws_ok(
  $$ select create_training_plan(
       '{"name":"Two-day road","goal_event":"distance_5k","goal_distance_m":5000,"start_date":"2036-06-01","end_date":"2036-06-07","days_per_week":2}',
       '[{"week_index":0,"phase":"build","target_volume_m":10000,"workouts":[
          {"scheduled_date":"2036-06-01","kind":"easy","target_distance_m":5000},
          {"scheduled_date":"2036-06-03","kind":"walk_run","target_duration_seconds":1800}
        ]}]') $$,
  '22023',
  'create_training_plan: only a walk-run plan may train two days a week; other plans need 3 to 7',
  'a two-day plan with a road session is refused'
);

select throws_ok(
  $$ select create_training_plan(
       '{"name":"One-day walk-run","goal_event":"distance_5k","goal_distance_m":5000,"start_date":"2036-07-05","end_date":"2036-07-11","days_per_week":1}',
       '[{"week_index":0,"phase":"build","target_volume_m":3000,"workouts":[
          {"scheduled_date":"2036-07-05","kind":"walk_run","target_duration_seconds":1800}
        ]}]') $$,
  '22023',
  'create_training_plan: days per week must be between 2 and 7',
  'one day a week is refused even for walk-run'
);
reset role;

select is(
  (select days_per_week from training_plans
   where user_id = 'c7c7c7c7-0000-0000-0000-0000000b0002' and name = 'Two-day walk-run'),
  2::smallint,
  'the saved plan keeps days_per_week = 2'
);

select throws_ok(
  $$ insert into training_plans (user_id, name, goal_event, goal_distance_m, start_date, end_date, days_per_week, status)
     values ('c7c7c7c7-0000-0000-0000-0000000b0002', 'One day', 'distance_5k', 5000, '2036-09-01', '2036-09-07', 1, 'completed') $$,
  '23514',
  null,
  'the table CHECK still refuses one day a week'
);

-- Direct writes, as the owner through PostgREST would make them.
insert into training_plans (id, user_id, name, goal_event, goal_distance_m, start_date, end_date, days_per_week, status) values
  ('c7c7c7c7-0000-0000-0000-0000000c0001', 'c7c7c7c7-0000-0000-0000-0000000b0002', 'Direct two-day', 'distance_5k', 5000, '2036-10-04', '2036-10-10', 2, 'completed'),
  ('c7c7c7c7-0000-0000-0000-0000000c0002', 'c7c7c7c7-0000-0000-0000-0000000b0002', 'Direct four-day', 'distance_5k', 5000, '2036-11-01', '2036-11-07', 4, 'completed');
insert into plan_weeks (id, plan_id, week_index) values
  ('c7c7c7c7-0000-0000-0000-0000000d0001', 'c7c7c7c7-0000-0000-0000-0000000c0001', 0),
  ('c7c7c7c7-0000-0000-0000-0000000d0002', 'c7c7c7c7-0000-0000-0000-0000000c0002', 0);
insert into plan_workouts (week_id, scheduled_date, kind, target_distance_m) values
  ('c7c7c7c7-0000-0000-0000-0000000d0002', '2036-11-02', 'tempo', 6000);

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"c7c7c7c7-0000-0000-0000-0000000b0002","role":"authenticated"}';
select lives_ok(
  $$ insert into plan_workouts (week_id, scheduled_date, kind, target_duration_seconds)
     values ('c7c7c7c7-0000-0000-0000-0000000d0001', '2036-10-04', 'walk_run', 1800) $$,
  'a walk-run session lands in a two-day plan');
select throws_ok(
  $$ insert into plan_workouts (week_id, scheduled_date, kind, target_distance_m)
     values ('c7c7c7c7-0000-0000-0000-0000000d0001', '2036-10-07', 'easy', 5000) $$,
  '23514', 'plan_workouts: a two-day plan holds only walk-run sessions',
  'a direct insert of a road session into a two-day plan is refused');
select throws_ok(
  $$ update plan_workouts set kind = 'tempo' where week_id = 'c7c7c7c7-0000-0000-0000-0000000d0001' and kind = 'walk_run' $$,
  '23514', 'plan_workouts: a two-day plan holds only walk-run sessions',
  'turning a two-day plan''s session into a road session is refused');
select throws_ok(
  $$ update training_plans set days_per_week = 2 where id = 'c7c7c7c7-0000-0000-0000-0000000c0002' $$,
  '23514', 'training_plans: a two-day plan holds only walk-run sessions',
  'a plan holding a road session cannot become two-day');
select throws_ok(
  $$ update plan_weeks set plan_id = 'c7c7c7c7-0000-0000-0000-0000000c0001' where id = 'c7c7c7c7-0000-0000-0000-0000000d0002' $$,
  '23514', 'plan_weeks: a two-day plan holds only walk-run sessions',
  'a week holding a road session cannot move into a two-day plan');
reset role;

select * from finish();
rollback;

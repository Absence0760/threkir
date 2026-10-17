-- Pins migration 20270915000001: a walk-run plan may train two days a week,
-- every other plan still needs three, and the table CHECK floor is 2.

begin;
select plan(5);

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

select * from finish();
rollback;

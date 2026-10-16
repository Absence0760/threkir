-- Pins migration 20270830000010: create_training_plan writes each workout's
-- race_taper_applied_at, so a tapered plan exported as JSON and imported
-- again keeps the stamps that stop the same B/C race taper cutting it twice.

begin;
select plan(3);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values ('c7c7c7c7-0000-0000-0000-0000000a0001', 'authenticated', 'authenticated', 'cts-owner@cts.local', '', now(), now())
on conflict (id) do nothing;
insert into user_profiles (id, display_name)
values ('c7c7c7c7-0000-0000-0000-0000000a0001', 'CTS Owner')
on conflict (id) do nothing;

create temp table cts_ids (label text primary key, id uuid);
grant select, insert on cts_ids to authenticated;

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"c7c7c7c7-0000-0000-0000-0000000a0001","role":"authenticated"}';

insert into cts_ids values ('plan', create_training_plan(
  '{"name":"Re-imported","goal_event":"distance_half","goal_distance_m":21097,"start_date":"2036-05-04","end_date":"2036-05-10","days_per_week":4}',
  '[{"week_index":0,"phase":"build","target_volume_m":13200,"workouts":[
     {"scheduled_date":"2036-05-06","kind":"easy","target_distance_m":5200,"race_taper_applied_at":"2036-04-30T07:15:00Z"},
     {"scheduled_date":"2036-05-08","kind":"easy","target_distance_m":8000}
   ]}]'));
reset role;

-- 1. The stamped workout keeps its stamp.
select is(
  (select wo.race_taper_applied_at
   from plan_workouts wo join plan_weeks w on w.id = wo.week_id
   where w.plan_id = (select id from cts_ids where label = 'plan') and wo.scheduled_date = '2036-05-06'),
  '2036-04-30T07:15:00Z'::timestamptz,
  'create_training_plan writes a workout''s taper stamp'
);

-- 2. A workout without the key stays unstamped.
select is(
  (select wo.race_taper_applied_at
   from plan_workouts wo join plan_weeks w on w.id = wo.week_id
   where w.plan_id = (select id from cts_ids where label = 'plan') and wo.scheduled_date = '2036-05-08'),
  null::timestamptz,
  'a workout with no stamp key writes NULL'
);

-- 3. A stamp that is not a timestamp refuses the whole create.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"c7c7c7c7-0000-0000-0000-0000000a0001","role":"authenticated"}';
select throws_ok(
  $$ select create_training_plan(
       '{"name":"Bad stamp","goal_event":"distance_10k","goal_distance_m":10000,"start_date":"2036-07-06","end_date":"2036-07-12","days_per_week":4}',
       '[{"week_index":0,"phase":"base","target_volume_m":5000,"workouts":[{"scheduled_date":"2036-07-08","kind":"easy","target_distance_m":5000,"race_taper_applied_at":"not a time"}]}]') $$,
  '22007',
  null,
  'a malformed stamp refuses the create'
);
reset role;

select * from finish();
rollback;

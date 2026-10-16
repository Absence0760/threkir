-- Pins migration 20270830000009: duplicate_plan_week leaves a week's race
-- workouts behind. It used to copy them as kind 'race' with no name or
-- priority, which planRaces reads as a second race (a C race seven days
-- later), with a countdown and a B/C taper window of its own. The copy's
-- target volume drops the race distance it no longer holds.

begin;
select plan(5);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values ('d9d9d9d9-0000-0000-0000-0000000a0001', 'authenticated', 'authenticated', 'dsr-owner@dsr.local', '', now(), now())
on conflict (id) do nothing;
insert into user_profiles (id, display_name)
values ('d9d9d9d9-0000-0000-0000-0000000a0001', 'DSR Owner')
on conflict (id) do nothing;

insert into training_plans (id, user_id, name, goal_event, goal_distance_m, start_date, end_date, days_per_week, status)
values ('dadadada-0000-0000-0000-000000000001', 'd9d9d9d9-0000-0000-0000-0000000a0001', 'Two Oceans block', 'distance_full', 42195, '2035-03-05', '2035-03-25', 4, 'active');
insert into plan_weeks (id, plan_id, week_index, phase, target_volume_m) values
  ('dbdbdbdb-0000-0000-0000-000000000010', 'dadadada-0000-0000-0000-000000000001', 0, 'build', 36000),
  ('dbdbdbdb-0000-0000-0000-000000000011', 'dadadada-0000-0000-0000-000000000001', 1, 'build', 10000),
  ('dbdbdbdb-0000-0000-0000-000000000012', 'dadadada-0000-0000-0000-000000000001', 2, 'race', 42195);
insert into plan_workouts (week_id, scheduled_date, kind, target_distance_m, race_name, race_priority) values
  ('dbdbdbdb-0000-0000-0000-000000000010', '2035-03-07', 'long', 26000, null, null),
  ('dbdbdbdb-0000-0000-0000-000000000010', '2035-03-11', 'race', 10000, 'Club 10K', 'B'),
  ('dbdbdbdb-0000-0000-0000-000000000011', '2035-03-18', 'race', 10000, null, null),
  ('dbdbdbdb-0000-0000-0000-000000000012', '2035-03-25', 'race', 42195, 'Comrades', 'A');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"d9d9d9d9-0000-0000-0000-0000000a0001","role":"authenticated"}';
select duplicate_plan_week('dadadada-0000-0000-0000-000000000001', 0);
reset role;

-- 1. The copy holds the long run and not the B race.
select is(
  (select array_agg(row(wo.scheduled_date, wo.kind::text, wo.target_distance_m::int)::text)
   from plan_workouts wo join plan_weeks w on w.id = wo.week_id
   where w.plan_id = 'dadadada-0000-0000-0000-000000000001' and w.week_index = 1),
  array[row(date '2035-03-14', 'long', 26000)::text],
  'a duplicated week copies its training and leaves its race behind'
);

-- 2. The plan still has exactly the races it had.
select is(
  (select count(*) from plan_workouts wo join plan_weeks w on w.id = wo.week_id
   where w.plan_id = 'dadadada-0000-0000-0000-000000000001' and wo.kind = 'race'),
  3::bigint,
  'duplicating a race week invents no race'
);

-- 3. The copy's volume drops the race distance: 36000 - 10000.
select is(
  (select target_volume_m::int from plan_weeks
   where plan_id = 'dadadada-0000-0000-0000-000000000001' and week_index = 1),
  26000,
  'the copy''s target volume no longer counts the race it left behind'
);

-- 4. A week that is only a race duplicates as an empty week at volume 0.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"d9d9d9d9-0000-0000-0000-0000000a0001","role":"authenticated"}';
select duplicate_plan_week('dadadada-0000-0000-0000-000000000001', 2);
reset role;
select is(
  (select row(w.target_volume_m::int, count(wo.id))::text
   from plan_weeks w left join plan_workouts wo on wo.week_id = w.id
   where w.plan_id = 'dadadada-0000-0000-0000-000000000001' and w.week_index = 3
   group by w.target_volume_m),
  row(0, 0::bigint)::text,
  'a race-only week copies as an empty week with no volume'
);

-- 5. The end date still moves a week per duplicate.
select is(
  (select end_date from training_plans where id = 'dadadada-0000-0000-0000-000000000001'),
  date '2035-04-08',
  'each duplicate still extends the plan by a week'
);

select * from finish();
rollback;

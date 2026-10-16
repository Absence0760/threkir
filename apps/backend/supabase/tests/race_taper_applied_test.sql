-- Pins migration 20270830000007 (decisions § 2051 follow-up): a B/C race
-- taper stamps plan_workouts.race_taper_applied_at through
-- apply_workout_adjustments, so the next proposal leaves the eased workout
-- alone, and every copy path carries the stamp with the eased distance it
-- describes: clone_plan_template, clone_public_plan, assign_plan_to_athlete
-- and duplicate_plan_week. Without the copy, a tapered plan's clone would
-- offer the same cut again on distances already cut.

begin;
select plan(8);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('e7e7e7e7-0000-0000-0000-0000000a0001', 'authenticated', 'authenticated', 'rta-owner@rta.local', '', now(), now()),
  ('e7e7e7e7-0000-0000-0000-0000000a0002', 'authenticated', 'authenticated', 'rta-athlete@rta.local', '', now(), now()),
  ('e7e7e7e7-0000-0000-0000-0000000a0003', 'authenticated', 'authenticated', 'rta-publisher@rta.local', '', now(), now())
on conflict (id) do nothing;
insert into user_profiles (id, display_name) values
  ('e7e7e7e7-0000-0000-0000-0000000a0001', 'RTA Owner'),
  ('e7e7e7e7-0000-0000-0000-0000000a0002', 'RTA Athlete'),
  ('e7e7e7e7-0000-0000-0000-0000000a0003', 'RTA Publisher')
on conflict (id) do nothing;
insert into coach_athletes (coach_id, athlete_id, status, invite_token) values
  ('e7e7e7e7-0000-0000-0000-0000000a0001', 'e7e7e7e7-0000-0000-0000-0000000a0002', 'active', 'tok-rta-athlete');

-- Owner: plan 1 (the taper target), template 2 (owner's, tapered). Publisher:
-- public template 3 (tapered).
insert into training_plans (id, user_id, name, goal_event, goal_distance_m, start_date, end_date, days_per_week, status, is_template, is_public_template)
values
  ('e8e8e8e8-0000-0000-0000-000000000001', 'e7e7e7e7-0000-0000-0000-0000000a0001', 'Tapered', 'distance_half', 21097, '2034-01-01', '2034-01-14', 4, 'active', false, false),
  ('e8e8e8e8-0000-0000-0000-000000000002', 'e7e7e7e7-0000-0000-0000-0000000a0001', 'Tapered template', 'distance_half', 21097, '2034-01-01', '2034-01-07', 4, 'completed', true, false),
  ('e8e8e8e8-0000-0000-0000-000000000003', 'e7e7e7e7-0000-0000-0000-0000000a0003', 'Tapered public', 'distance_half', 21097, '2034-01-01', '2034-01-07', 4, 'completed', true, true);
insert into plan_weeks (id, plan_id, week_index, phase, target_volume_m) values
  ('e9e9e9e9-0000-0000-0000-000000000010', 'e8e8e8e8-0000-0000-0000-000000000001', 0, 'build', 13000),
  ('e9e9e9e9-0000-0000-0000-000000000011', 'e8e8e8e8-0000-0000-0000-000000000001', 1, 'build', 8000),
  ('e9e9e9e9-0000-0000-0000-000000000020', 'e8e8e8e8-0000-0000-0000-000000000002', 0, 'build', 5200),
  ('e9e9e9e9-0000-0000-0000-000000000030', 'e8e8e8e8-0000-0000-0000-000000000003', 0, 'build', 5200);
insert into plan_workouts (id, week_id, scheduled_date, kind, target_distance_m, race_taper_applied_at) values
  ('eaeaeaea-0000-0000-0000-000000000101', 'e9e9e9e9-0000-0000-0000-000000000010', '2034-01-03', 'easy', 8000, null),
  ('eaeaeaea-0000-0000-0000-000000000102', 'e9e9e9e9-0000-0000-0000-000000000010', '2034-01-05', 'easy', 5000, null),
  ('eaeaeaea-0000-0000-0000-000000000111', 'e9e9e9e9-0000-0000-0000-000000000011', '2034-01-10', 'easy', 8000, null),
  ('eaeaeaea-0000-0000-0000-000000000201', 'e9e9e9e9-0000-0000-0000-000000000020', '2034-01-03', 'easy', 5200, '2033-12-20T08:00:00Z'),
  ('eaeaeaea-0000-0000-0000-000000000301', 'e9e9e9e9-0000-0000-0000-000000000030', '2034-01-03', 'easy', 5200, '2033-12-20T08:00:00Z');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"e7e7e7e7-0000-0000-0000-0000000a0001","role":"authenticated"}';

-- 1. The taper's apply writes the stamp beside the eased distance.
select lives_ok(
  $$ select apply_workout_adjustments('e8e8e8e8-0000-0000-0000-000000000001',
       '[{"id":"eaeaeaea-0000-0000-0000-000000000101","target_distance_m":5200,"race_taper_applied_at":"2034-01-01T07:30:00Z"}]') $$,
  'apply_workout_adjustments accepts race_taper_applied_at'
);
reset role;
select is(
  (select row(target_distance_m::int, race_taper_applied_at)::text
   from plan_workouts where id = 'eaeaeaea-0000-0000-0000-000000000101'),
  row(5200, '2034-01-01T07:30:00Z'::timestamptz)::text,
  'the eased workout carries its stamp'
);

-- 2. A later adjustment that does not name the key leaves the stamp alone.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"e7e7e7e7-0000-0000-0000-0000000a0001","role":"authenticated"}';
select apply_workout_adjustments('e8e8e8e8-0000-0000-0000-000000000001',
  '[{"id":"eaeaeaea-0000-0000-0000-000000000101","notes":"Shakeout"}]');
reset role;
select is(
  (select race_taper_applied_at from plan_workouts where id = 'eaeaeaea-0000-0000-0000-000000000101'),
  '2034-01-01T07:30:00Z'::timestamptz,
  'an adjustment that does not name the stamp keeps it'
);

-- 3. Duplicating the tapered week copies the stamp with the eased distance.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"e7e7e7e7-0000-0000-0000-0000000a0001","role":"authenticated"}';
select duplicate_plan_week('e8e8e8e8-0000-0000-0000-000000000001', 0);
reset role;
select is(
  (select array_agg(row(wo.target_distance_m::int, wo.race_taper_applied_at is not null)::text order by wo.scheduled_date)
   from plan_workouts wo join plan_weeks w on w.id = wo.week_id
   where w.plan_id = 'e8e8e8e8-0000-0000-0000-000000000001' and w.week_index = 1),
  array[row(5200, true)::text, row(5000, false)::text],
  'duplicate_plan_week copies the stamp with the eased distance, and no stamp where there was none'
);

-- 4. Cloning the owner's tapered template carries the stamp.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"e7e7e7e7-0000-0000-0000-0000000a0001","role":"authenticated"}';
select clone_plan_template('e8e8e8e8-0000-0000-0000-000000000002', '2034-06-04', 'refuse');
reset role;
select is(
  (select wo.race_taper_applied_at
   from plan_workouts wo join plan_weeks w on w.id = wo.week_id
   join training_plans tp on tp.id = w.plan_id
   where tp.parent_template_id = 'e8e8e8e8-0000-0000-0000-000000000002'),
  '2033-12-20T08:00:00Z'::timestamptz,
  'clone_plan_template carries the stamp'
);

-- 5. Cloning a public template carries the stamp.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"e7e7e7e7-0000-0000-0000-0000000a0001","role":"authenticated"}';
select clone_public_plan('e8e8e8e8-0000-0000-0000-000000000003', '2034-08-06', 'refuse');
reset role;
select is(
  (select wo.race_taper_applied_at
   from plan_workouts wo join plan_weeks w on w.id = wo.week_id
   join training_plans tp on tp.id = w.plan_id
   where tp.parent_template_id = 'e8e8e8e8-0000-0000-0000-000000000003'),
  '2033-12-20T08:00:00Z'::timestamptz,
  'clone_public_plan carries the stamp'
);

-- 6. Assigning the tapered plan to an athlete carries the stamp.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"e7e7e7e7-0000-0000-0000-0000000a0001","role":"authenticated"}';
select assign_plan_to_athlete('e8e8e8e8-0000-0000-0000-000000000002',
  'e7e7e7e7-0000-0000-0000-0000000a0002', '2034-10-01');
reset role;
select is(
  (select wo.race_taper_applied_at
   from plan_workouts wo join plan_weeks w on w.id = wo.week_id
   join training_plans tp on tp.id = w.plan_id
   where tp.user_id = 'e7e7e7e7-0000-0000-0000-0000000a0002'),
  '2033-12-20T08:00:00Z'::timestamptz,
  'assign_plan_to_athlete carries the stamp'
);

-- 7. A key that is not a writable column is still refused.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"e7e7e7e7-0000-0000-0000-0000000a0001","role":"authenticated"}';
select throws_ok(
  $$ select apply_workout_adjustments('e8e8e8e8-0000-0000-0000-000000000001',
       '[{"id":"eaeaeaea-0000-0000-0000-000000000102","completed_at":"2034-01-05T08:00:00Z"}]') $$,
  '22023',
  'apply_workout_adjustments: a change names a column it cannot write',
  'a key outside the writable set is still refused'
);
reset role;

select * from finish();
rollback;

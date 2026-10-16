-- Pins migration 20270830000005 (decisions § 2062): apply_workout_adjustments
-- writes a batch of workout patches and restates only the touched weeks'
-- volume in one transaction, trim_training_plan's completed-workout refusal
-- carries TR001 (and create_training_plan lets it through), trimmed_at is
-- cleared when a trimmed plan is made longer, and create_training_plan
-- refuses a workout dated outside the plan's window.

begin;
select plan(21);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('f0f0f0f0-0000-0000-0000-0000000a0001', 'authenticated', 'authenticated', 'prf-owner@prf.local', '', now(), now()),
  ('f0f0f0f0-0000-0000-0000-0000000a0002', 'authenticated', 'authenticated', 'prf-other@prf.local', '', now(), now())
on conflict (id) do nothing;
insert into user_profiles (id, display_name) values
  ('f0f0f0f0-0000-0000-0000-0000000a0001', 'PRF Owner'),
  ('f0f0f0f0-0000-0000-0000-0000000a0002', 'PRF Other')
on conflict (id) do nothing;

-- Owner: plan 1 (three weeks, the adjustment target), plan 2 (another of the
-- owner's plans), plan 4 (a completed workout after its would-be cut), plans
-- 5 and 6 (trimmed, then extended or shifted). Other: plan b3.
insert into training_plans (id, user_id, name, goal_event, goal_distance_m, start_date, end_date, days_per_week, status)
values
  ('f1f1f1f1-0000-0000-0000-000000000001', 'f0f0f0f0-0000-0000-0000-0000000a0001', 'Adjusted', 'distance_half', 21097, '2033-01-02', '2033-01-22', 4, 'active'),
  ('f1f1f1f1-0000-0000-0000-000000000002', 'f0f0f0f0-0000-0000-0000-0000000a0001', 'Elsewhere', 'distance_10k', 10000, '2033-03-06', '2033-03-12', 4, 'active'),
  ('f1f1f1f1-0000-0000-0000-000000000004', 'f0f0f0f0-0000-0000-0000-0000000a0001', 'Ran ahead', 'distance_10k', 10000, '2033-05-01', '2033-05-21', 4, 'active'),
  ('f1f1f1f1-0000-0000-0000-000000000005', 'f0f0f0f0-0000-0000-0000-0000000a0001', 'Extended', 'distance_10k', 10000, '2033-07-03', '2033-07-23', 4, 'active'),
  ('f1f1f1f1-0000-0000-0000-000000000006', 'f0f0f0f0-0000-0000-0000-0000000a0001', 'Shifted', 'distance_10k', 10000, '2033-09-04', '2033-09-24', 4, 'active'),
  ('f1f1f1f1-0000-0000-0000-0000000000b3', 'f0f0f0f0-0000-0000-0000-0000000a0002', 'Not yours', 'distance_10k', 10000, '2033-01-02', '2033-01-08', 4, 'active');
insert into plan_weeks (id, plan_id, week_index, phase, target_volume_m) values
  ('f2f2f2f2-0000-0000-0000-000000000010', 'f1f1f1f1-0000-0000-0000-000000000001', 0, 'base', 99999),
  ('f2f2f2f2-0000-0000-0000-000000000011', 'f1f1f1f1-0000-0000-0000-000000000001', 1, 'build', 99999),
  ('f2f2f2f2-0000-0000-0000-000000000012', 'f1f1f1f1-0000-0000-0000-000000000001', 2, 'peak', 55555),
  ('f2f2f2f2-0000-0000-0000-000000000020', 'f1f1f1f1-0000-0000-0000-000000000002', 0, 'base', 5000),
  ('f2f2f2f2-0000-0000-0000-000000000040', 'f1f1f1f1-0000-0000-0000-000000000004', 2, 'base', 6000),
  ('f2f2f2f2-0000-0000-0000-0000000000b3', 'f1f1f1f1-0000-0000-0000-0000000000b3', 0, 'base', 5000);
insert into plan_workouts (id, week_id, scheduled_date, kind, target_distance_m, target_pace_sec_per_km, target_pace_tolerance_sec, structure, notes) values
  ('f3f3f3f3-0000-0000-0000-000000000101', 'f2f2f2f2-0000-0000-0000-000000000010', '2033-01-04', 'tempo', 8000, 300, 10, null, 'Tempo'),
  ('f3f3f3f3-0000-0000-0000-000000000102', 'f2f2f2f2-0000-0000-0000-000000000010', '2033-01-06', 'easy', 4000, null, null, null, null),
  ('f3f3f3f3-0000-0000-0000-000000000111', 'f2f2f2f2-0000-0000-0000-000000000011', '2033-01-11', 'interval', 10000, 240, 5, '{"reps":6}', 'Sixes'),
  ('f3f3f3f3-0000-0000-0000-000000000121', 'f2f2f2f2-0000-0000-0000-000000000012', '2033-01-18', 'long', 18000, null, null, null, null),
  ('f3f3f3f3-0000-0000-0000-000000000201', 'f2f2f2f2-0000-0000-0000-000000000020', '2033-03-08', 'easy', 5000, null, null, null, null),
  ('f3f3f3f3-0000-0000-0000-000000000401', 'f2f2f2f2-0000-0000-0000-000000000040', '2033-05-15', 'easy', 6000, null, null, null, null),
  ('f3f3f3f3-0000-0000-0000-0000000003b3', 'f2f2f2f2-0000-0000-0000-0000000000b3', '2033-01-04', 'easy', 5000, null, null, null, 'Theirs');
update plan_workouts set manually_completed = true, completed_at = now()
where id = 'f3f3f3f3-0000-0000-0000-000000000401';

create temp table prf_args (label text primary key, plan jsonb, weeks jsonb);
grant select on prf_args to authenticated;
insert into prf_args values
  ('trims_ran_ahead',
   '{"name":"After","goal_event":"distance_10k","goal_distance_m":10000,"start_date":"2033-05-11","end_date":"2033-05-20","days_per_week":4}',
   '[{"week_index":0,"phase":"base","target_volume_m":5000,"workouts":[{"scheduled_date":"2033-05-12","kind":"easy","target_distance_m":5000}]}]'),
  ('out_of_window',
   '{"name":"Spills over","goal_event":"distance_10k","goal_distance_m":10000,"start_date":"2033-11-06","end_date":"2033-11-19","days_per_week":4}',
   '[{"week_index":0,"phase":"base","target_volume_m":5000,"workouts":[{"scheduled_date":"2033-11-25","kind":"easy","target_distance_m":5000}]}]');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"f0f0f0f0-0000-0000-0000-0000000a0001","role":"authenticated"}';

-- 1. Present keys are written, absent ones left alone, JSON null writes NULL.
select lives_ok(
  $$ select apply_workout_adjustments('f1f1f1f1-0000-0000-0000-000000000001',
       '[{"id":"f3f3f3f3-0000-0000-0000-000000000101","kind":"easy","target_distance_m":6000,"target_pace_sec_per_km":null},
         {"id":"f3f3f3f3-0000-0000-0000-000000000111","target_distance_m":7000,"structure":null}]') $$,
  'the owner applies a batch of adjustments'
);
reset role;
select is(
  (select row(kind, target_distance_m::int, target_pace_sec_per_km, target_pace_tolerance_sec, notes)::text
   from plan_workouts where id = 'f3f3f3f3-0000-0000-0000-000000000101'),
  row('easy'::workout_kind, 6000, null::int, 10, 'Tempo')::text,
  'present keys are written, a JSON null clears its column, absent keys are untouched'
);
select is(
  (select row(kind, target_distance_m::int, structure, target_pace_sec_per_km, notes)::text
   from plan_workouts where id = 'f3f3f3f3-0000-0000-0000-000000000111'),
  row('interval'::workout_kind, 7000, null::jsonb, 240, 'Sixes')::text,
  'a structure set to null is cleared while the kind and pace it did not name stay'
);
select is(
  (select array_agg(target_volume_m::int order by week_index) from plan_weeks
   where plan_id = 'f1f1f1f1-0000-0000-0000-000000000001'),
  array[10000, 7000, 55555],
  'each touched week''s volume is restated from its workouts; the untouched week keeps its own'
);

-- 2. A workout from another of the owner's plans refuses the whole batch.
set local role authenticated;
select throws_ok(
  $$ select apply_workout_adjustments('f1f1f1f1-0000-0000-0000-000000000001',
       '[{"id":"f3f3f3f3-0000-0000-0000-000000000102","target_distance_m":1000},
         {"id":"f3f3f3f3-0000-0000-0000-000000000201","target_distance_m":1000}]') $$,
  'P0001',
  'apply_workout_adjustments: workout f3f3f3f3-0000-0000-0000-000000000201 is not in plan f1f1f1f1-0000-0000-0000-000000000001',
  'a workout from another plan is refused'
);
reset role;
select is(
  (select array_agg(target_distance_m::int order by id) from plan_workouts
   where id in ('f3f3f3f3-0000-0000-0000-000000000102', 'f3f3f3f3-0000-0000-0000-000000000201')),
  array[4000, 5000],
  'the refused batch changed neither workout, including the one listed before the stray id'
);

-- 3. Another user's plan is refused and left as it was.
set local role authenticated;
select throws_ok(
  $$ select apply_workout_adjustments('f1f1f1f1-0000-0000-0000-0000000000b3',
       '[{"id":"f3f3f3f3-0000-0000-0000-0000000003b3","notes":"Mine now"}]') $$,
  'P0001',
  'apply_workout_adjustments: plan f1f1f1f1-0000-0000-0000-0000000000b3 not found',
  'another runner''s plan is refused'
);
select throws_ok(
  $$ select apply_workout_adjustments('f1f1f1f1-0000-0000-0000-000000000001',
       '[{"id":"f3f3f3f3-0000-0000-0000-0000000003b3","notes":"Mine now"}]') $$,
  'P0001',
  'apply_workout_adjustments: workout f3f3f3f3-0000-0000-0000-0000000003b3 is not in plan f1f1f1f1-0000-0000-0000-000000000001',
  'another runner''s workout cannot be smuggled into the owner''s plan'
);
reset role;
select is(
  (select notes from plan_workouts where id = 'f3f3f3f3-0000-0000-0000-0000000003b3'),
  'Theirs',
  'the other runner''s workout is unchanged'
);

-- 4. A key the RPC does not write is refused rather than ignored.
set local role authenticated;
select throws_ok(
  $$ select apply_workout_adjustments('f1f1f1f1-0000-0000-0000-000000000001',
       '[{"id":"f3f3f3f3-0000-0000-0000-000000000102","scheduled_date":"2033-01-07"}]') $$,
  '22023',
  'apply_workout_adjustments: a change names a column it cannot write',
  'an unknown key is refused'
);

-- 5. Trim's completed-workout refusal is TR001, also through create.
select throws_ok(
  $$ select trim_training_plan('f1f1f1f1-0000-0000-0000-000000000004', '2033-05-10') $$,
  'TR001',
  'trim_training_plan: completed workouts fall after 2033-05-10',
  'a trim over a completed workout raises TR001'
);
select throws_ok(
  $$ select create_training_plan(plan, weeks, 'trim') from prf_args where label = 'trims_ran_ahead' $$,
  'TR001',
  'trim_training_plan: completed workouts fall after 2033-05-10',
  'create_training_plan lets the trim refusal through unchanged'
);
reset role;
select is(
  (select row(end_date, trimmed_at)::text from training_plans where id = 'f1f1f1f1-0000-0000-0000-000000000004'),
  row('2033-05-21'::date, null::timestamptz)::text,
  'the refused trims left the plan''s end and stamp alone'
);

-- 6. trimmed_at: set by the trim, cleared by an extension, kept by a shift.
set local role authenticated;
select lives_ok(
  $$ select trim_training_plan('f1f1f1f1-0000-0000-0000-000000000005', '2033-07-16') $$,
  'the owner trims plan 5'
);
select lives_ok(
  $$ select trim_training_plan('f1f1f1f1-0000-0000-0000-000000000006', '2033-09-17') $$,
  'the owner trims plan 6'
);
reset role;
select isnt(
  (select trimmed_at from training_plans where id = 'f1f1f1f1-0000-0000-0000-000000000005'),
  null,
  'the trim''s own update keeps the stamp it sets'
);
set local role authenticated;
update training_plans set end_date = '2033-07-30' where id = 'f1f1f1f1-0000-0000-0000-000000000005';
select lives_ok(
  $$ select shift_training_plan('f1f1f1f1-0000-0000-0000-000000000006', 7) $$,
  'the owner shifts plan 6 a week'
);
reset role;
select is(
  (select row(end_date, trimmed_at)::text from training_plans where id = 'f1f1f1f1-0000-0000-0000-000000000005'),
  row('2033-07-30'::date, null::timestamptz)::text,
  'extending a trimmed plan clears its stamp'
);
select is(
  (select row(start_date, end_date, trimmed_at is not null)::text from training_plans where id = 'f1f1f1f1-0000-0000-0000-000000000006'),
  row('2033-09-11'::date, '2033-09-24'::date, true)::text,
  'shifting a trimmed plan keeps its stamp'
);

-- 7. create_training_plan refuses a workout outside the plan's window.
set local role authenticated;
select throws_ok(
  $$ select create_training_plan(plan, weeks) from prf_args where label = 'out_of_window' $$,
  '22023',
  'create_training_plan: every workout must fall between the plan''s start and end dates',
  'a workout after the plan''s end is refused'
);
reset role;
select is(
  (select array_agg(name order by start_date) from training_plans
   where user_id = 'f0f0f0f0-0000-0000-0000-0000000a0001'),
  array['Adjusted', 'Elsewhere', 'Ran ahead', 'Extended', 'Shifted'],
  'neither refused create wrote a plan'
);

select * from finish();
rollback;

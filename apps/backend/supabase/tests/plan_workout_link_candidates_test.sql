-- Pins migration 20270901000002 (issue #1186): a run that matched nothing on
-- its own local day is offered the open workouts within two days either
-- side, by the matcher's own 75% rule, nearest day first; only to its owner,
-- and never once it is linked.
begin;
select plan(15);

set local timezone = 'UTC';

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at) values
  ('11860000-0000-0000-0000-0000000001a1', 'authenticated', 'authenticated', 'cand@match.local', '', now(), now()),
  ('11860000-0000-0000-0000-0000000001b1', 'authenticated', 'authenticated', 'other@match.local', '', now(), now());
insert into user_profiles (id, display_name, age_confirmed_at) values
  ('11860000-0000-0000-0000-0000000001a1', 'Cand', now()),
  ('11860000-0000-0000-0000-0000000001b1', 'Other', now())
on conflict (id) do update set age_confirmed_at = excluded.age_confirmed_at;
insert into user_settings (user_id, prefs) values
  ('11860000-0000-0000-0000-0000000001a1', '{"time_zone":"America/Los_Angeles"}')
on conflict (user_id) do update set prefs = excluded.prefs;

insert into training_plans (id, user_id, name, goal_event, goal_distance_m, start_date, end_date, days_per_week, status) values
  ('11860000-0000-0000-0000-0000000002a1', '11860000-0000-0000-0000-0000000001a1', 'Active', 'distance_10k', 10000, '2031-01-05', '2031-02-28', 4, 'active'),
  ('11860000-0000-0000-0000-0000000002a2', '11860000-0000-0000-0000-0000000001a1', 'Old', 'distance_10k', 10000, '2031-01-05', '2031-02-28', 4, 'abandoned');
insert into plan_weeks (id, plan_id, week_index) values
  ('11860000-0000-0000-0000-0000000003a1', '11860000-0000-0000-0000-0000000002a1', 0),
  ('11860000-0000-0000-0000-0000000003a2', '11860000-0000-0000-0000-0000000002a2', 0);

-- The run is on Tuesday 2031-01-14 local (18:00 Pacific = 02:00 UTC on the
-- 15th), 10 km. Its own day has nothing, so it stays unlinked.
insert into plan_workouts (id, week_id, scheduled_date, kind, target_distance_m) values
  ('11860000-0000-0000-0000-0000000004a1', '11860000-0000-0000-0000-0000000003a1', '2031-01-16', 'long', 12000),    -- +2, fits
  ('11860000-0000-0000-0000-0000000004a2', '11860000-0000-0000-0000-0000000003a1', '2031-01-13', 'easy', 10000),    -- -1, fits
  ('11860000-0000-0000-0000-0000000004a3', '11860000-0000-0000-0000-0000000003a1', '2031-01-15', 'tempo', 20000),   -- +1, too far short
  ('11860000-0000-0000-0000-0000000004a4', '11860000-0000-0000-0000-0000000003a1', '2031-01-17', 'easy', 10000),    -- +3, out of window
  ('11860000-0000-0000-0000-0000000004a5', '11860000-0000-0000-0000-0000000003a1', '2031-01-12', 'easy', 10000),    -- -2, skipped below
  ('11860000-0000-0000-0000-0000000004a6', '11860000-0000-0000-0000-0000000003a2', '2031-01-15', 'easy', 10000);    -- abandoned plan
update plan_workouts set skipped_at = now() where id = '11860000-0000-0000-0000-0000000004a5';

insert into runs (id, user_id, started_at, duration_s, distance_m, source, activity_type) values
  ('11860000-0000-0000-0000-0000000005a1', '11860000-0000-0000-0000-0000000001a1', '2031-01-15 02:00:00+00', 3000, 10000, 'app', 'run'),
  ('11860000-0000-0000-0000-0000000005a2', '11860000-0000-0000-0000-0000000001a1', '2031-01-15 02:30:00+00', 3000, 30000, 'app', 'cycle');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"11860000-0000-0000-0000-0000000001a1","role":"authenticated"}';

select is(
  (select array_agg(workout_id order by ord) from (
     select workout_id, row_number() over () as ord
     from plan_workout_link_candidates('11860000-0000-0000-0000-0000000005a1')) c),
  array['11860000-0000-0000-0000-0000000004a2', '11860000-0000-0000-0000-0000000004a1']::uuid[],
  'the open, fitting workouts within two local days, nearest day first'
);
select is(
  (select day_offset from plan_workout_link_candidates('11860000-0000-0000-0000-0000000005a1')
   where workout_id = '11860000-0000-0000-0000-0000000004a1'),
  2,
  'day_offset counts from the run''s local day, not its UTC day'
);
select is(
  (select day_offset from plan_workout_link_candidates('11860000-0000-0000-0000-0000000005a1')
   where workout_id = '11860000-0000-0000-0000-0000000004a2'),
  -1,
  'a workout the day before reads as done late'
);
select ok(
  not exists (select 1 from plan_workout_link_candidates('11860000-0000-0000-0000-0000000005a1')
              where workout_id in ('11860000-0000-0000-0000-0000000004a3', '11860000-0000-0000-0000-0000000004a4',
                                   '11860000-0000-0000-0000-0000000004a5', '11860000-0000-0000-0000-0000000004a6')),
  'never a workout the run falls short of, outside the window, skipped, or in an abandoned plan'
);
select is(
  (select count(*)::int from plan_workout_link_candidates('11860000-0000-0000-0000-0000000005a2')),
  0,
  'a ride is offered nothing'
);
select is(
  (select completed_run_id from plan_workouts where id = '11860000-0000-0000-0000-0000000004a2'),
  null,
  'nothing was linked silently'
);

set local "request.jwt.claims" = '{"sub":"11860000-0000-0000-0000-0000000001b1","role":"authenticated"}';
select is(
  (select count(*)::int from plan_workout_link_candidates('11860000-0000-0000-0000-0000000005a1')),
  0,
  'another user is offered nothing for a run they do not own'
);
set local "request.jwt.claims" = '{"sub":"11860000-0000-0000-0000-0000000001a1","role":"authenticated"}';

-- Saying yes is the ordinary owner update: a hand link the matcher never moves.
update plan_workouts set completed_run_id = '11860000-0000-0000-0000-0000000005a1', completed_at = now()
where id = '11860000-0000-0000-0000-0000000004a2';
select is(
  (select count(*)::int from plan_workout_link_candidates('11860000-0000-0000-0000-0000000005a1')),
  0,
  'a linked run is offered nothing more'
);
select is(
  (select completed_run_id from plan_workouts where id = '11860000-0000-0000-0000-0000000004a2'),
  '11860000-0000-0000-0000-0000000005a1'::uuid,
  'the owner links the candidate through the table'
);

-- Taken off again by hand: never offered again for this run.
update plan_workouts set completed_run_id = null, completed_at = null
where id = '11860000-0000-0000-0000-0000000004a2';
select is(
  (select array_agg(workout_id) from plan_workout_link_candidates('11860000-0000-0000-0000-0000000005a1')),
  array['11860000-0000-0000-0000-0000000004a1']::uuid[],
  'a workout the runner took this run off is not offered again'
);

-- "Not this one": another user's dismissal does nothing; the owner's sticks.
set local "request.jwt.claims" = '{"sub":"11860000-0000-0000-0000-0000000001b1","role":"authenticated"}';
select dismiss_plan_workout_link('11860000-0000-0000-0000-0000000004a1', '11860000-0000-0000-0000-0000000005a1');
set local "request.jwt.claims" = '{"sub":"11860000-0000-0000-0000-0000000001a1","role":"authenticated"}';
select is(
  (select count(*)::int from plan_workout_link_candidates('11860000-0000-0000-0000-0000000005a1')),
  1,
  'another user cannot dismiss a workout for this run'
);
select dismiss_plan_workout_link('11860000-0000-0000-0000-0000000004a1', '11860000-0000-0000-0000-0000000005a1');
select is(
  (select count(*)::int from plan_workout_link_candidates('11860000-0000-0000-0000-0000000005a1')),
  0,
  'a dismissed workout is not offered again'
);

reset role;
set local "request.jwt.claims" = '';
select throws_ok(
  $$ select dismiss_plan_workout_link('11860000-0000-0000-0000-0000000004a1', '11860000-0000-0000-0000-0000000005a1') $$,
  '42501', null,
  'an anonymous caller cannot dismiss'
);
select throws_ok(
  $$ select * from plan_workout_link_candidates('11860000-0000-0000-0000-0000000005a1') $$,
  '42501', null,
  'an anonymous caller is refused'
);
select ok(
  not has_function_privilege('anon', 'public.plan_workout_link_candidates(uuid)', 'execute'),
  'anon holds no execute grant'
);

select * from finish();
rollback;

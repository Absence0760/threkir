-- Pins migration 20270830000003 (decisions § 2042) and the plan-chaining
-- paths 20270830000001 changed without a test: coach_roster_summary's
-- current-plan pick, assign_plan_to_athlete onto free dates, the atomic
-- shift_training_plan (alone and carrying the queued plans), and the target
-- volume trim_training_plan leaves on the week it cuts.

begin;
select plan(15);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('cccccccc-0000-0000-0000-0000000c0001', 'authenticated', 'authenticated', 'chain-coach@pcf.local', '', now(), now()),
  ('cccccccc-0000-0000-0000-0000000a0001', 'authenticated', 'authenticated', 'chain-x@pcf.local', '', now(), now()),
  ('cccccccc-0000-0000-0000-0000000a0002', 'authenticated', 'authenticated', 'chain-y@pcf.local', '', now(), now()),
  ('cccccccc-0000-0000-0000-0000000a0003', 'authenticated', 'authenticated', 'chain-z@pcf.local', '', now(), now()),
  ('cccccccc-0000-0000-0000-0000000a0004', 'authenticated', 'authenticated', 'chain-s@pcf.local', '', now(), now())
on conflict (id) do nothing;
insert into user_profiles (id, display_name) values
  ('cccccccc-0000-0000-0000-0000000c0001', 'Chain Coach'),
  ('cccccccc-0000-0000-0000-0000000a0001', 'Athlete X'),
  ('cccccccc-0000-0000-0000-0000000a0002', 'Athlete Y'),
  ('cccccccc-0000-0000-0000-0000000a0003', 'Athlete Z'),
  ('cccccccc-0000-0000-0000-0000000a0004', 'Shifter')
on conflict (id) do nothing;
insert into coach_athletes (coach_id, athlete_id, status, invite_token, accepted_at) values
  ('cccccccc-0000-0000-0000-0000000c0001', 'cccccccc-0000-0000-0000-0000000a0001', 'active', 'pcf-tok-x', now()),
  ('cccccccc-0000-0000-0000-0000000c0001', 'cccccccc-0000-0000-0000-0000000a0002', 'active', 'pcf-tok-y', now()),
  ('cccccccc-0000-0000-0000-0000000c0001', 'cccccccc-0000-0000-0000-0000000a0003', 'active', 'pcf-tok-z', now());

-- X: an ended block, the block covering today, and one queued after it.
-- Y: an ended block and a queued one (between plans).  Z: only a queued one.
insert into training_plans (id, user_id, name, goal_event, goal_distance_m, start_date, end_date, days_per_week, status)
values
  ('dddddddd-0000-0000-0000-0000000a0001', 'cccccccc-0000-0000-0000-0000000a0001', 'X ended', 'distance_10k', 10000, current_date - 60, current_date - 30, 4, 'active'),
  ('dddddddd-0000-0000-0000-0000000a0002', 'cccccccc-0000-0000-0000-0000000a0001', 'X current', 'distance_half', 21097, current_date - 10, current_date + 10, 4, 'active'),
  ('dddddddd-0000-0000-0000-0000000a0003', 'cccccccc-0000-0000-0000-0000000a0001', 'X queued', 'distance_full', 42195, current_date + 11, current_date + 40, 4, 'active'),
  ('dddddddd-0000-0000-0000-0000000b0001', 'cccccccc-0000-0000-0000-0000000a0002', 'Y ended', 'distance_10k', 10000, current_date - 40, current_date - 5, 4, 'active'),
  ('dddddddd-0000-0000-0000-0000000b0002', 'cccccccc-0000-0000-0000-0000000a0002', 'Y queued', 'distance_half', 21097, current_date + 5, current_date + 60, 4, 'active'),
  ('dddddddd-0000-0000-0000-0000000e0001', 'cccccccc-0000-0000-0000-0000000a0003', 'Z queued', 'distance_5k', 5000, current_date + 3, current_date + 30, 4, 'active'),
  ('dddddddd-0000-0000-0000-0000000c0001', 'cccccccc-0000-0000-0000-0000000c0001', 'Coach source', 'distance_10k', 10000, current_date, current_date + 27, 4, 'completed');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"cccccccc-0000-0000-0000-0000000c0001","role":"authenticated"}';

select is(
  (select active_plan_id from coach_roster_summary() where athlete_id = 'cccccccc-0000-0000-0000-0000000a0001'),
  'dddddddd-0000-0000-0000-0000000a0002'::uuid,
  'the roster shows the plan covering today, not the ended or the queued one'
);
select is(
  (select active_plan_id from coach_roster_summary() where athlete_id = 'cccccccc-0000-0000-0000-0000000a0002'),
  'dddddddd-0000-0000-0000-0000000b0001'::uuid,
  'between plans the roster shows the plan that ended most recently'
);
select is(
  (select active_plan_id from coach_roster_summary() where athlete_id = 'cccccccc-0000-0000-0000-0000000a0003'),
  'dddddddd-0000-0000-0000-0000000e0001'::uuid,
  'with only a queued plan the roster shows it'
);

select lives_ok(
  $$ select assign_plan_to_athlete('dddddddd-0000-0000-0000-0000000c0001',
                                   'cccccccc-0000-0000-0000-0000000a0001', current_date + 41) $$,
  'a coach can assign a plan onto dates after the athlete''s queued block'
);
select throws_ok(
  $$ select assign_plan_to_athlete('dddddddd-0000-0000-0000-0000000c0001',
                                   'cccccccc-0000-0000-0000-0000000a0001', current_date) $$,
  'P0001', null,
  'assigning over the athlete''s current block is refused'
);
reset role;

select is(
  (select count(*)::int from training_plans
   where user_id = 'cccccccc-0000-0000-0000-0000000a0001' and status = 'active'),
  4,
  'the athlete''s three blocks stay active beside the assigned one'
);

-- Shifting: two back-to-back blocks with a workout each.
insert into training_plans (id, user_id, name, goal_event, goal_distance_m, start_date, end_date, days_per_week, status)
values
  ('dddddddd-0000-0000-0000-0000000f0001', 'cccccccc-0000-0000-0000-0000000a0004', 'S first', 'distance_10k', 10000, '2031-01-06', '2031-01-19', 4, 'active'),
  ('dddddddd-0000-0000-0000-0000000f0002', 'cccccccc-0000-0000-0000-0000000a0004', 'S second', 'distance_half', 21097, '2031-01-20', '2031-02-02', 4, 'active'),
  ('dddddddd-0000-0000-0000-0000000f0003', 'cccccccc-0000-0000-0000-0000000a0004', 'S trim', 'distance_half', 21097, '2032-01-05', '2032-01-18', 4, 'completed');
insert into plan_weeks (id, plan_id, week_index, phase, target_volume_m) values
  ('eeeeeeee-0000-0000-0000-0000000f0001', 'dddddddd-0000-0000-0000-0000000f0001', 0, 'base', 8000),
  ('eeeeeeee-0000-0000-0000-0000000f0002', 'dddddddd-0000-0000-0000-0000000f0002', 0, 'base', 8000),
  ('eeeeeeee-0000-0000-0000-0000000f0003', 'dddddddd-0000-0000-0000-0000000f0003', 0, 'base', 18000);
insert into plan_workouts (week_id, scheduled_date, kind, target_distance_m) values
  ('eeeeeeee-0000-0000-0000-0000000f0001', '2031-01-08', 'easy', 8000),
  ('eeeeeeee-0000-0000-0000-0000000f0002', '2031-01-22', 'easy', 8000),
  ('eeeeeeee-0000-0000-0000-0000000f0003', '2032-01-05', 'easy', 8000),
  ('eeeeeeee-0000-0000-0000-0000000f0003', '2032-01-09', 'long', 10000);

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"cccccccc-0000-0000-0000-0000000a0004","role":"authenticated"}';
select throws_ok(
  $$ select shift_training_plan('dddddddd-0000-0000-0000-0000000f0001', 7) $$,
  '23P01', null,
  'shifting a block into the queued one alone is refused'
);
reset role;

select is(
  (select row(p.start_date, wo.scheduled_date)::text
   from training_plans p join plan_weeks w on w.plan_id = p.id join plan_workouts wo on wo.week_id = w.id
   where p.id = 'dddddddd-0000-0000-0000-0000000f0001'),
  row('2031-01-06'::date, '2031-01-08'::date)::text,
  'a refused shift moves neither the plan nor its workouts'
);

set local role authenticated;
select lives_ok(
  $$ select shift_training_plan('dddddddd-0000-0000-0000-0000000f0001', 7, true) $$,
  'shifting a block with the queued plans following it succeeds'
);
reset role;

select is(
  (select array_agg(row(start_date, end_date)::text order by start_date) from training_plans
   where user_id = 'cccccccc-0000-0000-0000-0000000a0004' and status = 'active'),
  array[row('2031-01-13'::date, '2031-01-26'::date)::text, row('2031-01-27'::date, '2031-02-09'::date)::text],
  'both blocks moved a week and still meet end to start'
);
select is(
  (select array_agg(wo.scheduled_date order by wo.scheduled_date)
   from plan_workouts wo join plan_weeks w on w.id = wo.week_id
   where w.plan_id in ('dddddddd-0000-0000-0000-0000000f0001', 'dddddddd-0000-0000-0000-0000000f0002')),
  array['2031-01-15'::date, '2031-01-29'::date],
  'their workouts moved with them'
);

update plan_workouts set manually_completed = true, completed_at = now()
where week_id = 'eeeeeeee-0000-0000-0000-0000000f0003' and scheduled_date = '2032-01-09';

set local role authenticated;
select throws_ok(
  $$ select trim_training_plan('dddddddd-0000-0000-0000-0000000f0003', '2032-01-07') $$,
  'TR001', 'trim_training_plan: completed workouts fall after 2032-01-07',
  'a trim that would delete a completed workout is refused'
);
reset role;

update plan_workouts set manually_completed = false, completed_at = null
where week_id = 'eeeeeeee-0000-0000-0000-0000000f0003' and scheduled_date = '2032-01-09';

set local role authenticated;
select lives_ok(
  $$ select trim_training_plan('dddddddd-0000-0000-0000-0000000f0003', '2032-01-07') $$,
  'the owner trims mid-week'
);
reset role;

select isnt(
  (select trimmed_at from training_plans where id = 'dddddddd-0000-0000-0000-0000000f0003'),
  null,
  'a trimmed plan is stamped so its old goal race is not shown on the new end date'
);

select is(
  (select target_volume_m::int from plan_weeks where id = 'eeeeeeee-0000-0000-0000-0000000f0003'),
  8000,
  'the cut week''s target volume is what its remaining workouts add up to'
);

select * from finish();
rollback;

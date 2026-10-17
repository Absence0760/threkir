-- Pins the plan-chaining branches the per-migration suites leave implicit
-- (decisions § 2008, § 2042, § 2050): only ACTIVE plans hold dates, so a
-- paused plan neither collides with nor blocks anything until it is resumed,
-- and a template can never be active; a backward shift onto the plan before
-- is refused whole; a trim with nothing to delete after the cut still ends
-- the plan and drops the empty weeks past it, while a "trim" to the plan's own
-- end or later is a no-op that stamps nothing; create_training_plan's
-- 'replace' completes every plan it overlaps and leaves a queued one alone;
-- assign_plan_to_athlete refuses an overlap as 23P01 naming the plans in the
-- way (20270830000008).

begin;
select plan(23);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('7e7e7e7e-0000-0000-0000-0000000a0001', 'authenticated', 'authenticated', 'edge-runner@pce.local', '', now(), now()),
  ('7e7e7e7e-0000-0000-0000-0000000a0002', 'authenticated', 'authenticated', 'edge-replacer@pce.local', '', now(), now()),
  ('7e7e7e7e-0000-0000-0000-0000000c0001', 'authenticated', 'authenticated', 'edge-coach@pce.local', '', now(), now()),
  ('7e7e7e7e-0000-0000-0000-0000000a0003', 'authenticated', 'authenticated', 'edge-athlete@pce.local', '', now(), now())
on conflict (id) do nothing;
insert into user_profiles (id, display_name) values
  ('7e7e7e7e-0000-0000-0000-0000000a0001', 'Edge Runner'),
  ('7e7e7e7e-0000-0000-0000-0000000a0002', 'Edge Replacer'),
  ('7e7e7e7e-0000-0000-0000-0000000c0001', 'Edge Coach'),
  ('7e7e7e7e-0000-0000-0000-0000000a0003', 'Edge Athlete')
on conflict (id) do nothing;

-- ─────────── Only active plans hold dates ───────────

insert into training_plans (id, user_id, name, goal_event, goal_distance_m, start_date, end_date, days_per_week, status)
values ('7e7e7e7e-1000-0000-0000-000000000001', '7e7e7e7e-0000-0000-0000-0000000a0001', 'Winter block', 'distance_half', 21097, '2035-01-01', '2035-01-28', 4, 'active');

select lives_ok(
  $$ insert into training_plans (id, user_id, name, goal_event, goal_distance_m, start_date, end_date, days_per_week, status)
     values ('7e7e7e7e-1000-0000-0000-000000000002', '7e7e7e7e-0000-0000-0000-0000000a0001', 'Paused block', 'distance_10k', 10000, '2035-01-10', '2035-02-10', 4, 'paused') $$,
  'a paused plan may overlap an active one'
);
select throws_ok(
  $$ update training_plans set status = 'active' where id = '7e7e7e7e-1000-0000-0000-000000000002' $$,
  '23P01', null,
  'resuming a paused plan over an active one is refused'
);
select throws_ok(
  $$ insert into training_plans (user_id, name, goal_event, goal_distance_m, start_date, end_date, days_per_week, status, is_template)
     values ('7e7e7e7e-0000-0000-0000-0000000a0001', 'Active template', 'distance_10k', 10000, '2035-01-05', '2035-01-20', 4, 'active', true) $$,
  '23514', null,
  'a template cannot be active, so no template ever holds dates against the constraint'
);

-- ─────────── Shifts ───────────

insert into training_plans (id, user_id, name, goal_event, goal_distance_m, start_date, end_date, days_per_week, status)
values ('7e7e7e7e-1000-0000-0000-000000000003', '7e7e7e7e-0000-0000-0000-0000000a0001', 'Spring block', 'distance_10k', 10000, '2035-03-01', '2035-03-14', 4, 'active');
insert into plan_weeks (id, plan_id, week_index, phase, target_volume_m)
values ('7e7e7e7e-2000-0000-0000-000000000003', '7e7e7e7e-1000-0000-0000-000000000003', 0, 'base', 8000);
insert into plan_workouts (week_id, scheduled_date, kind, target_distance_m)
values ('7e7e7e7e-2000-0000-0000-000000000003', '2035-03-03', 'easy', 8000);

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"7e7e7e7e-0000-0000-0000-0000000a0001","role":"authenticated"}';
select throws_ok(
  $$ select shift_training_plan('7e7e7e7e-1000-0000-0000-000000000003', -40) $$,
  '23P01', null,
  'shifting a plan back onto the plan before it is refused'
);
reset role;

select is(
  (select row(p.start_date, p.end_date, wo.scheduled_date)::text
   from training_plans p join plan_weeks w on w.plan_id = p.id join plan_workouts wo on wo.week_id = w.id
   where p.id = '7e7e7e7e-1000-0000-0000-000000000003'),
  row('2035-03-01'::date, '2035-03-14'::date, '2035-03-03'::date)::text,
  'the refused backward shift moved neither the plan nor its workout'
);

set local role authenticated;
select lives_ok(
  $$ select shift_training_plan('7e7e7e7e-1000-0000-0000-000000000003', -14) $$,
  'a backward shift into free dates succeeds'
);
select lives_ok(
  $$ select shift_training_plan('7e7e7e7e-1000-0000-0000-000000000002', 2) $$,
  'a paused plan shifts across an active one'
);
reset role;

select is(
  (select array_agg(row(name, start_date, end_date)::text order by name) from training_plans
   where id in ('7e7e7e7e-1000-0000-0000-000000000002', '7e7e7e7e-1000-0000-0000-000000000003')),
  array[row('Paused block', '2035-01-12'::date, '2035-02-12'::date)::text,
        row('Spring block', '2035-02-15'::date, '2035-02-28'::date)::text],
  'both shifts landed'
);

-- ─────────── Trims ───────────

-- Three weeks; only week 0 holds a workout, week 1 has a stale target volume.
insert into training_plans (id, user_id, name, goal_event, goal_distance_m, start_date, end_date, days_per_week, status)
values ('7e7e7e7e-1000-0000-0000-000000000004', '7e7e7e7e-0000-0000-0000-0000000a0001', 'Sparse block', 'distance_10k', 10000, '2035-05-06', '2035-05-26', 4, 'active');
insert into plan_weeks (id, plan_id, week_index, phase, target_volume_m) values
  ('7e7e7e7e-2000-0000-0000-000000000040', '7e7e7e7e-1000-0000-0000-000000000004', 0, 'base', 6000),
  ('7e7e7e7e-2000-0000-0000-000000000041', '7e7e7e7e-1000-0000-0000-000000000004', 1, 'build', 9000),
  ('7e7e7e7e-2000-0000-0000-000000000042', '7e7e7e7e-1000-0000-0000-000000000004', 2, 'taper', 4000);
insert into plan_workouts (week_id, scheduled_date, kind, target_distance_m)
values ('7e7e7e7e-2000-0000-0000-000000000040', '2035-05-07', 'easy', 6000);

-- A plan whose last workout sits on its end date, for the no-op trims.
insert into training_plans (id, user_id, name, goal_event, goal_distance_m, start_date, end_date, days_per_week, status)
values ('7e7e7e7e-1000-0000-0000-000000000005', '7e7e7e7e-0000-0000-0000-0000000a0001', 'Summer block', 'distance_10k', 10000, '2035-07-01', '2035-07-14', 4, 'active');
insert into plan_weeks (id, plan_id, week_index, phase, target_volume_m)
values ('7e7e7e7e-2000-0000-0000-000000000050', '7e7e7e7e-1000-0000-0000-000000000005', 0, 'base', 8000);
insert into plan_workouts (week_id, scheduled_date, kind, target_distance_m)
values ('7e7e7e7e-2000-0000-0000-000000000050', '2035-07-14', 'race', 10000);

set local role authenticated;
select lives_ok(
  $$ select trim_training_plan('7e7e7e7e-1000-0000-0000-000000000004', '2035-05-15') $$,
  'a plan with no workouts after the cut can still be ended early'
);
select lives_ok(
  $$ select trim_training_plan('7e7e7e7e-1000-0000-0000-000000000005', '2035-07-14') $$,
  'a trim to the plan''s own end date is accepted'
);
select lives_ok(
  $$ select trim_training_plan('7e7e7e7e-1000-0000-0000-000000000005', '2035-07-20') $$,
  'a trim past the plan''s end date is accepted'
);
reset role;

select is(
  (select row(end_date, trimmed_at is not null)::text from training_plans where id = '7e7e7e7e-1000-0000-0000-000000000004'),
  row('2035-05-15'::date, true)::text,
  'the sparse plan ends on the cut and is stamped as trimmed'
);
select is(
  (select array_agg(week_index::int order by week_index) from plan_weeks where plan_id = '7e7e7e7e-1000-0000-0000-000000000004'),
  array[0, 1],
  'the empty week wholly past the cut is dropped; the week the cut falls in is kept'
);
select is(
  (select array_agg(row(week_index, target_volume_m::int)::text order by week_index)
   from plan_weeks where plan_id = '7e7e7e7e-1000-0000-0000-000000000004'),
  array[row(0, 6000)::text, row(1, 0)::text],
  'the cut week''s volume restates to its (no) remaining workouts; the week before keeps its own'
);
select is(
  (select count(*)::int from plan_workouts wo join plan_weeks w on w.id = wo.week_id
   where w.plan_id = '7e7e7e7e-1000-0000-0000-000000000004'),
  1,
  'the workout before the cut is kept'
);
select is(
  (select row(p.end_date, p.trimmed_at is null, (select count(*) from plan_workouts where week_id = '7e7e7e7e-2000-0000-0000-000000000050'))::text
   from training_plans p where p.id = '7e7e7e7e-1000-0000-0000-000000000005'),
  row('2035-07-14'::date, true, 1)::text,
  'a trim to the end date or later changes nothing and stamps nothing, so the race on the end date stays the goal'
);

-- ─────────── create_training_plan ───────────

insert into training_plans (id, user_id, name, goal_event, goal_distance_m, start_date, end_date, days_per_week, status)
values
  ('7e7e7e7e-1000-0000-0000-0000000000a1', '7e7e7e7e-0000-0000-0000-0000000a0002', 'Block A', 'distance_10k', 10000, '2036-01-01', '2036-01-14', 4, 'active'),
  ('7e7e7e7e-1000-0000-0000-0000000000a2', '7e7e7e7e-0000-0000-0000-0000000a0002', 'Block B', 'distance_10k', 10000, '2036-01-15', '2036-01-28', 4, 'active'),
  ('7e7e7e7e-1000-0000-0000-0000000000a3', '7e7e7e7e-0000-0000-0000-0000000a0002', 'Block C', 'distance_10k', 10000, '2036-02-15', '2036-02-28', 4, 'active'),
  ('7e7e7e7e-1000-0000-0000-0000000000a4', '7e7e7e7e-0000-0000-0000-0000000a0002', 'Block D', 'distance_10k', 10000, '2036-04-01', '2036-04-30', 4, 'paused');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"7e7e7e7e-0000-0000-0000-0000000a0002","role":"authenticated"}';
select lives_ok(
  $$ select create_training_plan(
       '{"name":"Spans A and B","goal_event":"distance_half","goal_distance_m":21097,"start_date":"2036-01-10","end_date":"2036-02-07","days_per_week":4}'::jsonb,
       '[{"week_index":0,"phase":"base","target_volume_m":8000,"workouts":[{"kind":"easy","scheduled_date":"2036-01-11","target_distance_m":8000}]}]'::jsonb,
       'replace') $$,
  'a create with replace over two active plans succeeds'
);
select lives_ok(
  $$ select create_training_plan(
       '{"name":"Over the paused one","goal_event":"distance_10k","goal_distance_m":10000,"start_date":"2036-04-05","end_date":"2036-04-18","days_per_week":4}'::jsonb,
       '[{"week_index":0,"phase":"base","target_volume_m":8000,"workouts":[{"kind":"easy","scheduled_date":"2036-04-06","target_distance_m":8000}]}]'::jsonb) $$,
  'a paused plan over the new dates does not make a refusing create refuse'
);
reset role;

select is(
  (select array_agg(row(name, status)::text order by start_date) from training_plans
   where user_id = '7e7e7e7e-0000-0000-0000-0000000a0002'),
  array[row('Block A', 'abandoned')::text, row('Spans A and B', 'active')::text, row('Block B', 'abandoned')::text,
        row('Block C', 'active')::text, row('Block D', 'paused')::text, row('Over the paused one', 'active')::text],
  'replace abandoned both plans it overlapped and left the queued and the paused plan as they were'
);

-- ─────────── assign_plan_to_athlete ───────────

insert into coach_athletes (coach_id, athlete_id, status, invite_token, accepted_at)
values ('7e7e7e7e-0000-0000-0000-0000000c0001', '7e7e7e7e-0000-0000-0000-0000000a0003', 'active', 'pce-tok-edge', now());
insert into training_plans (id, user_id, name, goal_event, goal_distance_m, start_date, end_date, days_per_week, status)
values
  ('7e7e7e7e-1000-0000-0000-0000000000c1', '7e7e7e7e-0000-0000-0000-0000000c0001', 'Coach source', 'distance_10k', 10000, '2030-01-01', '2030-01-14', 4, 'completed'),
  ('7e7e7e7e-1000-0000-0000-0000000000b1', '7e7e7e7e-0000-0000-0000-0000000a0003', 'Athlete paused', 'distance_10k', 10000, '2037-01-01', '2037-01-31', 4, 'paused');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"7e7e7e7e-0000-0000-0000-0000000c0001","role":"authenticated"}';
select lives_ok(
  $$ select assign_plan_to_athlete('7e7e7e7e-1000-0000-0000-0000000000c1', '7e7e7e7e-0000-0000-0000-0000000a0003', '2037-01-05') $$,
  'an athlete''s paused plan over the dates does not block an assignment'
);
reset role;

select is(
  (select array_agg(row(name, status, start_date, end_date)::text order by status desc) from training_plans
   where user_id = '7e7e7e7e-0000-0000-0000-0000000a0003'),
  array[row('Athlete paused', 'paused', '2037-01-01'::date, '2037-01-31'::date)::text,
        row('Coach source', 'active', '2037-01-05'::date, '2037-01-18'::date)::text],
  'the assignment is active beside the untouched paused plan'
);

insert into training_plans (user_id, name, goal_event, goal_distance_m, start_date, end_date, days_per_week, status)
values ('7e7e7e7e-0000-0000-0000-0000000a0003', 'Athlete own', 'distance_10k', 10000, '2037-01-19', '2037-02-10', 4, 'active');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"7e7e7e7e-0000-0000-0000-0000000c0001","role":"authenticated"}';
select throws_ok(
  $$ select assign_plan_to_athlete('7e7e7e7e-1000-0000-0000-0000000000c1', '7e7e7e7e-0000-0000-0000-0000000a0003', '2037-01-10') $$,
  '23P01',
  'assign_plan_to_athlete: these dates overlap the athlete''s active plan "Coach source" (2037-01-05 to 2037-01-18), "Athlete own" (2037-01-19 to 2037-02-10)',
  'an assignment over the athlete''s active plans is an exclusion violation naming each plan in the way'
);
reset role;

select is(
  (select count(*)::int from training_plans where user_id = '7e7e7e7e-0000-0000-0000-0000000a0003'),
  3,
  'the refused assignment wrote no plan'
);

select * from finish();
rollback;

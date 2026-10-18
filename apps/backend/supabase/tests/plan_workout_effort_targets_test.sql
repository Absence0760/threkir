-- Pins 20270912000001 (issue #1186, decisions § 2092): the RPE and heart-rate
-- targets on plan_workouts, the Art 9 consent rule on the bpm range, what the
-- withdrawal clears, and which copy paths carry which range.
begin;
select plan(21);

-- The server gate (20270915000004) open, as seed.sql opens it locally.
insert into private.feature_flags (name, enabled) values ('hr_prescription', true)
  on conflict (name) do update set enabled = true;

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at) values
  ('2085aaaa-0000-0000-0000-0000000000c1', 'authenticated', 'authenticated', 'coach@pwet.local', '', now(), now()),
  ('2085aaaa-0000-0000-0000-0000000000a1', 'authenticated', 'authenticated', 'consented@pwet.local', '', now(), now()),
  ('2085aaaa-0000-0000-0000-0000000000b1', 'authenticated', 'authenticated', 'unconsented@pwet.local', '', now(), now())
on conflict (id) do nothing;
insert into user_profiles (id, display_name, health_data_consent_at) values
  ('2085aaaa-0000-0000-0000-0000000000c1', 'Coach', now()),
  ('2085aaaa-0000-0000-0000-0000000000a1', 'Consented', now()),
  ('2085aaaa-0000-0000-0000-0000000000b1', 'Unconsented', null)
on conflict (id) do nothing;
insert into user_settings (user_id, prefs) values
  ('2085aaaa-0000-0000-0000-0000000000a1', '{"hr_medication_affected": true, "preferred_unit": "km"}');
insert into coach_athletes (coach_id, athlete_id, status, invite_token, accepted_at) values
  ('2085aaaa-0000-0000-0000-0000000000c1', '2085aaaa-0000-0000-0000-0000000000a1', 'active', 'pwet-a', now()),
  ('2085aaaa-0000-0000-0000-0000000000c1', '2085aaaa-0000-0000-0000-0000000000b1', 'active', 'pwet-b', now());

insert into training_plans (id, user_id, name, goal_event, goal_distance_m, start_date, end_date, days_per_week, status, is_template) values
  ('2085bbbb-0000-0000-0000-0000000000a1', '2085aaaa-0000-0000-0000-0000000000a1', 'A', 'distance_10k', 10000, date '2031-03-03', date '2031-03-09', 4, 'active', false),
  ('2085bbbb-0000-0000-0000-0000000000b1', '2085aaaa-0000-0000-0000-0000000000b1', 'B', 'distance_10k', 10000, date '2031-03-03', date '2031-03-09', 4, 'active', false),
  ('2085bbbb-0000-0000-0000-0000000000c1', '2085aaaa-0000-0000-0000-0000000000c1', 'T', 'distance_10k', 10000, date '2031-03-03', date '2031-03-09', 4, 'completed', true),
  ('2085bbbb-0000-0000-0000-0000000000c2', '2085aaaa-0000-0000-0000-0000000000c1', 'S', 'distance_10k', 10000, date '2031-03-03', date '2031-03-09', 4, 'completed', false);
insert into plan_weeks (id, plan_id, week_index, phase, target_volume_m) values
  ('2085cccc-0000-0000-0000-0000000000a1', '2085bbbb-0000-0000-0000-0000000000a1', 0, 'build', 20000),
  ('2085cccc-0000-0000-0000-0000000000b1', '2085bbbb-0000-0000-0000-0000000000b1', 0, 'build', 20000),
  ('2085cccc-0000-0000-0000-0000000000c1', '2085bbbb-0000-0000-0000-0000000000c1', 0, 'build', 20000),
  ('2085cccc-0000-0000-0000-0000000000c2', '2085bbbb-0000-0000-0000-0000000000c2', 0, 'build', 20000);
insert into plan_workouts (id, week_id, scheduled_date, kind, target_distance_m, target_rpe_min, target_rpe_max) values
  ('2085dddd-0000-0000-0000-0000000000a1', '2085cccc-0000-0000-0000-0000000000a1', date '2031-03-04', 'easy', 8000, 3, 4),
  ('2085dddd-0000-0000-0000-0000000000b1', '2085cccc-0000-0000-0000-0000000000b1', date '2031-03-04', 'easy', 8000, 3, 4),
  ('2085dddd-0000-0000-0000-0000000000c1', '2085cccc-0000-0000-0000-0000000000c1', date '2031-03-04', 'easy', 8000, 3, 4);
-- The coach's own (consented) source plan carries a bpm cap of the coach's.
insert into plan_workouts (id, week_id, scheduled_date, kind, target_distance_m, target_rpe_min, target_rpe_max, target_hr_max_bpm) values
  ('2085dddd-0000-0000-0000-0000000000c2', '2085cccc-0000-0000-0000-0000000000c2', date '2031-03-04', 'easy', 8000, 3, 4, 130);

-- ─────────── ranges ───────────
select throws_ok(
  $$ update plan_workouts set target_rpe_max = 11 where id = '2085dddd-0000-0000-0000-0000000000a1' $$,
  '23514', null, 'an RPE above 10 is refused');
select throws_ok(
  $$ update plan_workouts set target_rpe_min = 5, target_rpe_max = 4 where id = '2085dddd-0000-0000-0000-0000000000a1' $$,
  '23514', null, 'an RPE range whose low end is above its high end is refused');
select throws_ok(
  $$ update plan_workouts set target_hr_max_bpm = 250 where id = '2085dddd-0000-0000-0000-0000000000a1' $$,
  '23514', null, 'a bpm cap above 230 is refused');
select throws_ok(
  $$ update plan_workouts set kind = 'rest', target_distance_m = null where id = '2085dddd-0000-0000-0000-0000000000a1' $$,
  '23514', null, 'a rest day cannot carry an effort target');

-- ─────────── the bpm range rests on the plan owner's consent ───────────
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"2085aaaa-0000-0000-0000-0000000000a1","role":"authenticated"}';
select lives_ok(
  $$ update plan_workouts set target_hr_max_bpm = 125 where id = '2085dddd-0000-0000-0000-0000000000a1' $$,
  'a consented owner sets a bpm cap');
set local "request.jwt.claims" = '{"sub":"2085aaaa-0000-0000-0000-0000000000b1","role":"authenticated"}';
select throws_ok(
  $$ update plan_workouts set target_hr_max_bpm = 125 where id = '2085dddd-0000-0000-0000-0000000000b1' $$,
  '42501', null, 'an owner without health-data consent cannot set a bpm cap');
set local "request.jwt.claims" = '{"sub":"2085aaaa-0000-0000-0000-0000000000c1","role":"authenticated"}';
select lives_ok(
  $$ update plan_workouts set target_hr_min_bpm = 110, target_hr_max_bpm = 125 where id = '2085dddd-0000-0000-0000-0000000000a1' $$,
  'an active coach sets a bpm range on a consented athlete''s workout');
select throws_ok(
  $$ update plan_workouts set target_hr_max_bpm = 125 where id = '2085dddd-0000-0000-0000-0000000000b1' $$,
  '42501', null, 'an active coach cannot set a bpm cap for an athlete without consent: the athlete''s consent is what it rests on');
select throws_ok(
  $$ update plan_workouts set target_hr_max_bpm = 125 where id = '2085dddd-0000-0000-0000-0000000000c1' $$,
  '23514', null, 'a template plan cannot carry a bpm target');
reset role;

-- ─────────── copy paths ───────────
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"2085aaaa-0000-0000-0000-0000000000a1","role":"authenticated"}';
select lives_ok(
  $$ select duplicate_plan_week('2085bbbb-0000-0000-0000-0000000000a1', 0) $$,
  'the owner duplicates the week');
reset role;
select is(
  (select row(target_rpe_min, target_rpe_max, target_hr_min_bpm, target_hr_max_bpm)::text
     from plan_workouts where scheduled_date = date '2031-03-11'
      and week_id in (select id from plan_weeks where plan_id = '2085bbbb-0000-0000-0000-0000000000a1')),
  '(3,4,110,125)',
  'duplicate_plan_week carries both ranges within the owner''s own plan');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"2085aaaa-0000-0000-0000-0000000000c1","role":"authenticated"}';
create temp table _assigned on commit drop as
  select assign_plan_to_athlete('2085bbbb-0000-0000-0000-0000000000c2', '2085aaaa-0000-0000-0000-0000000000a1', date '2031-04-07') as plan_id;
reset role;
select is(
  (select row(pw.target_rpe_min, pw.target_rpe_max, pw.target_hr_min_bpm, pw.target_hr_max_bpm)::text
     from plan_workouts pw join plan_weeks wk on wk.id = pw.week_id
    where wk.plan_id = (select plan_id from _assigned)),
  '(3,4,,)',
  'assign_plan_to_athlete carries the RPE range to the athlete and never the source''s bpm cap');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"2085aaaa-0000-0000-0000-0000000000c1","role":"authenticated"}';
create temp table _cloned on commit drop as
  select clone_plan_template('2085bbbb-0000-0000-0000-0000000000c1', date '2031-05-05', 'replace') as plan_id;
reset role;
select is(
  (select row(pw.target_rpe_min, pw.target_rpe_max)::text
     from plan_workouts pw join plan_weeks wk on wk.id = pw.week_id
    where wk.plan_id = (select plan_id from _cloned)),
  '(3,4)',
  'clone_plan_template carries the RPE range');

-- ─────────── the medication flag rests on the same consent ───────────
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"2085aaaa-0000-0000-0000-0000000000b1","role":"authenticated"}';
select throws_ok(
  $$ insert into user_settings (user_id, prefs) values ('2085aaaa-0000-0000-0000-0000000000b1', '{"hr_medication_affected": true}') $$,
  '42501', null, 'a runner without health-data consent cannot turn the medication flag on');
select lives_ok(
  $$ insert into user_settings (user_id, prefs) values ('2085aaaa-0000-0000-0000-0000000000b1', '{"hr_medication_affected": false, "preferred_unit": "mi"}') $$,
  'turning it off, or never on, needs no consent');
select lives_ok(
  $$ update user_settings set prefs = '{"hr_medication_affected": false, "preferred_unit": "km"}' where user_id = '2085aaaa-0000-0000-0000-0000000000b1' $$,
  'an unrelated settings write without consent still lands');
reset role;
select set_config('app.consent_write', 'on', true);
update user_profiles set health_data_consent_at = now() where id = '2085aaaa-0000-0000-0000-0000000000b1';
select set_config('app.consent_write', '', true);
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"2085aaaa-0000-0000-0000-0000000000b1","role":"authenticated"}';
select lives_ok(
  $$ update user_settings set prefs = prefs || '{"hr_medication_affected": true}' where user_id = '2085aaaa-0000-0000-0000-0000000000b1' $$,
  'once consent is on record the runner turns it on');
reset role;

-- ─────────── withdrawal ───────────
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"2085aaaa-0000-0000-0000-0000000000a1","role":"authenticated"}';
select lives_ok($$ select withdraw_health_data_consent() $$, 'the consented athlete withdraws');
reset role;
select is(
  (select count(*)::int from plan_workouts pw join plan_weeks wk on wk.id = pw.week_id
     join training_plans tp on tp.id = wk.plan_id
    where tp.user_id = '2085aaaa-0000-0000-0000-0000000000a1'
      and (pw.target_hr_min_bpm is not null or pw.target_hr_max_bpm is not null)),
  0,
  'withdrawal nulls every bpm target on the runner''s plans');
select is(
  (select count(*)::int from plan_workouts pw join plan_weeks wk on wk.id = pw.week_id
     join training_plans tp on tp.id = wk.plan_id
    where tp.user_id = '2085aaaa-0000-0000-0000-0000000000a1' and pw.target_rpe_max = 4),
  3,
  'withdrawal leaves the RPE ranges, which are not health data');
select is(
  (select prefs from user_settings where user_id = '2085aaaa-0000-0000-0000-0000000000a1'),
  '{"preferred_unit": "km"}'::jsonb,
  'withdrawal drops the hr_medication_affected key and nothing else');

select * from finish();
rollback;

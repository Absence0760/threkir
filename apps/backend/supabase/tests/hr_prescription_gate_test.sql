-- Pins 20270915000004 (decisions § 2095): with the hr_prescription gate shut
-- the database refuses a bpm target and turning the medication pref on, and
-- the roster computes no HR drift; with it open the consent rules of § 2092
-- apply. The medication pref takes only a JSON boolean (or null) either way.
begin;
select plan(12);

set local timezone = 'UTC';

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at) values
  ('2095aaaa-0000-0000-0000-0000000000c1', 'authenticated', 'authenticated', 'coach@hrgate.local', '', now(), now()),
  ('2095aaaa-0000-0000-0000-0000000000a1', 'authenticated', 'authenticated', 'athlete@hrgate.local', '', now(), now())
on conflict (id) do nothing;
insert into user_profiles (id, display_name, health_data_consent_at) values
  ('2095aaaa-0000-0000-0000-0000000000c1', 'Gate Coach', now()),
  ('2095aaaa-0000-0000-0000-0000000000a1', 'Gate Athlete', now())
on conflict (id) do nothing;
insert into user_settings (user_id, prefs) values ('2095aaaa-0000-0000-0000-0000000000a1', '{"preferred_unit": "km"}')
on conflict (user_id) do nothing;
insert into coach_athletes (coach_id, athlete_id, status, invite_token, accepted_at) values
  ('2095aaaa-0000-0000-0000-0000000000c1', '2095aaaa-0000-0000-0000-0000000000a1', 'active', 'hrgate-a', now());
insert into training_plans (id, user_id, name, goal_event, goal_distance_m, start_date, end_date, days_per_week, status) values
  ('2095bbbb-0000-0000-0000-0000000000a1', '2095aaaa-0000-0000-0000-0000000000a1', 'G', 'distance_10k', 10000,
   current_date - 56, current_date + 7, 4, 'active');
insert into plan_weeks (id, plan_id, week_index, phase, target_volume_m) values
  ('2095cccc-0000-0000-0000-0000000000a1', '2095bbbb-0000-0000-0000-0000000000a1', 0, 'build', 30000);
insert into plan_workouts (id, week_id, scheduled_date, kind, target_distance_m) values
  ('2095dddd-0000-0000-0000-0000000000a1', '2095cccc-0000-0000-0000-0000000000a1', current_date + 2, 'easy', 8000);

-- Five easy runs at 6:00/km, 140 bpm then 150: a 7.14 % drift with the gate open.
insert into runs (id, user_id, started_at, duration_s, distance_m, source, is_dnf, metadata)
select ('2095eeee-0000-0000-0000-0000000000' || lpad(n::text, 2, '0'))::uuid, '2095aaaa-0000-0000-0000-0000000000a1',
       now() - (days || ' days')::interval, 3600, 10000, 'app', false,
       jsonb_build_object('activity_type', 'run', 'avg_bpm', bpm)
from (values (1, 40, 140), (2, 33, 140), (3, 26, 140), (4, 10, 150), (5, 3, 150)) v(n, days, bpm);
insert into plan_workouts (week_id, scheduled_date, kind, target_distance_m, completed_run_id)
select '2095cccc-0000-0000-0000-0000000000a1', (now() - (days || ' days')::interval)::date, 'easy', 10000,
       ('2095eeee-0000-0000-0000-0000000000' || lpad(n::text, 2, '0'))::uuid
from (values (1, 40), (2, 33), (3, 26), (4, 10), (5, 3)) v(n, days);

-- Gate shut.
insert into private.feature_flags (name, enabled) values ('hr_prescription', false)
  on conflict (name) do update set enabled = false;

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"2095aaaa-0000-0000-0000-0000000000a1","role":"authenticated"}';
select throws_ok(
  $$ update plan_workouts set target_hr_max_bpm = 125 where id = '2095dddd-0000-0000-0000-0000000000a1' $$,
  '42501', 'plan_workouts: heart-rate targets are not enabled',
  'gate shut: a consented owner cannot write a bpm target');
select lives_ok(
  $$ update plan_workouts set target_rpe_min = 3, target_rpe_max = 4 where id = '2095dddd-0000-0000-0000-0000000000a1' $$,
  'gate shut: an RPE target is not Art 9 and still saves');
select throws_ok(
  $$ update user_settings set prefs = prefs || '{"hr_medication_affected": true}' where user_id = '2095aaaa-0000-0000-0000-0000000000a1' $$,
  '42501', 'user_settings: hr_medication_affected is not enabled',
  'gate shut: the medication pref cannot be turned on');
select lives_ok(
  $$ update user_settings set prefs = prefs || '{"hr_medication_affected": false}' where user_id = '2095aaaa-0000-0000-0000-0000000000a1' $$,
  'gate shut: the medication pref can still be turned off');
select throws_ok(
  $$ update user_settings set prefs = prefs || '{"hr_medication_affected": "true"}' where user_id = '2095aaaa-0000-0000-0000-0000000000a1' $$,
  '22023', 'user_settings: hr_medication_affected must be true or false',
  'a string "true" is refused');
set local "request.jwt.claims" = '{"sub":"2095aaaa-0000-0000-0000-0000000000c1","role":"authenticated"}';
select is(
  (select easy_hr_drift_pct from coach_roster_summary() where athlete_id = '2095aaaa-0000-0000-0000-0000000000a1'),
  null,
  'gate shut: the roster computes no HR drift');
reset role;

-- Gate open.
update private.feature_flags set enabled = true where name = 'hr_prescription';

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"2095aaaa-0000-0000-0000-0000000000a1","role":"authenticated"}';
select lives_ok(
  $$ update plan_workouts set target_hr_max_bpm = 125 where id = '2095dddd-0000-0000-0000-0000000000a1' $$,
  'gate open: a consented owner writes a bpm target');
select lives_ok(
  $$ update user_settings set prefs = prefs || '{"hr_medication_affected": true}' where user_id = '2095aaaa-0000-0000-0000-0000000000a1' $$,
  'gate open: a consented user turns the medication pref on');
select throws_ok(
  $$ update user_settings set prefs = prefs || '{"hr_medication_affected": 1}' where user_id = '2095aaaa-0000-0000-0000-0000000000a1' $$,
  '22023', 'user_settings: hr_medication_affected must be true or false',
  'gate open: a number is still refused');
select throws_ok(
  $$ update user_settings set prefs = prefs || '{"hr_medication_affected": "yes"}' where user_id = '2095aaaa-0000-0000-0000-0000000000a1' $$,
  '22023', 'user_settings: hr_medication_affected must be true or false',
  'gate open: any other string is refused');
set local "request.jwt.claims" = '{"sub":"2095aaaa-0000-0000-0000-0000000000c1","role":"authenticated"}';
select is(
  (select round(easy_hr_drift_pct::numeric, 2) from coach_roster_summary() where athlete_id = '2095aaaa-0000-0000-0000-0000000000a1'),
  7.14,
  'gate open: the roster computes the drift');
reset role;

-- Turning off and clearing are never gated.
update private.feature_flags set enabled = false where name = 'hr_prescription';
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"2095aaaa-0000-0000-0000-0000000000a1","role":"authenticated"}';
select lives_ok(
  $$ update plan_workouts set target_hr_max_bpm = null where id = '2095dddd-0000-0000-0000-0000000000a1' $$,
  'gate shut: a bpm target can still be cleared');
reset role;

select * from finish();
rollback;

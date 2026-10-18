-- Pins 20270912000002 (issue #1186, decisions § 2092): the roster's
-- recent_workouts (the input the client derives misses from), athlete_today,
-- and the easy-run HR drift, which is computed only for an athlete with
-- health-data consent and only from planned easy / recovery runs. Since
-- 20270915000003 (decisions § 2094) the drift is heart rate at the same pace,
-- and a malformed avg_bpm on one run cannot fail the roster.
begin;
select plan(12);

set local timezone = 'UTC';
insert into private.feature_flags (name, enabled) values ('hr_prescription', true)
  on conflict (name) do update set enabled = true;

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at) values
  ('2085eeee-0000-0000-0000-0000000000c1', 'authenticated', 'authenticated', 'coach@crhd.local', '', now(), now()),
  ('2085eeee-0000-0000-0000-0000000000a1', 'authenticated', 'authenticated', 'consented@crhd.local', '', now(), now()),
  ('2085eeee-0000-0000-0000-0000000000b1', 'authenticated', 'authenticated', 'unconsented@crhd.local', '', now(), now())
on conflict (id) do nothing;
insert into user_profiles (id, display_name, health_data_consent_at) values
  ('2085eeee-0000-0000-0000-0000000000a1', 'Consented', now()),
  ('2085eeee-0000-0000-0000-0000000000b1', 'Unconsented', null)
on conflict (id) do nothing;
insert into coach_athletes (coach_id, athlete_id, status, invite_token, accepted_at) values
  ('2085eeee-0000-0000-0000-0000000000c1', '2085eeee-0000-0000-0000-0000000000a1', 'active', 'crhd-a', now()),
  ('2085eeee-0000-0000-0000-0000000000c1', '2085eeee-0000-0000-0000-0000000000b1', 'active', 'crhd-b', now());

-- One active plan each, covering the last 56 days and the next week.
insert into training_plans (id, user_id, name, goal_event, goal_distance_m, start_date, end_date, days_per_week, status)
select ('2085ffff-0000-0000-0000-0000000000' || t || '1')::uuid, u, 'P ' || t, 'distance_10k', 10000,
       current_date - 56, current_date + 7, 4, 'active'
from (values ('a', '2085eeee-0000-0000-0000-0000000000a1'::uuid), ('b', '2085eeee-0000-0000-0000-0000000000b1'::uuid)) v(t, u);
insert into plan_weeks (id, plan_id, week_index, phase, target_volume_m)
select ('2085ffff-1111-0000-0000-0000000000' || t || '1')::uuid, ('2085ffff-0000-0000-0000-0000000000' || t || '1')::uuid, 0, 'build', 30000
from (values ('a'), ('b')) v(t);

-- Easy runs for both athletes: the same 10 km in 60 min (6:00/km), at 140 bpm
-- over the older window and 150 bpm over the last 14 days -- more beats at the
-- same pace, so the drift is 150/140 - 1 = 7.14 %.
create temp table _runs (n int, days int, bpm int) on commit drop;
insert into _runs values (1, 40, 140), (2, 33, 140), (3, 26, 140), (8, 12, 150), (4, 10, 150), (5, 3, 150);
insert into runs (id, user_id, started_at, duration_s, distance_m, source, is_dnf, metadata)
select ('2085ffff-2222-0000-0000-00000000' || t || lpad(n::text, 2, '0'))::uuid, u,
       now() - (days || ' days')::interval, 3600, 10000, 'app', false,
       jsonb_build_object('activity_type', 'run', 'avg_bpm', bpm)
from _runs, (values ('a1', '2085eeee-0000-0000-0000-0000000000a1'::uuid), ('b1', '2085eeee-0000-0000-0000-0000000000b1'::uuid)) v(t, u);
-- Each run is a completed easy workout; plus, for the miss streak, two
-- unrun workouts on the last two days, a skipped one and a rest day.
insert into plan_workouts (week_id, scheduled_date, kind, target_distance_m, completed_run_id)
select ('2085ffff-1111-0000-0000-0000000000' || substr(t, 1, 1) || '1')::uuid,
       (now() - (days || ' days')::interval)::date, 'easy', 10000,
       ('2085ffff-2222-0000-0000-00000000' || t || lpad(n::text, 2, '0'))::uuid
from _runs, (values ('a1'), ('b1')) v(t);
insert into plan_workouts (week_id, scheduled_date, kind, target_distance_m, skipped_at)
values
  ('2085ffff-1111-0000-0000-0000000000a1', current_date - 1, 'tempo', 8000, null),
  ('2085ffff-1111-0000-0000-0000000000a1', current_date - 2, 'easy', 6000, null),
  ('2085ffff-1111-0000-0000-0000000000a1', current_date - 4, 'easy', 6000, now()),
  ('2085ffff-1111-0000-0000-0000000000a1', current_date - 5, 'rest', null, null),
  ('2085ffff-1111-0000-0000-0000000000a1', current_date + 1, 'easy', 6000, null);

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"2085eeee-0000-0000-0000-0000000000c1","role":"authenticated"}';

select is(
  (select athlete_today from coach_roster_summary() where athlete_id = '2085eeee-0000-0000-0000-0000000000a1'),
  current_date,
  'athlete_today is the athlete''s local date (no zone set: the server date)');
select is(
  (select recent_workouts -> 0 from coach_roster_summary() where athlete_id = '2085eeee-0000-0000-0000-0000000000a1'),
  jsonb_build_object('scheduled_date', current_date - 1, 'kind', 'tempo', 'completed', false, 'skipped', false),
  'recent_workouts is newest first, in the shape isWorkoutMissed takes');
select is(
  (select jsonb_array_length(recent_workouts) from coach_roster_summary() where athlete_id = '2085eeee-0000-0000-0000-0000000000a1'),
  7,
  'recent_workouts holds the last 28 local days: four run workouts, the two unrun, the skipped one; no rest day, nothing from today on, nothing older');
select ok(
  (select bool_or((w ->> 'skipped')::boolean) from coach_roster_summary(), jsonb_array_elements(recent_workouts) w
    where athlete_id = '2085eeee-0000-0000-0000-0000000000a1'),
  'a skipped workout arrives marked skipped');
select is(
  (select round(easy_hr_drift_pct::numeric, 2) from coach_roster_summary() where athlete_id = '2085eeee-0000-0000-0000-0000000000a1'),
  7.14,
  'easy-run HR drift is mean HR at the same pace, recent 14 days against the 42 before');
select is(
  (select easy_hr_drift_pct from coach_roster_summary() where athlete_id = '2085eeee-0000-0000-0000-0000000000b1'),
  null,
  'no HR drift is computed for an athlete without health-data consent');
reset role;

-- A recent easy run 60 s/km faster at a higher HR is a different effort, not
-- drift; and one with a string avg_bpm is skipped rather than failing the read.
set local "request.jwt.claims" = '{}';
insert into runs (id, user_id, started_at, duration_s, distance_m, source, is_dnf, metadata) values
  ('2085ffff-2222-0000-0000-00000000a106', '2085eeee-0000-0000-0000-0000000000a1', now() - interval '6 days', 3000, 10000, 'app', false,
   jsonb_build_object('activity_type', 'run', 'avg_bpm', 175)),
  ('2085ffff-2222-0000-0000-00000000a107', '2085eeee-0000-0000-0000-0000000000a1', now() - interval '7 days', 3600, 10000, 'app', false,
   jsonb_build_object('activity_type', 'run', 'avg_bpm', 'n/a', 'hr_coverage', 'high'));
insert into plan_workouts (week_id, scheduled_date, kind, target_distance_m, completed_run_id) values
  ('2085ffff-1111-0000-0000-0000000000a1', current_date - 6, 'easy', 10000, '2085ffff-2222-0000-0000-00000000a106'),
  ('2085ffff-1111-0000-0000-0000000000a1', current_date - 7, 'easy', 10000, '2085ffff-2222-0000-0000-00000000a107');
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"2085eeee-0000-0000-0000-0000000000c1","role":"authenticated"}';
select lives_ok(
  $$ select * from coach_roster_summary() $$,
  'a run with a string avg_bpm and hr_coverage does not fail the roster');
select is(
  (select round(easy_hr_drift_pct::numeric, 2) from coach_roster_summary() where athlete_id = '2085eeee-0000-0000-0000-0000000000a1'),
  7.14,
  'a run outside 15 s/km of the median easy pace does not move the drift');
reset role;
set local "request.jwt.claims" = '{}';
delete from plan_workouts where completed_run_id in ('2085ffff-2222-0000-0000-00000000a106', '2085ffff-2222-0000-0000-00000000a107');
delete from runs where id in ('2085ffff-2222-0000-0000-00000000a106', '2085ffff-2222-0000-0000-00000000a107');

-- Two recent runs are too few: one hot day among them could drive the chip.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"2085eeee-0000-0000-0000-0000000000a1","role":"authenticated"}';
delete from runs where id = '2085ffff-2222-0000-0000-00000000a105';
set local "request.jwt.claims" = '{"sub":"2085eeee-0000-0000-0000-0000000000c1","role":"authenticated"}';
select is(
  (select easy_hr_drift_pct from coach_roster_summary() where athlete_id = '2085eeee-0000-0000-0000-0000000000a1'),
  null,
  'fewer than three recent easy runs gives no drift');
reset role;

-- Two athletes whose windows ran at different paces: 6:15/km then 5:45/km
-- (both inside 15 s/km of their 6:00 median), and 6:00/km then 7:00/km.
-- Faster or slower recent runs are not drift, so neither gets a figure.
set local "request.jwt.claims" = '{}';
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at) values
  ('2085eeee-0000-0000-0000-0000000000d1', 'authenticated', 'authenticated', 'split@crhd.local', '', now(), now()),
  ('2085eeee-0000-0000-0000-0000000000d2', 'authenticated', 'authenticated', 'shift@crhd.local', '', now(), now())
on conflict (id) do nothing;
insert into user_profiles (id, display_name, health_data_consent_at) values
  ('2085eeee-0000-0000-0000-0000000000d1', 'Split', now()),
  ('2085eeee-0000-0000-0000-0000000000d2', 'Shift', now())
on conflict (id) do nothing;
insert into coach_athletes (coach_id, athlete_id, status, invite_token, accepted_at) values
  ('2085eeee-0000-0000-0000-0000000000c1', '2085eeee-0000-0000-0000-0000000000d1', 'active', 'crhd-d1', now()),
  ('2085eeee-0000-0000-0000-0000000000c1', '2085eeee-0000-0000-0000-0000000000d2', 'active', 'crhd-d2', now());
insert into training_plans (id, user_id, name, goal_event, goal_distance_m, start_date, end_date, days_per_week, status)
select ('2085ffff-0000-0000-0000-0000000000' || t || '1')::uuid, u, 'P ' || t, 'distance_10k', 10000,
       current_date - 56, current_date + 7, 4, 'active'
from (values ('d', '2085eeee-0000-0000-0000-0000000000d1'::uuid), ('e', '2085eeee-0000-0000-0000-0000000000d2'::uuid)) v(t, u);
insert into plan_weeks (id, plan_id, week_index, phase, target_volume_m)
select ('2085ffff-1111-0000-0000-0000000000' || t || '1')::uuid, ('2085ffff-0000-0000-0000-0000000000' || t || '1')::uuid, 0, 'build', 30000
from (values ('d'), ('e')) v(t);
create temp table _paced (t text, n int, days int, secs int, bpm int) on commit drop;
insert into _paced values
  ('d', 1, 40, 3750, 140), ('d', 2, 33, 3750, 140), ('d', 3, 26, 3750, 140),
  ('d', 4, 12, 3450, 150), ('d', 5, 10, 3450, 150), ('d', 6, 3, 3450, 150),
  ('e', 1, 40, 3600, 140), ('e', 2, 33, 3600, 140), ('e', 3, 26, 3600, 140),
  ('e', 4, 12, 4200, 150), ('e', 5, 10, 4200, 150), ('e', 6, 3, 4200, 150);
insert into runs (id, user_id, started_at, duration_s, distance_m, source, is_dnf, metadata)
select ('2085ffff-3333-0000-0000-00000000' || t || lpad(n::text, 3, '0'))::uuid,
       case t when 'd' then '2085eeee-0000-0000-0000-0000000000d1'::uuid else '2085eeee-0000-0000-0000-0000000000d2'::uuid end,
       now() - (days || ' days')::interval, secs, 10000, 'app', false,
       jsonb_build_object('activity_type', 'run', 'avg_bpm', bpm)
from _paced;
insert into plan_workouts (week_id, scheduled_date, kind, target_distance_m, completed_run_id)
select ('2085ffff-1111-0000-0000-0000000000' || t || '1')::uuid, (now() - (days || ' days')::interval)::date, 'easy', 10000,
       ('2085ffff-3333-0000-0000-00000000' || t || lpad(n::text, 3, '0'))::uuid
from _paced;
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"2085eeee-0000-0000-0000-0000000000c1","role":"authenticated"}';
select is(
  (select easy_hr_drift_pct from coach_roster_summary() where athlete_id = '2085eeee-0000-0000-0000-0000000000d1'),
  null,
  'recent runs at 5:45/km against older ones at 6:15/km are a pace change, not drift');
select is(
  (select easy_hr_drift_pct from coach_roster_summary() where athlete_id = '2085eeee-0000-0000-0000-0000000000d2'),
  null,
  'recent runs at 7:00/km against older ones at 6:00/km give no drift');
reset role;
set local "request.jwt.claims" = '{}';

-- An athlete's own call sees nothing of anyone.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"2085eeee-0000-0000-0000-0000000000a1","role":"authenticated"}';
select is((select count(*)::int from coach_roster_summary()), 0, 'a non-coach caller gets no rows');
reset role;

select * from finish();
rollback;

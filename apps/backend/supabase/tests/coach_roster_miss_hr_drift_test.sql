-- Pins 20270912000002 (issue #1186, decisions § 2085): the roster's
-- recent_workouts (the input the client derives misses from), athlete_today,
-- and the easy-run HR drift, which is computed only for an athlete with
-- health-data consent and only from planned easy / recovery runs.
begin;
select plan(8);

set local timezone = 'UTC';

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

-- Easy runs for both athletes: the same 10 km in 60 min, at 140 bpm over the
-- older window and 150 bpm over the last 14 days -- more beats for the same
-- speed, so EF falls by 1 - 140/150 = 6.67 %.
create temp table _runs (n int, days int, bpm int) on commit drop;
insert into _runs values (1, 40, 140), (2, 33, 140), (3, 26, 140), (4, 10, 150), (5, 3, 150);
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
  6,
  'recent_workouts holds the last 28 local days: three run workouts, the two unrun, the skipped one; no rest day, nothing from today on, nothing older');
select ok(
  (select bool_or((w ->> 'skipped')::boolean) from coach_roster_summary(), jsonb_array_elements(recent_workouts) w
    where athlete_id = '2085eeee-0000-0000-0000-0000000000a1'),
  'a skipped workout arrives marked skipped');
select is(
  (select round(easy_hr_drift_pct::numeric, 2) from coach_roster_summary() where athlete_id = '2085eeee-0000-0000-0000-0000000000a1'),
  6.67,
  'easy-run HR drift is the efficiency-factor fall, recent 14 days against the 42 before');
select is(
  (select easy_hr_drift_pct from coach_roster_summary() where athlete_id = '2085eeee-0000-0000-0000-0000000000b1'),
  null,
  'no HR drift is computed for an athlete without health-data consent');
reset role;

-- One recent run alone is too little to compare.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"2085eeee-0000-0000-0000-0000000000a1","role":"authenticated"}';
delete from runs where id = '2085ffff-2222-0000-0000-00000000a105';
set local "request.jwt.claims" = '{"sub":"2085eeee-0000-0000-0000-0000000000c1","role":"authenticated"}';
select is(
  (select easy_hr_drift_pct from coach_roster_summary() where athlete_id = '2085eeee-0000-0000-0000-0000000000a1'),
  null,
  'fewer than two recent easy runs gives no drift');
reset role;

-- An athlete's own call sees nothing of anyone.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"2085eeee-0000-0000-0000-0000000000a1","role":"authenticated"}';
select is((select count(*)::int from coach_roster_summary()), 0, 'a non-coach caller gets no rows');
reset role;

select * from finish();
rollback;

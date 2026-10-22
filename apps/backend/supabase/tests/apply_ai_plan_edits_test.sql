-- Pins migration 20271021000050 (issue #1213, decisions § 2230):
-- apply_ai_plan_edits writes a reviewed AI plan edit in one transaction and
-- re-checks every change itself. Only the owner may call it; one change out
-- of bounds rolls back every change before it; a past, done, skipped or race
-- workout keeps its prescription; a taper or race week, a workout a B/C
-- taper already eased and one inside a B race's window (ahead or already run)
-- are never scaled above 1.0, and the 0.5 / 1.1 and today edges are exact; a completed plan is never
-- edited; the plans chained after it change only when asked and only by
-- scaling; and the coach who assigned the plan gets one notification.
--
-- Dates are relative to current_date because the RPC accepts the client's
-- today only within a day of the server's. Plan P starts seven days ago:
-- week 0 is over, week 1 starts today (build), week 2 is the taper. Plan F is
-- queued the day after P ends.

begin;
select plan(80);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at) values
  ('e5e5e5e5-0000-0000-0000-0000000000a1', 'authenticated', 'authenticated', 'aipe-owner@aipe.local', '', now(), now()),
  ('e5e5e5e5-0000-0000-0000-0000000000c1', 'authenticated', 'authenticated', 'aipe-coach@aipe.local', '', now(), now()),
  ('e5e5e5e5-0000-0000-0000-0000000000b1', 'authenticated', 'authenticated', 'aipe-other@aipe.local', '', now(), now())
on conflict (id) do nothing;
insert into user_profiles (id, display_name) values
  ('e5e5e5e5-0000-0000-0000-0000000000a1', 'AIPE owner'),
  ('e5e5e5e5-0000-0000-0000-0000000000c1', 'AIPE coach'),
  ('e5e5e5e5-0000-0000-0000-0000000000b1', 'AIPE other')
on conflict (id) do nothing;
insert into coach_athletes (coach_id, athlete_id, status, invite_token, accepted_at) values
  ('e5e5e5e5-0000-0000-0000-0000000000c1', 'e5e5e5e5-0000-0000-0000-0000000000a1', 'active', 'aipe-tok', now());

insert into training_plans (id, user_id, name, goal_event, goal_distance_m, start_date, end_date, days_per_week, status, assigned_by_coach_id) values
  ('e5e5e5e5-1111-0000-0000-000000000001', 'e5e5e5e5-0000-0000-0000-0000000000a1', 'P', 'distance_half', 21097,
   current_date - 7, current_date + 13, 4, 'active', 'e5e5e5e5-0000-0000-0000-0000000000c1'),
  ('e5e5e5e5-1111-0000-0000-000000000002', 'e5e5e5e5-0000-0000-0000-0000000000a1', 'F', 'distance_half', 21097,
   current_date + 14, current_date + 27, 4, 'active', null),
  ('e5e5e5e5-1111-0000-0000-000000000003', 'e5e5e5e5-0000-0000-0000-0000000000a1', 'Done block', 'distance_10k', 10000,
   current_date + 40, current_date + 46, 4, 'completed', null),
  ('e5e5e5e5-1111-0000-0000-000000000004', 'e5e5e5e5-0000-0000-0000-0000000000b1', 'Other', 'distance_10k', 10000,
   current_date, current_date + 6, 4, 'active', null);

insert into plan_weeks (id, plan_id, week_index, phase, target_volume_m) values
  ('e5e5e5e5-2222-0000-0000-000000000000', 'e5e5e5e5-1111-0000-0000-000000000001', 0, 'build', 30000),
  ('e5e5e5e5-2222-0000-0000-000000000001', 'e5e5e5e5-1111-0000-0000-000000000001', 1, 'build', 30000),
  ('e5e5e5e5-2222-0000-0000-000000000002', 'e5e5e5e5-1111-0000-0000-000000000001', 2, 'taper', 20000),
  ('e5e5e5e5-2222-0000-0000-000000000010', 'e5e5e5e5-1111-0000-0000-000000000002', 0, 'build', 30000),
  ('e5e5e5e5-2222-0000-0000-000000000011', 'e5e5e5e5-1111-0000-0000-000000000002', 1, 'taper', 20000),
  ('e5e5e5e5-2222-0000-0000-000000000020', 'e5e5e5e5-1111-0000-0000-000000000003', 0, 'build', 20000),
  ('e5e5e5e5-2222-0000-0000-000000000030', 'e5e5e5e5-1111-0000-0000-000000000004', 0, 'build', 20000);

insert into plan_workouts (id, week_id, scheduled_date, kind, target_distance_m, target_duration_seconds,
                           target_pace_sec_per_km, target_pace_tolerance_sec, manually_completed, skipped_at,
                           race_taper_applied_at) values
  -- P week 0, over.
  ('e5e5e5e5-3333-0000-0000-000000000001', 'e5e5e5e5-2222-0000-0000-000000000000', current_date - 3, 'easy', 8000, null, null, null, false, null, null),
  -- P week 1.
  ('e5e5e5e5-3333-0000-0000-000000000002', 'e5e5e5e5-2222-0000-0000-000000000001', current_date + 1, 'tempo', 8000, null, 270, 10, true, null, null),
  ('e5e5e5e5-3333-0000-0000-000000000003', 'e5e5e5e5-2222-0000-0000-000000000001', current_date + 2, 'easy', 6000, null, null, null, false, now(), null),
  ('e5e5e5e5-3333-0000-0000-000000000004', 'e5e5e5e5-2222-0000-0000-000000000001', current_date + 3, 'easy', 10000, 3600, null, null, false, null, null),
  ('e5e5e5e5-3333-0000-0000-000000000005', 'e5e5e5e5-2222-0000-0000-000000000001', current_date + 4, 'tempo', 8000, null, 270, 10, false, null, null),
  ('e5e5e5e5-3333-0000-0000-000000000006', 'e5e5e5e5-2222-0000-0000-000000000001', current_date + 5, 'rest', null, null, null, null, false, null, null),
  ('e5e5e5e5-3333-0000-0000-000000000007', 'e5e5e5e5-2222-0000-0000-000000000001', current_date + 6, 'easy', 6000, null, null, null, false, null, now()),
  -- P week 2, taper.
  ('e5e5e5e5-3333-0000-0000-000000000008', 'e5e5e5e5-2222-0000-0000-000000000002', current_date + 8, 'easy', 8000, null, null, null, false, null, null),
  ('e5e5e5e5-3333-0000-0000-000000000009', 'e5e5e5e5-2222-0000-0000-000000000002', current_date + 13, 'race', 21097, null, null, null, false, null, null),
  -- F.
  ('e5e5e5e5-3333-0000-0000-000000000010', 'e5e5e5e5-2222-0000-0000-000000000010', current_date + 15, 'easy', 10000, null, null, null, false, null, null),
  ('e5e5e5e5-3333-0000-0000-000000000011', 'e5e5e5e5-2222-0000-0000-000000000011', current_date + 22, 'easy', 6000, null, null, null, false, null, null),
  -- Done block.
  ('e5e5e5e5-3333-0000-0000-000000000020', 'e5e5e5e5-2222-0000-0000-000000000020', current_date + 41, 'easy', 6000, null, null, null, false, null, null),
  -- Another runner's plan.
  ('e5e5e5e5-3333-0000-0000-000000000030', 'e5e5e5e5-2222-0000-0000-000000000030', current_date + 1, 'easy', 6000, null, null, null, false, null, null);

-- A B race in F's first week, three days after F's easy run: that run is in
-- its six-day taper window (race_taper.ts).
insert into plan_workouts (id, week_id, scheduled_date, kind, target_distance_m, race_priority) values
  ('e5e5e5e5-3333-0000-0000-000000000012', 'e5e5e5e5-2222-0000-0000-000000000010', current_date + 18, 'race', 10000, 'B');

create function pg_temp.aipe(p_plan text, p_workouts jsonb, p_weeks jsonb default '[]'::jsonb,
                             p_following boolean default false, p_today date default current_date)
returns void language sql as $$
  select apply_ai_plan_edits(p_plan::uuid, p_today, p_following, p_workouts, p_weeks);
$$;
grant execute on function pg_temp.aipe(text, jsonb, jsonb, boolean, date) to authenticated;

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"e5e5e5e5-0000-0000-0000-0000000000a1","role":"authenticated"}';

-- 1. A scale, an ease to recovery, a skip, a move and a week target together.
select lives_ok(
  $$ select pg_temp.aipe('e5e5e5e5-1111-0000-0000-000000000001',
       ('[{"id":"e5e5e5e5-3333-0000-0000-000000000004","target_distance_m":11000,"target_duration_seconds":3960},
         {"id":"e5e5e5e5-3333-0000-0000-000000000005","kind":"recovery","target_distance_m":4800,
          "target_pace_sec_per_km":null,"target_pace_tolerance_sec":null,"structure":null},
         {"id":"e5e5e5e5-3333-0000-0000-000000000008","skip":true},
         {"id":"e5e5e5e5-3333-0000-0000-000000000006","scheduled_date":"' || (current_date + 0)::text || '"}]')::jsonb,
       '[{"id":"e5e5e5e5-2222-0000-0000-000000000001","target_volume_m":33000}]'::jsonb) $$,
  'the owner applies a scale, an ease, a skip, a move and a week target in one call'
);
select is(
  (select (target_distance_m, target_duration_seconds)::text from plan_workouts where id = 'e5e5e5e5-3333-0000-0000-000000000004'),
  '(11000.00,3960)',
  'the scaled workout carries its new distance and duration'
);
select is(
  (select (kind::text, target_distance_m, target_pace_sec_per_km, target_pace_tolerance_sec)::text
   from plan_workouts where id = 'e5e5e5e5-3333-0000-0000-000000000005'),
  '(recovery,4800.00,,)',
  'the eased tempo is a recovery run with no pace target'
);
select isnt(
  (select skipped_at from plan_workouts where id = 'e5e5e5e5-3333-0000-0000-000000000008'),
  null,
  'the skipped workout is stamped'
);
select is(
  (select scheduled_date from plan_workouts where id = 'e5e5e5e5-3333-0000-0000-000000000006'),
  current_date,
  'the rest day moved inside its week'
);
select is(
  (select target_volume_m from plan_weeks where id = 'e5e5e5e5-2222-0000-0000-000000000001'),
  33000.00,
  'the week target is written'
);

-- 2. Atomicity: one change out of bounds rolls back the ones before it.
select throws_ok(
  $$ select pg_temp.aipe('e5e5e5e5-1111-0000-0000-000000000001',
       '[{"id":"e5e5e5e5-3333-0000-0000-000000000004","target_distance_m":10000},
         {"id":"e5e5e5e5-3333-0000-0000-000000000001","target_distance_m":7000}]'::jsonb) $$,
  '22023', null,
  'a batch holding a past workout is refused'
);
select is(
  (select target_distance_m from plan_workouts where id = 'e5e5e5e5-3333-0000-0000-000000000004'),
  11000.00,
  'and the valid change before it was rolled back'
);
select throws_ok(
  $$ select pg_temp.aipe('e5e5e5e5-1111-0000-0000-000000000001', '[]'::jsonb,
       '[{"id":"e5e5e5e5-2222-0000-0000-000000000001","target_volume_m":30000},
         {"id":"e5e5e5e5-2222-0000-0000-000000000000","target_volume_m":27000}]'::jsonb) $$,
  '22023', null,
  'a week that is already over is refused'
);
select is(
  (select target_volume_m from plan_weeks where id = 'e5e5e5e5-2222-0000-0000-000000000001'),
  33000.00,
  'and the week target before it kept its value'
);

-- 3. Done, skipped, past and race workouts keep their prescription.
select throws_ok(
  $$ select pg_temp.aipe('e5e5e5e5-1111-0000-0000-000000000001',
       '[{"id":"e5e5e5e5-3333-0000-0000-000000000002","target_distance_m":7200}]'::jsonb) $$,
  '22023', null,
  'a completed workout is refused'
);
select throws_ok(
  $$ select pg_temp.aipe('e5e5e5e5-1111-0000-0000-000000000001',
       '[{"id":"e5e5e5e5-3333-0000-0000-000000000003","target_distance_m":5400}]'::jsonb) $$,
  '22023', null,
  'a skipped workout cannot be scaled'
);
select throws_ok(
  $$ select pg_temp.aipe('e5e5e5e5-1111-0000-0000-000000000001',
       '[{"id":"e5e5e5e5-3333-0000-0000-000000000009","target_distance_m":20000}]'::jsonb) $$,
  '22023', null,
  'a race is refused'
);
select is(
  (select array_agg(target_distance_m order by id) from plan_workouts
   where id in ('e5e5e5e5-3333-0000-0000-000000000001', 'e5e5e5e5-3333-0000-0000-000000000002',
                'e5e5e5e5-3333-0000-0000-000000000003', 'e5e5e5e5-3333-0000-0000-000000000009')),
  array[8000.00, 8000.00, 6000.00, 21097.00]::numeric[],
  'past, done, skipped and race workouts are untouched'
);

-- 4. Taper and race weeks, and an eased B/C taper workout, never scale above 1.0.
select throws_ok(
  $$ select pg_temp.aipe('e5e5e5e5-1111-0000-0000-000000000001', '[]'::jsonb,
       '[{"id":"e5e5e5e5-2222-0000-0000-000000000002","target_volume_m":22000}]'::jsonb) $$,
  '22023', null,
  'a taper week target is not scaled up'
);
select throws_ok(
  $$ select pg_temp.aipe('e5e5e5e5-1111-0000-0000-000000000001',
       '[{"id":"e5e5e5e5-3333-0000-0000-000000000007","target_distance_m":6600}]'::jsonb) $$,
  '22023', null,
  'a workout a B/C taper eased is not scaled up'
);
select lives_ok(
  $$ select pg_temp.aipe('e5e5e5e5-1111-0000-0000-000000000001', '[]'::jsonb,
       '[{"id":"e5e5e5e5-2222-0000-0000-000000000002","target_volume_m":18000}]'::jsonb) $$,
  'a taper week can be eased'
);
select throws_ok(
  $$ select pg_temp.aipe('e5e5e5e5-1111-0000-0000-000000000001',
       '[{"id":"e5e5e5e5-3333-0000-0000-000000000004","target_distance_m":13000}]'::jsonb) $$,
  '22023', null,
  'more than 1.1 times the current distance is refused'
);
select throws_ok(
  $$ select pg_temp.aipe('e5e5e5e5-1111-0000-0000-000000000001',
       '[{"id":"e5e5e5e5-3333-0000-0000-000000000004","target_distance_m":5000}]'::jsonb) $$,
  '22023', null,
  'less than half the current distance is refused'
);

-- 5. Shape: only the fields an AI edit writes, a date inside the week, once each.
select throws_ok(
  $$ select pg_temp.aipe('e5e5e5e5-1111-0000-0000-000000000001',
       '[{"id":"e5e5e5e5-3333-0000-0000-000000000004","notes":"run hard"}]'::jsonb) $$,
  '22023', null,
  'a field an AI edit cannot write is refused'
);
select throws_ok(
  $$ select pg_temp.aipe('e5e5e5e5-1111-0000-0000-000000000001',
       ('[{"id":"e5e5e5e5-3333-0000-0000-000000000004","scheduled_date":"' || (current_date + 8)::text || '"}]')::jsonb) $$,
  '22023', null,
  'a move out of the workout''s week is refused'
);
select throws_ok(
  $$ select pg_temp.aipe('e5e5e5e5-1111-0000-0000-000000000001',
       '[{"id":"e5e5e5e5-3333-0000-0000-000000000004","kind":"interval"}]'::jsonb) $$,
  '22023', null,
  'a kind change other than easing to recovery is refused'
);
select throws_ok(
  $$ select pg_temp.aipe('e5e5e5e5-1111-0000-0000-000000000001',
       '[{"id":"e5e5e5e5-3333-0000-0000-000000000004","target_distance_m":10500},
         {"id":"e5e5e5e5-3333-0000-0000-000000000004","target_distance_m":10600}]'::jsonb) $$,
  '22023', null,
  'a workout named twice is refused'
);
select throws_ok(
  $$ select pg_temp.aipe('e5e5e5e5-1111-0000-0000-000000000001',
       '[{"id":"e5e5e5e5-3333-0000-0000-000000000004","target_distance_m":10500}]'::jsonb,
       '[]'::jsonb, false, current_date - 5) $$,
  '22023', null,
  'a today far from the server''s is refused'
);

-- The exact edges of the scaling band and of today, on the 11 000 m easy run.
select lives_ok(
  $$ select pg_temp.aipe('e5e5e5e5-1111-0000-0000-000000000001', '[]'::jsonb, '[]'::jsonb, false, current_date + 1) $$,
  'a today one day ahead of the server''s is accepted'
);
select throws_ok(
  $$ select pg_temp.aipe('e5e5e5e5-1111-0000-0000-000000000001', '[]'::jsonb, '[]'::jsonb, false, current_date - 2) $$,
  '22023', null,
  'a today two days behind the server''s is refused'
);
select throws_ok(
  $$ select pg_temp.aipe('e5e5e5e5-1111-0000-0000-000000000001',
       '[{"id":"e5e5e5e5-3333-0000-0000-000000000004","target_distance_m":12101}]'::jsonb) $$,
  '22023', null,
  'one metre past ceil(1.1 x) is refused'
);
select lives_ok(
  $$ select pg_temp.aipe('e5e5e5e5-1111-0000-0000-000000000001',
       '[{"id":"e5e5e5e5-3333-0000-0000-000000000004","target_distance_m":12100}]'::jsonb) $$,
  'ceil(1.1 x) itself is accepted'
);
reset role;
update plan_workouts set target_distance_m = 11000 where id = 'e5e5e5e5-3333-0000-0000-000000000004';
set local role authenticated;
select throws_ok(
  $$ select pg_temp.aipe('e5e5e5e5-1111-0000-0000-000000000001',
       '[{"id":"e5e5e5e5-3333-0000-0000-000000000004","target_distance_m":5499}]'::jsonb) $$,
  '22023', null,
  'one metre under floor(0.5 x) is refused'
);
select lives_ok(
  $$ select pg_temp.aipe('e5e5e5e5-1111-0000-0000-000000000001',
       '[{"id":"e5e5e5e5-3333-0000-0000-000000000004","target_distance_m":5500}]'::jsonb) $$,
  'floor(0.5 x) itself is accepted'
);
reset role;
update plan_workouts set target_distance_m = 11000 where id = 'e5e5e5e5-3333-0000-0000-000000000004';
-- A B half marathon run yesterday: its seven-day recovery covers this week.
insert into plan_workouts (id, week_id, scheduled_date, kind, target_distance_m, race_priority) values
  ('e5e5e5e5-3333-0000-0000-000000000013', 'e5e5e5e5-2222-0000-0000-000000000000', current_date - 1, 'race', 21097, 'B');
set local role authenticated;
select throws_ok(
  $$ select pg_temp.aipe('e5e5e5e5-1111-0000-0000-000000000001',
       '[{"id":"e5e5e5e5-3333-0000-0000-000000000004","target_distance_m":12100}]'::jsonb) $$,
  '22023', null,
  'a workout in the recovery window of a race already run is not scaled up'
);
reset role;
delete from plan_workouts where id = 'e5e5e5e5-3333-0000-0000-000000000013';
-- The block before P, ended a week before P began, closing on a B 100 km
-- race: its 21-day recovery runs through P's current week, so this week's
-- easy run is held at 1.0 although the race is in another plan.
insert into training_plans (id, user_id, name, goal_event, goal_distance_m, start_date, end_date, days_per_week, status) values
  ('e5e5e5e5-1111-0000-0000-000000000005', 'e5e5e5e5-0000-0000-0000-0000000000a1', 'Before P', 'distance_half', 21097,
   current_date - 21, current_date - 8, 4, 'completed');
insert into plan_weeks (id, plan_id, week_index, phase, target_volume_m) values
  ('e5e5e5e5-2222-0000-0000-000000000050', 'e5e5e5e5-1111-0000-0000-000000000005', 0, 'race', 100000);
insert into plan_workouts (id, week_id, scheduled_date, kind, target_distance_m, race_priority) values
  ('e5e5e5e5-3333-0000-0000-000000000050', 'e5e5e5e5-2222-0000-0000-000000000050', current_date - 8, 'race', 100000, 'B');
set local role authenticated;
select throws_ok(
  $$ select pg_temp.aipe('e5e5e5e5-1111-0000-0000-000000000001',
       '[{"id":"e5e5e5e5-3333-0000-0000-000000000004","target_distance_m":12100}]'::jsonb) $$,
  '22023', null,
  'a workout in the recovery window of the preceding block''s B race is not scaled up'
);
reset role;
delete from training_plans where id = 'e5e5e5e5-1111-0000-0000-000000000005';

-- Which block is "the one before" is the same rule fetchPrecedingPlan reads:
-- the latest non-template active or completed plan ending before P starts,
-- ties to the lowest id. Each case puts the B 100 km race on one candidate
-- only, so whether the easy run is held says which plan was picked.
create function pg_temp.before_block(p_id text, p_end date, p_status text, p_race boolean) returns void
language sql as $f$
  insert into training_plans (id, user_id, name, goal_event, goal_distance_m, start_date, end_date, days_per_week, status)
  values (p_id::uuid, 'e5e5e5e5-0000-0000-0000-0000000000a1', 'Before ' || p_id, 'distance_half', 21097,
          p_end - 13, p_end, 4, p_status);
  insert into plan_weeks (plan_id, week_index, phase, target_volume_m) values (p_id::uuid, 0, 'race', 100000);
  insert into plan_workouts (week_id, scheduled_date, kind, target_distance_m, race_priority)
  select w.id, p_end, 'race', 100000, 'B' from plan_weeks w where w.plan_id = p_id::uuid and p_race;
$f$;
select pg_temp.before_block('e5e5e5e5-1111-0000-0000-000000000006', current_date - 8, 'completed', true);
select pg_temp.before_block('e5e5e5e5-1111-0000-0000-000000000007', current_date - 8, 'completed', false);
set local role authenticated;
select throws_ok(
  $$ select pg_temp.aipe('e5e5e5e5-1111-0000-0000-000000000001',
       '[{"id":"e5e5e5e5-3333-0000-0000-000000000004","target_distance_m":12100}]'::jsonb) $$,
  '22023', null,
  'two blocks ending the same day: the lower id is the one before, and its race holds'
);
reset role;
delete from training_plans where id in ('e5e5e5e5-1111-0000-0000-000000000006', 'e5e5e5e5-1111-0000-0000-000000000007');
select pg_temp.before_block('e5e5e5e5-1111-0000-0000-000000000006', current_date - 8, 'completed', false);
select pg_temp.before_block('e5e5e5e5-1111-0000-0000-000000000007', current_date - 8, 'completed', true);
set local role authenticated;
select lives_ok(
  $$ select pg_temp.aipe('e5e5e5e5-1111-0000-0000-000000000001',
       '[{"id":"e5e5e5e5-3333-0000-0000-000000000004","target_distance_m":12100}]'::jsonb) $$,
  'and a race on the higher id of the two is not the one before''s'
);
reset role;
update plan_workouts set target_distance_m = 11000 where id = 'e5e5e5e5-3333-0000-0000-000000000004';
delete from training_plans where id in ('e5e5e5e5-1111-0000-0000-000000000006', 'e5e5e5e5-1111-0000-0000-000000000007');
select pg_temp.before_block('e5e5e5e5-1111-0000-0000-000000000006', current_date - 20, 'completed', false);
select pg_temp.before_block('e5e5e5e5-1111-0000-0000-000000000007', current_date - 8, 'abandoned', true);
set local role authenticated;
select lives_ok(
  $$ select pg_temp.aipe('e5e5e5e5-1111-0000-0000-000000000001',
       '[{"id":"e5e5e5e5-3333-0000-0000-000000000004","target_distance_m":12100}]'::jsonb) $$,
  'an abandoned block ending later is skipped for the completed one before it'
);
reset role;
update plan_workouts set target_distance_m = 11000 where id = 'e5e5e5e5-3333-0000-0000-000000000004';
delete from training_plans where id = 'e5e5e5e5-1111-0000-0000-000000000007';
select pg_temp.before_block('e5e5e5e5-1111-0000-0000-000000000007', current_date - 7, 'completed', true);
set local role authenticated;
select lives_ok(
  $$ select pg_temp.aipe('e5e5e5e5-1111-0000-0000-000000000001',
       '[{"id":"e5e5e5e5-3333-0000-0000-000000000004","target_distance_m":12100}]'::jsonb) $$,
  'a block ending on the day P starts is not the one before it'
);
reset role;
update plan_workouts set target_distance_m = 11000 where id = 'e5e5e5e5-3333-0000-0000-000000000004';
delete from training_plans where id in ('e5e5e5e5-1111-0000-0000-000000000006', 'e5e5e5e5-1111-0000-0000-000000000007');
set local role authenticated;

-- 6. The chained block changes only when asked, and only by scaling.
select throws_ok(
  $$ select pg_temp.aipe('e5e5e5e5-1111-0000-0000-000000000001',
       '[{"id":"e5e5e5e5-3333-0000-0000-000000000010","target_distance_m":9000}]'::jsonb) $$,
  '22023', null,
  'without the following flag a later block is out of reach'
);
select lives_ok(
  $$ select pg_temp.aipe('e5e5e5e5-1111-0000-0000-000000000001',
       '[{"id":"e5e5e5e5-3333-0000-0000-000000000004","target_distance_m":9900},
         {"id":"e5e5e5e5-3333-0000-0000-000000000010","target_distance_m":9000},
         {"id":"e5e5e5e5-3333-0000-0000-000000000011","target_distance_m":5400}]'::jsonb,
       '[{"id":"e5e5e5e5-2222-0000-0000-000000000010","target_volume_m":27000}]'::jsonb, true) $$,
  'with it, this block and the next are eased together'
);
select is(
  (select array_agg(target_distance_m order by id) from plan_workouts
   where id in ('e5e5e5e5-3333-0000-0000-000000000004', 'e5e5e5e5-3333-0000-0000-000000000010',
                'e5e5e5e5-3333-0000-0000-000000000011')),
  array[9900.00, 9000.00, 5400.00]::numeric[],
  'both blocks carry the eased distances'
);
select throws_ok(
  $$ select pg_temp.aipe('e5e5e5e5-1111-0000-0000-000000000001',
       '[{"id":"e5e5e5e5-3333-0000-0000-000000000010","target_distance_m":9900}]'::jsonb, '[]'::jsonb, true) $$,
  '22023', null,
  'a workout inside a B race''s taper window is not scaled up'
);
select lives_ok(
  $$ select pg_temp.aipe('e5e5e5e5-1111-0000-0000-000000000001',
       '[{"id":"e5e5e5e5-3333-0000-0000-000000000010","target_distance_m":8100}]'::jsonb, '[]'::jsonb, true) $$,
  'but it can still be eased'
);
select throws_ok(
  $$ select pg_temp.aipe('e5e5e5e5-1111-0000-0000-000000000001', '[]'::jsonb,
       '[{"id":"e5e5e5e5-2222-0000-0000-000000000011","target_volume_m":22000}]'::jsonb, true) $$,
  '22023', null,
  'the next block''s taper week is not scaled up either'
);
select throws_ok(
  $$ select pg_temp.aipe('e5e5e5e5-1111-0000-0000-000000000001',
       '[{"id":"e5e5e5e5-3333-0000-0000-000000000011","target_distance_m":5940}]'::jsonb, '[]'::jsonb, true) $$,
  '22023', null,
  'nor is a workout in that taper week'
);
select throws_ok(
  $$ select pg_temp.aipe('e5e5e5e5-1111-0000-0000-000000000001',
       '[{"id":"e5e5e5e5-3333-0000-0000-000000000010","skip":true}]'::jsonb, '[]'::jsonb, true) $$,
  '22023', null,
  'a following block can only be scaled'
);

-- 7. A completed plan, and another runner's plan, are never edited.
select throws_ok(
  $$ select pg_temp.aipe('e5e5e5e5-1111-0000-0000-000000000003',
       '[{"id":"e5e5e5e5-3333-0000-0000-000000000020","target_distance_m":5400}]'::jsonb) $$,
  '22023', null,
  'a completed plan is refused'
);
select throws_ok(
  $$ select pg_temp.aipe('e5e5e5e5-1111-0000-0000-000000000004',
       '[{"id":"e5e5e5e5-3333-0000-0000-000000000030","target_distance_m":5400}]'::jsonb) $$,
  'P0002', null,
  'another runner''s plan is not found'
);

set local "request.jwt.claims" = '{"sub":"e5e5e5e5-0000-0000-0000-0000000000b1","role":"authenticated"}';
select throws_ok(
  $$ select pg_temp.aipe('e5e5e5e5-1111-0000-0000-000000000004',
       '[{"id":"e5e5e5e5-3333-0000-0000-000000000004","target_distance_m":9000}]'::jsonb) $$,
  '22023', null,
  'naming another runner''s workout through your own plan is refused'
);

reset role;

-- 8. The coach who assigned P hears about it once; F has no coach.
select is(
  (select count(*)::int from notifications
   where user_id = 'e5e5e5e5-0000-0000-0000-0000000000c1' and kind = 'plan_ai_edit'
     and actor_id = 'e5e5e5e5-0000-0000-0000-0000000000a1'
     and plan_id = 'e5e5e5e5-1111-0000-0000-000000000001'),
  1,
  'the assigning coach has one unread notification across three applies'
);
select is(
  (select count(*)::int from notifications where plan_id = 'e5e5e5e5-1111-0000-0000-000000000002'),
  0,
  'a plan nobody assigned notifies nobody'
);

update coach_athletes set status = 'ended', ended_at = now()
where coach_id = 'e5e5e5e5-0000-0000-0000-0000000000c1';
update notifications set read_at = now()
where user_id = 'e5e5e5e5-0000-0000-0000-0000000000c1' and kind = 'plan_ai_edit';
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"e5e5e5e5-0000-0000-0000-0000000000a1","role":"authenticated"}';
select pg_temp.aipe('e5e5e5e5-1111-0000-0000-000000000001',
  '[{"id":"e5e5e5e5-3333-0000-0000-000000000004","target_distance_m":10000}]'::jsonb);
reset role;
select is(
  (select count(*)::int from notifications
   where user_id = 'e5e5e5e5-0000-0000-0000-0000000000c1' and kind = 'plan_ai_edit'),
  1,
  'once the coach link has ended, a further apply notifies nobody'
);

-- 9. private.in_bc_race_window is the third copy of the race_taper.ts
-- windows (parity_pairs.md, race_taper): every branch, at its edge. One
-- completed plan per race, 200 days out, so nothing else is in reach.
insert into training_plans (id, user_id, name, goal_event, goal_distance_m, start_date, end_date, days_per_week, status)
select ('e5e5e5e5-1111-0000-0000-0000000001' || n)::uuid, 'e5e5e5e5-0000-0000-0000-0000000000a1', 'Window ' || n,
       'distance_half', case when n = '07' then 50000 else 21097 end,
       current_date + 170, case when n = '07' then current_date + 200 else current_date + 230 end, 4, 'completed'
from unnest(array['01', '02', '03', '04', '05', '06', '07', '08', '09', '10', '11']) as n;
insert into plan_weeks (id, plan_id, week_index, phase, target_volume_m)
select ('e5e5e5e5-2222-0000-0000-0000000001' || n)::uuid, ('e5e5e5e5-1111-0000-0000-0000000001' || n)::uuid, 4, 'build', 40000
from unnest(array['01', '02', '03', '04', '05', '06', '07', '08', '09', '10', '11']) as n;
insert into plan_workouts (id, week_id, scheduled_date, kind, target_distance_m, race_priority) values
  -- C: no priority, not on the end date.
  ('e5e5e5e5-3333-0000-0000-000000000101', 'e5e5e5e5-2222-0000-0000-000000000101', current_date + 200, 'race', 5000, null),
  ('e5e5e5e5-3333-0000-0000-000000000102', 'e5e5e5e5-2222-0000-0000-000000000102', current_date + 200, 'race', 21097, 'B'),
  ('e5e5e5e5-3333-0000-0000-000000000103', 'e5e5e5e5-2222-0000-0000-000000000103', current_date + 200, 'race', 13500, 'B'),
  ('e5e5e5e5-3333-0000-0000-000000000104', 'e5e5e5e5-2222-0000-0000-000000000104', current_date + 200, 'race', 50000, 'B'),
  ('e5e5e5e5-3333-0000-0000-000000000105', 'e5e5e5e5-2222-0000-0000-000000000105', current_date + 200, 'race', 100000, 'B'),
  ('e5e5e5e5-3333-0000-0000-000000000106', 'e5e5e5e5-2222-0000-0000-000000000106', current_date + 200, 'race', null, 'B'),
  -- On its plan's end date with no distance: the 50 km goal.
  ('e5e5e5e5-3333-0000-0000-000000000107', 'e5e5e5e5-2222-0000-0000-000000000107', current_date + 200, 'race', null, 'B'),
  ('e5e5e5e5-3333-0000-0000-000000000108', 'e5e5e5e5-2222-0000-0000-000000000108', current_date + 200, 'race', 5000, 'B'),
  ('e5e5e5e5-3333-0000-0000-000000000109', 'e5e5e5e5-2222-0000-0000-000000000109', current_date + 200, 'race', 30000, 'B'),
  ('e5e5e5e5-3333-0000-0000-000000000110', 'e5e5e5e5-2222-0000-0000-000000000110', current_date + 200, 'race', 42195, 'B'),
  ('e5e5e5e5-3333-0000-0000-000000000111', 'e5e5e5e5-2222-0000-0000-000000000111', current_date + 200, 'race', 0, 'B');

set local role authenticated;
create function pg_temp.win(n text, offset_days int) returns boolean language sql as $$
  select private.in_bc_race_window(array[('e5e5e5e5-1111-0000-0000-0000000001' || n)::uuid],
                                   current_date + 200 + offset_days);
$$;
select is(pg_temp.win('01', -3), true,  'C race: 3 days before is in its taper');
select is(pg_temp.win('01', -4), false, 'C race: 4 days before is not');
select is(pg_temp.win('01', 2), true,   'C race: 2 days after is in its recovery');
select is(pg_temp.win('01', 3), false,  'C race: 3 days after is not');
select is(pg_temp.win('02', 0), false,  'race day itself is in neither window');
select is(pg_temp.win('02', -6), true,  'B 21.1 km: 6 days before is in its taper');
select is(pg_temp.win('02', -7), false, 'B 21.1 km: 7 days before is not');
select is(pg_temp.win('02', 7), true,   'B 21.1 km: round(7.03) = 7 recovery days');
select is(pg_temp.win('02', 8), false,  'B 21.1 km: day 8 is past them');
select is(pg_temp.win('03', 5), true,   'B 13.5 km: round(4.5) = 5, half away from zero');
select is(pg_temp.win('03', 6), false,  'B 13.5 km: day 6 is past them');
select is(pg_temp.win('04', -8), true,  'B 50 km: an ultra tapers from 8 days out');
select is(pg_temp.win('04', -9), false, 'B 50 km: 9 days out is not');
select is(pg_temp.win('04', 11), true,  'B 50 km: round(7 + 3.90) = 11 recovery days');
select is(pg_temp.win('04', 12), false, 'B 50 km: day 12 is past them');
select is(pg_temp.win('05', 21), true,  'B 100 km: recovery capped at 21 days');
select is(pg_temp.win('05', 22), false, 'B 100 km: day 22 is past the cap');
select is(pg_temp.win('06', 5), true,   'B with no distance: 5 recovery days');
select is(pg_temp.win('06', 6), false,  'B with no distance: day 6 is past them');
select is(pg_temp.win('07', -8), true,  'an end-date B race with no distance takes the 50 km goal: 8-day taper');
select is(pg_temp.win('07', 11), true,  'and 11 recovery days');
select is(pg_temp.win('07', 12), false, 'and not 12');
select is(pg_temp.win('08', 4), true,   'B 5 km: round(1.67) = 2 is held up to 4 recovery days');
select is(pg_temp.win('08', 5), false,  'B 5 km: day 5 is past them');
select is(pg_temp.win('09', 7), true,   'B 30 km: round(10) is held down to 7 recovery days');
select is(pg_temp.win('09', 8), false,  'B 30 km: day 8 is past them');
select is(pg_temp.win('10', -6), true,  'B exactly a marathon is not an ultra: 6-day taper');
select is(pg_temp.win('10', -7), false, 'B exactly a marathon: 7 days out is not in it');
select is(pg_temp.win('11', 5), true,   'B with a 0 m distance: 5 recovery days');
select is(pg_temp.win('11', 6), false,  'B with a 0 m distance: day 6 is past them');

select * from finish();
rollback;

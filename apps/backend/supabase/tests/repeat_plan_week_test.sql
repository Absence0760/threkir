-- Pins migration 20271003000001: repeat_plan_week runs this week, or the week
-- that just finished, again next week. The copy goes in at the current week +
-- 1 and every later week moves back one; a race plan drops one pre-taper week
-- that has not started so race day holds, and a plan without a race moves its
-- end. Only the owner may call it, ownership is checked before the hourly rate
-- limit, every refusal writes nothing, and the break offer's prefs key is never
-- touched. A copied week carries heart-rate targets only while the HR gate is
-- open and the owner consents.
--
-- Also pins that reschedule_plan_after_break, now a wrapper over the same
-- private.repeat_plan_weeks body, still answers its own way.
--
-- Dates are relative to current_date because the RPC trusts the client's
-- today only within a day of the server's. S is the Sunday four weeks before
-- this week's Sunday, so weeks 0-3 are past and week 4 is under way.

begin;
select plan(43);

create temp table rpw_s as
  select (current_date - extract(dow from current_date)::integer - 28) as s;
grant select on rpw_s to authenticated;

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
select ('c7c7c7c7-0000-0000-0000-00000000000' || o)::uuid, 'authenticated', 'authenticated',
       'rpw-' || o || '@rpw.local', '', now(), now()
from unnest(array['a', 'b', 'c', 'd', 'e', 'f']) as o
on conflict (id) do nothing;
insert into user_profiles (id, display_name, health_data_consent_at)
select ('c7c7c7c7-0000-0000-0000-00000000000' || o)::uuid, 'RPW ' || o,
       case when o in ('a', 'd') then now() end
from unnest(array['a', 'b', 'c', 'd', 'e', 'f']) as o
on conflict (id) do update set health_data_consent_at = excluded.health_data_consent_at;

insert into private.feature_flags (name, enabled) values ('hr_prescription', true)
  on conflict (name) do update set enabled = true;

-- Ten-week plans. A race plan (r): base 0-1, build 2-5, peak 6-7, taper 8,
-- race 9 on its last Sunday, the end date. A walk-run plan (w): every week
-- build, no race, ending on week 9's Saturday. A long run every Sunday (weeks
-- 0 and 1 done), an easy run every Wednesday, heart-rate targets on the long
-- runs of weeks 3 and 4 for A and D, the two who consent.
--   a1 A race (active)   a2 A race (paused)   b1 B walk   d1 D walk
--   e1 E walk, e2 E's next plan starting the day after e1 ends   f1 F walk
create temp table rpw_plans (tag text, owner text, shape text, status text);
insert into rpw_plans values
  ('a1', 'a', 'r', 'active'), ('a2', 'a', 'r', 'paused'), ('b1', 'b', 'w', 'active'),
  ('d1', 'd', 'w', 'active'), ('e1', 'e', 'w', 'active'), ('f1', 'f', 'w', 'active');

insert into training_plans (id, user_id, name, goal_event, goal_distance_m, start_date, end_date, days_per_week, status)
select ('c1c1c1c1-0000-0000-0000-0000000000' || p.tag)::uuid,
       ('c7c7c7c7-0000-0000-0000-00000000000' || p.owner)::uuid,
       'RPW ' || p.tag, 'distance_5k', 5000, s,
       s + case when p.shape = 'r' then 63 else 69 end, 3, p.status
from rpw_s, rpw_plans p;
insert into training_plans (id, user_id, name, goal_event, goal_distance_m, start_date, end_date, days_per_week, status)
select 'c1c1c1c1-0000-0000-0000-0000000000e2', 'c7c7c7c7-0000-0000-0000-00000000000e',
       'RPW next', 'distance_5k', 5000, s + 70, s + 140, 3, 'active'
from rpw_s;

insert into plan_weeks (id, plan_id, week_index, phase, target_volume_m)
select ('c2c2c2c2-0000-0000-0000-0000' || p.tag || lpad(i::text, 6, '0'))::uuid,
       ('c1c1c1c1-0000-0000-0000-0000000000' || p.tag)::uuid, i,
       (case when p.shape = 'w' then 'build'
             when i < 2 then 'base' when i < 6 then 'build' when i < 8 then 'peak'
             when i = 8 then 'taper' else 'race' end)::plan_phase,
       10000
from rpw_plans p, generate_series(0, 9) as i;

insert into plan_workouts (id, week_id, scheduled_date, kind, target_distance_m, manually_completed,
                           target_hr_min_bpm, target_hr_max_bpm)
select ('c3c3c3c3-0000-0000-0000-' || p.tag || lpad(i::text, 2, '0') || '01000000')::uuid,
       ('c2c2c2c2-0000-0000-0000-0000' || p.tag || lpad(i::text, 6, '0'))::uuid,
       s + 7 * i,
       (case when p.shape = 'r' and i = 9 then 'race' else 'long' end)::workout_kind,
       case when p.shape = 'r' and i = 9 then 21097 else 8000 end,
       i <= 1,
       case when i in (3, 4) and p.owner in ('a', 'd') then 140 end,
       case when i in (3, 4) and p.owner in ('a', 'd') then 155 end
from rpw_s, rpw_plans p, generate_series(0, 9) as i;
insert into plan_workouts (id, week_id, scheduled_date, kind, target_distance_m)
select ('c3c3c3c3-0000-0000-0000-' || p.tag || lpad(i::text, 2, '0') || '02000000')::uuid,
       ('c2c2c2c2-0000-0000-0000-0000' || p.tag || lpad(i::text, 6, '0'))::uuid,
       s + 7 * i + 3, 'easy', 4000
from rpw_s, rpw_plans p, generate_series(0, 9) as i
where not (p.shape = 'r' and i = 9);

set local role authenticated;

-- ── Who may call ───────────────────────────────────────────────────────────

select throws_ok(
  $$select repeat_plan_week('c1c1c1c1-0000-0000-0000-0000000000b1', current_date,
      'c2c2c2c2-0000-0000-0000-0000b1000004')$$,
  '42501', 'repeat_plan_week: not authenticated', 'an unauthenticated caller is refused');

set local "request.jwt.claims" = '{"sub":"c7c7c7c7-0000-0000-0000-00000000000c","role":"authenticated"}';
select throws_ok(
  $$select repeat_plan_week('c1c1c1c1-0000-0000-0000-0000000000b1', current_date,
      'c2c2c2c2-0000-0000-0000-0000b1000004')$$,
  'P0002', 'repeat_plan_week: plan c1c1c1c1-0000-0000-0000-0000000000b1 not found',
  'another runner''s plan is refused');
reset role;
select is((select count(*)::int from rate_limits
           where user_id = 'c7c7c7c7-0000-0000-0000-00000000000c'),
  0, 'a refused stranger spends no rate-limit budget');
set local role authenticated;

-- ── Refusals, each writing nothing ─────────────────────────────────────────

set local "request.jwt.claims" = '{"sub":"c7c7c7c7-0000-0000-0000-00000000000a","role":"authenticated"}';

create temp table rpw_before as
  select string_agg(w.week_index || ':' || wo.id || ':' || wo.scheduled_date, ',' order by wo.id) as fp
  from plan_workouts wo join plan_weeks w on w.id = wo.week_id
  where w.plan_id = 'c1c1c1c1-0000-0000-0000-0000000000a1';

select throws_ok(
  $$select repeat_plan_week('c1c1c1c1-0000-0000-0000-0000000000a1', current_date - 3,
      'c2c2c2c2-0000-0000-0000-0000a1000004', 'c2c2c2c2-0000-0000-0000-0000a1000005')$$,
  '22023', 'repeat_plan_week: today must be within a day of the server date',
  'a client today far from the server date is refused');
select throws_ok(
  $$select repeat_plan_week('c1c1c1c1-0000-0000-0000-0000000000a2', current_date,
      'c2c2c2c2-0000-0000-0000-0000a2000004', 'c2c2c2c2-0000-0000-0000-0000a2000005')$$,
  '22023', 'repeat_plan_week: only an active plan that is under way',
  'a paused plan is refused');
select throws_ok(
  $$select repeat_plan_week('c1c1c1c1-0000-0000-0000-0000000000a1', current_date,
      'c2c2c2c2-0000-0000-0000-0000a1000002', 'c2c2c2c2-0000-0000-0000-0000a1000005')$$,
  '22023', 'repeat_plan_week: only this week or last week can run again',
  'a week two back cannot run again');
select throws_ok(
  $$select repeat_plan_week('c1c1c1c1-0000-0000-0000-0000000000a1', current_date,
      'c2c2c2c2-0000-0000-0000-0000a1000005', 'c2c2c2c2-0000-0000-0000-0000a1000006')$$,
  '22023', 'repeat_plan_week: only this week or last week can run again',
  'a week that has not started cannot run again');
select throws_ok(
  $$select repeat_plan_week('c1c1c1c1-0000-0000-0000-0000000000a1', current_date,
      'c2c2c2c2-0000-0000-0000-0000b1000004', 'c2c2c2c2-0000-0000-0000-0000a1000005')$$,
  '22023', 'repeat_plan_week: only this week or last week can run again',
  'a week from another plan is refused');
select throws_ok(
  $$select repeat_plan_week('c1c1c1c1-0000-0000-0000-0000000000a1', current_date,
      'c2c2c2c2-0000-0000-0000-0000a1000004')$$,
  '22023', 'repeat_plan_week: a race plan drops as many weeks as it repeats',
  'a race plan that would move its race day is refused');
select throws_ok(
  $$select repeat_plan_week('c1c1c1c1-0000-0000-0000-0000000000a1', current_date,
      'c2c2c2c2-0000-0000-0000-0000a1000004', 'c2c2c2c2-0000-0000-0000-0000a1000008')$$,
  '22023', 'repeat_plan_week: only pre-taper weeks that have not started can be dropped',
  'the taper is never dropped');
select throws_ok(
  $$select repeat_plan_week('c1c1c1c1-0000-0000-0000-0000000000a1', current_date,
      'c2c2c2c2-0000-0000-0000-0000a1000004', 'c2c2c2c2-0000-0000-0000-0000b1000005')$$,
  '22023', 'repeat_plan_week: only pre-taper weeks that have not started can be dropped',
  'another plan''s week is never dropped');
update plan_workouts set manually_completed = true where id = 'c3c3c3c3-0000-0000-0000-a10601000000';
select throws_ok(
  $$select repeat_plan_week('c1c1c1c1-0000-0000-0000-0000000000a1', current_date,
      'c2c2c2c2-0000-0000-0000-0000a1000004', 'c2c2c2c2-0000-0000-0000-0000a1000007')$$,
  '22023', 'repeat_plan_week: a week that would move holds a race or a completed workout',
  'a completed workout in a week that would move is refused');
update plan_workouts set manually_completed = false where id = 'c3c3c3c3-0000-0000-0000-a10601000000';

select is((select fp from rpw_before),
  (select string_agg(w.week_index || ':' || wo.id || ':' || wo.scheduled_date, ',' order by wo.id)
   from plan_workouts wo join plan_weeks w on w.id = wo.week_id
   where w.plan_id = 'c1c1c1c1-0000-0000-0000-0000000000a1'),
  'refusals: no week, workout or date changed');
select is((select end_date from training_plans where id = 'c1c1c1c1-0000-0000-0000-0000000000a1'),
  (select s + 63 from rpw_s), 'refusals: the plan keeps its end date');

-- ── A race plan repeats this week and keeps race day ──────────────────────

select isnt((select repeat_plan_week('c1c1c1c1-0000-0000-0000-0000000000a1', current_date,
      'c2c2c2c2-0000-0000-0000-0000a1000004', 'c2c2c2c2-0000-0000-0000-0000a1000005')),
  null, 'the race plan runs week 4 again and returns the new week');
select is((select array_agg(phase::text order by week_index) from plan_weeks where plan_id = 'c1c1c1c1-0000-0000-0000-0000000000a1'),
  array['base', 'base', 'build', 'build', 'build', 'build', 'peak', 'peak', 'taper', 'race'],
  'race plan: still ten weeks, the latest build week traded for the copy');
select is((select count(*)::int from plan_weeks where id = 'c2c2c2c2-0000-0000-0000-0000a1000005'),
  0, 'race plan: the dropped week is gone');
select is((select array_agg(wo.kind::text || '@' || (wo.scheduled_date - s) order by wo.scheduled_date)
           from plan_workouts wo join plan_weeks w on w.id = wo.week_id, rpw_s
           where w.plan_id = 'c1c1c1c1-0000-0000-0000-0000000000a1' and w.week_index = 5),
  array['long@35', 'easy@38'], 'race plan: week 4 runs again as week 5, on its weekdays');
select is((select target_hr_min_bpm::int || '-' || target_hr_max_bpm::int from plan_workouts wo join plan_weeks w on w.id = wo.week_id
           where w.plan_id = 'c1c1c1c1-0000-0000-0000-0000000000a1' and w.week_index = 5 and wo.kind = 'long'),
  '140-155', 'race plan: a consenting owner with the gate open keeps the heart-rate targets');
select is((select week_index::int from plan_weeks where id = 'c2c2c2c2-0000-0000-0000-0000a1000006'),
  6, 'race plan: the peak does not move');
select is((select scheduled_date from plan_workouts where id = 'c3c3c3c3-0000-0000-0000-a10901000000'),
  (select s + 63 from rpw_s), 'race plan: the race keeps its day');
select is((select end_date from training_plans where id = 'c1c1c1c1-0000-0000-0000-0000000000a1'),
  (select s + 63 from rpw_s), 'race plan: the end date holds');
select is((select count(*)::int from plan_workouts where week_id = 'c2c2c2c2-0000-0000-0000-0000a1000004'),
  2, 'race plan: the week itself stays as it was');
select is((select prefs -> 'plan_break_dismissed' from user_settings where user_id = 'c7c7c7c7-0000-0000-0000-00000000000a'),
  null, 'race plan: the break offer is not answered by a repeat');

-- ── A walk-run plan repeats this week and moves its end ───────────────────

set local "request.jwt.claims" = '{"sub":"c7c7c7c7-0000-0000-0000-00000000000b","role":"authenticated"}';
select throws_ok(
  $$select repeat_plan_week('c1c1c1c1-0000-0000-0000-0000000000b1', current_date,
      'c2c2c2c2-0000-0000-0000-0000b1000004', 'c2c2c2c2-0000-0000-0000-0000b1000005')$$,
  '22023', 'repeat_plan_week: a plan without a race drops no weeks',
  'a plan without a race drops nothing');
select isnt((select repeat_plan_week('c1c1c1c1-0000-0000-0000-0000000000b1', current_date,
      'c2c2c2c2-0000-0000-0000-0000b1000004')),
  null, 'the walk-run plan runs this week again');
select is((select array_agg(week_index::int order by week_index) from plan_weeks where plan_id = 'c1c1c1c1-0000-0000-0000-0000000000b1'),
  array[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10], 'walk-run: one week added');
select is((select array_agg(wo.kind::text || '@' || (wo.scheduled_date - s) order by wo.scheduled_date)
           from plan_workouts wo join plan_weeks w on w.id = wo.week_id, rpw_s
           where w.plan_id = 'c1c1c1c1-0000-0000-0000-0000000000b1' and w.week_index = 5),
  array['long@35', 'easy@38'], 'walk-run: this week runs again next week');
select is((select week_index::int || '@' || (wo.scheduled_date - s) from plan_workouts wo
           join plan_weeks w on w.id = wo.week_id, rpw_s
           where wo.id = 'c3c3c3c3-0000-0000-0000-b10901000000'),
  '10@70', 'walk-run: the last week and its workouts move back one');
select is((select end_date from training_plans where id = 'c1c1c1c1-0000-0000-0000-0000000000b1'),
  (select s + 76 from rpw_s), 'walk-run: the end date moves back a week');
select is((select count(*)::int from plan_workouts wo join plan_weeks w on w.id = wo.week_id
           where w.plan_id = 'c1c1c1c1-0000-0000-0000-0000000000b1' and w.week_index = 5
             and (wo.target_hr_min_bpm is not null or wo.manually_completed or wo.skipped_at is not null)),
  0, 'walk-run: the copy carries no completion, skip or heart-rate target');

-- ── Last week, the one that just finished ─────────────────────────────────

reset role;
update private.feature_flags set enabled = false where name = 'hr_prescription';
update plan_workouts set missed_ack_at = now() where id = 'c3c3c3c3-0000-0000-0000-d10701000000';
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"c7c7c7c7-0000-0000-0000-00000000000d","role":"authenticated"}';
select isnt((select repeat_plan_week('c1c1c1c1-0000-0000-0000-0000000000d1', current_date,
      'c2c2c2c2-0000-0000-0000-0000d1000003')),
  null, 'last week runs again');
select is((select count(*)::int from plan_workouts
           where week_id = 'c2c2c2c2-0000-0000-0000-0000d1000003' and missed_ack_at is not null),
  2, 'last week: its missed workouts are answered, since the copy restores them');
select is((select missed_ack_at from plan_workouts where id = 'c3c3c3c3-0000-0000-0000-d10701000000'),
  null, 'last week: a workout that moved loses its answer');
select is((select count(*)::int from plan_workouts wo join plan_weeks w on w.id = wo.week_id
           where w.plan_id = 'c1c1c1c1-0000-0000-0000-0000000000d1' and w.week_index = 5
             and wo.target_hr_min_bpm is not null),
  0, 'last week: with the heart-rate gate closed, a consenting owner''s copy carries no target');
reset role;
update private.feature_flags set enabled = true where name = 'hr_prescription';
set local role authenticated;
select is((select array_agg(wo.kind::text || '@' || (wo.scheduled_date - s) order by wo.scheduled_date)
           from plan_workouts wo join plan_weeks w on w.id = wo.week_id, rpw_s
           where w.plan_id = 'c1c1c1c1-0000-0000-0000-0000000000d1' and w.week_index = 5),
  array['long@35', 'easy@38'], 'last week: it goes in after this week, not inside it');
select is((select week_index::int from plan_weeks where id = 'c2c2c2c2-0000-0000-0000-0000d1000004'),
  4, 'last week: this week stays where it is');

-- ── A later end that runs into the next active plan ───────────────────────

set local "request.jwt.claims" = '{"sub":"c7c7c7c7-0000-0000-0000-00000000000e","role":"authenticated"}';
select throws_ok(
  $$select repeat_plan_week('c1c1c1c1-0000-0000-0000-0000000000e1', current_date,
      'c2c2c2c2-0000-0000-0000-0000e1000004')$$,
  '23P01', 'conflicting key value violates exclusion constraint "training_plans_active_no_overlap"',
  'a later end that runs into another active plan is refused');
select is((select count(*)::int || '/' || (max(tp.end_date) - min(s))
           from plan_weeks w join training_plans tp on tp.id = w.plan_id, rpw_s
           where w.plan_id = 'c1c1c1c1-0000-0000-0000-0000000000e1'),
  '10/69', 'overlap: no week was added and the end date holds');

-- ── The hourly cap ────────────────────────────────────────────────────────

set local "request.jwt.claims" = '{"sub":"c7c7c7c7-0000-0000-0000-00000000000f","role":"authenticated"}';
select lives_ok(
  $$ do $d$ begin
       for i in 1..20 loop
         perform public.repeat_plan_week('c1c1c1c1-0000-0000-0000-0000000000f1', current_date,
           'c2c2c2c2-0000-0000-0000-0000f1000004');
       end loop;
     end $d$ $$,
  'twenty repeats in an hour are allowed');
select is((select count(*)::int from plan_weeks where plan_id = 'c1c1c1c1-0000-0000-0000-0000000000f1'),
  30, 'each of them added a week');
select throws_like(
  $$select repeat_plan_week('c1c1c1c1-0000-0000-0000-0000000000f1', current_date,
      'c2c2c2c2-0000-0000-0000-0000f1000004')$$,
  'rate limit exceeded for repeat_plan_week%',
  'the twenty-first is refused');

-- ── reschedule_plan_after_break still answers its own way ─────────────────

select throws_ok(
  $$select reschedule_plan_after_break('c1c1c1c1-0000-0000-0000-0000000000f1', current_date, current_date - 10,
      array['c2c2c2c2-0000-0000-0000-0000f1000002']::uuid[], array['c2c2c2c2-0000-0000-0000-0000f1000005']::uuid[])$$,
  '22023', 'reschedule_plan_after_break: a plan without a race drops no weeks',
  'the break RPC keeps its own name on a refusal from the shared body');

select * from finish();
rollback;

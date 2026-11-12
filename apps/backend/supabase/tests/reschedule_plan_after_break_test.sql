-- Pins migration 20270923000001: reschedule_plan_after_break runs the latest
-- weeks again after a break of a week or more. Copies go in after the current
-- week; every later week moves back by whole weeks; a race plan drops as many
-- pre-taper weeks as it copies so race day holds, and a plan without a race
-- moves its end. The past, completed workouts, other races and other runners'
-- plans are never touched; every refusal writes nothing; the answered offer
-- is recorded in user_settings.prefs in the same transaction. A copied week
-- carries heart-rate targets only while the HR gate is open and the owner
-- consents.
--
-- Dates are relative to current_date because the RPC trusts the client's
-- today only within a day of the server's. S is the Sunday four weeks before
-- this week's Sunday, so weeks 0-3 are past and week 4 is under way.

begin;
select plan(60);

create temp table rpab_s as
  select (current_date - extract(dow from current_date)::integer - 28) as s;
grant select on rpab_s to authenticated;

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('b7b7b7b7-0000-0000-0000-00000000000a', 'authenticated', 'authenticated', 'rpab-a@rpab.local', '', now(), now()),
  ('b7b7b7b7-0000-0000-0000-00000000000b', 'authenticated', 'authenticated', 'rpab-b@rpab.local', '', now(), now()),
  ('b7b7b7b7-0000-0000-0000-00000000000c', 'authenticated', 'authenticated', 'rpab-c@rpab.local', '', now(), now()),
  ('b7b7b7b7-0000-0000-0000-00000000000d', 'authenticated', 'authenticated', 'rpab-d@rpab.local', '', now(), now()),
  ('b7b7b7b7-0000-0000-0000-00000000000e', 'authenticated', 'authenticated', 'rpab-e@rpab.local', '', now(), now()),
  ('b7b7b7b7-0000-0000-0000-00000000000f', 'authenticated', 'authenticated', 'rpab-f@rpab.local', '', now(), now())
on conflict (id) do nothing;
insert into user_profiles (id, display_name, health_data_consent_at) values
  ('b7b7b7b7-0000-0000-0000-00000000000a', 'RPAB A', now()),
  ('b7b7b7b7-0000-0000-0000-00000000000b', 'RPAB B', null),
  ('b7b7b7b7-0000-0000-0000-00000000000c', 'RPAB C', null),
  ('b7b7b7b7-0000-0000-0000-00000000000d', 'RPAB D', null),
  ('b7b7b7b7-0000-0000-0000-00000000000e', 'RPAB E', null),
  ('b7b7b7b7-0000-0000-0000-00000000000f', 'RPAB F', now())
on conflict (id) do update set health_data_consent_at = excluded.health_data_consent_at;

insert into private.feature_flags (name, enabled) values ('hr_prescription', true)
  on conflict (name) do update set enabled = true;

-- Ten-week plans. A race plan (r): base 0-1, build 2-5, peak 6-7, taper 8,
-- race 9 on its last Sunday, the end date. A plan without a race (w): every
-- week build, ending on week 9's Saturday. A long run every Sunday (weeks 0
-- and 1 done), an easy run every Wednesday, heart-rate targets on week 4's
-- long run.
--   a1 A race (active)   a2 A race (paused)   b1 B walk (active)
--   d1 D walk (active, a B race on week 7)   e1 E walk (active)
--   e2 E's next plan, active, starting the day after e1 ends
create temp table rpab_plans (tag text, owner text, shape text, status text);
insert into rpab_plans values
  ('a1', 'a', 'r', 'active'), ('a2', 'a', 'r', 'paused'), ('b1', 'b', 'w', 'active'),
  ('d1', 'd', 'w', 'active'), ('e1', 'e', 'w', 'active'), ('f1', 'f', 'w', 'active');

insert into training_plans (id, user_id, name, goal_event, goal_distance_m, start_date, end_date, days_per_week, status)
select ('b1b1b1b1-0000-0000-0000-0000000000' || p.tag)::uuid,
       ('b7b7b7b7-0000-0000-0000-00000000000' || p.owner)::uuid,
       'RPAB ' || p.tag, 'distance_half', 21097, s,
       s + case when p.shape = 'r' then 63 else 69 end, 4, p.status
from rpab_s, rpab_plans p;
insert into training_plans (id, user_id, name, goal_event, goal_distance_m, start_date, end_date, days_per_week, status)
select 'b1b1b1b1-0000-0000-0000-0000000000e2', 'b7b7b7b7-0000-0000-0000-00000000000e',
       'RPAB next', 'distance_half', 21097, s + 70, s + 140, 4, 'active'
from rpab_s;

insert into plan_weeks (id, plan_id, week_index, phase, target_volume_m)
select ('b2b2b2b2-0000-0000-0000-0000' || p.tag || lpad(i::text, 6, '0'))::uuid,
       ('b1b1b1b1-0000-0000-0000-0000000000' || p.tag)::uuid, i,
       (case when p.shape = 'w' then 'build'
             when i < 2 then 'base' when i < 6 then 'build' when i < 8 then 'peak'
             when i = 8 then 'taper' else 'race' end)::plan_phase,
       10000
from rpab_plans p, generate_series(0, 9) as i;

insert into plan_workouts (id, week_id, scheduled_date, kind, target_distance_m, manually_completed,
                           target_hr_min_bpm, target_hr_max_bpm)
select ('b3b3b3b3-0000-0000-0000-' || p.tag || lpad(i::text, 2, '0') || '01000000')::uuid,
       ('b2b2b2b2-0000-0000-0000-0000' || p.tag || lpad(i::text, 6, '0'))::uuid,
       s + 7 * i,
       (case when p.shape = 'r' and i = 9 then 'race'
             when p.tag = 'd1' and i = 7 then 'race' else 'long' end)::workout_kind,
       case when p.shape = 'r' and i = 9 then 21097 else 12000 end,
       i <= 1,
       case when i = 4 and p.owner in ('a', 'f') then 140 end,
       case when i = 4 and p.owner in ('a', 'f') then 155 end
from rpab_s, rpab_plans p, generate_series(0, 9) as i;
insert into plan_workouts (id, week_id, scheduled_date, kind, target_distance_m)
select ('b3b3b3b3-0000-0000-0000-' || p.tag || lpad(i::text, 2, '0') || '02000000')::uuid,
       ('b2b2b2b2-0000-0000-0000-0000' || p.tag || lpad(i::text, 6, '0'))::uuid,
       s + 7 * i + 3, 'easy', 6000
from rpab_s, rpab_plans p, generate_series(0, 9) as i
where not (p.shape = 'r' and i = 9);

set local role authenticated;

-- ── Who may call ───────────────────────────────────────────────────────────

select throws_ok(
  $$select reschedule_plan_after_break('b1b1b1b1-0000-0000-0000-0000000000a1', current_date, current_date - 20,
      array['b2b2b2b2-0000-0000-0000-0000a1000004']::uuid[], array['b2b2b2b2-0000-0000-0000-0000a1000005']::uuid[])$$,
  '42501', 'reschedule_plan_after_break: not authenticated', 'an unauthenticated caller is refused');

set local "request.jwt.claims" = '{"sub":"b7b7b7b7-0000-0000-0000-00000000000c","role":"authenticated"}';
select throws_ok(
  $$select reschedule_plan_after_break('b1b1b1b1-0000-0000-0000-0000000000a1', current_date, current_date - 20,
      array['b2b2b2b2-0000-0000-0000-0000a1000004']::uuid[], array['b2b2b2b2-0000-0000-0000-0000a1000005']::uuid[])$$,
  'P0002', 'reschedule_plan_after_break: plan b1b1b1b1-0000-0000-0000-0000000000a1 not found',
  'another runner''s plan is refused');

set local "request.jwt.claims" = '{"sub":"b7b7b7b7-0000-0000-0000-00000000000a","role":"authenticated"}';

create temp table rpab_before as
  select string_agg(w.week_index || ':' || wo.id || ':' || wo.scheduled_date, ',' order by wo.id) as fp
  from plan_workouts wo join plan_weeks w on w.id = wo.week_id
  where w.plan_id = 'b1b1b1b1-0000-0000-0000-0000000000a1';

-- ── Refusals, each writing nothing ─────────────────────────────────────────

select throws_ok(
  $$select reschedule_plan_after_break('b1b1b1b1-0000-0000-0000-0000000000a1', current_date - 3, current_date - 20,
      array['b2b2b2b2-0000-0000-0000-0000a1000004']::uuid[], array['b2b2b2b2-0000-0000-0000-0000a1000005']::uuid[])$$,
  '22023', 'reschedule_plan_after_break: today must be within a day of the server date',
  'a client today far from the server date is refused');

select throws_ok(
  $$select reschedule_plan_after_break('b1b1b1b1-0000-0000-0000-0000000000a1', current_date, current_date + 1,
      array['b2b2b2b2-0000-0000-0000-0000a1000004']::uuid[], array['b2b2b2b2-0000-0000-0000-0000a1000005']::uuid[])$$,
  '22023', 'reschedule_plan_after_break: the break must start on or before today',
  'a break starting after today is refused');

select throws_ok(
  $$select reschedule_plan_after_break('b1b1b1b1-0000-0000-0000-0000000000a1', current_date, current_date - 20, '{}')$$,
  '22023', 'reschedule_plan_after_break: repeat 1 to 52 weeks', 'repeating no week is refused');

select throws_ok(
  $$select reschedule_plan_after_break('b1b1b1b1-0000-0000-0000-0000000000a2', current_date, current_date - 20,
      array['b2b2b2b2-0000-0000-0000-0000a2000004']::uuid[], array['b2b2b2b2-0000-0000-0000-0000a2000005']::uuid[])$$,
  '22023', 'reschedule_plan_after_break: only an active plan that is under way',
  'a paused plan is refused (resuming handles it)');

select throws_ok(
  $$select reschedule_plan_after_break('b1b1b1b1-0000-0000-0000-0000000000a1', current_date, current_date - 20,
      array['b2b2b2b2-0000-0000-0000-0000a1000005']::uuid[], array['b2b2b2b2-0000-0000-0000-0000a1000006']::uuid[])$$,
  '22023', 'reschedule_plan_after_break: only pre-taper weeks up to this one can run again',
  'a week that has not started cannot be run again');

select throws_ok(
  $$select reschedule_plan_after_break('b1b1b1b1-0000-0000-0000-0000000000a1', current_date, current_date - 20,
      array['b2b2b2b2-0000-0000-0000-0000a1000004']::uuid[])$$,
  '22023', 'reschedule_plan_after_break: a race plan drops as many weeks as it repeats',
  'a race plan that would move its race day is refused');

select throws_ok(
  $$select reschedule_plan_after_break('b1b1b1b1-0000-0000-0000-0000000000a1', current_date, current_date - 20,
      array['b2b2b2b2-0000-0000-0000-0000a1000004']::uuid[], array['b2b2b2b2-0000-0000-0000-0000a1000008']::uuid[])$$,
  '22023', 'reschedule_plan_after_break: only pre-taper weeks that have not started can be dropped',
  'the taper is never dropped');

select throws_ok(
  $$select reschedule_plan_after_break('b1b1b1b1-0000-0000-0000-0000000000a1', current_date, current_date - 20,
      array['b2b2b2b2-0000-0000-0000-0000a1000004']::uuid[], array['b2b2b2b2-0000-0000-0000-0000a1000003']::uuid[])$$,
  '22023', 'reschedule_plan_after_break: only pre-taper weeks that have not started can be dropped',
  'a past week is never dropped');

update plan_workouts set manually_completed = true where id = 'b3b3b3b3-0000-0000-0000-a10501000000';
select throws_ok(
  $$select reschedule_plan_after_break('b1b1b1b1-0000-0000-0000-0000000000a1', current_date, current_date - 20,
      array['b2b2b2b2-0000-0000-0000-0000a1000004']::uuid[], array['b2b2b2b2-0000-0000-0000-0000a1000005']::uuid[])$$,
  '22023', 'reschedule_plan_after_break: a dropped week holds a race or a completed workout',
  'a week holding a completed workout is never dropped');
select throws_ok(
  $$select reschedule_plan_after_break('b1b1b1b1-0000-0000-0000-0000000000a1', current_date, current_date - 20,
      array['b2b2b2b2-0000-0000-0000-0000a1000004']::uuid[], array['b2b2b2b2-0000-0000-0000-0000a1000007']::uuid[])$$,
  '22023', 'reschedule_plan_after_break: a week that would move holds a race or a completed workout',
  'a completed workout in a week that would move is refused');
update plan_workouts set manually_completed = false where id = 'b3b3b3b3-0000-0000-0000-a10501000000';

select is((select fp from rpab_before),
  (select string_agg(w.week_index || ':' || wo.id || ':' || wo.scheduled_date, ',' order by wo.id)
   from plan_workouts wo join plan_weeks w on w.id = wo.week_id
   where w.plan_id = 'b1b1b1b1-0000-0000-0000-0000000000a1'),
  'refusals: no week, workout or date changed');
select is((select end_date from training_plans where id = 'b1b1b1b1-0000-0000-0000-0000000000a1'),
  (select s + 63 from rpab_s), 'refusals: the plan keeps its end date');
select is((select prefs -> 'plan_break_dismissed' from user_settings where user_id = 'b7b7b7b7-0000-0000-0000-00000000000a'),
  null, 'refusals: the offer is not recorded as answered');

-- ── A race plan runs two weeks again and keeps race day ───────────────────

-- A workout the runner skipped inside the break, and an answer already held
-- by a workout in a week that will move.
reset role;
update plan_workouts set skipped_at = now() where id = 'b3b3b3b3-0000-0000-0000-a10302000000';
update plan_workouts set missed_ack_at = now() where id = 'b3b3b3b3-0000-0000-0000-a10601000000';
set local role authenticated;

select lives_ok(
  $$select reschedule_plan_after_break('b1b1b1b1-0000-0000-0000-0000000000a1', current_date, (select s + 8 from rpab_s),
      array['b2b2b2b2-0000-0000-0000-0000a1000003', 'b2b2b2b2-0000-0000-0000-0000a1000004']::uuid[],
      array['b2b2b2b2-0000-0000-0000-0000a1000005', 'b2b2b2b2-0000-0000-0000-0000a1000007']::uuid[])$$,
  'the race plan runs weeks 3 and 4 again');

select is((select array_agg(week_index::int order by week_index) from plan_weeks where plan_id = 'b1b1b1b1-0000-0000-0000-0000000000a1'),
  array[0, 1, 2, 3, 4, 5, 6, 7, 8, 9], 'race plan: still ten weeks, indexed without a gap');
select is((select array_agg(phase::text order by week_index) from plan_weeks where plan_id = 'b1b1b1b1-0000-0000-0000-0000000000a1'),
  array['base', 'base', 'build', 'build', 'build', 'build', 'build', 'peak', 'taper', 'race'],
  'race plan: two build weeks copied in, the latest build and peak dropped, the taper kept');
select is((select count(*)::int from plan_weeks where id in ('b2b2b2b2-0000-0000-0000-0000a1000005', 'b2b2b2b2-0000-0000-0000-0000a1000007')),
  0, 'race plan: the dropped weeks are gone');
select is((select week_index::int from plan_weeks where id = 'b2b2b2b2-0000-0000-0000-0000a1000006'),
  7, 'race plan: the first peak week moves back one');
select is((select scheduled_date from plan_workouts where id = 'b3b3b3b3-0000-0000-0000-a10601000000'),
  (select s + 49 from rpab_s), 'race plan: its long run moves back a week with it');
select is((select week_index::int from plan_weeks where id = 'b2b2b2b2-0000-0000-0000-0000a1000008'),
  8, 'race plan: the taper stays where it was');
select is((select scheduled_date from plan_workouts where id = 'b3b3b3b3-0000-0000-0000-a10901000000'),
  (select s + 63 from rpab_s), 'race plan: the race keeps its day');
select is((select end_date from training_plans where id = 'b1b1b1b1-0000-0000-0000-0000000000a1'),
  (select s + 63 from rpab_s), 'race plan: the end date holds');
select is((select array_agg(scheduled_date order by scheduled_date) from plan_workouts wo join plan_weeks w on w.id = wo.week_id
           where w.plan_id = 'b1b1b1b1-0000-0000-0000-0000000000a1' and w.week_index = 5),
  (select array[s + 35, s + 38] from rpab_s), 'race plan: week 3 runs again in week 5, on its weekdays');
select is((select array_agg(wo.kind::text || ':' || wo.target_distance_m::int order by scheduled_date) from plan_workouts wo join plan_weeks w on w.id = wo.week_id
           where w.plan_id = 'b1b1b1b1-0000-0000-0000-0000000000a1' and w.week_index = 6),
  array['long:12000', 'easy:6000'], 'race plan: week 4 runs again in week 6');
select is((select target_hr_min_bpm::int || '-' || target_hr_max_bpm::int from plan_workouts wo join plan_weeks w on w.id = wo.week_id
           where w.plan_id = 'b1b1b1b1-0000-0000-0000-0000000000a1' and w.week_index = 6 and wo.kind = 'long'),
  '140-155', 'race plan: a consenting owner with the gate open keeps the heart-rate targets');
select is((select count(*)::int from plan_workouts wo join plan_weeks w on w.id = wo.week_id
           where w.plan_id = 'b1b1b1b1-0000-0000-0000-0000000000a1' and w.week_index in (5, 6)
             and (wo.manually_completed or wo.completed_run_id is not null or wo.skipped_at is not null)),
  0, 'race plan: the copies carry no completion or skip');
select is((select week_index::int from plan_weeks where id = 'b2b2b2b2-0000-0000-0000-0000a1000004'),
  4, 'race plan: the current week stays where it is');
select is((select array_agg(scheduled_date order by id) from plan_workouts
           where id in ('b3b3b3b3-0000-0000-0000-a10001000000', 'b3b3b3b3-0000-0000-0000-a10101000000')),
  (select array[s, s + 7] from rpab_s), 'race plan: the past and its completed workouts never move');
select is((select manually_completed from plan_workouts where id = 'b3b3b3b3-0000-0000-0000-a10101000000'),
  true, 'race plan: a completed workout stays completed');
select is((select prefs -> 'plan_break_dismissed' from user_settings where user_id = 'b7b7b7b7-0000-0000-0000-00000000000a'),
  (select jsonb_build_object('plan_id', 'b1b1b1b1-0000-0000-0000-0000000000a1', 'from', s + 8, 'until', current_date) from rpab_s),
  'race plan: the offer is recorded as answered for this break, with its last day');
create temp table rpab_missed as
  select wo.id, wo.missed_ack_at
  from plan_workouts wo join plan_weeks w on w.id = wo.week_id, rpab_s
  where w.plan_id = 'b1b1b1b1-0000-0000-0000-0000000000a1' and w.week_index <= 4
    and wo.scheduled_date >= s + 8 and wo.scheduled_date < current_date
    and wo.kind <> 'rest' and wo.completed_run_id is null and not wo.manually_completed
    and wo.skipped_at is null;
select ok((select count(*) from rpab_missed) >= 4, 'missed: the break covered at least four open workouts');
select is((select count(*)::int from rpab_missed where missed_ack_at is null),
  0, 'missed: every open workout the break covered is answered');
select is((select missed_ack_at from plan_workouts where id = 'b3b3b3b3-0000-0000-0000-a10302000000'),
  null, 'missed: a workout the runner skipped is not answered for them');
select is((select missed_ack_at from plan_workouts where id = 'b3b3b3b3-0000-0000-0000-a10101000000'),
  null, 'missed: a done workout before the break is not answered');
select is((select count(*)::int from plan_workouts wo join plan_weeks w on w.id = wo.week_id
           where w.plan_id = 'b1b1b1b1-0000-0000-0000-0000000000a1' and w.week_index = 4
             and wo.scheduled_date >= current_date and wo.missed_ack_at is not null),
  0, 'missed: nothing dated today or later is answered');
select is((select count(*)::int from plan_workouts wo join plan_weeks w on w.id = wo.week_id
           where w.plan_id = 'b1b1b1b1-0000-0000-0000-0000000000a1' and w.week_index in (5, 6)
             and wo.missed_ack_at is not null),
  0, 'missed: the copies start unanswered');
select is((select missed_ack_at from plan_workouts where id = 'b3b3b3b3-0000-0000-0000-a10601000000'),
  null, 'missed: a workout that moved loses the answer it held');
select is((select end_date from training_plans where id = 'b1b1b1b1-0000-0000-0000-0000000000a2'),
  (select s + 63 from rpab_s), 'race plan: the owner''s other plan is untouched');

-- ── A plan without a race moves its end back ──────────────────────────────

set local "request.jwt.claims" = '{"sub":"b7b7b7b7-0000-0000-0000-00000000000b","role":"authenticated"}';

select throws_ok(
  $$select reschedule_plan_after_break('b1b1b1b1-0000-0000-0000-0000000000b1', current_date, current_date - 10,
      array['b2b2b2b2-0000-0000-0000-0000b1000004']::uuid[], array['b2b2b2b2-0000-0000-0000-0000b1000005']::uuid[])$$,
  '22023', 'reschedule_plan_after_break: a plan without a race drops no weeks',
  'a plan without a race drops nothing');

select lives_ok(
  $$select reschedule_plan_after_break('b1b1b1b1-0000-0000-0000-0000000000b1', current_date, current_date - 10,
      array['b2b2b2b2-0000-0000-0000-0000b1000004']::uuid[])$$,
  'the plan without a race runs this week again');
select is((select array_agg(week_index::int order by week_index) from plan_weeks where plan_id = 'b1b1b1b1-0000-0000-0000-0000000000b1'),
  array[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10], 'no race: one week added');
select is((select week_index::int from plan_weeks where id = 'b2b2b2b2-0000-0000-0000-0000b1000009'),
  10, 'no race: the last week moves back one');
select is((select scheduled_date from plan_workouts where id = 'b3b3b3b3-0000-0000-0000-b10902000000'),
  (select s + 73 from rpab_s), 'no race: its workouts move back a week');
select is((select end_date from training_plans where id = 'b1b1b1b1-0000-0000-0000-0000000000b1'),
  (select s + 76 from rpab_s), 'no race: the end date moves back a week');
select is((select array_agg(scheduled_date order by scheduled_date) from plan_workouts wo join plan_weeks w on w.id = wo.week_id
           where w.plan_id = 'b1b1b1b1-0000-0000-0000-0000000000b1' and w.week_index = 5),
  (select array[s + 35, s + 38] from rpab_s), 'no race: this week runs again next week');
select is((select count(*)::int from plan_workouts wo join plan_weeks w on w.id = wo.week_id
           where w.plan_id = 'b1b1b1b1-0000-0000-0000-0000000000b1' and w.week_index = 5
             and (wo.target_hr_min_bpm is not null or wo.target_hr_max_bpm is not null)),
  0, 'no race: without health-data consent the copy carries no heart-rate target');
select is((select prefs -> 'plan_break_dismissed' ->> 'plan_id' from user_settings where user_id = 'b7b7b7b7-0000-0000-0000-00000000000b'),
  'b1b1b1b1-0000-0000-0000-0000000000b1', 'no race: a runner with no settings row gets one with the answer');

-- ── A B race in a week that would move ────────────────────────────────────

set local "request.jwt.claims" = '{"sub":"b7b7b7b7-0000-0000-0000-00000000000d","role":"authenticated"}';
select throws_ok(
  $$select reschedule_plan_after_break('b1b1b1b1-0000-0000-0000-0000000000d1', current_date, current_date - 10,
      array['b2b2b2b2-0000-0000-0000-0000d1000004']::uuid[])$$,
  '22023', 'reschedule_plan_after_break: a week that would move holds a race or a completed workout',
  'another race in a week that would move is refused');
select is((select scheduled_date from plan_workouts where id = 'b3b3b3b3-0000-0000-0000-d10701000000'),
  (select s + 49 from rpab_s), 'B race: it keeps its day');
select is((select count(*)::int from plan_weeks where plan_id = 'b1b1b1b1-0000-0000-0000-0000000000d1'),
  10, 'B race: no week was added');

-- ── A later end that runs into the next active plan ───────────────────────

set local "request.jwt.claims" = '{"sub":"b7b7b7b7-0000-0000-0000-00000000000e","role":"authenticated"}';
select throws_ok(
  $$select reschedule_plan_after_break('b1b1b1b1-0000-0000-0000-0000000000e1', current_date, current_date - 10,
      array['b2b2b2b2-0000-0000-0000-0000e1000004']::uuid[])$$,
  '23P01', 'conflicting key value violates exclusion constraint "training_plans_active_no_overlap"',
  'a later end that runs into another active plan is refused');
select is((select count(*)::int from plan_weeks where plan_id = 'b1b1b1b1-0000-0000-0000-0000000000e1'),
  10, 'overlap: no week was added');
select is((select end_date from training_plans where id = 'b1b1b1b1-0000-0000-0000-0000000000e1'),
  (select s + 69 from rpab_s), 'overlap: the plan keeps its end date');
select is((select prefs -> 'plan_break_dismissed' from user_settings where user_id = 'b7b7b7b7-0000-0000-0000-00000000000e'),
  null, 'overlap: the offer is not recorded as answered');

-- ── The HR gate shut, consent given ───────────────────────────────────────

reset role;
update private.feature_flags set enabled = false where name = 'hr_prescription';
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"b7b7b7b7-0000-0000-0000-00000000000f","role":"authenticated"}';
select lives_ok(
  $$select reschedule_plan_after_break('b1b1b1b1-0000-0000-0000-0000000000f1', current_date, current_date - 10,
      array['b2b2b2b2-0000-0000-0000-0000f1000004']::uuid[])$$,
  'a consenting runner with the HR gate shut can still run a week again');
select is((select count(*)::int from plan_workouts wo join plan_weeks w on w.id = wo.week_id
           where w.plan_id = 'b1b1b1b1-0000-0000-0000-0000000000f1' and w.week_index = 5
             and (wo.target_hr_min_bpm is not null or wo.target_hr_max_bpm is not null)),
  0, 'gate shut: the copy carries no heart-rate target despite consent');
select is((select target_hr_min_bpm::int from plan_workouts where id = 'b3b3b3b3-0000-0000-0000-f10401000000'),
  140, 'gate shut: the week copied keeps its own targets');
select is((select prefs -> 'plan_break_dismissed' from user_settings where user_id = 'b7b7b7b7-0000-0000-0000-00000000000f'),
  jsonb_build_object('plan_id', 'b1b1b1b1-0000-0000-0000-0000000000f1', 'from', current_date - 10, 'until', current_date),
  'gate shut: the offer is recorded as answered for this break, with its last day');

select * from finish();
rollback;

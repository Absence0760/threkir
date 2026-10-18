-- Pins migration 20270919000001: change_plan_race_date re-anchors the weeks
-- still ahead on a new race date. An earlier race drops pre-taper weeks and
-- keeps the taper; a later race repeats a build week; the past, completed
-- workouts, other races and other runners' plans are never touched; a date
-- the plan cannot reach with its taper intact, or one that runs into another
-- active plan, is refused with nothing written. A repeated week carries its
-- heart-rate targets only while the HR gate is open and the owner consents.
--
-- Dates are relative to current_date because the RPC trusts the client's
-- today only within a day of the server's. S is the Sunday two weeks before
-- this week's Sunday, so weeks 0 and 1 are past and week 2 is under way.

begin;
select plan(55);

create temp table cprd_s as
  select (current_date - extract(dow from current_date)::integer - 14) as s;
grant select on cprd_s to authenticated;

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('c7c7c7c7-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'cprd-owner@cprd.local', '', now(), now()),
  ('c7c7c7c7-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'cprd-other@cprd.local', '', now(), now())
on conflict (id) do nothing;
insert into user_profiles (id, display_name, health_data_consent_at) values
  ('c7c7c7c7-0000-0000-0000-000000000001', 'CPRD Owner', now()),
  ('c7c7c7c7-0000-0000-0000-000000000002', 'CPRD Other', null)
on conflict (id) do update set health_data_consent_at = excluded.health_data_consent_at;

insert into private.feature_flags (name, enabled) values ('hr_prescription', true)
  on conflict (name) do update set enabled = true;

-- Ten-week half-marathon plans of one shape. Phases: base 0-1, build 2-5,
-- peak 6-7, taper 8, race 9; a long run every Sunday (week 0's done), a tempo
-- on week 3's Tuesday, the race on week 9's Sunday and six easy days after it.
--   00a earlier (paused)       00b later, HR gate shut (paused)
--   00c ended early (paused)   00d overlap (active; 00e queued after it)
--   0a1 same-week move         0a2 later, HR gate open (paused)
-- 0a3 has the same shape but started 64 days ago, so its race week began
-- yesterday and its race (yesterday) is already behind.
create temp table cprd_plans (tag text, status text, trimmed timestamptz, start_offset integer);
insert into cprd_plans values
  ('00a', 'paused', null, 0), ('00b', 'paused', null, 0), ('00c', 'paused', now(), 0),
  ('00d', 'active', null, 0), ('0a1', 'paused', null, 0), ('0a2', 'paused', null, 0),
  ('0a3', 'paused', null, null);

insert into training_plans (id, user_id, name, goal_event, goal_distance_m, start_date, end_date, days_per_week, status, trimmed_at)
select ('c1c1c1c1-0000-0000-0000-000000000' || p.tag)::uuid, 'c7c7c7c7-0000-0000-0000-000000000001',
       'CPRD ' || p.tag, 'distance_half', 21097, st, st + 69, 4, p.status, p.trimmed
from cprd_s, cprd_plans p,
     lateral (select coalesce(s + p.start_offset, current_date - 64) as st) x;
insert into training_plans (id, user_id, name, goal_event, goal_distance_m, start_date, end_date, days_per_week, status)
select 'c1c1c1c1-0000-0000-0000-00000000000e', 'c7c7c7c7-0000-0000-0000-000000000001',
       'CPRD queued', 'distance_full', 42195, s + 75, s + 180, 4, 'active'
from cprd_s;

insert into plan_weeks (id, plan_id, week_index, phase, target_volume_m)
select ('c2c2c2c2-0000-0000-0000-00000' || p.tag || lpad(i::text, 4, '0'))::uuid,
       ('c1c1c1c1-0000-0000-0000-000000000' || p.tag)::uuid, i,
       (case when i < 2 then 'base' when i < 6 then 'build' when i < 8 then 'peak'
             when i = 8 then 'taper' else 'race' end)::plan_phase,
       10000
from cprd_plans p, generate_series(0, 9) as i;

insert into plan_workouts (id, week_id, scheduled_date, kind, target_distance_m, manually_completed,
                           target_hr_min_bpm, target_hr_max_bpm)
select ('c3c3c3c3-0000-0000-0000-00' || p.tag || lpad(i::text, 2, '0') || '00000')::uuid,
       ('c2c2c2c2-0000-0000-0000-00000' || p.tag || lpad(i::text, 4, '0'))::uuid,
       t.start_date + 7 * i,
       (case when i = 9 then 'race' else 'long' end)::workout_kind,
       case when i = 9 then 21097 else 12000 end,
       i = 0,
       case when i = 5 and p.tag in ('00b', '0a2') then 140 end,
       case when i = 5 and p.tag in ('00b', '0a2') then 155 end
from cprd_plans p
join training_plans t on t.id = ('c1c1c1c1-0000-0000-0000-000000000' || p.tag)::uuid,
     generate_series(0, 9) as i;
insert into plan_workouts (id, week_id, scheduled_date, kind, target_distance_m)
select ('c3c3c3c3-0000-0000-0000-00' || p.tag || '0300002')::uuid,
       ('c2c2c2c2-0000-0000-0000-00000' || p.tag || '0003')::uuid,
       t.start_date + 23, 'tempo', 8000
from cprd_plans p
join training_plans t on t.id = ('c1c1c1c1-0000-0000-0000-000000000' || p.tag)::uuid;
insert into plan_workouts (id, week_id, scheduled_date, kind, target_distance_m)
select ('c3c3c3c3-0000-0000-0000-00' || p.tag || '090000' || d)::uuid,
       ('c2c2c2c2-0000-0000-0000-00000' || p.tag || '0009')::uuid,
       t.start_date + 63 + d, 'easy', 5000
from cprd_plans p
join training_plans t on t.id = ('c1c1c1c1-0000-0000-0000-000000000' || p.tag)::uuid,
     generate_series(1, 6) as d;

set local role authenticated;

-- ── Who may call ───────────────────────────────────────────────────────────

select throws_ok(
  $$select change_plan_race_date('c1c1c1c1-0000-0000-0000-00000000000a', (select s + 52 from cprd_s), current_date)$$,
  '42501', 'change_plan_race_date: not authenticated', 'an unauthenticated caller is refused');

set local "request.jwt.claims" = '{"sub":"c7c7c7c7-0000-0000-0000-000000000002","role":"authenticated"}';
select throws_ok(
  $$select change_plan_race_date('c1c1c1c1-0000-0000-0000-00000000000a', (select s + 52 from cprd_s), current_date,
      array['c2c2c2c2-0000-0000-0000-0000000a0005', 'c2c2c2c2-0000-0000-0000-0000000a0004']::uuid[])$$,
  'P0002', null, 'another runner''s plan is refused');

set local "request.jwt.claims" = '{"sub":"c7c7c7c7-0000-0000-0000-000000000001","role":"authenticated"}';

-- ── Refusals, each writing nothing ─────────────────────────────────────────

select throws_ok(
  $$select change_plan_race_date('c1c1c1c1-0000-0000-0000-00000000000c', (select s + 70 from cprd_s), current_date,
      '{}', 9, 1, 'c2c2c2c2-0000-0000-0000-0000000c0005')$$,
  '22023', 'change_plan_race_date: only an active or paused plan that still ends on its race',
  'a plan ended early has no race to move');

select throws_ok(
  $$select change_plan_race_date('c1c1c1c1-0000-0000-0000-00000000000a', (select s + 21 from cprd_s), current_date,
      array['c2c2c2c2-0000-0000-0000-0000000a0003', 'c2c2c2c2-0000-0000-0000-0000000a0004',
            'c2c2c2c2-0000-0000-0000-0000000a0005', 'c2c2c2c2-0000-0000-0000-0000000a0006',
            'c2c2c2c2-0000-0000-0000-0000000a0007']::uuid[],
      null, 0, null, 'c3c3c3c3-0000-0000-0000-0000a0900000')$$,
  '22023', null, 'a race too close for the taper is refused even with the whole build cut');

select throws_ok(
  $$select change_plan_race_date('c1c1c1c1-0000-0000-0000-00000000000a', (select s + 52 from cprd_s), current_date,
      array['c2c2c2c2-0000-0000-0000-0000000a0008', 'c2c2c2c2-0000-0000-0000-0000000a0005']::uuid[],
      null, 0, null, 'c3c3c3c3-0000-0000-0000-0000a0900000')$$,
  '22023', 'change_plan_race_date: only pre-taper weeks that have not started can be dropped',
  'the taper week is never dropped');

select throws_ok(
  $$select change_plan_race_date('c1c1c1c1-0000-0000-0000-00000000000a', (select s + 52 from cprd_s), current_date,
      array['c2c2c2c2-0000-0000-0000-0000000a0001', 'c2c2c2c2-0000-0000-0000-0000000a0005']::uuid[],
      null, 0, null, 'c3c3c3c3-0000-0000-0000-0000a0900000')$$,
  '22023', 'change_plan_race_date: only pre-taper weeks that have not started can be dropped',
  'a past week is never dropped');

select throws_ok(
  $$select change_plan_race_date('c1c1c1c1-0000-0000-0000-00000000000a', current_date, current_date)$$,
  '22023', 'change_plan_race_date: the race date must be after today', 'a race today or past is refused');

select throws_ok(
  $$select change_plan_race_date('c1c1c1c1-0000-0000-0000-00000000000a', (select s + 52 from cprd_s), current_date - 3)$$,
  '22023', 'change_plan_race_date: today must be within a day of the server date',
  'a client today far from the server date is refused');

select throws_ok(
  $$select change_plan_race_date('c1c1c1c1-0000-0000-0000-00000000000a', (select s + 52 from cprd_s), current_date,
      array['c2c2c2c2-0000-0000-0000-0000000a0005']::uuid[], 6, 1, 'c2c2c2c2-0000-0000-0000-0000000a0004')$$,
  '22023', 'change_plan_race_date: weeks are either dropped or inserted, not both',
  'dropping and inserting at once is refused');

update plan_workouts set manually_completed = true where id = 'c3c3c3c3-0000-0000-0000-0000a0600000';
select throws_ok(
  $$select change_plan_race_date('c1c1c1c1-0000-0000-0000-00000000000a', (select s + 52 from cprd_s), current_date,
      array['c2c2c2c2-0000-0000-0000-0000000a0005', 'c2c2c2c2-0000-0000-0000-0000000a0004']::uuid[],
      null, 0, null, 'c3c3c3c3-0000-0000-0000-0000a0900000')$$,
  '22023', 'change_plan_race_date: a week that would move holds another race or a completed workout',
  'a completed workout in a week that would move is refused');
update plan_workouts set manually_completed = false where id = 'c3c3c3c3-0000-0000-0000-0000a0600000';

update plan_workouts set kind = 'race', race_priority = 'B' where id = 'c3c3c3c3-0000-0000-0000-0000a0700000';
select throws_ok(
  $$select change_plan_race_date('c1c1c1c1-0000-0000-0000-00000000000a', (select s + 52 from cprd_s), current_date,
      array['c2c2c2c2-0000-0000-0000-0000000a0005', 'c2c2c2c2-0000-0000-0000-0000000a0004']::uuid[],
      null, 0, null, 'c3c3c3c3-0000-0000-0000-0000a0900000')$$,
  '22023', 'change_plan_race_date: a week that would move holds another race or a completed workout',
  'another race in a week that would move is refused');
update plan_workouts set kind = 'long', race_priority = null where id = 'c3c3c3c3-0000-0000-0000-0000a0700000';

select is((select count(*)::int from plan_weeks where plan_id = 'c1c1c1c1-0000-0000-0000-00000000000a'),
  10, 'refusals: every week is still there');
select is((select array_agg(week_index::int order by week_index) from plan_weeks where plan_id = 'c1c1c1c1-0000-0000-0000-00000000000a'),
  array[0, 1, 2, 3, 4, 5, 6, 7, 8, 9], 'refusals: no week is re-indexed');
select is((select count(*)::int from plan_workouts wo join plan_weeks w on w.id = wo.week_id
           where w.plan_id = 'c1c1c1c1-0000-0000-0000-00000000000a'),
  17, 'refusals: every workout is still there');
select is((select scheduled_date from plan_workouts where id = 'c3c3c3c3-0000-0000-0000-0000a0900000'),
  (select s + 63 from cprd_s), 'refusals: the race keeps its day');
select is((select end_date from training_plans where id = 'c1c1c1c1-0000-0000-0000-00000000000a'),
  (select s + 69 from cprd_s), 'refusals: the plan keeps its end date');

-- ── A later race that runs into a queued active plan ──────────────────────

select throws_ok(
  $$select change_plan_race_date('c1c1c1c1-0000-0000-0000-00000000000d', (select s + 77 from cprd_s), current_date,
      '{}', 6, 2, 'c2c2c2c2-0000-0000-0000-0000000d0005', 'c3c3c3c3-0000-0000-0000-0000d0900000')$$,
  '23P01', null, 'a later race that runs into another active plan is refused');
select is((select count(*)::int from plan_weeks where plan_id = 'c1c1c1c1-0000-0000-0000-00000000000d'),
  10, 'overlap: no week was inserted');
select is((select count(*)::int from plan_workouts wo join plan_weeks w on w.id = wo.week_id
           where w.plan_id = 'c1c1c1c1-0000-0000-0000-00000000000d'),
  17, 'overlap: no workout was added or removed');
select is((select scheduled_date from plan_workouts where id = 'c3c3c3c3-0000-0000-0000-0000d0900000'),
  (select s + 63 from cprd_s), 'overlap: the race keeps its day');
select is((select end_date from training_plans where id = 'c1c1c1c1-0000-0000-0000-00000000000d'),
  (select s + 69 from cprd_s), 'overlap: the plan keeps its end date');

-- ── Earlier: two weeks and two days forward to week 7's Friday ────────────

select lives_ok(
  $$select change_plan_race_date('c1c1c1c1-0000-0000-0000-00000000000a', (select s + 52 from cprd_s), current_date,
      array['c2c2c2c2-0000-0000-0000-0000000a0005', 'c2c2c2c2-0000-0000-0000-0000000a0004']::uuid[],
      null, 0, null, 'c3c3c3c3-0000-0000-0000-0000a0900000')$$,
  'the owner moves the race earlier, dropping two build weeks');
select is((select end_date from training_plans where id = 'c1c1c1c1-0000-0000-0000-00000000000a'),
  (select s + 52 from cprd_s), 'the plan ends on the new race date');
select is((select array_agg(phase::text order by week_index) from plan_weeks where plan_id = 'c1c1c1c1-0000-0000-0000-00000000000a'),
  array['base', 'base', 'build', 'build', 'peak', 'peak', 'taper', 'race'], 'the build loses two weeks, the taper none');
select is((select array_agg(week_index::int order by week_index) from plan_weeks where plan_id = 'c1c1c1c1-0000-0000-0000-00000000000a'),
  array[0, 1, 2, 3, 4, 5, 6, 7], 'the weeks are re-indexed without a gap');
select is((select scheduled_date from plan_workouts where id = 'c3c3c3c3-0000-0000-0000-0000a0900000'),
  (select s + 52 from cprd_s), 'the race lands on the new day');
select is((select scheduled_date from plan_workouts where id = 'c3c3c3c3-0000-0000-0000-0000a0900003'),
  (select s + 49 from cprd_s), 'the run on race day takes the race''s old day, which is still ahead');
select is((select count(*)::int from plan_workouts
           where week_id = 'c2c2c2c2-0000-0000-0000-0000000a0009' and scheduled_date > (select s + 52 from cprd_s)),
  0, 'nothing is left after race day');
select is((select scheduled_date from plan_workouts where id = 'c3c3c3c3-0000-0000-0000-0000a0000000'),
  (select s from cprd_s), 'the completed week-0 run keeps its day');
select is((select scheduled_date from plan_workouts where id = 'c3c3c3c3-0000-0000-0000-0000a0300002'),
  (select s + 23 from cprd_s), 'a week before the dropped ones keeps its dates');
select is((select week_index::int from plan_weeks where id = 'c2c2c2c2-0000-0000-0000-0000000a0002'),
  2, 'the current week keeps its index');
select is((select target_volume_m::int from plan_weeks where id = 'c2c2c2c2-0000-0000-0000-0000000a0009'),
  (select sum(target_distance_m)::int from plan_workouts where week_id = 'c2c2c2c2-0000-0000-0000-0000000a0009'),
  'the race week''s volume is restated');

-- ── Same week: the race moves two days later inside race week ─────────────

select lives_ok(
  $$select change_plan_race_date('c1c1c1c1-0000-0000-0000-0000000000a1', (select s + 65 from cprd_s), current_date,
      '{}', null, 0, null, 'c3c3c3c3-0000-0000-0000-000a10900000')$$,
  'the owner moves the race inside its week');
select is((select scheduled_date from plan_workouts where id = 'c3c3c3c3-0000-0000-0000-000a10900000'),
  (select s + 65 from cprd_s), 'the race is on the new day');
select is((select scheduled_date from plan_workouts where id = 'c3c3c3c3-0000-0000-0000-000a10900002'),
  (select s + 63 from cprd_s), 'the run it displaced takes its old day');
select is((select count(*)::int from plan_workouts wo join plan_weeks w on w.id = wo.week_id
           where w.plan_id = 'c1c1c1c1-0000-0000-0000-0000000000a1' and w.week_index < 9
             and wo.scheduled_date <> (select s from cprd_s) + 7 * w.week_index + case when wo.kind = 'tempo' then 2 else 0 end),
  0, 'no other week moves');
select is((select array_agg(week_index::int order by week_index) from plan_weeks where plan_id = 'c1c1c1c1-0000-0000-0000-0000000000a1'),
  array[0, 1, 2, 3, 4, 5, 6, 7, 8, 9], 'no week is added or dropped');
select is((select end_date from training_plans where id = 'c1c1c1c1-0000-0000-0000-0000000000a1'),
  (select s + 65 from cprd_s), 'the plan ends on race day');

-- ── Race week under way: the race (yesterday) goes to a later day ─────────

select lives_ok(
  $$select change_plan_race_date('c1c1c1c1-0000-0000-0000-0000000000a3', current_date + 3, current_date,
      '{}', null, 0, null, 'c3c3c3c3-0000-0000-0000-000a30900000')$$,
  'a race whose old day has passed moves to a later day of its week');
select is((select scheduled_date from plan_workouts where id = 'c3c3c3c3-0000-0000-0000-000a30900000'),
  current_date + 3, 'the race is on the new day');
select is((select count(*)::int from plan_workouts where id = 'c3c3c3c3-0000-0000-0000-000a30900004'),
  0, 'the run on the new day is removed rather than moved into the past');
select is((select scheduled_date from plan_workouts where id = 'c3c3c3c3-0000-0000-0000-000a30900001'),
  current_date, 'today''s run stays');

-- ── Later, HR gate shut: the repeated week drops its heart-rate targets ───

reset role;
update private.feature_flags set enabled = false where name = 'hr_prescription';
set local role authenticated;

select lives_ok(
  $$select change_plan_race_date('c1c1c1c1-0000-0000-0000-00000000000b', (select s + 77 from cprd_s), current_date,
      '{}', 6, 2, 'c2c2c2c2-0000-0000-0000-0000000b0005', 'c3c3c3c3-0000-0000-0000-0000b0900000')$$,
  'with the HR gate shut a later race still applies');
select is((select end_date from training_plans where id = 'c1c1c1c1-0000-0000-0000-00000000000b'),
  (select s + 77 from cprd_s), 'the plan ends on the later race date');
select is((select array_agg(phase::text order by week_index) from plan_weeks where plan_id = 'c1c1c1c1-0000-0000-0000-00000000000b'),
  array['base', 'base', 'build', 'build', 'build', 'build', 'build', 'build', 'peak', 'peak', 'taper', 'race'],
  'two build weeks go in before the peak, the taper is unchanged');
select is((select array_agg(week_index::int order by week_index) from plan_weeks where plan_id = 'c1c1c1c1-0000-0000-0000-00000000000b'),
  array[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11], 'the weeks are indexed without a gap');
select is((select scheduled_date from plan_workouts where id = 'c3c3c3c3-0000-0000-0000-0000b0900000'),
  (select s + 77 from cprd_s), 'the race moves with its week');
select is((select count(*)::int from plan_workouts wo join plan_weeks w on w.id = wo.week_id
           where w.plan_id = 'c1c1c1c1-0000-0000-0000-00000000000b' and w.week_index in (6, 7) and wo.kind = 'long'),
  2, 'each inserted week repeats the build week''s long run');
select is((select count(*)::int from plan_workouts wo join plan_weeks w on w.id = wo.week_id
           where w.plan_id = 'c1c1c1c1-0000-0000-0000-00000000000b' and w.week_index in (6, 7)
             and (wo.target_hr_min_bpm is not null or wo.target_hr_max_bpm is not null)),
  0, 'the repeated weeks carry no heart-rate target');
select is((select target_hr_max_bpm::int from plan_workouts where id = 'c3c3c3c3-0000-0000-0000-0000b0500000'),
  155, 'the source week keeps its own');

-- ── Later, HR gate open with consent: the targets are repeated too ────────

reset role;
update private.feature_flags set enabled = true where name = 'hr_prescription';
set local role authenticated;

select lives_ok(
  $$select change_plan_race_date('c1c1c1c1-0000-0000-0000-0000000000a2', (select s + 77 from cprd_s), current_date,
      '{}', 6, 2, 'c2c2c2c2-0000-0000-0000-000000a20005', 'c3c3c3c3-0000-0000-0000-000a20900000')$$,
  'with the HR gate open and consent a later race applies');
select is((select count(*)::int from plan_workouts wo join plan_weeks w on w.id = wo.week_id
           where w.plan_id = 'c1c1c1c1-0000-0000-0000-0000000000a2' and w.week_index in (6, 7)
             and wo.target_hr_min_bpm = 140 and wo.target_hr_max_bpm = 155),
  2, 'the repeated weeks carry the heart-rate target');

-- ── Invariants across every plan that changed ─────────────────────────────

select is((select count(*)::int from plan_workouts wo join plan_weeks w on w.id = wo.week_id
           join training_plans p on p.id = w.plan_id
           where p.user_id = 'c7c7c7c7-0000-0000-0000-000000000001'
             and (wo.scheduled_date < p.start_date + 7 * w.week_index
                  or wo.scheduled_date > p.start_date + 7 * w.week_index + 6)),
  0, 'every workout is still inside its week');
select is((select count(*)::int from (
             select wo.week_id, wo.scheduled_date from plan_workouts wo join plan_weeks w on w.id = wo.week_id
             join training_plans p on p.id = w.plan_id
             where p.user_id = 'c7c7c7c7-0000-0000-0000-000000000001'
             group by 1, 2 having count(*) > 1) d),
  0, 'one workout per day still holds');
select is((select count(*)::int from training_plans p
           where p.user_id = 'c7c7c7c7-0000-0000-0000-000000000001'
             and p.end_date < (select max(wo.scheduled_date) from plan_workouts wo join plan_weeks w on w.id = wo.week_id where w.plan_id = p.id)),
  0, 'no plan holds a workout past its end date');

select * from finish();
rollback;

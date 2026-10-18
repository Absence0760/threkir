-- Pins migration 20270919000001: change_plan_race_date re-anchors the weeks
-- still ahead on a new race date. An earlier race drops pre-taper weeks and
-- keeps the taper; a later race repeats a build week; the past, completed
-- workouts and other runners' plans are never touched; a date the plan cannot
-- reach with its taper intact is refused with nothing written.
--
-- Dates are relative to current_date because the RPC trusts the client's
-- today only within a day of the server's. S is the Sunday two weeks before
-- this week's Sunday, so weeks 0 and 1 are past and week 2 is under way.

begin;
select plan(26);

create temp table cprd_s as
  select (current_date - extract(dow from current_date)::integer - 14) as s;
grant select on cprd_s to authenticated;

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('c7c7c7c7-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'cprd-owner@cprd.local', '', now(), now()),
  ('c7c7c7c7-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'cprd-other@cprd.local', '', now(), now())
on conflict (id) do nothing;
insert into user_profiles (id, display_name) values
  ('c7c7c7c7-0000-0000-0000-000000000001', 'CPRD Owner'),
  ('c7c7c7c7-0000-0000-0000-000000000002', 'CPRD Other')
on conflict (id) do nothing;

-- Three ten-week half-marathon plans of the same shape (A active, B paused so
-- the two may share dates, C trimmed so it no longer ends on its race).
-- Phases: base 0-1, build 2-5, peak 6-7, taper 8, race 9; the race on the
-- race week's Sunday and the rest of that week filled, as the generator does.
insert into training_plans (id, user_id, name, goal_event, goal_distance_m, start_date, end_date, days_per_week, status, trimmed_at)
select v.id::uuid, 'c7c7c7c7-0000-0000-0000-000000000001', v.name, 'distance_half', 21097, s, s + 69, 4, v.status, v.trimmed
from cprd_s, (values
  ('c1c1c1c1-0000-0000-0000-00000000000a', 'Earlier', 'active', null::timestamptz),
  ('c1c1c1c1-0000-0000-0000-00000000000b', 'Later', 'paused', null::timestamptz),
  ('c1c1c1c1-0000-0000-0000-00000000000c', 'Trimmed', 'paused', now())
) as v(id, name, status, trimmed);

insert into plan_weeks (id, plan_id, week_index, phase, target_volume_m)
select ('c2c2c2c2-0000-0000-0000-00000' || p.tag || lpad(i::text, 4, '0'))::uuid,
       p.id::uuid, i,
       (case when i < 2 then 'base' when i < 6 then 'build' when i < 8 then 'peak'
             when i = 8 then 'taper' else 'race' end)::plan_phase,
       10000
from (values ('c1c1c1c1-0000-0000-0000-00000000000a', '00a'),
             ('c1c1c1c1-0000-0000-0000-00000000000b', '00b'),
             ('c1c1c1c1-0000-0000-0000-00000000000c', '00c')) as p(id, tag),
     generate_series(0, 9) as i;

-- One long run on every week's Sunday (week 0's done), a tempo on week 3's
-- Tuesday, and the race week: race Sunday, then six easy days.
insert into plan_workouts (id, week_id, scheduled_date, kind, target_distance_m, manually_completed)
select ('c3c3c3c3-0000-0000-0000-00' || p.tag || lpad(i::text, 2, '0') || '00000')::uuid,
       ('c2c2c2c2-0000-0000-0000-00000' || p.tag || lpad(i::text, 4, '0'))::uuid,
       s + 7 * i,
       (case when i = 9 then 'race' else 'long' end)::workout_kind,
       case when i = 9 then 21097 else 12000 end,
       i = 0
from cprd_s,
     (values ('00a'), ('00b'), ('00c')) as p(tag),
     generate_series(0, 9) as i;
insert into plan_workouts (id, week_id, scheduled_date, kind, target_distance_m)
select ('c3c3c3c3-0000-0000-0000-00' || p.tag || '0300002')::uuid,
       ('c2c2c2c2-0000-0000-0000-00000' || p.tag || '0003')::uuid,
       s + 23, 'tempo', 8000
from cprd_s, (values ('00a'), ('00b')) as p(tag);
insert into plan_workouts (id, week_id, scheduled_date, kind, target_distance_m)
select ('c3c3c3c3-0000-0000-0000-00' || p.tag || '090000' || d)::uuid,
       ('c2c2c2c2-0000-0000-0000-00000' || p.tag || '0009')::uuid,
       s + 63 + d, 'easy', 5000
from cprd_s, (values ('00a'), ('00b')) as p(tag), generate_series(1, 6) as d;

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"c7c7c7c7-0000-0000-0000-000000000002","role":"authenticated"}';

select throws_ok(
  $$select change_plan_race_date('c1c1c1c1-0000-0000-0000-00000000000a', (select s + 52 from cprd_s), current_date,
      array['c2c2c2c2-0000-0000-0000-0000000a0005', 'c2c2c2c2-0000-0000-0000-0000000a0004']::uuid[])$$,
  'P0002', null, 'another runner''s plan is refused');

set local "request.jwt.claims" = '{"sub":"c7c7c7c7-0000-0000-0000-000000000001","role":"authenticated"}';

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

select is((select count(*)::int from plan_weeks where plan_id = 'c1c1c1c1-0000-0000-0000-00000000000a'),
  10, 'the refusals wrote nothing');

-- Earlier: the race moves two weeks and two days forward to week 7's Friday.
select lives_ok(
  $$select change_plan_race_date('c1c1c1c1-0000-0000-0000-00000000000a', (select s + 52 from cprd_s), current_date,
      array['c2c2c2c2-0000-0000-0000-0000000a0005', 'c2c2c2c2-0000-0000-0000-0000000a0004']::uuid[],
      null, 0, null, 'c3c3c3c3-0000-0000-0000-0000a0900000')$$,
  'the owner moves the race earlier, dropping two build weeks');
select is((select end_date from training_plans where id = 'c1c1c1c1-0000-0000-0000-00000000000a'),
  (select s + 52 from cprd_s), 'the plan ends on the new race date');
select is((select count(*)::int from plan_weeks where plan_id = 'c1c1c1c1-0000-0000-0000-00000000000a' and phase = 'build'),
  2, 'the build loses two weeks');
select is((select count(*)::int from plan_weeks where plan_id = 'c1c1c1c1-0000-0000-0000-00000000000a' and phase in ('taper', 'race')),
  2, 'the taper and race weeks are all still there');
select is((select week_index::int from plan_weeks where id = 'c2c2c2c2-0000-0000-0000-0000000a0009'),
  7, 'the race week moves back two indexes');
select is((select scheduled_date from plan_workouts where id = 'c3c3c3c3-0000-0000-0000-0000a0900000'),
  (select s + 52 from cprd_s), 'the race lands on the new day');
select is((select scheduled_date from plan_workouts where id = 'c3c3c3c3-0000-0000-0000-0000a0900003'),
  (select s + 49 from cprd_s), 'the run on race day takes the race''s old day');
select is((select count(*)::int from plan_workouts wo join plan_weeks w on w.id = wo.week_id
           where w.id = 'c2c2c2c2-0000-0000-0000-0000000a0009' and wo.scheduled_date > (select s + 52 from cprd_s)),
  0, 'nothing is left after race day');
select is((select scheduled_date from plan_workouts where id = 'c3c3c3c3-0000-0000-0000-0000a0000000'),
  (select s from cprd_s), 'the completed week-0 run keeps its day');
select is((select scheduled_date from plan_workouts where id = 'c3c3c3c3-0000-0000-0000-0000a0300002'),
  (select s + 23 from cprd_s), 'a week before the dropped ones keeps its dates');
select is((select week_index::int from plan_weeks where id = 'c2c2c2c2-0000-0000-0000-0000000a0002'),
  2, 'the current week keeps its index');

-- Later: the race moves two weeks back, so two copies of the last build week go in.
select lives_ok(
  $$select change_plan_race_date('c1c1c1c1-0000-0000-0000-00000000000b', (select s + 77 from cprd_s), current_date,
      '{}', 6, 2, 'c2c2c2c2-0000-0000-0000-0000000b0005', 'c3c3c3c3-0000-0000-0000-0000b0900000')$$,
  'the owner moves a paused plan''s race later, repeating a build week');
select is((select end_date from training_plans where id = 'c1c1c1c1-0000-0000-0000-00000000000b'),
  (select s + 77 from cprd_s), 'the plan ends on the later race date');
select is((select count(*)::int from plan_weeks where plan_id = 'c1c1c1c1-0000-0000-0000-00000000000b' and phase = 'build'),
  6, 'the build grows by two weeks');
select is((select count(*)::int from plan_weeks where plan_id = 'c1c1c1c1-0000-0000-0000-00000000000b' and phase in ('taper', 'race')),
  2, 'the taper is unchanged');
select is((select scheduled_date from plan_workouts where id = 'c3c3c3c3-0000-0000-0000-0000b0900000'),
  (select s + 77 from cprd_s), 'the race moves with its week');
select is((select count(*)::int from plan_workouts wo join plan_weeks w on w.id = wo.week_id
           where w.plan_id = 'c1c1c1c1-0000-0000-0000-00000000000b' and w.week_index in (6, 7) and wo.kind = 'long'),
  2, 'each inserted week repeats the build week''s long run');

select is((select count(*)::int from plan_workouts wo join plan_weeks w on w.id = wo.week_id
           join training_plans p on p.id = w.plan_id, cprd_s
           where p.id in ('c1c1c1c1-0000-0000-0000-00000000000a', 'c1c1c1c1-0000-0000-0000-00000000000b')
             and (wo.scheduled_date < p.start_date + 7 * w.week_index
                  or wo.scheduled_date > p.start_date + 7 * w.week_index + 6)),
  0, 'every workout is still inside its week');
select is((select count(*)::int from (
             select wo.week_id, wo.scheduled_date from plan_workouts wo join plan_weeks w on w.id = wo.week_id
             where w.plan_id in ('c1c1c1c1-0000-0000-0000-00000000000a', 'c1c1c1c1-0000-0000-0000-00000000000b')
             group by 1, 2 having count(*) > 1) d),
  0, 'one workout per day still holds');

select * from finish();
rollback;

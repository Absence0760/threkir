-- Pins migration 20271201000001 (issue #1362, decisions § 2387): the two
-- operator reads behind /admin/home-metrics.
--
--   * the boundary: anon has no EXECUTE, and a signed-in non-admin is refused
--     (42501) rather than handed an empty result;
--   * the shape: aggregates only, no user id in either result type;
--   * the arithmetic, on rows seeded into the previous ISO week (W): a run
--     makes a user active, a Coach day with message_count = 0 is not use, a
--     Coach day in another week does not count, Coach use without a run is
--     not in the denominator; rest days, today, templates, abandoned plans and
--     a paused plan's days from its pause are not scheduled days;
--   * a zero denominator is a null percentage.
--
-- Both reads count across every user, so the seed's own rows in the 16-week
-- window are deleted first (inside this rolled-back transaction) and the
-- figures below are absolute.

begin;
select plan(14);

create temp table hm_wk as
select
  (now() at time zone 'UTC')::date as today,
  (now() at time zone 'UTC')::date
    - (extract(isodow from (now() at time zone 'UTC')::date)::int - 1) as this_week;
alter table hm_wk add column w date;
alter table hm_wk add column first_week date;
update hm_wk set w = this_week - 7, first_week = this_week - 105;
grant select on hm_wk to authenticated;

delete from public.user_coach_usage where usage_date >= (select first_week from hm_wk);
delete from public.plan_workouts where scheduled_date >= (select first_week from hm_wk);
delete from public.runs where started_at >= ((select first_week from hm_wk)::timestamp at time zone 'UTC');

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('9e1e0000-0000-0000-0000-0000000000a1', 'authenticated', 'authenticated', 'hm-admin@hm.local', '', now(), now()),
  ('9e1e0000-0000-0000-0000-0000000000b1', 'authenticated', 'authenticated', 'hm-u1@hm.local', '', now(), now()),
  ('9e1e0000-0000-0000-0000-0000000000b2', 'authenticated', 'authenticated', 'hm-u2@hm.local', '', now(), now()),
  ('9e1e0000-0000-0000-0000-0000000000b3', 'authenticated', 'authenticated', 'hm-u3@hm.local', '', now(), now()),
  ('9e1e0000-0000-0000-0000-0000000000b4', 'authenticated', 'authenticated', 'hm-u4@hm.local', '', now(), now()),
  ('9e1e0000-0000-0000-0000-0000000000b5', 'authenticated', 'authenticated', 'hm-u5@hm.local', '', now(), now())
on conflict (id) do nothing;

insert into app_admins (user_id) values ('9e1e0000-0000-0000-0000-0000000000a1');

-- Coach engagement, week W:
--   u1 two runs + 2 Coach messages  -> active, coached (counted once)
--   u2 a run, a Coach row with 0    -> active, not coached
--   u3 a run in W, Coach in W - 7   -> active in W, not coached; W - 7 has no run
--   u4 Coach in W, no run           -> in neither count
insert into runs (id, user_id, started_at, distance_m, duration_s, source, metadata)
select v.id::uuid, v.uid::uuid, (w + v.d)::timestamp at time zone 'UTC' + interval '9 hours',
       5000, 1800, 'app', '{"activity_type":"run"}'
from hm_wk, (values
  ('9e1e0000-0000-0000-0000-000000000c01', '9e1e0000-0000-0000-0000-0000000000b1', 0),
  ('9e1e0000-0000-0000-0000-000000000c02', '9e1e0000-0000-0000-0000-0000000000b1', 2),
  ('9e1e0000-0000-0000-0000-000000000c03', '9e1e0000-0000-0000-0000-0000000000b2', 1),
  ('9e1e0000-0000-0000-0000-000000000c04', '9e1e0000-0000-0000-0000-0000000000b3', 6)
) as v(id, uid, d);

insert into user_coach_usage (user_id, usage_date, message_count)
select v.uid::uuid, w + v.d, v.n
from hm_wk, (values
  ('9e1e0000-0000-0000-0000-0000000000b1', 1, 2),
  ('9e1e0000-0000-0000-0000-0000000000b2', 1, 0),
  ('9e1e0000-0000-0000-0000-0000000000b3', -3, 4),
  ('9e1e0000-0000-0000-0000-0000000000b4', 4, 1)
) as v(uid, d, n);

-- Plan-day completion, week W (every day of W is before today):
--   plan A (u1, active): W+0 easy done by u1's run, W+1 easy marked done,
--     W+2 rest, W+3 tempo open, W+4 long open, and an easy day TODAY marked done
--     -> 4 scheduled, 2 done (rest and today excluded)
--   plan B (u4, template): W+0 easy                -> excluded
--   plan C (u3, abandoned): W+0 easy               -> excluded
--   plan D (u5, paused at W+3 12:00 UTC): W+1 easy open (counted), W+5 easy
--     (after the pause)                            -> 1 scheduled, 0 done
-- W total: 5 scheduled, 2 done, 40.0 %.
insert into training_plans (id, user_id, name, goal_event, goal_distance_m, start_date, end_date,
                            days_per_week, status, is_template)
select v.id::uuid, v.uid::uuid, v.name, 'distance_10k', 10000, w - 7, today + 30, 4, v.status, v.tmpl
from hm_wk, (values
  ('9e1e0000-0000-0000-0000-000000000d01', '9e1e0000-0000-0000-0000-0000000000b1', 'HM active', 'active', false),
  ('9e1e0000-0000-0000-0000-000000000d02', '9e1e0000-0000-0000-0000-0000000000b4', 'HM template', 'completed', true),
  ('9e1e0000-0000-0000-0000-000000000d03', '9e1e0000-0000-0000-0000-0000000000b3', 'HM abandoned', 'abandoned', false),
  ('9e1e0000-0000-0000-0000-000000000d04', '9e1e0000-0000-0000-0000-0000000000b5', 'HM paused', 'paused', false)
) as v(id, uid, name, status, tmpl);

update training_plans
   set paused_at = ((select w from hm_wk) + 3)::timestamp at time zone 'UTC' + interval '12 hours'
 where id = '9e1e0000-0000-0000-0000-000000000d04';

insert into plan_weeks (id, plan_id, week_index, phase, target_volume_m) values
  ('9e1e0000-0000-0000-0000-000000000e01', '9e1e0000-0000-0000-0000-000000000d01', 0, 'base', 20000),
  ('9e1e0000-0000-0000-0000-000000000e02', '9e1e0000-0000-0000-0000-000000000d02', 0, 'base', 20000),
  ('9e1e0000-0000-0000-0000-000000000e03', '9e1e0000-0000-0000-0000-000000000d03', 0, 'base', 20000),
  ('9e1e0000-0000-0000-0000-000000000e04', '9e1e0000-0000-0000-0000-000000000d04', 0, 'base', 20000);

insert into plan_workouts (week_id, scheduled_date, kind, target_distance_m, manually_completed, completed_run_id)
select v.wk::uuid, case when v.d is null then today else w + v.d end, v.kind::workout_kind, 5000, v.manual, v.run::uuid
from hm_wk, (values
  ('9e1e0000-0000-0000-0000-000000000e01', 0, 'easy', false, '9e1e0000-0000-0000-0000-000000000c01'),
  ('9e1e0000-0000-0000-0000-000000000e01', 1, 'easy', true, null),
  ('9e1e0000-0000-0000-0000-000000000e01', 2, 'rest', false, null),
  ('9e1e0000-0000-0000-0000-000000000e01', 3, 'tempo', false, null),
  ('9e1e0000-0000-0000-0000-000000000e01', 4, 'long', false, null),
  ('9e1e0000-0000-0000-0000-000000000e01', null, 'easy', true, null),
  ('9e1e0000-0000-0000-0000-000000000e02', 0, 'easy', false, null),
  ('9e1e0000-0000-0000-0000-000000000e03', 0, 'easy', false, null),
  ('9e1e0000-0000-0000-0000-000000000e04', 1, 'easy', false, null),
  ('9e1e0000-0000-0000-0000-000000000e04', 5, 'easy', false, null)
) as v(wk, d, kind, manual, run);

-- ── 1. the boundary ─────────────────────────────────────────────────────────
select ok(
  not has_function_privilege('anon', 'public.admin_home_coach_engagement_weeks()', 'EXECUTE')
    and not has_function_privilege('anon', 'public.admin_home_plan_completion_weeks()', 'EXECUTE'),
  'anon has no EXECUTE on either Home metrics read'
);
select ok(
  has_function_privilege('authenticated', 'public.admin_home_coach_engagement_weeks()', 'EXECUTE')
    and has_function_privilege('authenticated', 'public.admin_home_plan_completion_weeks()', 'EXECUTE'),
  'authenticated may call both (the body does the gating)'
);

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"9e1e0000-0000-0000-0000-0000000000b1","role":"authenticated"}';

select throws_ok(
  $$select * from public.admin_home_coach_engagement_weeks()$$,
  '42501', null, 'a signed-in non-admin is refused the Coach engagement read');
select throws_ok(
  $$select * from public.admin_home_plan_completion_weeks()$$,
  '42501', null, 'a signed-in non-admin is refused the plan completion read');

reset role;

-- ── 2. aggregates only ──────────────────────────────────────────────────────
select is(
  pg_get_function_result('public.admin_home_coach_engagement_weeks()'::regprocedure),
  'TABLE(week_start date, active_runners bigint, coached_runners bigint, coached_pct numeric)',
  'the Coach engagement result carries a week and counts, no user id'
);
select is(
  pg_get_function_result('public.admin_home_plan_completion_weeks()'::regprocedure),
  'TABLE(week_start date, scheduled_days bigint, completed_days bigint, completed_pct numeric)',
  'the plan completion result carries a week and counts, no user id'
);

-- ── 3. the admin's figures ──────────────────────────────────────────────────
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"9e1e0000-0000-0000-0000-0000000000a1","role":"authenticated"}';

select is(
  (select array[count(*)::text, min(week_start)::text, max(week_start)::text]
     from public.admin_home_coach_engagement_weeks()),
  (select array['16', first_week::text, this_week::text] from hm_wk),
  'Coach engagement: 16 ISO weeks, oldest first, ending with the current UTC week'
);
select is(
  (select array[active_runners, coached_runners]::bigint[]
     from public.admin_home_coach_engagement_weeks() where week_start = (select w from hm_wk)),
  array[3, 1]::bigint[],
  'week W: three runners active, one of them coached (zero-message day and other-week day are not use)'
);
select is(
  (select coached_pct from public.admin_home_coach_engagement_weeks() where week_start = (select w from hm_wk)),
  33.3::numeric,
  'week W: 1 of 3 is 33.3 %'
);
select is(
  (select array[active_runners::text, coached_runners::text, coalesce(coached_pct::text, 'null')]
     from public.admin_home_coach_engagement_weeks() where week_start = (select w - 7 from hm_wk)),
  array['0', '0', 'null'],
  'week W-7: Coach use without a run is not counted, and 0 active is a null percentage'
);

select is(
  (select array[count(*)::text, min(week_start)::text, max(week_start)::text]
     from public.admin_home_plan_completion_weeks()),
  (select array['16', first_week::text, this_week::text] from hm_wk),
  'plan completion: 16 ISO weeks, oldest first, ending with the current UTC week'
);
select is(
  (select array[scheduled_days, completed_days]::bigint[]
     from public.admin_home_plan_completion_weeks() where week_start = (select w from hm_wk)),
  array[5, 2]::bigint[],
  'week W: rest, template, abandoned and post-pause days excluded; run-linked and marked-done days count'
);
select is(
  (select completed_pct from public.admin_home_plan_completion_weeks() where week_start = (select w from hm_wk)),
  40.0::numeric,
  'week W: 2 of 5 is 40.0 %'
);
select is(
  (select array[scheduled_days::text, completed_days::text, coalesce(completed_pct::text, 'null')]
     from public.admin_home_plan_completion_weeks() where week_start = (select this_week from hm_wk)),
  array['0', '0', 'null'],
  'the current week: a day scheduled today is not yet counted, and 0 scheduled is a null percentage'
);

reset role;

select * from finish();
rollback;

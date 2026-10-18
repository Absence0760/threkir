-- Pins 20270918000001 (decisions § 2110): a bulk run insert stays cheap with
-- the run-to-workout matcher on it. private.athlete_local_date used to scan
-- pg_timezone_names on every call, 12-17 ms each, and the matcher calls it
-- once per inserted run plus once per candidate run, so a 55-run plant took
-- 1.4 s locally and hit the authenticator's 8 s statement_timeout on CI. An
-- import (Strava backfill, GPX batch, race results) is the same statement.
--
-- The timeout below is a ceiling, not a benchmark: 240 runs over twelve
-- matched days take tens of milliseconds now and took several seconds
-- before, so 3 s separates the two by an order of magnitude either way.

begin;
select plan(4);

set local timezone = 'UTC';

select ok(
  (select prosrc not ilike '%pg_timezone_names%'
   from pg_proc where oid = 'private.athlete_local_date(text, timestamptz)'::regprocedure),
  'athlete_local_date resolves the zone without scanning pg_timezone_names'
);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values ('0918aaaa-0000-0000-0000-0000000000a1', 'authenticated', 'authenticated', 'bulk@pmbi.local', '', now(), now())
on conflict (id) do nothing;
insert into user_profiles (id, display_name)
values ('0918aaaa-0000-0000-0000-0000000000a1', 'Bulk')
on conflict (id) do nothing;
insert into user_settings (user_id, prefs)
values ('0918aaaa-0000-0000-0000-0000000000a1', '{"time_zone":"America/New_York"}')
on conflict (user_id) do update set prefs = excluded.prefs;

do $$
declare
  v_plan uuid;
  v_week uuid;
begin
  insert into training_plans (user_id, name, goal_event, goal_distance_m, start_date, end_date,
                              days_per_week, status)
  values ('0918aaaa-0000-0000-0000-0000000000a1', 'Bulk plan', 'distance_10k', 10000,
          '2031-05-04', '2031-05-17', 7, 'active')
  returning id into v_plan;
  insert into plan_weeks (plan_id, week_index) values (v_plan, 0) returning id into v_week;
  insert into plan_workouts (week_id, scheduled_date, kind, target_distance_m)
  select v_week, d::date, 'easy', 5000
  from generate_series('2031-05-04'::date, '2031-05-15'::date, interval '1 day') d;
end;
$$;

set local statement_timeout = '3s';
select lives_ok(
  $$ insert into runs (user_id, started_at, duration_s, distance_m, source, is_public,
                       activity_type, is_dnf, metadata)
     select '0918aaaa-0000-0000-0000-0000000000a1',
            '2031-05-04 14:00:00+00'::timestamptz + make_interval(days => i / 20, mins => i % 20),
            1800, 4000 + i, 'app', false, 'run', false, '{}'::jsonb
     from generate_series(0, 239) i $$,
  'a 240-run insert over twelve planned days completes inside a 3 s statement timeout'
);
reset statement_timeout;

select is(
  (select count(*)::int from runs where user_id = '0918aaaa-0000-0000-0000-0000000000a1'),
  240,
  'every planted run landed'
);

select is(
  (select count(*)::int
   from plan_workouts pw
   join plan_weeks wk on wk.id = pw.week_id
   join training_plans tp on tp.id = wk.plan_id
   where tp.user_id = '0918aaaa-0000-0000-0000-0000000000a1'
     and pw.completed_run_id is not null),
  12,
  'the matcher still ran: each of the twelve planned days took one of its runs'
);

select * from finish();
rollback;

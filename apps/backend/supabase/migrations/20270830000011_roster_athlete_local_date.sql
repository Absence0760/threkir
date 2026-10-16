-- The coach roster picks each athlete's current plan by the ATHLETE's local
-- date, not the server's UTC date (issue #1182).
--
-- coach_roster_summary compared plan windows against current_date, the
-- database's UTC date, while every client picks the current plan by the
-- runner's local date (plan_current.ts / plan_current.dart). With plans
-- chained back to back (decisions § 2008) the two disagreed for the hours the
-- dates differ on a changeover day: the coach's roster named one plan and the
-- athlete's dashboard the other.
--
-- The server had no zone for an athlete, so clients now write their IANA time
-- zone into the universal settings bag as `time_zone` (docs/backend/settings.md)
-- and the roster reads it. It is a bag key read in SQL, the same documented
-- exception to the placement rule as safety_overdue_minutes and the
-- worker-read email prefs.
--
-- 1. private.check_time_zone_pref refuses a `time_zone` Postgres does not know
--    (pg_timezone_names) with 22023, on insert and whenever the key changes, so
--    `at time zone` can never be handed a name it would raise on. Absent or
--    JSON null is allowed (unset).
-- 2. private.athlete_local_date(zone, at) is the athlete's calendar date at an
--    instant: in `zone` when Postgres knows it, else the session's date (what
--    current_date was). It looks the name up rather than trusting the trigger,
--    so a row written before it still cannot make the roster raise.
-- 3. coach_roster_summary is re-emitted whole from its latest body
--    (20270830000001); only the active_plan ordering changes, from
--    current_date to each athlete's local date. Grants are restated.
--
-- user_settings is a per-user table (not in GUARDED_TABLES); adding a trigger
-- takes a brief lock and rewrites nothing.

create or replace function private.check_time_zone_pref()
returns trigger
language plpgsql
set search_path = public, pg_catalog
as $$
declare
  tz jsonb := new.prefs -> 'time_zone';
begin
  if tg_op = 'UPDATE' and tz is not distinct from (old.prefs -> 'time_zone') then
    return new;
  end if;
  if tz is null or tz = 'null'::jsonb then
    return new;
  end if;
  if jsonb_typeof(tz) <> 'string'
     or not exists (select 1 from pg_timezone_names where name = tz #>> '{}') then
    raise exception using
      errcode = 'invalid_parameter_value',
      message = format('user_settings.prefs.time_zone: %s is not a known IANA time zone', tz);
  end if;
  return new;
end;
$$;

revoke execute on function private.check_time_zone_pref() from public, anon, authenticated;

drop trigger if exists user_settings_check_time_zone on user_settings;
create trigger user_settings_check_time_zone
  before insert or update of prefs on user_settings
  for each row execute function private.check_time_zone_pref();

create or replace function private.athlete_local_date(p_time_zone text, p_at timestamptz)
returns date
language sql
stable
set search_path = public, pg_catalog
as $$
  select coalesce(
    (select (p_at at time zone n.name)::date from pg_timezone_names n where n.name = p_time_zone),
    p_at::date
  );
$$;

revoke execute on function private.athlete_local_date(text, timestamptz) from public, anon, authenticated;

create or replace function coach_roster_summary()
returns table (
  athlete_id          uuid,
  display_name        text,
  avatar_url          text,
  last_run_at         timestamptz,
  runs_7d             int,
  distance_7d_m       double precision,
  load_acute          double precision,
  load_chronic        double precision,
  active_plan_id      uuid,
  plan_completion_pct int
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  return query
  with mine as (
    select ca.athlete_id
    from coach_athletes ca
    where ca.coach_id = auth.uid()
      and ca.status = 'active'
      and ca.athlete_id is not null
  ),
  -- Each athlete's calendar date now, in the zone their clients last wrote
  -- (the `time_zone` universal pref), else the server's date. The current
  -- plan is picked against this, as the athlete's own dashboard picks it.
  athlete_today as (
    select
      mine.athlete_id,
      private.athlete_local_date(us.prefs ->> 'time_zone', now()) as today
    from mine
    left join user_settings us on us.user_id = mine.athlete_id
  ),
  -- Distance-proxy daily stress mirrors training_load.ts's distance fallback
  -- (10 points / km). The headline "load" column is a coarse triage signal,
  -- not the calibrated TRIMP curve on the athlete's own dashboard -- a coach
  -- scanning a roster wants "ramping vs tapering", which the acute:chronic
  -- ratio gives from the proxy alone. is_dnf runs are excluded (they aren't a
  -- training stimulus the athlete completed). No activity_type filter: the
  -- athlete's own dashboard load runs over every runs-table row too, so the
  -- two surfaces agree.
  athlete_runs as (
    select
      r.user_id,
      r.started_at,
      r.distance_m,
      (coalesce(r.distance_m, 0) / 1000.0) * 10.0 as stress
    from runs r
    join mine on mine.athlete_id = r.user_id
    where r.is_dnf = false
      and r.started_at >= now() - interval '28 days'
  ),
  run_agg as (
    select
      ar.user_id,
      max(ar.started_at) as last_run_at_28d,
      count(*) filter (where ar.started_at >= now() - interval '7 days')::int as runs_7d,
      coalesce(sum(ar.distance_m) filter (where ar.started_at >= now() - interval '7 days'), 0)::double precision as distance_7d_m,
      coalesce(sum(ar.stress) filter (where ar.started_at >= now() - interval '7 days'), 0)::double precision as load_acute,
      -- Chronic load is the average weekly stress over the 28-day window
      -- (total 28-day stress / 4), the conventional ACWR denominator scale.
      (coalesce(sum(ar.stress), 0) / 4.0)::double precision as load_chronic
    from athlete_runs ar
    group by ar.user_id
  ),
  -- Each athlete's most-recent run regardless of the 28-day window, so the
  -- recency column is honest for an athlete who hasn't run in a month (the
  -- run_agg window would otherwise show last_run_at as null for them).
  last_run as (
    select r.user_id, max(r.started_at) as last_run_at
    from runs r
    join mine on mine.athlete_id = r.user_id
    group by r.user_id
  ),
  active_plan as (
    select distinct on (tp.user_id)
      tp.user_id,
      tp.id as plan_id
    from training_plans tp
    join athlete_today atd on atd.athlete_id = tp.user_id
    where tp.status = 'active'
      and coalesce(tp.is_template, false) = false
    -- Several active plans can be chained; pick the one plan_current.ts picks:
    -- the plan covering the athlete's today, else the latest-ended, else the
    -- next to start.
    order by tp.user_id,
      case
        when atd.today between tp.start_date and tp.end_date then 0
        when tp.end_date < atd.today then 1
        else 2
      end,
      case when tp.end_date < atd.today then tp.end_date end desc nulls last,
      tp.start_date
  ),
  -- Completion % mirrors fetchAthletePlanOverview: done = completed_run_id is
  -- not null OR manually_completed; denominator excludes rest workouts and
  -- intentionally-skipped ones (skipped_at not null).
  plan_progress as (
    select
      ap.user_id,
      ap.plan_id,
      count(*) filter (
        where pw.completed_run_id is not null or pw.manually_completed = true
      )::int as done,
      count(*) filter (
        where pw.kind <> 'rest' and pw.skipped_at is null
      )::int as total
    from active_plan ap
    join plan_weeks pwk on pwk.plan_id = ap.plan_id
    join plan_workouts pw on pw.week_id = pwk.id
    group by ap.user_id, ap.plan_id
  )
  select
    p.id as athlete_id,
    p.display_name,
    p.avatar_url,
    lr.last_run_at,
    coalesce(ra.runs_7d, 0) as runs_7d,
    coalesce(ra.distance_7d_m, 0)::double precision as distance_7d_m,
    coalesce(ra.load_acute, 0)::double precision as load_acute,
    coalesce(ra.load_chronic, 0)::double precision as load_chronic,
    ap.plan_id as active_plan_id,
    case
      when pp.total is null or pp.total = 0 then 0
      else round((pp.done::numeric / pp.total::numeric) * 100)::int
    end as plan_completion_pct
  from mine
  join user_profiles p on p.id = mine.athlete_id
  left join run_agg ra on ra.user_id = mine.athlete_id
  left join last_run lr on lr.user_id = mine.athlete_id
  left join active_plan ap on ap.user_id = mine.athlete_id
  left join plan_progress pp on pp.user_id = mine.athlete_id
  order by lr.last_run_at desc nulls last, p.display_name asc;
end;
$$;

revoke execute on function public.coach_roster_summary() from public, anon;
grant execute on function public.coach_roster_summary() to authenticated;
grant execute on function public.coach_roster_summary() to service_role;

-- The coach roster gains a consecutive-miss input and an easy-run HR-drift
-- flag (issue #1186, persona "coach, and an older athlete on beta-blockers";
-- decisions § 2085).
--
-- Three columns join coach_roster_summary:
--
--   athlete_today      the athlete's local date (private.athlete_local_date),
--                      the `today` the client's isWorkoutMissed needs.
--   recent_workouts    the current plan's non-rest workouts over the last 28
--                      local days. Missed is DERIVED on the client by the
--                      plan_current parity pair (decisions § 2084), never
--                      restated in SQL, so the roster and the athlete's own
--                      plan cannot disagree about which day was a miss.
--   easy_hr_drift_pct  efficiency-factor drift on planned easy runs, recent
--                      14 days vs the 42 before. Art 9: computed only for an
--                      athlete with health_data_consent_at, and only inside
--                      this coach-link-gated read (decisions § 98).
--
-- The return type changes, so the function is dropped and recreated from its
-- latest body (20270830000011); grants are restated.

drop function if exists public.coach_roster_summary();

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
  plan_completion_pct int,
  athlete_today       date,
  recent_workouts     jsonb,
  easy_hr_drift_pct   double precision
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
  ),
  -- The current plan's non-rest workouts over the athlete's last 28 local
  -- days, newest first, in the shape planWorkoutStatus / isWorkoutMissed
  -- take (plan_current.ts / plan_current.dart). The client derives "missed"
  -- and the consecutive-miss streak from it; the rule is not restated here.
  recent as (
    select
      ap.user_id,
      jsonb_agg(
        jsonb_build_object(
          'scheduled_date', pw.scheduled_date,
          'kind', pw.kind,
          'completed', (pw.completed_run_id is not null or pw.manually_completed),
          'skipped', (pw.skipped_at is not null)
        )
        order by pw.scheduled_date desc
      ) as workouts
    from active_plan ap
    join athlete_today atd on atd.athlete_id = ap.user_id
    join plan_weeks pwk on pwk.plan_id = ap.plan_id
    join plan_workouts pw on pw.week_id = pwk.id
    where pw.kind <> 'rest'
      and pw.scheduled_date >= atd.today - 28
      and pw.scheduled_date < atd.today
    group by ap.user_id
  ),
  -- Easy-run heart-rate drift: the efficiency factor (metres per minute per
  -- beat, the aerobic-decoupling literature's EF) of the athlete's planned
  -- easy / recovery runs over the last 14 days against the 42 days before.
  -- Positive = more beats for the same speed. Art 9: HR is processed here
  -- only for an athlete with health_data_consent_at on record, and only
  -- inside this coach-link-gated read (decisions § 98). Runs whose average
  -- was taken over under half the run (hr_coverage, metadata.md) and DNFs are
  -- left out; null unless both windows hold enough runs to compare.
  easy_runs as (
    select
      r.user_id,
      r.started_at,
      (r.distance_m / r.duration_s * 60.0)
        / (r.metadata ->> 'avg_bpm')::double precision as ef
    from runs r
    join mine on mine.athlete_id = r.user_id
    join user_profiles hp on hp.id = r.user_id and hp.health_data_consent_at is not null
    where r.is_dnf = false
      and r.started_at >= now() - interval '56 days'
      and r.distance_m >= 1000
      and r.duration_s > 0
      and jsonb_typeof(r.metadata -> 'avg_bpm') = 'number'
      and (r.metadata ->> 'avg_bpm')::double precision between 30 and 230
      and (
        jsonb_typeof(r.metadata -> 'hr_coverage') is distinct from 'number'
        or (r.metadata ->> 'hr_coverage')::double precision >= 0.5
      )
      and exists (
        select 1 from plan_workouts epw
        where epw.completed_run_id = r.id
          and epw.kind in ('easy', 'recovery')
      )
  ),
  hr_drift as (
    select
      er.user_id,
      case
        when count(*) filter (where er.started_at >= now() - interval '14 days') >= 2
         and count(*) filter (where er.started_at < now() - interval '14 days') >= 3
        then (
          1 - avg(er.ef) filter (where er.started_at >= now() - interval '14 days')
            / avg(er.ef) filter (where er.started_at < now() - interval '14 days')
        ) * 100.0
      end as drift_pct
    from easy_runs er
    group by er.user_id
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
    end as plan_completion_pct,
    atd.today as athlete_today,
    coalesce(rc.workouts, '[]'::jsonb) as recent_workouts,
    hd.drift_pct::double precision as easy_hr_drift_pct
  from mine
  join user_profiles p on p.id = mine.athlete_id
  left join run_agg ra on ra.user_id = mine.athlete_id
  left join last_run lr on lr.user_id = mine.athlete_id
  left join active_plan ap on ap.user_id = mine.athlete_id
  left join plan_progress pp on pp.user_id = mine.athlete_id
  left join athlete_today atd on atd.athlete_id = mine.athlete_id
  left join recent rc on rc.user_id = mine.athlete_id
  left join hr_drift hd on hd.user_id = mine.athlete_id
  order by lr.last_run_at desc nulls last, p.display_name asc;
end;
$$;

revoke execute on function public.coach_roster_summary() from public, anon;
grant execute on function public.coach_roster_summary() to authenticated;
grant execute on function public.coach_roster_summary() to service_role;

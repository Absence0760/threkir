-- The plan calendar feed carries the current plan only (issue #1186 review;
-- decisions § 2099).
--
-- Plans can be chained (several `active` plans whose windows do not overlap),
-- and plan_calendar_feed_events returned the workouts of every one of them,
-- while the app, the Settings copy ("your active plan's workouts") and the
-- coach roster all mean the one plan pickCurrentPlan picks. The feed now picks
-- the same plan with the same ordering as coach_roster_summary's active_plan
-- CTE, against the runner's local date (private.athlete_local_date over the
-- time_zone pref, 20270830000011). Same signature; grants restated.

create or replace function public.plan_calendar_feed_events(p_feed_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_uid uuid;
  v_unit text;
  v_locale text;
  v_tz text;
  v_today date;
  v_plan uuid;
  v_workouts jsonb;
begin
  select user_id into v_uid from public.plan_calendar_feeds where id = p_feed_id;
  if v_uid is null then
    return null;
  end if;

  update public.plan_calendar_feeds
     set last_fetched_at = now()
   where id = p_feed_id
     and (last_fetched_at is null or last_fetched_at < now() - interval '1 hour');

  select s.prefs ->> 'locale',
         coalesce(nullif(s.prefs ->> 'preferred_unit', ''), p.preferred_unit),
         s.prefs ->> 'time_zone'
    into v_locale, v_unit, v_tz
    from public.user_profiles p
    left join public.user_settings s on s.user_id = p.id
   where p.id = v_uid;

  -- The current plan, picked as pickCurrentPlan (plan_current.ts) and
  -- coach_roster_summary pick it: the active plan covering the runner's
  -- local today, else the latest-ended, else the next to start.
  v_today := private.athlete_local_date(v_tz, now());
  select tp.id into v_plan
    from public.training_plans tp
   where tp.user_id = v_uid
     and tp.status = 'active'
     and not tp.is_template
   order by
     case
       when v_today between tp.start_date and tp.end_date then 0
       when tp.end_date < v_today then 1
       else 2
     end,
     case when tp.end_date < v_today then tp.end_date end desc nulls last,
     tp.start_date
   limit 1;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', w.id,
           'date', w.scheduled_date,
           'kind', w.kind,
           'target_distance_m', w.target_distance_m,
           'target_duration_seconds', w.target_duration_seconds,
           'target_pace_sec_per_km', w.target_pace_sec_per_km,
           'target_pace_end_sec_per_km', w.target_pace_end_sec_per_km,
           'target_pace_tolerance_sec', w.target_pace_tolerance_sec
         ) order by w.scheduled_date, w.id), '[]'::jsonb)
    into v_workouts
    from public.plan_weeks pw
    join public.plan_workouts w on w.week_id = pw.id
   where pw.plan_id = v_plan
     and w.kind <> 'rest';

  return jsonb_build_object(
    'unit', case when v_unit = 'mi' then 'mi' else 'km' end,
    'locale', v_locale,
    'workouts', v_workouts
  );
end;
$$;

revoke execute on function public.plan_calendar_feed_events(uuid) from public, anon, authenticated;
grant execute on function public.plan_calendar_feed_events(uuid) to service_role;

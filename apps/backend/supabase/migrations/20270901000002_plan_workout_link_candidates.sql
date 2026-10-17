-- Cross-day workout candidates for a run (issue #1186, decisions § 2079).
--
-- The matcher (20270901000001) links a run only on its own local day. A
-- workout done a day or two early or late is never linked silently: the run
-- detail page asks "was this Thursday's planned workout, done early?" from
-- this list, and a yes links through the ordinary owner update, which makes
-- it a hand link the matcher never moves. A no goes through
-- dismiss_plan_workout_link (below), so the question is not asked again.
--
-- Returns nothing unless the caller owns the run, the run is not linked to
-- any workout yet, and it is not a ride. Candidates are the open workouts
-- (not rest, not skipped, not ticked by hand, not linked, and not one the
-- runner already took this run off) of the caller's
-- active non-template plans within two local days either side of the run,
-- excluding its own day, that the run qualifies for by the matcher's own
-- rule (private.plan_match_score: 75% of the target or more). Nearest day
-- first, then the closest fit.

create or replace function public.plan_workout_link_candidates(p_run_id uuid)
returns table (
  workout_id              uuid,
  plan_id                 uuid,
  scheduled_date          date,
  kind                    workout_kind,
  target_distance_m       numeric,
  target_duration_seconds integer,
  day_offset              integer
)
language plpgsql
stable
security definer
set search_path = public, pg_catalog
as $$
declare
  v_uid uuid := auth.uid();
  v_run record;
  v_day date;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  select r.id, r.started_at, r.distance_m, r.duration_s, r.activity_type
    into v_run
  from runs r
  where r.id = p_run_id and r.user_id = v_uid;
  if not found or v_run.activity_type = 'cycle' then
    return;
  end if;
  if exists (select 1 from plan_workouts pw where pw.completed_run_id = p_run_id) then
    return;
  end if;

  select private.athlete_local_date(us.prefs ->> 'time_zone', v_run.started_at)
    into v_day
  from (select 1) one
  left join user_settings us on us.user_id = v_uid;

  return query
  select pw.id,
         tp.id,
         pw.scheduled_date,
         pw.kind,
         pw.target_distance_m,
         pw.target_duration_seconds,
         (pw.scheduled_date - v_day)::integer
  from plan_workouts pw
  join plan_weeks wk on wk.id = pw.week_id
  join training_plans tp on tp.id = wk.plan_id
  where tp.user_id = v_uid
    and tp.status = 'active'
    and not tp.is_template
    and pw.scheduled_date between v_day - 2 and v_day + 2
    and pw.scheduled_date <> v_day
    and pw.kind <> 'rest'
    and pw.skipped_at is null
    and not pw.manually_completed
    and pw.completed_run_id is null
    and not exists (
      select 1 from private.plan_workout_link_refusals f
      where f.workout_id = pw.id and f.run_id = p_run_id
    )
    and private.plan_match_score(pw.target_distance_m, pw.target_duration_seconds,
                                 v_run.distance_m, v_run.duration_s) is not null
  order by abs(pw.scheduled_date - v_day),
           private.plan_match_score(pw.target_distance_m, pw.target_duration_seconds,
                                    v_run.distance_m, v_run.duration_s),
           pw.scheduled_date;
end;
$$;

revoke execute on function public.plan_workout_link_candidates(uuid) from public, anon;
grant execute on function public.plan_workout_link_candidates(uuid) to authenticated;

-- "Not this one" on the prompt: the runner says this run was not that
-- workout. Recorded as a refusal, so neither the candidate list nor the
-- matcher offers the pair again and the prompt does not come back on the
-- next visit. A no-op unless the caller owns both the run and the workout.
create or replace function public.dismiss_plan_workout_link(p_workout_id uuid, p_run_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  insert into private.plan_workout_link_refusals (workout_id, run_id)
  select pw.id, r.id
  from plan_workouts pw
  join plan_weeks wk on wk.id = pw.week_id
  join training_plans tp on tp.id = wk.plan_id
  join runs r on r.id = p_run_id and r.user_id = v_uid
  where pw.id = p_workout_id
    and tp.user_id = v_uid
  on conflict do nothing;
end;
$$;

revoke execute on function public.dismiss_plan_workout_link(uuid, uuid) from public, anon;
grant execute on function public.dismiss_plan_workout_link(uuid, uuid) to authenticated;

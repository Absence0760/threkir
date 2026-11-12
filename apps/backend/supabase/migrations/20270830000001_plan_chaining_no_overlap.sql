-- Plan chaining (decisions § 2008): a runner may hold several ACTIVE plans
-- as long as their date windows do not overlap, so a Comrades block can be
-- queued behind a Richmond block instead of closing it early.
--
-- training_plans_one_active (one active row per user) becomes an exclusion
-- constraint on (user_id, [start_date, end_date]) over active rows. Every
-- user holds at most one active plan before this migration, so the
-- constraint cannot fail to build. training_plans is a per-user,
-- human-authored table (not in GUARDED_TABLES); the build's lock is brief.
--
-- The writers that used to complete EVERY active plan before inserting
-- (clone_public_plan, clone_plan_template) now complete only the plans the
-- new window overlaps; assign_plan_to_athlete refuses only on an overlap.
-- coach_roster_summary picks the current plan the way plan_current.ts does.
-- Each is re-emitted as its FULL latest body (the bare-body clobber rule).
--
-- trim_training_plan ends a plan early (deletes its workouts after the new
-- end date and any week left empty past it) so a new plan can start the
-- next day. SECURITY INVOKER: the owner write policies decide who may.

create extension if not exists btree_gist with schema extensions;

drop index if exists training_plans_one_active;

alter table training_plans
  add constraint training_plans_active_no_overlap
  exclude using gist (
    user_id extensions.gist_uuid_ops with =,
    daterange(start_date, end_date, '[]') with &&
  ) where (status = 'active');

CREATE OR REPLACE FUNCTION public.clone_public_plan(template_id uuid, new_start_date date)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  caller uuid := auth.uid();
  tmpl training_plans%rowtype;
  new_plan_id uuid;
  new_week_id uuid;
  date_offset_days int;
  week_record record;
  workout_record record;
begin
  if caller is null then
    raise exception 'clone_public_plan: not authenticated';
  end if;

  -- Anti-bulk-clone rate limit — same shape as clone_plan_template
  -- (20 clones / hour / caller). A caller with the public library list
  -- cannot loop-clone every public template UUID into their account.
  perform enforce_create_rate_limit('clone_public_plan', caller, 20, 3600);

  -- DEFINER context bypasses RLS, so this reads any public template
  -- regardless of caller. The is_public_template gate is the access check.
  select * into tmpl
  from training_plans
  where id = template_id
    and is_template = true
    and is_public_template = true;

  if not found then
    raise exception 'clone_public_plan: public template not found';
  end if;

  date_offset_days := new_start_date - tmpl.start_date;

  -- Complete only the active plans the clone's window overlaps, so the
  -- insert can't trip training_plans_active_no_overlap (a raw 23P01) while
  -- a plan queued before or after it stays active.
  update training_plans
  set status = 'completed', updated_at = now()
  where user_id = caller
    and status = 'active'
    and is_template = false
    and daterange(start_date, end_date, '[]')
        && daterange(new_start_date, tmpl.end_date + date_offset_days, '[]');

  insert into training_plans (
    user_id, name, goal_event, goal_distance_m, goal_time_seconds,
    start_date, end_date, days_per_week, vdot, current_5k_seconds,
    status, notes, parent_template_id, is_template, is_public_template,
    source, rules
  )
  values (
    caller, tmpl.name, tmpl.goal_event, tmpl.goal_distance_m, tmpl.goal_time_seconds,
    new_start_date, tmpl.end_date + date_offset_days,
    tmpl.days_per_week,
    -- Publisher-private fitness data — never propagated to the clone.
    -- The clone owner sets their own VDOT via /plans/new.
    null, null,
    'active', tmpl.notes, template_id, false, false,
    tmpl.source, tmpl.rules
  )
  returning id into new_plan_id;

  for week_record in
    select * from plan_weeks where plan_id = template_id order by week_index
  loop
    insert into plan_weeks (plan_id, week_index, phase, target_volume_m, notes)
    values (new_plan_id, week_record.week_index, week_record.phase,
            week_record.target_volume_m, week_record.notes)
    returning id into new_week_id;

    for workout_record in
      select * from plan_workouts where week_id = week_record.id
    loop
      insert into plan_workouts (
        week_id, scheduled_date, kind, target_distance_m, target_duration_seconds,
        target_pace_sec_per_km, target_pace_end_sec_per_km,
        target_pace_tolerance_sec, pace_zone, structure, notes
      )
      values (
        new_week_id,
        workout_record.scheduled_date + date_offset_days,
        workout_record.kind, workout_record.target_distance_m,
        workout_record.target_duration_seconds,
        workout_record.target_pace_sec_per_km,
        workout_record.target_pace_end_sec_per_km,
        workout_record.target_pace_tolerance_sec,
        workout_record.pace_zone,
        workout_record.structure, workout_record.notes
      );
    end loop;
  end loop;

  return new_plan_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.clone_plan_template(template_id uuid, new_start_date date)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
declare
  caller uuid := auth.uid();
  tmpl training_plans%rowtype;
  new_plan_id uuid;
  new_week_id uuid;
  date_offset_days int;
  week_record record;
  workout_record record;
begin
  if caller is null then
    raise exception 'clone_plan_template: not authenticated';
  end if;

  -- Anti-bulk-clone rate limit (migration 20260927_001). 20 clones per
  -- hour per caller — same shape as create_route. A club member with
  -- the public-template list cannot loop-clone every public template
  -- UUID and bulk-create rows under their account.
  perform enforce_create_rate_limit('clone_plan_template', caller, 20, 3600);

  select * into tmpl
  from training_plans
  where id = template_id and is_template = true;

  if not found then
    raise exception 'clone_plan_template: template not found';
  end if;

  if tmpl.user_id <> caller
     and not (tmpl.club_id is not null and is_club_member(tmpl.club_id))
  then
    raise exception 'clone_plan_template: not authorised to clone template %', template_id;
  end if;

  date_offset_days := new_start_date - tmpl.start_date;

  -- Complete only the active plans the clone's window overlaps (see
  -- clone_public_plan); a plan queued around it stays active.
  update training_plans
  set status = 'completed', updated_at = now()
  where user_id = caller
    and status = 'active'
    and is_template = false
    and daterange(start_date, end_date, '[]')
        && daterange(new_start_date, tmpl.end_date + date_offset_days, '[]');

  insert into training_plans (
    user_id, name, goal_event, goal_distance_m, goal_time_seconds,
    start_date, end_date, days_per_week, vdot, current_5k_seconds,
    status, notes, parent_template_id, is_template, source, rules
  )
  values (
    caller, tmpl.name, tmpl.goal_event, tmpl.goal_distance_m, tmpl.goal_time_seconds,
    new_start_date, tmpl.end_date + date_offset_days,
    tmpl.days_per_week,
    -- Publisher-private fitness data — never propagated to the clone
    -- (migration 20260721_001).
    null, null,
    'active', tmpl.notes, template_id, false, tmpl.source, tmpl.rules
  )
  returning id into new_plan_id;

  for week_record in
    select * from plan_weeks where plan_id = template_id order by week_index
  loop
    insert into plan_weeks (plan_id, week_index, phase, target_volume_m, notes)
    values (new_plan_id, week_record.week_index, week_record.phase,
            week_record.target_volume_m, week_record.notes)
    returning id into new_week_id;

    for workout_record in
      select * from plan_workouts where week_id = week_record.id
    loop
      insert into plan_workouts (
        week_id, scheduled_date, kind, target_distance_m, target_duration_seconds,
        target_pace_sec_per_km, target_pace_end_sec_per_km, target_pace_tolerance_sec,
        pace_zone, structure, notes
      )
      values (
        new_week_id,
        workout_record.scheduled_date + date_offset_days,
        workout_record.kind, workout_record.target_distance_m,
        workout_record.target_duration_seconds,
        workout_record.target_pace_sec_per_km,
        workout_record.target_pace_end_sec_per_km,
        workout_record.target_pace_tolerance_sec,
        workout_record.pace_zone,
        workout_record.structure, workout_record.notes
      );
    end loop;
  end loop;

  return new_plan_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.assign_plan_to_athlete(p_source_plan_id uuid, p_athlete_id uuid, p_start_date date)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  caller           uuid := auth.uid();
  src              training_plans%rowtype;
  date_offset_days int;
  new_plan_id      uuid;
  week_record      record;
  workout_record   record;
  new_week_id      uuid;
begin
  if caller is null then
    raise exception 'assign_plan_to_athlete: not authenticated';
  end if;

  if caller = p_athlete_id then
    raise exception 'assign_plan_to_athlete: cannot assign a plan to yourself';
  end if;

  -- Consent gate: the active coach_athletes link is the athlete's consent.
  if not private.is_active_coach_of(caller, p_athlete_id) then
    raise exception 'assign_plan_to_athlete: not an active coach of athlete %', p_athlete_id;
  end if;

  -- Source must exist and be readable by the caller (own plan/template, or a
  -- club template they're a member of) -- mirrors clone_plan_template's gate.
  select * into src from training_plans where id = p_source_plan_id;
  if not found then
    raise exception 'assign_plan_to_athlete: source plan % not found', p_source_plan_id;
  end if;
  if src.user_id <> caller
     and not (src.is_template = true and src.club_id is not null and private.is_club_member(src.club_id))
  then
    raise exception 'assign_plan_to_athlete: not authorised to use source plan %', p_source_plan_id;
  end if;

  date_offset_days := p_start_date - src.start_date;

  -- Never silently clobber the athlete's own plan: refuse only when one of
  -- their active plans covers any of the assigned dates. A plan before or
  -- after the assignment can stay.
  if exists (
    select 1 from training_plans
    where user_id = p_athlete_id and status = 'active'
      and daterange(start_date, end_date, '[]')
          && daterange(p_start_date, src.end_date + date_offset_days, '[]')
  ) then
    raise exception 'assign_plan_to_athlete: athlete already has an active plan for those dates';
  end if;

  insert into training_plans (
    user_id, name, goal_event, goal_distance_m, goal_time_seconds,
    start_date, end_date, days_per_week, vdot, current_5k_seconds,
    status, notes, parent_template_id, is_template, assigned_by_coach_id,
    source, rules
  )
  values (
    p_athlete_id, src.name, src.goal_event, src.goal_distance_m, src.goal_time_seconds,
    p_start_date, src.end_date + date_offset_days,
    src.days_per_week,
    -- Source-owner-private: the coach's own fitness measurements and their own
    -- plan-level free text. The prescription is plan_workouts + rules, both
    -- carried below. Same three columns 20270508_001 strips from a template.
    null, null,
    'active', null, p_source_plan_id, false, caller,
    src.source, src.rules
  )
  returning id into new_plan_id;

  -- Date-shift weeks → workouts by the same offset (mirrors clone_plan_template).
  for week_record in
    select * from plan_weeks where plan_id = p_source_plan_id order by week_index
  loop
    insert into plan_weeks (plan_id, week_index, phase, target_volume_m, notes)
    values (new_plan_id, week_record.week_index, week_record.phase,
            week_record.target_volume_m, week_record.notes)
    returning id into new_week_id;

    for workout_record in
      select * from plan_workouts where week_id = week_record.id
    loop
      insert into plan_workouts (
        week_id, scheduled_date, kind, target_distance_m, target_duration_seconds,
        target_pace_sec_per_km, target_pace_end_sec_per_km, target_pace_tolerance_sec,
        pace_zone, structure, notes
      )
      values (
        new_week_id,
        workout_record.scheduled_date + date_offset_days,
        workout_record.kind,
        workout_record.target_distance_m,
        workout_record.target_duration_seconds,
        workout_record.target_pace_sec_per_km,
        workout_record.target_pace_end_sec_per_km,
        workout_record.target_pace_tolerance_sec,
        workout_record.pace_zone,
        workout_record.structure,
        workout_record.notes
      );
    end loop;
  end loop;

  return new_plan_id;
end;
$function$;

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
    join mine on mine.athlete_id = tp.user_id
    where tp.status = 'active'
      and coalesce(tp.is_template, false) = false
    -- Several active plans can be chained; pick the one plan_current.ts picks:
    -- the plan covering today, else the latest-ended, else the next to start.
    order by tp.user_id,
      case
        when current_date between tp.start_date and tp.end_date then 0
        when tp.end_date < current_date then 1
        else 2
      end,
      case when tp.end_date < current_date then tp.end_date end desc nulls last,
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

create or replace function public.trim_training_plan(p_plan_id uuid, p_new_end_date date)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  plan_row training_plans%rowtype;
begin
  if auth.uid() is null then
    raise exception 'trim_training_plan: not authenticated';
  end if;

  select * into plan_row
  from training_plans
  where id = p_plan_id and user_id = auth.uid()
  for update;
  if not found then
    raise exception 'trim_training_plan: plan % not found', p_plan_id;
  end if;

  if p_new_end_date < plan_row.start_date then
    raise exception 'trim_training_plan: new end date % is before the plan starts', p_new_end_date;
  end if;
  if p_new_end_date >= plan_row.end_date then
    return;
  end if;

  delete from plan_workouts wo
  using plan_weeks w
  where wo.week_id = w.id
    and w.plan_id = p_plan_id
    and wo.scheduled_date > p_new_end_date;

  delete from plan_weeks w
  where w.plan_id = p_plan_id
    and plan_row.start_date + w.week_index * 7 > p_new_end_date
    and not exists (select 1 from plan_workouts wo where wo.week_id = w.id);

  update training_plans
  set end_date = p_new_end_date, updated_at = now()
  where id = p_plan_id;
end;
$$;

revoke execute on function public.trim_training_plan(uuid, date) from public, anon;
grant execute on function public.trim_training_plan(uuid, date) to authenticated;

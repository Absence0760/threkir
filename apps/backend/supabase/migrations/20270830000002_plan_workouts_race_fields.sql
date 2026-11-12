-- Several races in one plan (decisions § 2009): a `race` workout carries
-- its own name and an A/B/C priority, so a Comrades block can hold Two
-- Oceans as a B race with its own countdown, goal and taper rather than the
-- plan's end date being the only race it knows. The race distance is the
-- workout's target_distance_m and its goal time target_duration_seconds;
-- the plan's goal_* columns still describe the A race at end_date.
--
-- The clone and assign RPCs copy the two new columns (re-emitted as their
-- FULL latest bodies from 20270830000001). duplicate_plan_week deliberately
-- does not: a copied week is training, and duplicating a race week should
-- not invent a second race with the same name.

alter table plan_workouts
  add column race_name text,
  add column race_priority text;

alter table plan_workouts
  add constraint plan_workouts_race_name_length
    check (race_name is null or char_length(btrim(race_name)) between 1 and 120),
  add constraint plan_workouts_race_priority_check
    check (race_priority is null or race_priority in ('A', 'B', 'C')),
  add constraint plan_workouts_race_fields_only_on_race
    check (kind = 'race' or (race_name is null and race_priority is null));

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
        target_pace_tolerance_sec, pace_zone, structure, notes,
        race_name, race_priority
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
        workout_record.structure, workout_record.notes,
        workout_record.race_name, workout_record.race_priority
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
        pace_zone, structure, notes,
        race_name, race_priority
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
        workout_record.structure, workout_record.notes,
        workout_record.race_name, workout_record.race_priority
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
        pace_zone, structure, notes,
        race_name, race_priority
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
        workout_record.notes,
        workout_record.race_name, workout_record.race_priority
      );
    end loop;
  end loop;

  return new_plan_id;
end;
$function$;

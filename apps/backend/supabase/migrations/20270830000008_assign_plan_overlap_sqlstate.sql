-- assign_plan_to_athlete's overlap refusal carries SQLSTATE 23P01
-- (exclusion_violation) and names the athlete's plans in the way (decisions
-- § 2065).
--
-- It raised a bare P0001 ("athlete already has an active plan for those
-- dates"), which both clients could only show as their generic "Couldn't
-- assign the plan. Please try again." — advice that can never work, since a
-- retry meets the same plan. 23P01 is the code the overlap constraint itself
-- (training_plans_active_no_overlap) and create_training_plan's 'refuse'
-- raise, so the clients' existing overlap mapping recognises it and the
-- coaching surfaces say which dates to pick instead.
--
-- Re-emitted whole from its latest body (20270830000007); only the overlap
-- branch changes. CREATE OR REPLACE keeps the signature and grants; they are
-- restated below all the same.

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
  overlapping      text;
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
  select string_agg(format('"%s" (%s to %s)', name, start_date, end_date), ', ' order by start_date)
  into overlapping
  from training_plans
  where user_id = p_athlete_id and status = 'active'
    and daterange(start_date, end_date, '[]')
        && daterange(p_start_date, src.end_date + date_offset_days, '[]');
  if overlapping is not null then
    raise exception using
      errcode = 'exclusion_violation',
      message = 'assign_plan_to_athlete: these dates overlap the athlete''s active plan ' || overlapping;
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
        race_name, race_priority, race_taper_applied_at
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
        workout_record.race_name, workout_record.race_priority,
        workout_record.race_taper_applied_at
      );
    end loop;
  end loop;

  return new_plan_id;
end;
$function$;

revoke execute on function public.assign_plan_to_athlete(uuid, uuid, date) from public, anon;
grant execute on function public.assign_plan_to_athlete(uuid, uuid, date) to authenticated;
grant execute on function public.assign_plan_to_athlete(uuid, uuid, date) to service_role;

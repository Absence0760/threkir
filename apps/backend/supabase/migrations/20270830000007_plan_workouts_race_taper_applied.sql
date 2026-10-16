-- A B/C race taper applied twice compounded (decisions § 2063; a § 2051 follow-up).
--
-- raceTaperProposals scales a workout's CURRENT distance, so once Apply had
-- cut an easy run to 65% it stayed in the window and the next "Taper around
-- B/C races" proposed 65% of that, then 65% of that again, for as long as the
-- race was ahead and the button was offered. The plan holds no record of the
-- original prescription to compute from, so the workout now records that it
-- was eased: plan_workouts.race_taper_applied_at, stamped by the taper's own
-- apply and read by the proposal, which leaves a stamped workout alone.
--
-- Nullable with no default: a catalog-only ADD COLUMN, no rewrite and no
-- scan (docs/backend/migration_locks.md).
--
-- apply_workout_adjustments (latest body 20270830000005) accepts the key.
-- The copy paths carry the stamp with the eased distance it describes, or a
-- copy of a tapered plan would offer the same cut again:
-- clone_public_plan / clone_plan_template (latest bodies 20270830000004),
-- assign_plan_to_athlete (20270830000002) and duplicate_plan_week
-- (20270705000003), each re-emitted whole. CREATE OR REPLACE keeps their
-- signatures and grants; the grants are restated below all the same.

alter table plan_workouts add column race_taper_applied_at timestamptz;

create or replace function public.apply_workout_adjustments(p_plan_id uuid, p_changes jsonb)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  ch jsonb;
  v_id uuid;
  v_week uuid;
  touched_weeks uuid[] := '{}';
  allowed text[] := array[
    'id', 'kind', 'target_distance_m', 'target_duration_seconds',
    'target_pace_sec_per_km', 'target_pace_tolerance_sec', 'pace_zone',
    'structure', 'notes', 'race_name', 'race_priority', 'race_taper_applied_at'
  ];
begin
  if caller is null then
    raise exception 'apply_workout_adjustments: not authenticated';
  end if;
  if p_changes is null or jsonb_typeof(p_changes) <> 'array' then
    raise exception using
      errcode = 'invalid_parameter_value',
      message = 'apply_workout_adjustments: changes must be a list';
  end if;

  perform 1
  from training_plans
  where id = p_plan_id and user_id = caller
  for update;
  if not found then
    raise exception 'apply_workout_adjustments: plan % not found', p_plan_id;
  end if;

  for ch in select value from jsonb_array_elements(p_changes) loop
    if jsonb_typeof(ch) <> 'object' or ch->>'id' is null then
      raise exception using
        errcode = 'invalid_parameter_value',
        message = 'apply_workout_adjustments: every change needs an id';
    end if;
    if exists (select 1 from jsonb_object_keys(ch) k where k <> all (allowed)) then
      raise exception using
        errcode = 'invalid_parameter_value',
        message = 'apply_workout_adjustments: a change names a column it cannot write';
    end if;
    v_id := (ch->>'id')::uuid;

    select wo.week_id into v_week
    from plan_workouts wo
    join plan_weeks w on w.id = wo.week_id
    where wo.id = v_id and w.plan_id = p_plan_id;
    if not found then
      raise exception 'apply_workout_adjustments: workout % is not in plan %', v_id, p_plan_id;
    end if;

    update plan_workouts set
      kind = case when ch ? 'kind' then (ch->>'kind')::workout_kind else kind end,
      target_distance_m = case when ch ? 'target_distance_m'
        then (ch->>'target_distance_m')::numeric else target_distance_m end,
      target_duration_seconds = case when ch ? 'target_duration_seconds'
        then (ch->>'target_duration_seconds')::numeric::int else target_duration_seconds end,
      target_pace_sec_per_km = case when ch ? 'target_pace_sec_per_km'
        then (ch->>'target_pace_sec_per_km')::numeric::int else target_pace_sec_per_km end,
      target_pace_tolerance_sec = case when ch ? 'target_pace_tolerance_sec'
        then (ch->>'target_pace_tolerance_sec')::numeric::int else target_pace_tolerance_sec end,
      pace_zone = case when ch ? 'pace_zone' then ch->>'pace_zone' else pace_zone end,
      structure = case when ch ? 'structure'
        then nullif(ch->'structure', 'null'::jsonb) else structure end,
      notes = case when ch ? 'notes' then ch->>'notes' else notes end,
      race_name = case when ch ? 'race_name' then ch->>'race_name' else race_name end,
      race_priority = case when ch ? 'race_priority' then ch->>'race_priority' else race_priority end,
      race_taper_applied_at = case when ch ? 'race_taper_applied_at'
        then (ch->>'race_taper_applied_at')::timestamptz else race_taper_applied_at end
    where id = v_id;

    touched_weeks := array_append(touched_weeks, v_week);
  end loop;

  update plan_weeks w
  set target_volume_m = coalesce((
    select sum(wo.target_distance_m) from plan_workouts wo where wo.week_id = w.id
  ), 0)
  where w.id = any (touched_weeks);
end;
$$;

CREATE OR REPLACE FUNCTION public.clone_public_plan(template_id uuid, new_start_date date, p_overlap text DEFAULT 'replace'::text)
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
  overlapped record;
begin
  if caller is null then
    raise exception 'clone_public_plan: not authenticated';
  end if;
  if p_overlap is null or p_overlap not in ('refuse', 'replace', 'trim') then
    raise exception using
      errcode = 'invalid_parameter_value',
      message = 'clone_public_plan: overlap must be refuse, replace or trim';
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

  -- Resolve the active plans the new window overlaps per p_overlap, inside
  -- this transaction: a later failure rolls the resolution back with it.
  if exists (
    select 1 from training_plans
    where user_id = caller and status = 'active'
      and daterange(start_date, end_date, '[]') && daterange(new_start_date, tmpl.end_date + date_offset_days, '[]')
  ) then
    if p_overlap = 'refuse' then
      raise exception using
        errcode = 'exclusion_violation',
        message = 'clone_public_plan: these dates overlap an active training plan';
    elsif p_overlap = 'replace' then
      update training_plans
      set status = 'completed', updated_at = now()
      where user_id = caller
        and status = 'active'
        and daterange(start_date, end_date, '[]') && daterange(new_start_date, tmpl.end_date + date_offset_days, '[]');
    else
      if exists (
        select 1 from training_plans
        where user_id = caller and status = 'active'
          and daterange(start_date, end_date, '[]') && daterange(new_start_date, tmpl.end_date + date_offset_days, '[]')
          and start_date >= new_start_date
      ) then
        raise exception using
          errcode = 'exclusion_violation',
          message = 'clone_public_plan: an overlapping plan starts on or after the new start date, so it cannot be ended early';
      end if;
      for overlapped in
        select id from training_plans
        where user_id = caller and status = 'active'
          and daterange(start_date, end_date, '[]') && daterange(new_start_date, tmpl.end_date + date_offset_days, '[]')
      loop
        perform trim_training_plan(overlapped.id, new_start_date - 1);
      end loop;
    end if;
  end if;

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
        race_name, race_priority, race_taper_applied_at
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
        workout_record.race_name, workout_record.race_priority,
        workout_record.race_taper_applied_at
      );
    end loop;
  end loop;

  return new_plan_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.clone_plan_template(template_id uuid, new_start_date date, p_overlap text DEFAULT 'replace'::text)
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
  overlapped record;
begin
  if caller is null then
    raise exception 'clone_plan_template: not authenticated';
  end if;
  if p_overlap is null or p_overlap not in ('refuse', 'replace', 'trim') then
    raise exception using
      errcode = 'invalid_parameter_value',
      message = 'clone_plan_template: overlap must be refuse, replace or trim';
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

  -- Resolve the active plans the new window overlaps per p_overlap, inside
  -- this transaction: a later failure rolls the resolution back with it.
  if exists (
    select 1 from training_plans
    where user_id = caller and status = 'active'
      and daterange(start_date, end_date, '[]') && daterange(new_start_date, tmpl.end_date + date_offset_days, '[]')
  ) then
    if p_overlap = 'refuse' then
      raise exception using
        errcode = 'exclusion_violation',
        message = 'clone_plan_template: these dates overlap an active training plan';
    elsif p_overlap = 'replace' then
      update training_plans
      set status = 'completed', updated_at = now()
      where user_id = caller
        and status = 'active'
        and daterange(start_date, end_date, '[]') && daterange(new_start_date, tmpl.end_date + date_offset_days, '[]');
    else
      if exists (
        select 1 from training_plans
        where user_id = caller and status = 'active'
          and daterange(start_date, end_date, '[]') && daterange(new_start_date, tmpl.end_date + date_offset_days, '[]')
          and start_date >= new_start_date
      ) then
        raise exception using
          errcode = 'exclusion_violation',
          message = 'clone_plan_template: an overlapping plan starts on or after the new start date, so it cannot be ended early';
      end if;
      for overlapped in
        select id from training_plans
        where user_id = caller and status = 'active'
          and daterange(start_date, end_date, '[]') && daterange(new_start_date, tmpl.end_date + date_offset_days, '[]')
      loop
        perform trim_training_plan(overlapped.id, new_start_date - 1);
      end loop;
    end if;
  end if;

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
        race_name, race_priority, race_taper_applied_at
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
        workout_record.race_name, workout_record.race_priority,
        workout_record.race_taper_applied_at
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

CREATE OR REPLACE FUNCTION public.duplicate_plan_week(p_plan_id uuid, p_week_index integer)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  caller        uuid := auth.uid();
  v_plan        training_plans%rowtype;
  v_src         plan_weeks%rowtype;
  v_new_week_id uuid;
  workout_record record;
begin
  if caller is null then
    raise exception 'duplicate_plan_week: not authenticated';
  end if;

  select * into v_plan from training_plans where id = p_plan_id;
  if not found then
    raise exception 'duplicate_plan_week: plan % not found', p_plan_id;
  end if;

  -- Owner-only. Club members can read a template's weeks but only the
  -- owner restructures it.
  if v_plan.user_id <> caller then
    raise exception 'duplicate_plan_week: not authorised to edit plan %', p_plan_id;
  end if;

  select * into v_src from plan_weeks
    where plan_id = p_plan_id and week_index = p_week_index;
  if not found then
    raise exception 'duplicate_plan_week: week % not found in plan %',
      p_week_index, p_plan_id;
  end if;

  -- Push the workouts of every later week back by 7 days. Done BEFORE
  -- the re-index (while the tail is still the only thing past
  -- p_week_index) and BEFORE the copy exists, so the new week's
  -- workouts aren't caught by this shift.
  update plan_workouts
    set scheduled_date = scheduled_date + 7
    where week_id in (
      select id from plan_weeks
      where plan_id = p_plan_id and week_index > p_week_index
    );

  -- Make room at p_week_index + 1 by bumping every later week up one. The
  -- unique constraint is checked per row, so a single statement transiently
  -- collides; it is DEFERRABLE INITIALLY IMMEDIATE as of this migration and is
  -- deferred for the span of the renumber, then set back to immediate so a
  -- duplicate raises HERE rather than at COMMIT. This replaces a hop through
  -- negative index space, which worked but made `week_index >= 0` unstatable.
  set constraints plan_weeks_plan_id_week_index_key deferred;
  update plan_weeks set week_index = week_index + 1
    where plan_id = p_plan_id and week_index > p_week_index;
  set constraints plan_weeks_plan_id_week_index_key immediate;

  insert into plan_weeks (plan_id, week_index, phase, target_volume_m, notes)
    values (p_plan_id, p_week_index + 1, v_src.phase, v_src.target_volume_m, v_src.notes)
    returning id into v_new_week_id;

  for workout_record in
    select * from plan_workouts where week_id = v_src.id
  loop
    insert into plan_workouts (
      week_id, scheduled_date, kind, target_distance_m, target_duration_seconds,
      target_pace_sec_per_km, target_pace_end_sec_per_km, target_pace_tolerance_sec,
      pace_zone, structure, notes, race_taper_applied_at
    )
    values (
      v_new_week_id,
      workout_record.scheduled_date + 7,
      workout_record.kind,
      workout_record.target_distance_m,
      workout_record.target_duration_seconds,
      workout_record.target_pace_sec_per_km,
      workout_record.target_pace_end_sec_per_km,
      workout_record.target_pace_tolerance_sec,
      workout_record.pace_zone,
      workout_record.structure,
      workout_record.notes,
      workout_record.race_taper_applied_at
    );
  end loop;

  update training_plans
    set end_date = end_date + 7, updated_at = now()
    where id = p_plan_id;

  return v_new_week_id;
end;
$function$;

revoke execute on function public.apply_workout_adjustments(uuid, jsonb) from public, anon;
grant execute on function public.apply_workout_adjustments(uuid, jsonb) to authenticated;

revoke execute on function public.clone_public_plan(uuid, date, text) from public, anon;
grant execute on function public.clone_public_plan(uuid, date, text) to authenticated;
grant execute on function public.clone_public_plan(uuid, date, text) to service_role;

revoke execute on function public.clone_plan_template(uuid, date, text) from public, anon;
grant execute on function public.clone_plan_template(uuid, date, text) to authenticated;

revoke execute on function public.assign_plan_to_athlete(uuid, uuid, date) from public, anon;
grant execute on function public.assign_plan_to_athlete(uuid, uuid, date) to authenticated;
grant execute on function public.assign_plan_to_athlete(uuid, uuid, date) to service_role;

revoke execute on function public.duplicate_plan_week(uuid, integer) from public, anon;
grant execute on function public.duplicate_plan_week(uuid, integer) to authenticated;
grant execute on function public.duplicate_plan_week(uuid, integer) to service_role;

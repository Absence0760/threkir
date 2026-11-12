-- Creating a plan resolves its overlaps atomically (decisions § 2050).
--
-- Both clients used to resolve the active plans a new plan overlapped (mark
-- them completed, or trim them with trim_training_plan) and THEN insert the
-- plan, its weeks and its workouts as separate requests. A failure after the
-- resolve left the old plan completed or trimmed with no new plan to show
-- for it, and a caller passing 'replace' after a stale "nothing overlaps"
-- read completed a plan created in between without asking.
--
-- create_training_plan does the whole write in one transaction: validate,
-- resolve per p_overlap, insert the plan, its weeks and their workouts.
-- 'refuse' (the default) raises exclusion_violation (23P01) when anything
-- overlaps, so a client that saw no overlap never changes a plan it did not
-- name; 'replace' completes the overlapped plans; 'trim' ends each the day
-- before the new start via trim_training_plan, refusing (23P01) when one
-- starts on or after it. SECURITY INVOKER: the owner policies decide, and
-- user_id is always the caller.
--
-- clone_plan_template / clone_public_plan gain the same p_overlap as a third
-- argument. Its default stays 'replace', the behaviour every shipped mobile
-- build calling the two-argument form relies on; current clients pass the
-- runner's choice. A new argument is a new signature, so each is dropped and
-- re-created with its FULL latest body (20270830000002) and its grants
-- restated as 20260926_001 / 20260927_001 / 20270626000001 left them.

create or replace function public.create_training_plan(
  p_plan jsonb,
  p_weeks jsonb,
  p_overlap text default 'refuse'
)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  v_name text;
  v_start date;
  v_end date;
  v_days int;
  v_goal_distance numeric;
  v_goal_time int;
  v_recent_5k int;
  new_plan_id uuid;
  new_week_id uuid;
  wk jsonb;
  wo jsonb;
  overlapped record;
begin
  if caller is null then
    raise exception 'create_training_plan: not authenticated';
  end if;
  if p_overlap is null or p_overlap not in ('refuse', 'replace', 'trim') then
    raise exception using
      errcode = 'invalid_parameter_value',
      message = 'create_training_plan: overlap must be refuse, replace or trim';
  end if;
  if p_plan is null or jsonb_typeof(p_plan) <> 'object' then
    raise exception using
      errcode = 'invalid_parameter_value',
      message = 'create_training_plan: plan must be an object';
  end if;

  v_name := btrim(coalesce(p_plan->>'name', ''));
  v_start := (p_plan->>'start_date')::date;
  v_end := (p_plan->>'end_date')::date;
  v_days := (p_plan->>'days_per_week')::int;
  v_goal_distance := (p_plan->>'goal_distance_m')::numeric;
  v_goal_time := (p_plan->>'goal_time_seconds')::numeric::int;
  v_recent_5k := (p_plan->>'current_5k_seconds')::numeric::int;

  if v_name = '' then
    raise exception using errcode = 'invalid_parameter_value',
      message = 'create_training_plan: name is required';
  end if;
  if v_start is null or v_end is null or v_end < v_start then
    raise exception using errcode = 'invalid_parameter_value',
      message = 'create_training_plan: the plan needs a start date on or before its end date';
  end if;
  if v_days is null or v_days not between 3 and 7 then
    raise exception using errcode = 'invalid_parameter_value',
      message = 'create_training_plan: days per week must be between 3 and 7';
  end if;
  if v_goal_distance is null or v_goal_distance <= 0 then
    raise exception using errcode = 'invalid_parameter_value',
      message = 'create_training_plan: goal distance must be positive';
  end if;
  if v_goal_time is not null and v_goal_time <= 0 then
    raise exception using errcode = 'invalid_parameter_value',
      message = 'create_training_plan: goal time must be positive';
  end if;
  if v_recent_5k is not null and v_recent_5k <= 0 then
    raise exception using errcode = 'invalid_parameter_value',
      message = 'create_training_plan: recent 5K time must be positive';
  end if;
  if p_weeks is null or jsonb_typeof(p_weeks) <> 'array' or jsonb_array_length(p_weeks) = 0 then
    raise exception using errcode = 'invalid_parameter_value',
      message = 'create_training_plan: the plan has no weeks';
  end if;
  for wk in select value from jsonb_array_elements(p_weeks) loop
    if jsonb_typeof(wk) <> 'object' or wk->>'week_index' is null then
      raise exception using errcode = 'invalid_parameter_value',
        message = 'create_training_plan: every week needs a week_index';
    end if;
    if wk ? 'workouts' and jsonb_typeof(wk->'workouts') <> 'array' then
      raise exception using errcode = 'invalid_parameter_value',
        message = 'create_training_plan: a week''s workouts must be a list';
    end if;
    for wo in select value from jsonb_array_elements(coalesce(wk->'workouts', '[]'::jsonb)) loop
      if coalesce(wo->>'kind', '') = '' or wo->>'scheduled_date' is null then
        raise exception using errcode = 'invalid_parameter_value',
          message = 'create_training_plan: every workout needs a kind and a date';
      end if;
    end loop;
  end loop;

  -- Resolve the active plans the new window overlaps per p_overlap, inside
  -- this transaction: a later failure rolls the resolution back with it.
  if exists (
    select 1 from training_plans
    where user_id = caller and status = 'active'
      and daterange(start_date, end_date, '[]') && daterange(v_start, v_end, '[]')
  ) then
    if p_overlap = 'refuse' then
      raise exception using
        errcode = 'exclusion_violation',
        message = 'create_training_plan: these dates overlap an active training plan';
    elsif p_overlap = 'replace' then
      update training_plans
      set status = 'completed', updated_at = now()
      where user_id = caller
        and status = 'active'
        and daterange(start_date, end_date, '[]') && daterange(v_start, v_end, '[]');
    else
      if exists (
        select 1 from training_plans
        where user_id = caller and status = 'active'
          and daterange(start_date, end_date, '[]') && daterange(v_start, v_end, '[]')
          and start_date >= v_start
      ) then
        raise exception using
          errcode = 'exclusion_violation',
          message = 'create_training_plan: an overlapping plan starts on or after the new start date, so it cannot be ended early';
      end if;
      for overlapped in
        select id from training_plans
        where user_id = caller and status = 'active'
          and daterange(start_date, end_date, '[]') && daterange(v_start, v_end, '[]')
      loop
        perform trim_training_plan(overlapped.id, v_start - 1);
      end loop;
    end if;
  end if;

  insert into training_plans (
    user_id, name, goal_event, goal_distance_m, goal_time_seconds,
    start_date, end_date, days_per_week, vdot, current_5k_seconds,
    status, source, notes
  )
  values (
    caller, v_name, (p_plan->>'goal_event')::goal_event, v_goal_distance, v_goal_time,
    v_start, v_end, v_days, (p_plan->>'vdot')::numeric, v_recent_5k,
    'active', 'generated', nullif(btrim(coalesce(p_plan->>'notes', '')), '')
  )
  returning id into new_plan_id;

  for wk in select value from jsonb_array_elements(p_weeks) loop
    insert into plan_weeks (plan_id, week_index, phase, target_volume_m, notes)
    values (
      new_plan_id,
      (wk->>'week_index')::int,
      coalesce((wk->>'phase')::plan_phase, 'base'),
      (wk->>'target_volume_m')::numeric,
      wk->>'notes'
    )
    returning id into new_week_id;

    for wo in select value from jsonb_array_elements(coalesce(wk->'workouts', '[]'::jsonb)) loop
      insert into plan_workouts (
        week_id, scheduled_date, kind, target_distance_m, target_duration_seconds,
        target_pace_sec_per_km, target_pace_tolerance_sec, structure, notes,
        race_name, race_priority
      )
      values (
        new_week_id,
        (wo->>'scheduled_date')::date,
        (wo->>'kind')::workout_kind,
        (wo->>'target_distance_m')::numeric,
        (wo->>'target_duration_seconds')::numeric::int,
        (wo->>'target_pace_sec_per_km')::numeric::int,
        (wo->>'target_pace_tolerance_sec')::numeric::int,
        nullif(wo->'structure', 'null'::jsonb),
        wo->>'notes',
        wo->>'race_name',
        wo->>'race_priority'
      );
    end loop;
  end loop;

  return new_plan_id;
end;
$$;

revoke execute on function public.create_training_plan(jsonb, jsonb, text) from public, anon;
grant execute on function public.create_training_plan(jsonb, jsonb, text) to authenticated;

drop function public.clone_public_plan(uuid, date);
drop function public.clone_plan_template(uuid, date);

CREATE FUNCTION public.clone_public_plan(template_id uuid, new_start_date date, p_overlap text DEFAULT 'replace'::text)
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

CREATE FUNCTION public.clone_plan_template(template_id uuid, new_start_date date, p_overlap text DEFAULT 'replace'::text)
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

revoke execute on function public.clone_public_plan(uuid, date, text) from public, anon;
grant execute on function public.clone_public_plan(uuid, date, text) to authenticated;
grant execute on function public.clone_public_plan(uuid, date, text) to service_role;

revoke execute on function public.clone_plan_template(uuid, date, text) from public, anon;
grant execute on function public.clone_plan_template(uuid, date, text) to authenticated;

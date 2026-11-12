-- create_training_plan writes plan_workouts.race_taper_applied_at
-- (decisions § 2063 addendum). A plan exported as JSON and imported again
-- carries each workout's taper stamp, so the eased distances it holds are
-- not offered, and cut by, the same B/C race taper a second time. A workout
-- with no `race_taper_applied_at` key writes NULL, as before.
--
-- Re-emitted whole from its latest body (20270830000005); grants restated.

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
      if (wo->>'scheduled_date')::date not between v_start and v_end then
        raise exception using errcode = 'invalid_parameter_value',
          message = 'create_training_plan: every workout must fall between the plan''s start and end dates';
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
        race_name, race_priority, race_taper_applied_at
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
        wo->>'race_priority',
        (wo->>'race_taper_applied_at')::timestamptz
      );
    end loop;
  end loop;

  return new_plan_id;
end;
$$;

revoke execute on function public.create_training_plan(jsonb, jsonb, text) from public, anon;
grant execute on function public.create_training_plan(jsonb, jsonb, text) to authenticated;

-- Plan review follow-ups (decisions § 2062).
--
-- apply_workout_adjustments writes a batch of per-workout patches and restates
-- the target volume of every week it touched, in ONE transaction. The plan
-- page's "Taper around B/C races" and cycle-plan adjustments used to send one
-- update per workout and then one per week, so a failure part-way left some
-- workouts eased, others not, and week headers that matched neither. A key
-- present in a change is written (JSON null writes NULL); a key absent leaves
-- the column alone. Every id must be a workout of p_plan_id and the plan must
-- be the caller's, or the whole call raises and nothing changes. SECURITY
-- INVOKER: the owner policies still decide every write.
--
-- trim_training_plan is re-emitted whole so its "completed workouts fall
-- after the cut" refusal carries its own SQLSTATE, TR001, which clients map
-- to readable copy instead of a raw message. create_training_plan and the two
-- clone RPCs call it for p_overlap = 'trim' and let it propagate unchanged.
--
-- training_plans.trimmed_at was never cleared. A trimmed plan that is later
-- made LONGER (a meta edit of its end date, duplicate_plan_week) has its end
-- back as a real race day, so a BEFORE UPDATE trigger clears the stamp then.
-- A pure shift keeps the length and keeps the stamp; the trim itself is
-- shorter and is the update that sets it.
--
-- create_training_plan is re-emitted whole (latest body 20270830000004) to
-- refuse a workout dated outside the plan's own window, which no reader of
-- the plan (weeks, adherence, overlap) can account for.

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
    'structure', 'notes', 'race_name', 'race_priority'
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
      race_priority = case when ch ? 'race_priority' then ch->>'race_priority' else race_priority end
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

revoke execute on function public.apply_workout_adjustments(uuid, jsonb) from public, anon;
grant execute on function public.apply_workout_adjustments(uuid, jsonb) to authenticated;

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

  if exists (
    select 1 from plan_workouts wo
    join plan_weeks w on w.id = wo.week_id
    where w.plan_id = p_plan_id
      and wo.scheduled_date > p_new_end_date
      and (wo.completed_run_id is not null or wo.manually_completed)
  ) then
    raise exception using
      errcode = 'TR001',
      message = format('trim_training_plan: completed workouts fall after %s', p_new_end_date);
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

  update plan_weeks w
  set target_volume_m = coalesce((
    select sum(wo.target_distance_m) from plan_workouts wo where wo.week_id = w.id
  ), 0)
  where w.plan_id = p_plan_id
    and p_new_end_date between plan_row.start_date + w.week_index * 7
                           and plan_row.start_date + w.week_index * 7 + 6
    and p_new_end_date < plan_row.start_date + w.week_index * 7 + 6;

  update training_plans
  set end_date = p_new_end_date, trimmed_at = now(), updated_at = now()
  where id = p_plan_id;
end;
$$;

create or replace function private.clear_trimmed_at_on_extension()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if old.trimmed_at is not null
     and new.trimmed_at is not distinct from old.trimmed_at
     and new.end_date - new.start_date > old.end_date - old.start_date then
    new.trimmed_at := null;
  end if;
  return new;
end;
$$;

drop trigger if exists training_plans_clear_trimmed_at on training_plans;
create trigger training_plans_clear_trimmed_at
  before update of start_date, end_date on training_plans
  for each row execute function private.clear_trimmed_at_on_extension();

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

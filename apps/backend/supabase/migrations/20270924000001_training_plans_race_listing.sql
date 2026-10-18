-- A plan built from a race remembers the race (decisions § 2156).
--
-- The race page's "Build a plan for this race" / "Add to my season" opened the
-- wizard with the race's name, date and distance, and the plan it created was
-- tied to the race by nothing but those copied facts (§ 2154). This adds the
-- link: training_plans.race_listing_id, nullable, set-null when the listing is
-- deleted, so the plan outlives its calendar entry.
--
-- Who writes it
--   * create_training_plan reads an optional p_plan.race_listing_id. It is
--     resolved through public_race_listings, so the RPC only links a listing
--     the caller could read anyway; an unknown or malformed id writes null.
--   * The owner may set or clear it on their own plan through the existing
--     owner UPDATE policy. A listing is public calendar data, so the link
--     discloses nothing the owner could not already reach; no new policy.
--
-- Which copies carry it
--   * A template never does. A published plan is read by every library or
--     club reader, and "the publisher is running Richmond on 14 November" is
--     the publisher's own business, the same call 20270508_001 made for vdot,
--     current_5k_seconds and notes. strip_template_private_fields nulls it on
--     every template write, which covers the publish inserts, a forged REST
--     insert, and an existing plan flipped to is_template.
--   * clone_plan_template, clone_public_plan and assign_plan_to_athlete copy
--     a named column list that does not include it, so a copy made for
--     someone else starts unlinked.
--   * restart_training_plan does not carry it either. It refuses a plan whose
--     race is still ahead (RR001), so the race a restarted plan was built for
--     is always behind the copy, and a link would label a plan that ends
--     months later with a race it no longer leads to.
--
-- Locks: training_plans is a per-runner table, not one of the high-volume
-- tables check_migration_online_safety.mjs guards. ADD COLUMN of a nullable
-- column with no default is a catalogue change; the FK's validation reads the
-- table once under that statement's lock, against a column that is null in
-- every row. The covering index is partial on the non-null rows, so it is
-- built empty. Both are short; neither rewrites the table.

alter table training_plans
  add column race_listing_id uuid references race_listings (id) on delete set null;

create index training_plans_race_listing_idx
  on training_plans (race_listing_id)
  where race_listing_id is not null;

-- Full body carried forward from 20270508_001; race_listing_id joins the
-- owner-private fields a template never holds.
create or replace function private.strip_template_private_fields()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if NEW.is_template = true then
    NEW.vdot := null;
    NEW.current_5k_seconds := null;
    NEW.notes := null;
    NEW.race_listing_id := null;
  end if;
  return NEW;
end;
$$;

-- Full body carried forward from 20270915000001; only the race link is new.
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
  v_race_listing uuid;
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
  -- The race the plan was built for. An id that is not a uuid, or a listing
  -- deleted since the race page loaded, leaves the plan unlinked instead of
  -- refusing it: the link is context on the plan, not part of it.
  if coalesce(p_plan->>'race_listing_id', '')
       ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    select l.id into v_race_listing
    from public_race_listings l
    where l.id = (p_plan->>'race_listing_id')::uuid;
  end if;

  if v_name = '' then
    raise exception using errcode = 'invalid_parameter_value',
      message = 'create_training_plan: name is required';
  end if;
  if v_start is null or v_end is null or v_end < v_start then
    raise exception using errcode = 'invalid_parameter_value',
      message = 'create_training_plan: the plan needs a start date on or before its end date';
  end if;
  if v_days is null or v_days not between 2 and 7 then
    raise exception using errcode = 'invalid_parameter_value',
      message = 'create_training_plan: days per week must be between 2 and 7';
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

  if v_days = 2 and (
    not exists (
      select 1
      from jsonb_array_elements(p_weeks) d_wk,
           jsonb_array_elements(coalesce(d_wk->'workouts', '[]'::jsonb)) d_wo
      where d_wo->>'kind' = 'walk_run'
    )
    or exists (
      select 1
      from jsonb_array_elements(p_weeks) d_wk,
           jsonb_array_elements(coalesce(d_wk->'workouts', '[]'::jsonb)) d_wo
      where coalesce(d_wo->>'kind', '') not in ('walk_run', 'rest', 'race')
    )
  ) then
    raise exception using errcode = 'invalid_parameter_value',
      message = 'create_training_plan: only a walk-run plan may train two days a week; other plans need 3 to 7';
  end if;

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
      set status = 'abandoned', updated_at = now()
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
    status, source, notes, race_listing_id
  )
  values (
    caller, v_name, (p_plan->>'goal_event')::goal_event, v_goal_distance, v_goal_time,
    v_start, v_end, v_days, (p_plan->>'vdot')::numeric, v_recent_5k,
    'active', 'generated', nullif(btrim(coalesce(p_plan->>'notes', '')), ''), v_race_listing
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
        race_name, race_priority, race_taper_applied_at,
        target_rpe_min, target_rpe_max, target_hr_min_bpm, target_hr_max_bpm
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
        (wo->>'race_taper_applied_at')::timestamptz,
        (wo->>'target_rpe_min')::numeric::int,
        (wo->>'target_rpe_max')::numeric::int,
        (wo->>'target_hr_min_bpm')::numeric::int,
        (wo->>'target_hr_max_bpm')::numeric::int
      );
    end loop;
  end loop;

  return new_plan_id;
end;
$$;

revoke execute on function public.create_training_plan(jsonb, jsonb, text) from public, anon;
grant execute on function public.create_training_plan(jsonb, jsonb, text) to authenticated;

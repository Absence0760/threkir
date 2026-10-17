-- Effort and heart-rate targets on a planned workout (issue #1186, persona
-- "coach, and an older athlete on beta-blockers"; decisions § 2085).
--
-- plan_workouts carried pace, distance, duration, structure and notes, so a
-- coach could not prescribe "easy = RPE 3-4" or "cap at 125 bpm". Four
-- optional columns, each a closed range with either end open:
--
--   target_rpe_min / target_rpe_max       1..10 (Borg CR-10)
--   target_hr_min_bpm / target_hr_max_bpm 30..230 (the clamp every recorder
--                                          applies to avg_bpm, metadata.md)
--
-- "Cap at 125 bpm" is max-only; "RPE 3-4" is both. Neither sits on a rest
-- day (plan_workouts_effort_targets_not_on_rest), the same shape as the race
-- fields' kind rule.
--
-- A bpm target is HR-derived prescription about one person, which is Art 9
-- health data. It is fail-closed in three places:
--
--   1. private.check_plan_workout_hr_target refuses a non-null bpm target
--      (42501) unless the PLAN OWNER has health_data_consent_at on record, and
--      refuses one on a template plan (23514) -- a template is copied to other
--      people, and the prescription is not theirs. It runs for a coach's write
--      too, because it is the athlete's consent that the target rests on.
--   2. withdraw_health_data_consent nulls the owner's bpm targets and drops
--      the `hr_medication_affected` settings key in the same transaction
--      (Art 7(3)), alongside height, gender and the weight series.
--   3. The three cross-user copy paths (clone_plan_template,
--      clone_public_plan, assign_plan_to_athlete) carry the RPE range and
--      NOT the bpm range; the owner-to-owner paths (create_training_plan,
--      duplicate_plan_week) carry both. Each is re-emitted whole from its
--      latest body (20270903000001 / 20270830000008 / 20270830000009).
--
-- The client UI is additionally behind PUBLIC_HR_PRESCRIPTION_ENABLED /
-- HR_PRESCRIPTION_ENABLED (default off) until the § 150 sign-off.
--
-- plan_workouts is not a GUARDED_TABLE; the columns are nullable with no
-- default (catalog-only add) and the CHECKs verify against all-null columns.

alter table plan_workouts
  add column target_rpe_min smallint
    constraint plan_workouts_target_rpe_min_range check (target_rpe_min between 1 and 10),
  add column target_rpe_max smallint
    constraint plan_workouts_target_rpe_max_range check (target_rpe_max between 1 and 10),
  add column target_hr_min_bpm smallint
    constraint plan_workouts_target_hr_min_range check (target_hr_min_bpm between 30 and 230),
  add column target_hr_max_bpm smallint
    constraint plan_workouts_target_hr_max_range check (target_hr_max_bpm between 30 and 230);

alter table plan_workouts
  add constraint plan_workouts_target_rpe_ordered
    check (target_rpe_min is null or target_rpe_max is null or target_rpe_min <= target_rpe_max),
  add constraint plan_workouts_target_hr_ordered
    check (target_hr_min_bpm is null or target_hr_max_bpm is null or target_hr_min_bpm <= target_hr_max_bpm),
  add constraint plan_workouts_effort_targets_not_on_rest
    check (
      kind <> 'rest'
      or (target_rpe_min is null and target_rpe_max is null
          and target_hr_min_bpm is null and target_hr_max_bpm is null)
    );

comment on column plan_workouts.target_rpe_min is
  'Lower end of the prescribed effort, RPE 1-10 (Borg CR-10). Null = open.';
comment on column plan_workouts.target_rpe_max is
  'Upper end of the prescribed effort, RPE 1-10. Null = open.';
comment on column plan_workouts.target_hr_min_bpm is
  'Art 9. Lower end of the prescribed heart rate, bpm. Needs the plan owner''s '
  'health_data_consent_at (private.check_plan_workout_hr_target); nulled on withdrawal.';
comment on column plan_workouts.target_hr_max_bpm is
  'Art 9. Heart-rate cap, bpm. Same consent rule as target_hr_min_bpm.';

create or replace function private.check_plan_workout_hr_target()
returns trigger
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_owner    uuid;
  v_template boolean;
begin
  if new.target_hr_min_bpm is null and new.target_hr_max_bpm is null then
    return new;
  end if;
  if tg_op = 'UPDATE'
     and new.target_hr_min_bpm is not distinct from old.target_hr_min_bpm
     and new.target_hr_max_bpm is not distinct from old.target_hr_max_bpm
     and new.week_id = old.week_id then
    return new;
  end if;
  select tp.user_id, coalesce(tp.is_template, false)
    into v_owner, v_template
  from plan_weeks pw
  join training_plans tp on tp.id = pw.plan_id
  where pw.id = new.week_id;
  if v_template then
    raise exception using
      errcode = 'check_violation',
      message = 'plan_workouts: a heart-rate target cannot sit on a template plan';
  end if;
  if not exists (
    select 1 from user_profiles up
    where up.id = v_owner and up.health_data_consent_at is not null
  ) then
    raise exception using
      errcode = 'insufficient_privilege',
      message = 'plan_workouts: a heart-rate target needs the plan owner''s health-data consent';
  end if;
  return new;
end;
$$;

revoke execute on function private.check_plan_workout_hr_target() from public, anon, authenticated;

create trigger plan_workouts_check_hr_target
  before insert or update of target_hr_min_bpm, target_hr_max_bpm, week_id on plan_workouts
  for each row execute function private.check_plan_workout_hr_target();

-- Withdrawal re-emitted from 20270605_001, plus the two Art 9 items this
-- change adds.
create or replace function withdraw_health_data_consent()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  perform set_config('app.consent_write', 'on', true);
  -- Insert-or-update so the withdrawal ALWAYS lands a row carrying the
  -- withdrawn state — a 0-row silent no-op here means special-category
  -- data lives on while the user believes it erased.
  --
  -- `date_of_birth` is deliberately absent: it is the child-safety age
  -- record, not an Art 9 column (§ 721).
  insert into user_profiles (id)
  values (v_uid)
  on conflict (id) do update
    set health_data_consent_at = null,
        height_cm = null,
        gender = null;
  -- Art 7(3): the special-category weight series goes in the same
  -- transaction — no partial-failure window between two client calls.
  delete from body_metrics where user_id = v_uid;
  -- Heart-rate prescription on the runner's own plans, and the
  -- medication-affected flag (§ 2085).
  update plan_workouts pw
     set target_hr_min_bpm = null, target_hr_max_bpm = null
    from plan_weeks pwk
    join training_plans tp on tp.id = pwk.plan_id
   where pw.week_id = pwk.id
     and tp.user_id = v_uid
     and (pw.target_hr_min_bpm is not null or pw.target_hr_max_bpm is not null);
  update user_settings
     set prefs = prefs - 'hr_medication_affected'
   where user_id = v_uid
     and prefs ? 'hr_medication_affected';
end;
$$;

revoke all on function withdraw_health_data_consent() from public, anon;
grant execute on function withdraw_health_data_consent() to authenticated, service_role;

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
      set status = 'abandoned', updated_at = now()
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
        race_name, race_priority, race_taper_applied_at,
        target_rpe_min, target_rpe_max
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
        workout_record.race_taper_applied_at,
        workout_record.target_rpe_min, workout_record.target_rpe_max
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
      set status = 'abandoned', updated_at = now()
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
        race_name, race_priority, race_taper_applied_at,
        target_rpe_min, target_rpe_max
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
        workout_record.race_taper_applied_at,
        workout_record.target_rpe_min, workout_record.target_rpe_max
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
        race_name, race_priority, race_taper_applied_at,
        target_rpe_min, target_rpe_max
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
        workout_record.race_taper_applied_at,
        workout_record.target_rpe_min, workout_record.target_rpe_max
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
    values (
      p_plan_id, p_week_index + 1, v_src.phase,
      -- The race workouts stay behind, so their distance leaves the copy's
      -- volume with them.
      case when v_src.target_volume_m is null then null
           else greatest(0, v_src.target_volume_m - coalesce((
             select sum(wo.target_distance_m) from plan_workouts wo
             where wo.week_id = v_src.id and wo.kind = 'race'
           ), 0))
      end,
      v_src.notes
    )
    returning id into v_new_week_id;

  for workout_record in
    select * from plan_workouts where week_id = v_src.id and kind <> 'race'
  loop
    insert into plan_workouts (
      week_id, scheduled_date, kind, target_distance_m, target_duration_seconds,
      target_pace_sec_per_km, target_pace_end_sec_per_km, target_pace_tolerance_sec,
      pace_zone, structure, notes, race_taper_applied_at,
      target_rpe_min, target_rpe_max, target_hr_min_bpm, target_hr_max_bpm
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
      workout_record.race_taper_applied_at,
      workout_record.target_rpe_min, workout_record.target_rpe_max,
      workout_record.target_hr_min_bpm, workout_record.target_hr_max_bpm
    );
  end loop;

  update training_plans
    set end_date = end_date + 7, updated_at = now()
    where id = p_plan_id;

  return v_new_week_id;
end;
$function$;


revoke execute on function public.create_training_plan(jsonb, jsonb, text) from public, anon;
grant execute on function public.create_training_plan(jsonb, jsonb, text) to authenticated;

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

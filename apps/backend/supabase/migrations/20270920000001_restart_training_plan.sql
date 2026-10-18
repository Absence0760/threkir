-- Restart a plan: a fresh copy of one of the runner's own plans, starting on
-- a date they pick, made active in the same transaction that retires what it
-- replaces.
--
-- The copy carries the plan's structure: every week, every workout with its
-- targets, structure and race fields, the goal, rules and notes, all moved by
-- one day offset so each workout keeps its place in its week. It carries no
-- completion, skip or run link: those columns take their defaults.
--
-- What it retires, as `abandoned` (the replace path of the create and clone
-- RPCs, 20270903000001): every active plan of the caller's that the new window
-- overlaps, and the source plan itself while it is active or paused, since
-- restarting a plan ends the attempt in progress. A completed or abandoned
-- source keeps its status. Nothing is deleted: the source's weeks, workouts,
-- completions and run links stay as they were.
--
-- Refused:
--   * a template (is_template): templates are copied through
--     clone_plan_template, which strips owner-private fields;
--   * a start before the runner's local today (RR002). "Today" is
--     private.athlete_local_date on prefs.time_zone; with no zone on record it
--     is the UTC date less one day, so a device west of UTC, whose today can
--     be the UTC yesterday, is never refused a start it calls today. The
--     clients check against the device's date, which can run behind the
--     stored zone (a phone not yet switched after travel), so the refusal has
--     its own code and message;
--   * a plan with a race on or after the runner's local today (RR001). Moving
--     the whole plan would move race day off the real date (decisions § 2121).
--
-- The ownership check runs before the rate limit, so a request for a plan the
-- caller does not own, or one that does not exist, spends none of their budget.
--
-- Carried conservatively:
--   * assigned_by_coach_id is NOT carried: notify_plan_assigned fires on an
--     insert that names a coach, and the coach did not assign this copy. The
--     coach still reads it through the coach_athletes link like any plan.
--   * club_id is NOT carried: on a personal plan it is the club a template was
--     published to, and the copy is the runner's own, not a club template.
--   * bpm targets are carried only while the hr_prescription gate is open and
--     the runner has health-data consent on record; otherwise null, so the
--     copy never trips check_plan_workout_hr_target. RPE ranges always carry.
--   * vdot and current_5k_seconds carry: this is the owner's own data on the
--     owner's own copy, unlike the cross-user clone paths.
--
-- SECURITY DEFINER because the runner's local date comes from
-- private.athlete_local_date, which authenticated cannot execute. Ownership is
-- checked in the body (user_id = caller) since RLS is not consulted.

create or replace function public.restart_training_plan(
  p_plan_id uuid,
  p_start_date date
)
returns uuid
language plpgsql
security definer
set search_path = public, private
as $$
declare
  caller uuid := auth.uid();
  src training_plans%rowtype;
  v_tz text;
  v_today date;
  v_offset int;
  v_end date;
  v_carry_hr boolean;
  new_plan_id uuid;
  new_week_id uuid;
  week_record record;
  workout_record record;
begin
  if caller is null then
    raise exception 'restart_training_plan: not authenticated';
  end if;
  if p_start_date is null then
    raise exception using
      errcode = 'invalid_parameter_value',
      message = 'restart_training_plan: a start date is required';
  end if;

  select * into src
  from training_plans
  where id = p_plan_id and user_id = caller
  for update;
  if not found then
    raise exception 'restart_training_plan: plan % not found', p_plan_id;
  end if;
  if src.is_template then
    raise exception using
      errcode = 'invalid_parameter_value',
      message = 'restart_training_plan: a template cannot be restarted';
  end if;

  perform enforce_create_rate_limit('restart_training_plan', caller, 20, 3600);

  select us.prefs ->> 'time_zone' into v_tz
  from user_settings us
  where us.user_id = caller;
  v_today := private.athlete_local_date(v_tz, now());
  if v_tz is null then
    v_today := v_today - 1;
  end if;

  if p_start_date < v_today then
    raise exception using
      errcode = 'RR002',
      message = 'restart_training_plan: the new start date is before today';
  end if;

  if exists (
    select 1
    from plan_workouts pwo
    join plan_weeks pw on pw.id = pwo.week_id
    where pw.plan_id = src.id
      and pwo.kind = 'race'
      and pwo.scheduled_date >= v_today
  ) then
    raise exception using
      errcode = 'RR001',
      message = 'restart_training_plan: this plan has a race still ahead';
  end if;

  v_offset := p_start_date - src.start_date;
  v_end := src.end_date + v_offset;

  update training_plans
  set status = 'abandoned', updated_at = now()
  where user_id = caller
    and (
      (status = 'active'
        and daterange(start_date, end_date, '[]') && daterange(p_start_date, v_end, '[]'))
      or (id = src.id and status in ('active', 'paused'))
    );

  v_carry_hr := private.hr_prescription_enabled()
    and exists (
      select 1 from user_profiles up
      where up.id = caller and up.health_data_consent_at is not null
    );

  insert into training_plans (
    user_id, name, goal_event, goal_distance_m, goal_time_seconds,
    start_date, end_date, days_per_week, vdot, current_5k_seconds,
    status, notes, parent_template_id, is_template, is_public_template,
    source, rules
  )
  values (
    caller, src.name, src.goal_event, src.goal_distance_m, src.goal_time_seconds,
    p_start_date, v_end, src.days_per_week, src.vdot, src.current_5k_seconds,
    'active', src.notes, src.parent_template_id, false, false,
    src.source, src.rules
  )
  returning id into new_plan_id;

  for week_record in
    select * from plan_weeks where plan_id = src.id order by week_index
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
        target_rpe_min, target_rpe_max,
        target_hr_min_bpm, target_hr_max_bpm
      )
      values (
        new_week_id,
        workout_record.scheduled_date + v_offset,
        workout_record.kind, workout_record.target_distance_m,
        workout_record.target_duration_seconds,
        workout_record.target_pace_sec_per_km,
        workout_record.target_pace_end_sec_per_km,
        workout_record.target_pace_tolerance_sec,
        workout_record.pace_zone,
        workout_record.structure, workout_record.notes,
        workout_record.race_name, workout_record.race_priority,
        workout_record.race_taper_applied_at,
        workout_record.target_rpe_min, workout_record.target_rpe_max,
        case when v_carry_hr then workout_record.target_hr_min_bpm end,
        case when v_carry_hr then workout_record.target_hr_max_bpm end
      );
    end loop;
  end loop;

  return new_plan_id;
end;
$$;

revoke execute on function public.restart_training_plan(uuid, date) from public, anon;
grant execute on function public.restart_training_plan(uuid, date) to authenticated;

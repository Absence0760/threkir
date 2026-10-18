-- Changing a plan's race date mid-plan.
--
-- The race moves; the plan has to end on the new day without losing its
-- taper. The weeks still ahead are re-anchored in whole weeks so every
-- workout keeps its weekday role and stays inside the week window the clients
-- derive from start_date + 7 * week_index:
--
--   - an earlier race drops whole pre-taper weeks that have not started
--     (p_drop_week_ids), and every week after the first one dropped moves back
--     by the number of dropped weeks before it;
--   - a later race inserts p_insert_count copies of a pre-taper week
--     (p_repeat_week_id) at p_insert_at, phase build, and every week from
--     p_insert_at moves forward by that many weeks.
--
-- Then the race itself goes to p_race_date inside the (moved) race week: the
-- row already on that day takes the race's old day when that day is still
-- ahead and before the race, and is removed otherwise; the race week's days
-- after race day are removed, its volume restated, and end_date becomes the
-- race date, the shape the season planner writes (§ 2009 reads it as the A
-- race on the end date).
--
-- A repeated week carries its heart-rate targets only while the HR
-- prescription gate is open and the owner has consented, as
-- restart_training_plan does: check_plan_workout_hr_target refuses an insert
-- carrying bpm otherwise, which would fail the whole change.
--
-- The client picks the weeks (`raceDateChange`, the plan_race_date pair) from
-- the runner's local today; this checks every choice against that day before
-- writing anything: no week that has started moves or goes, a taper or race
-- week is never dropped, no completed workout and no other race is moved or
-- removed, and the race date must land in the plan's last week. A later race
-- date that runs into another active plan fails on
-- training_plans_active_no_overlap (23P01) with nothing written.
--
-- SECURITY INVOKER with an owner check, as shift_training_plan: the
-- plan_weeks / plan_workouts policies decide every write. Both uniqueness
-- constraints involved are DEFERRABLE INITIALLY IMMEDIATE (20270705000003,
-- 20270902000001) and are deferred only around the writes that pass through a
-- transient collision, then set back to immediate so a real duplicate raises
-- here rather than at COMMIT.
--
-- No column changes, so no row type is regenerated beyond gen:types picking
-- up the function.

-- The consent column is not readable under the caller's own grants, so the
-- gate is read here, for the caller only (no argument, so it is no oracle on
-- anyone else's consent).
create or replace function private.caller_may_carry_hr_targets()
returns boolean
language sql
stable
security definer
set search_path = public, private
as $$
  select private.hr_prescription_enabled()
    and exists (
      select 1 from user_profiles up
      where up.id = auth.uid() and up.health_data_consent_at is not null
    );
$$;

revoke execute on function private.caller_may_carry_hr_targets() from public, anon;
grant execute on function private.caller_may_carry_hr_targets() to authenticated;

create or replace function public.change_plan_race_date(
  p_plan_id uuid,
  p_race_date date,
  p_today date,
  p_drop_week_ids uuid[] default '{}',
  p_insert_at integer default null,
  p_insert_count integer default 0,
  p_repeat_week_id uuid default null,
  p_race_workout_id uuid default null
)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  plan_row training_plans%rowtype;
  v_drops uuid[] := coalesce(p_drop_week_ids, '{}');
  v_drop_count integer := coalesce(array_length(coalesce(p_drop_week_ids, '{}'), 1), 0);
  v_insert integer := coalesce(p_insert_count, 0);
  v_current_week integer;
  v_first_drop integer;
  v_last_index integer;
  v_last_week_id uuid;
  v_race_old date;
  v_occupant uuid;
  v_new_week_id uuid;
  v_src plan_weeks%rowtype;
  v_carry_hr boolean;
  i integer;
begin
  if caller is null then
    raise exception using
      errcode = 'insufficient_privilege',
      message = 'change_plan_race_date: not authenticated';
  end if;
  if p_race_date is null or p_today is null or abs(p_today - current_date) > 1 then
    raise exception using
      errcode = 'invalid_parameter_value',
      message = 'change_plan_race_date: today must be within a day of the server date';
  end if;
  if p_race_date <= p_today then
    raise exception using
      errcode = 'invalid_parameter_value',
      message = 'change_plan_race_date: the race date must be after today';
  end if;
  if v_insert < 0 or v_insert > 52 then
    raise exception using
      errcode = 'invalid_parameter_value',
      message = 'change_plan_race_date: insert 0 to 52 weeks';
  end if;
  if v_insert > 0 and v_drop_count > 0 then
    raise exception using
      errcode = 'invalid_parameter_value',
      message = 'change_plan_race_date: weeks are either dropped or inserted, not both';
  end if;

  select * into plan_row
  from training_plans
  where id = p_plan_id and user_id = caller
  for update;
  if not found then
    raise exception using
      errcode = 'no_data_found',
      message = format('change_plan_race_date: plan %s not found', p_plan_id);
  end if;
  if plan_row.is_template or plan_row.status not in ('active', 'paused')
     or plan_row.trimmed_at is not null then
    raise exception using
      errcode = 'invalid_parameter_value',
      message = 'change_plan_race_date: only an active or paused plan that still ends on its race';
  end if;

  v_current_week := floor((p_today - plan_row.start_date) / 7.0)::integer;

  select w.id, w.week_index into v_last_week_id, v_last_index
  from plan_weeks w
  where w.plan_id = p_plan_id
  order by w.week_index desc
  limit 1;
  if v_last_week_id is null then
    raise exception using
      errcode = 'invalid_parameter_value',
      message = 'change_plan_race_date: the plan has no weeks';
  end if;

  if p_race_workout_id is not null and not exists (
    select 1 from plan_workouts wo
    where wo.id = p_race_workout_id and wo.week_id = v_last_week_id and wo.kind = 'race'
      and wo.completed_run_id is null and not wo.manually_completed
  ) then
    raise exception using
      errcode = 'invalid_parameter_value',
      message = 'change_plan_race_date: the race to move is not an open race in the last week';
  end if;

  -- Validate the dropped weeks.
  if v_drop_count > 0 then
    if (select count(*) from plan_weeks w
        where w.plan_id = p_plan_id and w.id = any (v_drops)
          and w.week_index > v_current_week
          and w.phase not in ('taper', 'race')) <> v_drop_count then
      raise exception using
        errcode = 'invalid_parameter_value',
        message = 'change_plan_race_date: only pre-taper weeks that have not started can be dropped';
    end if;
    if exists (
      select 1 from plan_workouts wo
      where wo.week_id = any (v_drops)
        and (wo.kind = 'race' or wo.completed_run_id is not null or wo.manually_completed)
    ) then
      raise exception using
        errcode = 'invalid_parameter_value',
        message = 'change_plan_race_date: a dropped week holds a race or a completed workout';
    end if;
    select min(w.week_index) into v_first_drop
    from plan_weeks w where w.id = any (v_drops);
  end if;

  if v_insert > 0 then
    if p_insert_at is null or p_insert_at <= v_current_week or p_insert_at > v_last_index then
      raise exception using
        errcode = 'invalid_parameter_value',
        message = 'change_plan_race_date: weeks are inserted before a week that has not started';
    end if;
    select * into v_src from plan_weeks
    where id = p_repeat_week_id and plan_id = p_plan_id and phase not in ('taper', 'race')
      and week_index < p_insert_at;
    if not found then
      raise exception using
        errcode = 'invalid_parameter_value',
        message = 'change_plan_race_date: the week to repeat must be a pre-taper week of this plan';
    end if;
  end if;

  -- Nothing that moves may be history or another race.
  if exists (
    select 1 from plan_workouts wo
    join plan_weeks w on w.id = wo.week_id
    where w.plan_id = p_plan_id
      and not (w.id = any (v_drops))
      and ((v_drop_count > 0 and w.week_index > v_first_drop)
           or (v_insert > 0 and w.week_index >= p_insert_at))
      and ((wo.kind = 'race' and wo.id is distinct from p_race_workout_id)
           or wo.completed_run_id is not null or wo.manually_completed)
  ) then
    raise exception using
      errcode = 'invalid_parameter_value',
      message = 'change_plan_race_date: a week that would move holds another race or a completed workout';
  end if;

  set constraints plan_workouts_one_per_day deferred;
  set constraints plan_weeks_plan_id_week_index_key deferred;

  if v_drop_count > 0 then
    update plan_workouts wo
    set scheduled_date = wo.scheduled_date - 7 * (
      select count(*)::integer from plan_weeks d
      where d.id = any (v_drops) and d.week_index < w.week_index
    )
    from plan_weeks w
    where wo.week_id = w.id and w.plan_id = p_plan_id
      and not (w.id = any (v_drops)) and w.week_index > v_first_drop;

    update plan_weeks w
    set week_index = w.week_index - (
      select count(*)::integer from plan_weeks d
      where d.id = any (v_drops) and d.week_index < w.week_index
    )
    where w.plan_id = p_plan_id and not (w.id = any (v_drops)) and w.week_index > v_first_drop;

    delete from plan_weeks where id = any (v_drops);
  end if;

  if v_insert > 0 then
    v_carry_hr := private.caller_may_carry_hr_targets();

    update plan_workouts
    set scheduled_date = scheduled_date + 7 * v_insert
    where week_id in (
      select id from plan_weeks where plan_id = p_plan_id and week_index >= p_insert_at
    );
    update plan_weeks
    set week_index = week_index + v_insert
    where plan_id = p_plan_id and week_index >= p_insert_at;

    for i in 0 .. v_insert - 1 loop
      insert into plan_weeks (plan_id, week_index, phase, target_volume_m, notes)
      values (
        p_plan_id, p_insert_at + i, 'build',
        coalesce((select sum(wo.target_distance_m) from plan_workouts wo
                  where wo.week_id = v_src.id and wo.kind <> 'race'), 0),
        v_src.notes
      )
      returning id into v_new_week_id;

      insert into plan_workouts (
        week_id, scheduled_date, kind, target_distance_m, target_duration_seconds,
        target_pace_sec_per_km, target_pace_end_sec_per_km, target_pace_tolerance_sec,
        pace_zone, structure, notes,
        target_rpe_min, target_rpe_max, target_hr_min_bpm, target_hr_max_bpm
      )
      select v_new_week_id,
             wo.scheduled_date + 7 * (p_insert_at + i - v_src.week_index),
             wo.kind, wo.target_distance_m, wo.target_duration_seconds,
             wo.target_pace_sec_per_km, wo.target_pace_end_sec_per_km, wo.target_pace_tolerance_sec,
             wo.pace_zone, wo.structure, wo.notes,
             wo.target_rpe_min, wo.target_rpe_max,
             case when v_carry_hr then wo.target_hr_min_bpm end,
             case when v_carry_hr then wo.target_hr_max_bpm end
      from plan_workouts wo
      where wo.week_id = v_src.id and wo.kind <> 'race';
    end loop;
  end if;

  select w.week_index into v_last_index from plan_weeks w where w.id = v_last_week_id;
  if p_race_date < plan_row.start_date + 7 * v_last_index
     or p_race_date > plan_row.start_date + 7 * v_last_index + 6 then
    raise exception using
      errcode = 'invalid_parameter_value',
      message = format('change_plan_race_date: %s does not fall in the plan''s race week', p_race_date);
  end if;

  if p_race_workout_id is not null then
    select scheduled_date into v_race_old from plan_workouts where id = p_race_workout_id;
    if v_race_old <> p_race_date then
      select wo.id into v_occupant from plan_workouts wo
      where wo.week_id = v_last_week_id and wo.scheduled_date = p_race_date;
      if v_occupant is not null then
        if exists (
          select 1 from plan_workouts wo
          where wo.id = v_occupant
            and (wo.kind = 'race' or wo.completed_run_id is not null or wo.manually_completed)
        ) then
          raise exception using
            errcode = 'invalid_parameter_value',
            message = 'change_plan_race_date: the new race day holds another race or a completed workout';
        end if;
        if v_race_old > p_today and v_race_old < p_race_date then
          update plan_workouts set scheduled_date = v_race_old where id = v_occupant;
        else
          delete from plan_workouts where id = v_occupant;
        end if;
      end if;
      update plan_workouts set scheduled_date = p_race_date where id = p_race_workout_id;
    end if;
  end if;

  if exists (
    select 1 from plan_workouts wo
    where wo.week_id = v_last_week_id
      and (wo.scheduled_date > p_race_date
           or (wo.scheduled_date = p_race_date and p_race_workout_id is not null
               and wo.id <> p_race_workout_id))
      and (wo.kind = 'race' or wo.completed_run_id is not null or wo.manually_completed)
  ) then
    raise exception using
      errcode = 'invalid_parameter_value',
      message = 'change_plan_race_date: a race or a completed workout falls after the new race date';
  end if;
  delete from plan_workouts
  where week_id = v_last_week_id and scheduled_date > p_race_date;

  set constraints plan_workouts_one_per_day immediate;
  set constraints plan_weeks_plan_id_week_index_key immediate;

  update plan_weeks
  set target_volume_m = coalesce((
    select sum(wo.target_distance_m) from plan_workouts wo where wo.week_id = v_last_week_id
  ), 0)
  where id = v_last_week_id;

  update training_plans
  set end_date = p_race_date, updated_at = now()
  where id = p_plan_id;
end;
$$;

revoke execute on function public.change_plan_race_date(uuid, date, date, uuid[], integer, integer, uuid, uuid) from public, anon;
grant execute on function public.change_plan_race_date(uuid, date, date, uuid[], integer, integer, uuid, uuid) to authenticated;

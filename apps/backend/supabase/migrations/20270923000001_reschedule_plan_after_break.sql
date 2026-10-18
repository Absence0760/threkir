-- Picking a plan back up after a break of a week or more (decisions § 2128).
--
-- The weeks the runner missed are history and stay where they are. This runs
-- the latest weeks up to the current one again, from next week:
--
--   - p_repeat_week_ids are copied, oldest first, into new weeks at the
--     current week + 1, + 2, ... (no completion, no skip, no run link, no race
--     row), each workout keeping its weekday;
--   - every week after the current one moves back by the number of copies,
--     less the dropped weeks before it;
--   - a plan that ends on a race keeps its race day: it must drop exactly as
--     many pre-taper weeks that have not started (p_drop_week_ids) as it
--     copies, so its race week does not move. A plan without one drops nothing
--     and its end date moves back by the copies.
--
-- The client picks the weeks (`planBreakChange`, the plan_break pair) from the
-- runner's local today; this checks every choice against that day before
-- writing anything: only weeks that have fully or partly passed are copied
-- and none of them is a taper or race week; only pre-taper weeks that have
-- not started, hold no race and nothing done are dropped; and nothing that
-- moves holds a race or a completed workout. A later end that runs into
-- another active plan fails on training_plans_active_no_overlap (23P01) with
-- nothing written.
--
-- The same transaction records the offer as answered in
-- user_settings.prefs.plan_break_dismissed ({plan_id, from, until}), so
-- neither the web card nor the phone's offers the same break again and the
-- plan nudge does not judge the weeks it covered; and it answers the
-- missed-workout prompt (missed_ack_at, 20270921000001) for every unanswered
-- open workout the break covered, so the prompt does not then offer a
-- make-up for a long run the re-run weeks already restore. Copies take
-- missed_ack_at's null default (explicit column list), and a moved workout
-- loses any answer through plan_workouts_clear_missed_ack.
--
-- A copied week carries its heart-rate targets only while the HR prescription
-- gate is open and the owner has consented (private.caller_may_carry_hr_targets,
-- 20270919000001); check_plan_workout_hr_target would refuse the insert
-- otherwise and fail the whole change.
--
-- SECURITY INVOKER with an owner check, as change_plan_race_date: the
-- plan_weeks / plan_workouts / user_settings policies decide every write. The
-- two uniqueness constraints a move passes through are DEFERRABLE INITIALLY
-- IMMEDIATE and are deferred only around those writes.

create or replace function public.reschedule_plan_after_break(
  p_plan_id uuid,
  p_today date,
  p_break_from date,
  p_repeat_week_ids uuid[],
  p_drop_week_ids uuid[] default '{}'
)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  plan_row training_plans%rowtype;
  v_repeat uuid[] := coalesce(p_repeat_week_ids, '{}');
  v_drops uuid[] := coalesce(p_drop_week_ids, '{}');
  v_k integer := coalesce(array_length(coalesce(p_repeat_week_ids, '{}'), 1), 0);
  v_drop_count integer := coalesce(array_length(coalesce(p_drop_week_ids, '{}'), 1), 0);
  v_current integer;
  v_last_index integer;
  v_last_phase text;
  v_carry_hr boolean;
  v_src plan_weeks%rowtype;
  v_new_week_id uuid;
  v_slot integer := 0;
begin
  if caller is null then
    raise exception using
      errcode = 'insufficient_privilege',
      message = 'reschedule_plan_after_break: not authenticated';
  end if;
  if p_today is null or abs(p_today - current_date) > 1 then
    raise exception using
      errcode = 'invalid_parameter_value',
      message = 'reschedule_plan_after_break: today must be within a day of the server date';
  end if;
  if p_break_from is null or p_break_from > p_today then
    raise exception using
      errcode = 'invalid_parameter_value',
      message = 'reschedule_plan_after_break: the break must start on or before today';
  end if;
  if v_k < 1 or v_k > 52 then
    raise exception using
      errcode = 'invalid_parameter_value',
      message = 'reschedule_plan_after_break: repeat 1 to 52 weeks';
  end if;

  select * into plan_row
  from training_plans
  where id = p_plan_id and user_id = caller
  for update;
  if not found then
    raise exception using
      errcode = 'no_data_found',
      message = format('reschedule_plan_after_break: plan %s not found', p_plan_id);
  end if;
  if plan_row.is_template or plan_row.status <> 'active' or plan_row.trimmed_at is not null
     or p_today < plan_row.start_date or p_today > plan_row.end_date then
    raise exception using
      errcode = 'invalid_parameter_value',
      message = 'reschedule_plan_after_break: only an active plan that is under way';
  end if;

  v_current := floor((p_today - plan_row.start_date) / 7.0)::integer;

  select w.week_index, w.phase::text into v_last_index, v_last_phase
  from plan_weeks w
  where w.plan_id = p_plan_id
  order by w.week_index desc
  limit 1;
  if v_last_index is null or v_last_index <= v_current then
    raise exception using
      errcode = 'invalid_parameter_value',
      message = 'reschedule_plan_after_break: the plan has no week after this one';
  end if;

  if (select count(distinct w.id) from plan_weeks w
      where w.plan_id = p_plan_id and w.id = any (v_repeat)
        and w.week_index <= v_current and w.phase not in ('taper', 'race')) <> v_k then
    raise exception using
      errcode = 'invalid_parameter_value',
      message = 'reschedule_plan_after_break: only pre-taper weeks up to this one can run again';
  end if;

  if v_last_phase = 'race' and v_drop_count <> v_k then
    raise exception using
      errcode = 'invalid_parameter_value',
      message = 'reschedule_plan_after_break: a race plan drops as many weeks as it repeats';
  end if;
  if v_last_phase <> 'race' and v_drop_count > 0 then
    raise exception using
      errcode = 'invalid_parameter_value',
      message = 'reschedule_plan_after_break: a plan without a race drops no weeks';
  end if;
  if v_drop_count > 0 then
    if (select count(distinct w.id) from plan_weeks w
        where w.plan_id = p_plan_id and w.id = any (v_drops)
          and w.week_index > v_current and w.phase not in ('taper', 'race')) <> v_drop_count then
      raise exception using
        errcode = 'invalid_parameter_value',
        message = 'reschedule_plan_after_break: only pre-taper weeks that have not started can be dropped';
    end if;
    if exists (
      select 1 from plan_workouts wo
      where wo.week_id = any (v_drops)
        and (wo.kind = 'race' or wo.completed_run_id is not null or wo.manually_completed)
    ) then
      raise exception using
        errcode = 'invalid_parameter_value',
        message = 'reschedule_plan_after_break: a dropped week holds a race or a completed workout';
    end if;
  end if;

  if exists (
    select 1 from plan_workouts wo
    join plan_weeks w on w.id = wo.week_id
    where w.plan_id = p_plan_id and w.week_index > v_current and not (w.id = any (v_drops))
      and v_k <> (select count(*)::integer from plan_weeks d
                  where d.id = any (v_drops) and d.week_index < w.week_index)
      and (wo.kind = 'race' or wo.completed_run_id is not null or wo.manually_completed)
  ) then
    raise exception using
      errcode = 'invalid_parameter_value',
      message = 'reschedule_plan_after_break: a week that would move holds a race or a completed workout';
  end if;

  set constraints plan_workouts_one_per_day deferred;
  set constraints plan_weeks_plan_id_week_index_key deferred;

  update plan_workouts wo
  set scheduled_date = wo.scheduled_date + 7 * (v_k - (
    select count(*)::integer from plan_weeks d
    where d.id = any (v_drops) and d.week_index < w.week_index
  ))
  from plan_weeks w
  where wo.week_id = w.id and w.plan_id = p_plan_id
    and w.week_index > v_current and not (w.id = any (v_drops))
    and v_k <> (select count(*)::integer from plan_weeks d
                where d.id = any (v_drops) and d.week_index < w.week_index);

  update plan_weeks w
  set week_index = w.week_index + v_k - (
    select count(*)::integer from plan_weeks d
    where d.id = any (v_drops) and d.week_index < w.week_index
  )
  where w.plan_id = p_plan_id and w.week_index > v_current and not (w.id = any (v_drops))
    and v_k <> (select count(*)::integer from plan_weeks d
                where d.id = any (v_drops) and d.week_index < w.week_index);

  delete from plan_weeks where id = any (v_drops);

  v_carry_hr := private.caller_may_carry_hr_targets();

  for v_src in
    select * from plan_weeks w
    where w.plan_id = p_plan_id and w.id = any (v_repeat)
    order by w.week_index
  loop
    v_slot := v_slot + 1;
    insert into plan_weeks (plan_id, week_index, phase, target_volume_m, notes)
    values (
      p_plan_id, v_current + v_slot, v_src.phase,
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
           wo.scheduled_date + 7 * (v_current + v_slot - v_src.week_index),
           wo.kind, wo.target_distance_m, wo.target_duration_seconds,
           wo.target_pace_sec_per_km, wo.target_pace_end_sec_per_km, wo.target_pace_tolerance_sec,
           wo.pace_zone, wo.structure, wo.notes,
           wo.target_rpe_min, wo.target_rpe_max,
           case when v_carry_hr then wo.target_hr_min_bpm end,
           case when v_carry_hr then wo.target_hr_max_bpm end
    from plan_workouts wo
    where wo.week_id = v_src.id and wo.kind <> 'race';
  end loop;

  set constraints plan_workouts_one_per_day immediate;
  set constraints plan_weeks_plan_id_week_index_key immediate;

  update training_plans
  set end_date = end_date + 7 * (v_k - v_drop_count), updated_at = now()
  where id = p_plan_id;

  update plan_workouts wo
  set missed_ack_at = now()
  from plan_weeks w
  where wo.week_id = w.id and w.plan_id = p_plan_id
    and wo.kind <> 'rest'
    and wo.completed_run_id is null and not wo.manually_completed
    and wo.skipped_at is null and wo.missed_ack_at is null
    and wo.scheduled_date >= p_break_from and wo.scheduled_date < p_today;

  insert into user_settings (user_id, prefs)
  values (caller, jsonb_build_object('plan_break_dismissed',
            jsonb_build_object('plan_id', p_plan_id, 'from', p_break_from, 'until', p_today)))
  on conflict (user_id) do update
    set prefs = coalesce(user_settings.prefs, '{}'::jsonb) || excluded.prefs,
        updated_at = now();
end;
$$;

revoke execute on function public.reschedule_plan_after_break(uuid, date, date, uuid[], uuid[]) from public, anon;
grant execute on function public.reschedule_plan_after_break(uuid, date, date, uuid[], uuid[]) to authenticated;

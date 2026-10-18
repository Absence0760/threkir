-- "Too hard? Repeat this week" (issue #1186): run this week, or the week that
-- just finished, again next week, and push every later week back by one.
--
-- Walk-run plans have no other answer to a niggle than skip or abandon, so the
-- clients surface it prominently there; it applies to any active plan.
--
-- It is the one-week case of what reschedule_plan_after_break (20270923000001,
-- decisions § 2128) already does after a break, so that function's body moves
-- into private.repeat_plan_weeks and both RPCs call it:
--
--   - the repeated week is copied into a new week at the current week + 1 (no
--     completion, no skip, no run link, no race row), each workout keeping its
--     weekday;
--   - every later week moves back one whole week;
--   - a plan that ends on a race keeps its race day: it drops one pre-taper
--     week that has not started (p_drop_week_id, picked by the client in
--     change_plan_race_date's order) instead of moving its end. A race plan
--     with no such week is refused, and the clients point at "Change race
--     date". A plan without a race moves its end date back a week, and a later
--     end that runs into another active plan fails on
--     training_plans_active_no_overlap (23P01) with nothing written;
--   - nothing done, no other race and nothing that has started moves.
--
-- What repeat_plan_week adds over the shared body: only the current week or
-- the one before it can run again ("this week was too hard", or "last week
-- was"), and an hourly rate limit. The ownership check runs before the rate
-- limit, so a request for a plan the caller does not own spends none of their
-- budget. It does not touch user_settings.prefs.plan_break_dismissed: that key
-- answers a break offer, and this is not one.
--
-- SECURITY DEFINER because enforce_create_rate_limit is not executable by
-- authenticated (20270626000001). RLS is therefore not consulted, so the
-- shared body locks the plan on user_id = auth.uid() and checks every week id
-- it is handed against that plan. reschedule_plan_after_break stays SECURITY
-- INVOKER, so its writes are still decided by the plan_weeks / plan_workouts /
-- user_settings policies; the shared body is invoker for that reason and is
-- granted to authenticated. Called directly it is no more than
-- reschedule_plan_after_break without the prefs write, under the caller's RLS.
--
-- reschedule_plan_after_break's signature, checks, their order and every
-- message are unchanged (its pgTAP suite pins the messages).
--
-- Online-safety: CREATE OR REPLACE FUNCTION takes no lock on any relation;
-- no column changes, so only gen:types picks up the new RPC.

create or replace function private.repeat_plan_weeks(
  p_fn text,
  p_plan_id uuid,
  p_today date,
  p_repeat_week_ids uuid[],
  p_drop_week_ids uuid[]
)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
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
  select * into plan_row
  from training_plans
  where id = p_plan_id and user_id = auth.uid()
  for update;
  if not found then
    raise exception using
      errcode = 'no_data_found',
      message = format('%s: plan %s not found', p_fn, p_plan_id);
  end if;
  if plan_row.is_template or plan_row.status <> 'active' or plan_row.trimmed_at is not null
     or p_today < plan_row.start_date or p_today > plan_row.end_date then
    raise exception using
      errcode = 'invalid_parameter_value',
      message = p_fn || ': only an active plan that is under way';
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
      message = p_fn || ': the plan has no week after this one';
  end if;

  if (select count(distinct w.id) from plan_weeks w
      where w.plan_id = p_plan_id and w.id = any (v_repeat)
        and w.week_index <= v_current and w.phase not in ('taper', 'race')) <> v_k then
    raise exception using
      errcode = 'invalid_parameter_value',
      message = p_fn || ': only pre-taper weeks up to this one can run again';
  end if;

  if v_last_phase = 'race' and v_drop_count <> v_k then
    raise exception using
      errcode = 'invalid_parameter_value',
      message = p_fn || ': a race plan drops as many weeks as it repeats';
  end if;
  if v_last_phase <> 'race' and v_drop_count > 0 then
    raise exception using
      errcode = 'invalid_parameter_value',
      message = p_fn || ': a plan without a race drops no weeks';
  end if;
  if v_drop_count > 0 then
    if (select count(distinct w.id) from plan_weeks w
        where w.plan_id = p_plan_id and w.id = any (v_drops)
          and w.week_index > v_current and w.phase not in ('taper', 'race')) <> v_drop_count then
      raise exception using
        errcode = 'invalid_parameter_value',
        message = p_fn || ': only pre-taper weeks that have not started can be dropped';
    end if;
    if exists (
      select 1 from plan_workouts wo
      where wo.week_id = any (v_drops)
        and (wo.kind = 'race' or wo.completed_run_id is not null or wo.manually_completed)
    ) then
      raise exception using
        errcode = 'invalid_parameter_value',
        message = p_fn || ': a dropped week holds a race or a completed workout';
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
      message = p_fn || ': a week that would move holds a race or a completed workout';
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

  return v_new_week_id;
end;
$$;

revoke execute on function private.repeat_plan_weeks(text, uuid, date, uuid[], uuid[]) from public, anon;
grant execute on function private.repeat_plan_weeks(text, uuid, date, uuid[], uuid[]) to authenticated;

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
  v_k integer := coalesce(array_length(coalesce(p_repeat_week_ids, '{}'), 1), 0);
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

  perform private.repeat_plan_weeks(
    'reschedule_plan_after_break', p_plan_id, p_today, p_repeat_week_ids, p_drop_week_ids
  );

  insert into user_settings (user_id, prefs)
  values (caller, jsonb_build_object('plan_break_dismissed',
            jsonb_build_object('plan_id', p_plan_id, 'from', p_break_from)))
  on conflict (user_id) do update
    set prefs = coalesce(user_settings.prefs, '{}'::jsonb) || excluded.prefs,
        updated_at = now();
end;
$$;

revoke execute on function public.reschedule_plan_after_break(uuid, date, date, uuid[], uuid[]) from public, anon;
grant execute on function public.reschedule_plan_after_break(uuid, date, date, uuid[], uuid[]) to authenticated;

create or replace function public.repeat_plan_week(
  p_plan_id uuid,
  p_today date,
  p_week_id uuid,
  p_drop_week_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public, private
as $$
declare
  caller uuid := auth.uid();
  plan_row training_plans%rowtype;
  v_current integer;
begin
  if caller is null then
    raise exception using
      errcode = 'insufficient_privilege',
      message = 'repeat_plan_week: not authenticated';
  end if;

  select * into plan_row
  from training_plans
  where id = p_plan_id and user_id = caller
  for update;
  if not found then
    raise exception using
      errcode = 'no_data_found',
      message = format('repeat_plan_week: plan %s not found', p_plan_id);
  end if;

  perform enforce_create_rate_limit('repeat_plan_week', caller, 20, 3600);

  if p_today is null or abs(p_today - current_date) > 1 then
    raise exception using
      errcode = 'invalid_parameter_value',
      message = 'repeat_plan_week: today must be within a day of the server date';
  end if;
  if plan_row.is_template or plan_row.status <> 'active' or plan_row.trimmed_at is not null
     or p_today < plan_row.start_date or p_today > plan_row.end_date then
    raise exception using
      errcode = 'invalid_parameter_value',
      message = 'repeat_plan_week: only an active plan that is under way';
  end if;

  v_current := floor((p_today - plan_row.start_date) / 7.0)::integer;
  if not exists (
    select 1 from plan_weeks w
    where w.id = p_week_id and w.plan_id = p_plan_id
      and w.week_index between v_current - 1 and v_current
  ) then
    raise exception using
      errcode = 'invalid_parameter_value',
      message = 'repeat_plan_week: only this week or last week can run again';
  end if;

  return private.repeat_plan_weeks(
    'repeat_plan_week', p_plan_id, p_today, array[p_week_id],
    case when p_drop_week_id is null then '{}'::uuid[] else array[p_drop_week_id] end
  );
end;
$$;

revoke execute on function public.repeat_plan_week(uuid, date, uuid, uuid) from public, anon;
grant execute on function public.repeat_plan_week(uuid, date, uuid, uuid) to authenticated;

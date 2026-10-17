-- Moving a planned workout to another day (issue #1186, decisions § 2073).
--
-- `plan_workouts_one_per_day` (20260421_001) is UNIQUE (week_id,
-- scheduled_date), checked per row, and a generated week stores seven rows,
-- rest days included. So every way of changing a date collided with a row
-- that was about to move out of the way:
--
--   - the AI adjust's `swap_days` sent two parallel updates that trade
--     dates, and the first one always met the other's row;
--   - its `move_workout` onto any day of a generated week met that day's row
--     (usually a rest day);
--   - `shift_training_plan` moved every row by p_days in one statement, which
--     on a dense week meets the row one day later unless p_days is a multiple
--     of seven (a whole week moves past itself without touching another).
--
-- The constraint becomes DEFERRABLE INITIALLY IMMEDIATE, as
-- 20270705000003 did for `plan_weeks`: every other writer still gets its
-- 23505 at the statement, and the functions below defer it only for the
-- span of their own writes, then set it back to IMMEDIATE so a duplicate
-- raises inside the call rather than at COMMIT.
--
-- reschedule_plan_workouts(plan, [{id, date}]) is the primitive: it sets the
-- dates of several workouts of one plan in one transaction. A workout stays
-- in its own plan week (so no week's volume moves with it, the rule the AI
-- adjust already followed) and inside the plan's dates; a completed workout
-- never moves, because it records what happened on that day. SECURITY
-- INVOKER: the plan_workouts UPDATE policies decide who may write (the
-- owner, a club admin of a club plan, an active coach of a personal plan),
-- and an update RLS filtered out is reported as 42501 instead of silently
-- doing nothing.
--
-- move_plan_workout(workout, date) is what a runner means by "move it to
-- Thursday": when Thursday already holds a row, the two trade days, so a
-- generated week's rest day takes the moved workout's old day. It returns
-- the id of the workout it swapped with, or null.
--
-- ── Online safety (docs/backend/migration_locks.md) ────────────────────────
-- Deferrability can only change by re-creating the constraint. The new
-- unique index is built first, under SHARE (reads continue, writes wait for
-- the build), and then attached with ADD CONSTRAINT … USING INDEX, so the
-- ACCESS EXCLUSIVE the swap needs is held only for the catalog flip, not for
-- the index build. `plan_workouts` is not in the playbook's high-volume set.
--
-- No column moves, so neither row-type generator has a table to regenerate;
-- `gen:types` picks up the two new functions.

create unique index plan_workouts_one_per_day_deferrable
  on plan_workouts (week_id, scheduled_date);

alter table plan_workouts
  drop constraint plan_workouts_one_per_day,
  add constraint plan_workouts_one_per_day
    unique using index plan_workouts_one_per_day_deferrable
    deferrable initially immediate;

create or replace function public.reschedule_plan_workouts(p_plan_id uuid, p_moves jsonb)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  v_start date;
  v_end date;
  mv jsonb;
  v_id uuid;
  v_date date;
  v_old date;
  v_week_index integer;
  v_done boolean;
  v_week_start date;
  v_rows integer;
  seen uuid[] := '{}';
  ids uuid[] := '{}';
  dates date[] := '{}';
  i integer;
begin
  if caller is null then
    raise exception using
      errcode = 'insufficient_privilege',
      message = 'reschedule_plan_workouts: not authenticated';
  end if;
  if p_moves is null or jsonb_typeof(p_moves) <> 'array' then
    raise exception using
      errcode = 'invalid_parameter_value',
      message = 'reschedule_plan_workouts: moves must be a list';
  end if;

  select start_date, end_date into v_start, v_end
  from training_plans
  where id = p_plan_id;
  if not found then
    raise exception using
      errcode = 'no_data_found',
      message = format('reschedule_plan_workouts: plan %s not found', p_plan_id);
  end if;

  -- Validate every move before writing any, so a bad one changes nothing.
  for mv in select value from jsonb_array_elements(p_moves) loop
    if jsonb_typeof(mv) <> 'object' or mv->>'id' is null or mv->>'date' is null then
      raise exception using
        errcode = 'invalid_parameter_value',
        message = 'reschedule_plan_workouts: every move needs an id and a date';
    end if;
    v_id := (mv->>'id')::uuid;
    v_date := (mv->>'date')::date;
    if v_id = any (seen) then
      raise exception using
        errcode = 'invalid_parameter_value',
        message = format('reschedule_plan_workouts: workout %s is moved twice', v_id);
    end if;
    seen := seen || v_id;

    select wo.scheduled_date,
           w.week_index,
           (wo.completed_run_id is not null or wo.manually_completed)
      into v_old, v_week_index, v_done
    from plan_workouts wo
    join plan_weeks w on w.id = wo.week_id
    where wo.id = v_id and w.plan_id = p_plan_id;
    if not found then
      raise exception using
        errcode = 'invalid_parameter_value',
        message = format('reschedule_plan_workouts: workout %s is not in plan %s', v_id, p_plan_id);
    end if;
    if v_old = v_date then
      continue;
    end if;
    if v_done then
      raise exception using
        errcode = 'invalid_parameter_value',
        message = format('reschedule_plan_workouts: workout %s is completed and keeps its day', v_id);
    end if;

    v_week_start := v_start + v_week_index * 7;
    if v_date < v_week_start
       or v_date > least(v_week_start + 6, v_end) then
      raise exception using
        errcode = 'invalid_parameter_value',
        message = format('reschedule_plan_workouts: %s is outside the week of workout %s', v_date, v_id);
    end if;

    ids := ids || v_id;
    dates := dates || v_date;
  end loop;

  if coalesce(array_length(ids, 1), 0) = 0 then
    return;
  end if;

  set constraints plan_workouts_one_per_day deferred;
  for i in 1 .. array_length(ids, 1) loop
    update plan_workouts set scheduled_date = dates[i] where id = ids[i];
    get diagnostics v_rows = row_count;
    if v_rows <> 1 then
      raise exception using
        errcode = 'insufficient_privilege',
        message = format('reschedule_plan_workouts: not authorised to edit plan %s', p_plan_id);
    end if;
  end loop;
  set constraints plan_workouts_one_per_day immediate;
end;
$$;

revoke execute on function public.reschedule_plan_workouts(uuid, jsonb) from public, anon;
grant execute on function public.reschedule_plan_workouts(uuid, jsonb) to authenticated;

create or replace function public.move_plan_workout(p_workout_id uuid, p_date date)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_plan uuid;
  v_week uuid;
  v_old date;
  v_occupant uuid;
begin
  if auth.uid() is null then
    raise exception using
      errcode = 'insufficient_privilege',
      message = 'move_plan_workout: not authenticated';
  end if;
  if p_date is null then
    raise exception using
      errcode = 'invalid_parameter_value',
      message = 'move_plan_workout: a date is required';
  end if;

  select w.plan_id, wo.week_id, wo.scheduled_date
    into v_plan, v_week, v_old
  from plan_workouts wo
  join plan_weeks w on w.id = wo.week_id
  where wo.id = p_workout_id;
  if not found then
    raise exception using
      errcode = 'no_data_found',
      message = format('move_plan_workout: workout %s not found', p_workout_id);
  end if;
  if v_old = p_date then
    return null;
  end if;

  select id into v_occupant
  from plan_workouts
  where week_id = v_week and scheduled_date = p_date;

  perform reschedule_plan_workouts(
    v_plan,
    case
      when v_occupant is null then
        jsonb_build_array(jsonb_build_object('id', p_workout_id, 'date', p_date))
      else
        jsonb_build_array(
          jsonb_build_object('id', p_workout_id, 'date', p_date),
          jsonb_build_object('id', v_occupant, 'date', v_old)
        )
    end
  );
  return v_occupant;
end;
$$;

revoke execute on function public.move_plan_workout(uuid, date) from public, anon;
grant execute on function public.move_plan_workout(uuid, date) to authenticated;

-- Re-emitted whole (latest body 20270830000003) to defer the per-day
-- uniqueness for the span of its one-statement move: shifting a dense week
-- by anything but a multiple of seven otherwise meets the next day's row.
create or replace function public.shift_training_plan(
  p_plan_id uuid,
  p_days integer,
  p_shift_following boolean default false
)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  plan_row training_plans%rowtype;
  target record;
begin
  if auth.uid() is null then
    raise exception 'shift_training_plan: not authenticated';
  end if;
  if p_days is null or abs(p_days) > 366 then
    raise exception 'shift_training_plan: shift must be between -366 and 366 days';
  end if;

  select * into plan_row
  from training_plans
  where id = p_plan_id and user_id = auth.uid()
  for update;
  if not found then
    raise exception 'shift_training_plan: plan % not found', p_plan_id;
  end if;
  if p_days = 0 then
    return;
  end if;

  for target in
    select tp.id
    from training_plans tp
    where tp.id = p_plan_id
       or (p_shift_following
           and tp.user_id = auth.uid()
           and tp.status = 'active'
           and not tp.is_template
           and tp.start_date > plan_row.end_date)
    order by
      case when p_days > 0 then tp.start_date end desc,
      case when p_days < 0 then tp.start_date end asc
  loop
    set constraints plan_workouts_one_per_day deferred;
    update plan_workouts wo
    set scheduled_date = wo.scheduled_date + p_days
    from plan_weeks w
    where wo.week_id = w.id and w.plan_id = target.id;
    set constraints plan_workouts_one_per_day immediate;

    update training_plans
    set start_date = start_date + p_days,
        end_date = end_date + p_days,
        updated_at = now()
    where id = target.id;
  end loop;
end;
$$;

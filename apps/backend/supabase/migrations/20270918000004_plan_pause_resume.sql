-- Pausing a plan used to change only its status, so on resume every week that
-- passed while it sat paused came back as missed (issue #1186). This records
-- when a plan was paused and lets a resume push the weeks that had not started
-- yet back by whole weeks, in one transaction.
--
-- Whole weeks, from the week after the pause: those weeks hold no history, and
-- moving them by 7-day steps keeps every workout inside its week's window,
-- which the clients derive from start_date + 7 * week_index. The week the
-- runner paused in stays where it is, so nothing already done moves. The
-- client computes the two numbers (the `plan_resume` parity pair) from the
-- runner's local dates; this applies them.

alter table training_plans add column paused_at timestamptz;

comment on column training_plans.paused_at is
  'When the plan last went to status paused; null otherwise. Maintained by '
  'training_plans_stamp_paused_at. Plans paused before this column existed read null, '
  'which offers no shift on resume.';

create or replace function private.stamp_plan_paused_at()
returns trigger
language plpgsql
set search_path = public, pg_catalog
as $$
begin
  if new.status = 'paused' and old.status is distinct from 'paused' then
    new.paused_at := now();
  elsif new.status is distinct from 'paused' then
    new.paused_at := null;
  end if;
  return new;
end;
$$;

create trigger training_plans_stamp_paused_at
  before update of status on training_plans
  for each row execute function private.stamp_plan_paused_at();

create or replace function public.resume_training_plan(
  p_plan_id uuid,
  p_from_week_index integer default null,
  p_shift_weeks integer default 0
)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  v_status text;
  v_moved integer;
begin
  if caller is null then
    raise exception 'resume_training_plan: not authenticated';
  end if;
  if p_shift_weeks is null or p_shift_weeks < 0 or p_shift_weeks > 52 then
    raise exception using
      errcode = 'invalid_parameter_value',
      message = 'resume_training_plan: shift must be 0 to 52 weeks';
  end if;
  if p_shift_weeks > 0 and (p_from_week_index is null or p_from_week_index < 1) then
    raise exception using
      errcode = 'invalid_parameter_value',
      message = 'resume_training_plan: a shift needs the first week to move, after week 0';
  end if;

  select status into v_status
  from training_plans
  where id = p_plan_id and user_id = caller
  for update;
  if not found then
    raise exception 'resume_training_plan: plan % not found', p_plan_id;
  end if;
  if v_status <> 'paused' then
    raise exception using
      errcode = 'invalid_parameter_value',
      message = 'resume_training_plan: plan is not paused';
  end if;

  if p_shift_weeks > 0 then
    update plan_workouts
      set scheduled_date = scheduled_date + 7 * p_shift_weeks
      where week_id in (
        select id from plan_weeks
        where plan_id = p_plan_id and week_index >= p_from_week_index
      );
    set constraints plan_weeks_plan_id_week_index_key deferred;
    update plan_weeks set week_index = week_index + p_shift_weeks
      where plan_id = p_plan_id and week_index >= p_from_week_index;
    get diagnostics v_moved = row_count;
    set constraints plan_weeks_plan_id_week_index_key immediate;
    if v_moved > 0 then
      update training_plans
        set end_date = end_date + 7 * p_shift_weeks
        where id = p_plan_id;
    end if;
  end if;

  update training_plans
    set status = 'active', updated_at = now()
    where id = p_plan_id;
end;
$$;

revoke execute on function public.resume_training_plan(uuid, integer, integer) from public, anon;
grant execute on function public.resume_training_plan(uuid, integer, integer) to authenticated;

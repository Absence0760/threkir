-- A plan's goal time and the paces derived from it change together (issue
-- #1186). The client computes the per-workout patches (`plan_repace`, a TS↔Dart
-- parity pair) and this writes the goal, the plan's VDOT and those patches in
-- one transaction, so a failure part-way can never leave a new goal over the
-- old paces or the reverse. The workout half is apply_workout_adjustments,
-- called as is, so its key whitelist, owner check and week-volume restatement
-- apply unchanged.

create or replace function public.set_plan_goal_time(
  p_plan_id uuid,
  p_goal_time_seconds integer,
  p_vdot numeric,
  p_changes jsonb
)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  caller uuid := auth.uid();
begin
  if caller is null then
    raise exception 'set_plan_goal_time: not authenticated';
  end if;
  if p_goal_time_seconds is not null and p_goal_time_seconds <= 0 then
    raise exception using
      errcode = 'invalid_parameter_value',
      message = 'set_plan_goal_time: goal time must be positive';
  end if;

  update training_plans
  set goal_time_seconds = p_goal_time_seconds,
      vdot = coalesce(p_vdot, vdot),
      updated_at = now()
  where id = p_plan_id and user_id = caller;
  if not found then
    raise exception 'set_plan_goal_time: plan % not found', p_plan_id;
  end if;

  perform public.apply_workout_adjustments(p_plan_id, coalesce(p_changes, '[]'::jsonb));
end;
$$;

revoke execute on function public.set_plan_goal_time(uuid, integer, numeric, jsonb) from public, anon;
grant execute on function public.set_plan_goal_time(uuid, integer, numeric, jsonb) to authenticated;

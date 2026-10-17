-- A heart-rate target cannot reach a template through the plan row or a week
-- move (issue #1186 security review; decisions § 2096).
--
-- private.check_plan_workout_hr_target refuses a bpm target on a template, but
-- it fires on plan_workouts writes only. Two other writes put existing bpm
-- targets under a template without touching a workout:
--
--   * `update training_plans set is_template = true, is_public_template = true,
--     status = 'completed'` on a plan whose workouts carry bpm targets. The
--     owner policy allows it, strip_template_private_fields nulls vdot / notes
--     / current_5k_seconds and nothing else, and the plan library then exposes
--     the targets -- someone else's Art 9 prescription.
--   * `update plan_weeks set plan_id = <a template>` on a week whose workouts
--     carry them.
--
-- The flip now nulls the plan's bpm targets in the same statement, as the
-- other private fields are nulled; a template holds none by rule, so this is
-- the strip, not a refusal. A week move into a template plan refuses (23514)
-- while the week carries a bpm target, the same answer the workout trigger
-- gives a direct write. Neither is gated on the hr_prescription flag: both
-- only ever remove or refuse heart-rate data.

create or replace function private.strip_template_hr_targets()
returns trigger
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
begin
  update plan_workouts pw
     set target_hr_min_bpm = null, target_hr_max_bpm = null
    from plan_weeks pwk
   where pw.week_id = pwk.id
     and pwk.plan_id = new.id
     and (pw.target_hr_min_bpm is not null or pw.target_hr_max_bpm is not null);
  return null;
end;
$$;

revoke execute on function private.strip_template_hr_targets() from public, anon, authenticated;

create trigger training_plans_strip_template_hr_targets
  after update of is_template on training_plans
  for each row
  when (new.is_template and not coalesce(old.is_template, false))
  execute function private.strip_template_hr_targets();

create or replace function private.check_plan_week_hr_move()
returns trigger
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
begin
  if new.plan_id is not distinct from old.plan_id then
    return new;
  end if;
  if exists (
       select 1 from training_plans tp
       where tp.id = new.plan_id and coalesce(tp.is_template, false)
     )
     and exists (
       select 1 from plan_workouts pw
       where pw.week_id = new.id
         and (pw.target_hr_min_bpm is not null or pw.target_hr_max_bpm is not null)
     ) then
    raise exception using
      errcode = 'check_violation',
      message = 'plan_weeks: a week carrying a heart-rate target cannot move into a template plan';
  end if;
  return new;
end;
$$;

revoke execute on function private.check_plan_week_hr_move() from public, anon, authenticated;

create trigger plan_weeks_check_hr_move
  before update of plan_id on plan_weeks
  for each row execute function private.check_plan_week_hr_move();

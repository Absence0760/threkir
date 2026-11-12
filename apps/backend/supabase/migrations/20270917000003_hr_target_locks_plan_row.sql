-- A bpm target and a template flip on the same plan serialise (issue #1186
-- second review; decisions § 2107).
--
-- private.check_plan_workout_hr_target refuses a bpm target on a template
-- plan, and since 20270915000005 flipping a plan to a template nulls its bpm
-- targets. Each read the other's row without a lock, so in two concurrent
-- transactions an insert could read is_template = false while a flip's
-- strip, running before the insert committed, did not see the new target:
-- both commit and the template holds a heart-rate target.
--
-- The trigger now reads the plan row FOR SHARE. The flip is an UPDATE of
-- that row and holds its row lock until commit, and FOR SHARE conflicts with
-- it, so:
--   * insert first: the flip waits for the insert to commit, and its AFTER
--     trigger's UPDATE then sees and nulls the committed target;
--   * flip first: the insert waits for the flip to commit and, under READ
--     COMMITTED, re-reads the locked row as flipped, so it is refused (23514).
-- A single session cannot interleave two transactions, so pgTAP pins that the
-- lock is taken rather than replaying the race. Re-emitted whole from
-- 20270915000004 with the hr_prescription gate kept.

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
  if not private.hr_prescription_enabled() then
    raise exception using
      errcode = 'insufficient_privilege',
      message = 'plan_workouts: heart-rate targets are not enabled';
  end if;
  select tp.user_id, coalesce(tp.is_template, false)
    into v_owner, v_template
  from plan_weeks pw
  join training_plans tp on tp.id = pw.plan_id
  where pw.id = new.week_id
  for share of tp;
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

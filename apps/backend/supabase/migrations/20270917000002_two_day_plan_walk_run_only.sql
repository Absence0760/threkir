-- A two-day plan holds only walk-run sessions on every write path (issue
-- #1186 second review; decisions § 2104).
--
-- 20270915000001 let days_per_week = 2 through the table CHECK for any plan
-- and enforced "walk-run only" in create_training_plan alone, so a direct
-- PostgREST insert, an edit of a workout's kind, a days_per_week update or a
-- week moved between plans could still make a two-day road plan. Three
-- triggers hold the same rule as the RPC, restricted to the kinds a walk-run
-- plan holds (walk_run, rest, race):
--
--   * plan_workouts, BEFORE INSERT OR UPDATE OF kind, week_id: a workout of
--     any other kind cannot land in a two-day plan. Only that case reads the
--     plan, so a walk_run / rest / race write costs nothing;
--   * training_plans, BEFORE INSERT OR UPDATE OF days_per_week: a plan cannot
--     become two-day while it holds such a workout;
--   * plan_weeks, BEFORE UPDATE OF plan_id: a week holding one cannot move
--     into a two-day plan.
--
-- Race-safe: the workout and week triggers read the plan row FOR SHARE, which
-- conflicts with the row lock a days_per_week UPDATE takes before its BEFORE
-- trigger runs. Whichever transaction locks the plan row first commits before
-- the other's check runs, and under READ COMMITTED that check's own statement
-- snapshot then sees the committed rows, so a concurrent "make it two-day"
-- and "add a tempo run" cannot both pass.
--
-- No backfill: the floor was 3 until 20270915000001, and every two-day plan
-- since has come through create_training_plan's walk-run check. The
-- functions and triggers are catalogue-only changes.

create or replace function private.check_two_day_plan_workout()
returns trigger
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_days smallint;
begin
  if new.kind in ('walk_run', 'rest', 'race') then
    return new;
  end if;
  if tg_op = 'UPDATE' and new.kind = old.kind and new.week_id = old.week_id then
    return new;
  end if;
  select tp.days_per_week into v_days
    from plan_weeks pw
    join training_plans tp on tp.id = pw.plan_id
   where pw.id = new.week_id
     for share of tp;
  if v_days = 2 then
    raise exception using
      errcode = 'check_violation',
      message = 'plan_workouts: a two-day plan holds only walk-run sessions';
  end if;
  return new;
end;
$$;

revoke execute on function private.check_two_day_plan_workout() from public, anon, authenticated;

create trigger plan_workouts_check_two_day_plan
  before insert or update of kind, week_id on plan_workouts
  for each row execute function private.check_two_day_plan_workout();

create or replace function private.check_two_day_plan()
returns trigger
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
begin
  if new.days_per_week <> 2 then
    return new;
  end if;
  if tg_op = 'UPDATE' and old.days_per_week = 2 then
    return new;
  end if;
  if exists (
    select 1
      from plan_weeks pw
      join plan_workouts w on w.week_id = pw.id
     where pw.plan_id = new.id
       and w.kind not in ('walk_run', 'rest', 'race')
  ) then
    raise exception using
      errcode = 'check_violation',
      message = 'training_plans: a two-day plan holds only walk-run sessions';
  end if;
  return new;
end;
$$;

revoke execute on function private.check_two_day_plan() from public, anon, authenticated;

create trigger training_plans_check_two_day_plan
  before insert or update of days_per_week on training_plans
  for each row execute function private.check_two_day_plan();

create or replace function private.check_two_day_plan_week_move()
returns trigger
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_days smallint;
begin
  if new.plan_id is not distinct from old.plan_id then
    return new;
  end if;
  select tp.days_per_week into v_days
    from training_plans tp
   where tp.id = new.plan_id
     for share;
  if v_days = 2 and exists (
    select 1 from plan_workouts w
     where w.week_id = new.id
       and w.kind not in ('walk_run', 'rest', 'race')
  ) then
    raise exception using
      errcode = 'check_violation',
      message = 'plan_weeks: a two-day plan holds only walk-run sessions';
  end if;
  return new;
end;
$$;

revoke execute on function private.check_two_day_plan_week_move() from public, anon, authenticated;

create trigger plan_weeks_check_two_day_plan_move
  before update of plan_id on plan_weeks
  for each row execute function private.check_two_day_plan_week_move();

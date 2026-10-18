-- The workout reminder is sent only to a runner whose time zone is known
-- (issue #1186 review; decisions § 2097).
--
-- 20270913000001 read the local morning in prefs.time_zone and fell back to
-- UTC when it was unset or unknown. For a runner far from UTC that is the
-- middle of their night: a "today's workout" email at 07:00 UTC lands at 02:00
-- in New York and 18:00 in Sydney, and names the wrong day for a good part of
-- the world. No reminder is better than one at the wrong hour, so a runner
-- with no time_zone, or one pg_timezone_names does not know, is skipped. The
-- web and mobile clients write time_zone on sign-in (20270830000011), so this
-- is the gap before a client has run, not a standing state.

create or replace function public.enqueue_workout_reminders(p_now timestamptz default now())
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
begin
  with zones as (
    select name from pg_timezone_names
  ),
  local_now as (
    select tp.user_id,
           tp.id as plan_id,
           (p_now at time zone z.name) as local_ts
      from training_plans tp
      join user_settings us on us.user_id = tp.user_id
      join zones z on z.name = us.prefs ->> 'time_zone'
     where tp.status = 'active'
       and not tp.is_template
       and (us.prefs ->> 'notify_workout_reminder') is distinct from 'off'
  ),
  due as (
    select distinct ln.user_id, ln.plan_id, ln.local_ts::date as workout_date
      from local_now ln
      join plan_weeks w on w.plan_id = ln.plan_id
      join plan_workouts pw on pw.week_id = w.id
     where extract(hour from ln.local_ts) between 7 and 11
       and pw.scheduled_date = ln.local_ts::date
       and pw.kind <> 'rest'
       and not pw.manually_completed
       and pw.completed_run_id is null
       and pw.skipped_at is null
  ),
  claimed as (
    insert into private.workout_reminder_claims (user_id, workout_date)
    select user_id, workout_date from due
    on conflict (user_id, workout_date) do nothing
    returning user_id, workout_date
  )
  insert into notifications (user_id, kind, plan_id)
  select d.user_id, 'workout_reminder', d.plan_id
    from due d
    join claimed c on c.user_id = d.user_id and c.workout_date = d.workout_date;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke execute on function public.enqueue_workout_reminders(timestamptz) from public, anon, authenticated;
grant execute on function public.enqueue_workout_reminders(timestamptz) to service_role;

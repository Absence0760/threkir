-- Month-close notice, part 2: the ledger, the hourly job and its gate (issue
-- #1343 phase 3, decisions § 2426 / § 2511).
--
-- When a calendar month closes where a park is, every runner with an effort
-- on one of its courses that month gets one bell notice per course: the
-- course, the month and their best time on it, never a rank (a rank depends
-- on who is looking, and this job has no caller). The notice deep-links to
-- the course's board for that month (`?period=YYYY-MM`).
--
-- Who, per tick (hourly at :29):
--   * a course of an ACTIVE park whose catalogue segment is active (the board
--     a closed course keeps is still a board, so a closed course is included);
--   * during the first three local days of the month where the park is, for
--     the month that just closed. The window lets a missed tick, or an effort
--     imported on the 2nd for the 31st, still reach its runner, and it is
--     what stops a backlog: turning the gate on in the middle of a month
--     raises nothing for any older month;
--   * every runner with an effort on that course whose started_at falls in
--     that month in the park's timezone, the same reading the monthly board
--     uses, whatever its run's visibility (it is their own time);
--   * who has not muted the kind: only the literal
--     `prefs.notify_park_course_month = 'off'` mutes, applied here before the
--     row exists (a clock-raised notice, like workout_reminder), and again by
--     the worker's kindMuted map for a row raised before the mute was set.
-- An empty month raises nothing, because there is no effort to group.
--
-- Idempotent per (course, month, runner): `private.park_course_month_notices`
-- has one row each, and a notice is inserted only for a claim the same
-- statement won. The ledger, not a unique index on notifications, carries the
-- key: the ledger survives the runner clearing the notice, and an index build
-- on notifications blocks the fan-out (docs/backend/migration_locks.md). The
-- job deletes ledger rows once their month can no longer come round again.
--
-- Gate: `park_course_month_notices` in private.feature_flags, seeded OFF. The
-- clients render the kind with the monthly board (#1343 phase 2), so the job
-- raises nothing until the flag is declared in apps/backend/ops/prod_config.json
-- once that ships (decisions § 2430).
--
-- Locks: a new table and its index, functions and a cron row. Nothing on a
-- populated table.

insert into private.feature_flags (name, enabled)
values ('park_course_month_notices', false)
on conflict (name) do nothing;

-- In `private`, so PostgREST never exposes it and no client role holds a
-- grant. Not in the Art 20 export: it is a delivery throttle, not something
-- the subject provided, and the notification it gates is exported. Both FKs
-- cascade, so deleting the account or the course removes its rows.
create table private.park_course_month_notices (
  park_course_id uuid not null references public.park_courses(id) on delete cascade,
  month          date not null constraint park_course_month_notices_first_day
                   check (extract(day from month) = 1),
  user_id        uuid not null references auth.users(id) on delete cascade,
  notified_at    timestamptz not null default now(),
  primary key (park_course_id, month, user_id)
);

create index park_course_month_notices_month_idx
  on private.park_course_month_notices (month);
create index park_course_month_notices_user_idx
  on private.park_course_month_notices (user_id);

comment on table private.park_course_month_notices is
  'One row per (park course, local month, runner) a park_course_month_closed notice was raised for; '
  'enqueue_park_course_month_notices inserts a notice only for a claim it wins. 20271226041343.';

alter table private.park_course_month_notices enable row level security;
revoke all on table private.park_course_month_notices
  from public, anon, authenticated, service_role;

-- p_now exists so the selection can be tested at a chosen instant; cron calls
-- it with no argument. SECURITY DEFINER so it can write notifications (whose
-- INSERT is closed to clients) and the private ledger. Returns the number of
-- notices raised so a manual run is observable.
create or replace function public.enqueue_park_course_month_notices(p_now timestamptz default now())
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
begin
  if not coalesce(
    (select f.enabled from private.feature_flags f where f.name = 'park_course_month_notices'),
    false
  ) then
    return 0;
  end if;

  -- A ledger row can suppress nothing once its month is past every zone's
  -- three-day window, which 70 days after its 1st always is.
  delete from private.park_course_month_notices
   where month < (p_now at time zone 'UTC')::date - 70;

  with courses as (
    select pc.id as course_id,
           pc.global_segment_id,
           p.timezone,
           date_trunc('month', p_now at time zone p.timezone) as this_month,
           (p_now at time zone p.timezone) as local_now
      from park_courses pc
      join parks p on p.id = pc.park_id and p.is_active
      join global_segments gs on gs.id = pc.global_segment_id and gs.is_active
  ),
  closing as (
    select c.course_id,
           c.global_segment_id,
           c.timezone,
           (c.this_month - interval '1 month')::date as month,
           -- The instants of local midnight on the two 1sts, padded a day so
           -- the range only narrows the read; the month test below is exact.
           ((c.this_month - interval '1 month') at time zone c.timezone) - interval '1 day' as read_from,
           (c.this_month at time zone c.timezone) + interval '1 day' as read_to
      from courses c
     where c.local_now < c.this_month + interval '3 days'
  ),
  best as (
    select cl.course_id,
           cl.month,
           e.user_id,
           greatest(1, round(min(e.time_seconds)))::integer as time_s
      from closing cl
      join global_segment_efforts e
        on e.global_segment_id = cl.global_segment_id
       and e.started_at >= cl.read_from
       and e.started_at < cl.read_to
       and date_trunc('month', e.started_at at time zone cl.timezone)::date = cl.month
      left join user_settings us on us.user_id = e.user_id
     where (us.prefs ->> 'notify_park_course_month') is distinct from 'off'
     group by cl.course_id, cl.month, e.user_id
  ),
  claimed as (
    insert into private.park_course_month_notices (park_course_id, month, user_id)
    select course_id, month, user_id from best
    on conflict (park_course_id, month, user_id) do nothing
    returning park_course_id, month, user_id
  )
  insert into notifications (user_id, kind, park_course_id, park_course_month, park_course_time_s)
  select b.user_id, 'park_course_month_closed', b.course_id, b.month, b.time_s
    from best b
    join claimed c
      on c.park_course_id = b.course_id
     and c.month = b.month
     and c.user_id = b.user_id;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke execute on function public.enqueue_park_course_month_notices(timestamptz) from public, anon, authenticated;
grant execute on function public.enqueue_park_course_month_notices(timestamptz) to service_role;

-- Hourly at :29, a minute no other hourly job uses. cron.schedule is
-- idempotent on name.
select cron.schedule(
  'enqueue-park-course-month-notices',
  '29 * * * *',
  $$select public.enqueue_park_course_month_notices()$$
);

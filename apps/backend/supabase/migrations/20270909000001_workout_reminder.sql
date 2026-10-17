-- "Today's workout" reminder: a `workout_reminder` notification kind raised
-- once a local morning for the runner's active plan (issue #1186 § Workouts
-- off the phone).
--
-- Shape copies `event_reminder` (20261130_001): a scheduled function inserts
-- notification rows, and the AFTER INSERT triggers already on `notifications`
-- turn each one into the email / web-push / native-push jobs. Nothing new is
-- needed on the delivery side, and every credential-dependent leg keeps the
-- gate it already has: the worker sends no email while SMTP is unset and no
-- native push while FCM/APNs are unset (docs/features/native_push.md), so in
-- an environment without them the reminder is a bell row and nothing else.
--
-- Who is reminded, per tick (hourly):
--   * the owner of an `active`, non-template plan (one per user, by
--     training_plans_one_active; a template cannot be active, by
--     training_plans_template_status, and the `not is_template` below only
--     says so) — a paused, finished or abandoned plan reminds nobody;
--   * whose LOCAL time is between 07:00 and 11:59, local meaning
--     user_settings.prefs.time_zone (validated against pg_timezone_names on
--     write, 20270830000011) and UTC when it is unset or unknown. The window
--     is five hours wide so a missed tick catches up the same morning but the
--     reminder never arrives in the afternoon;
--   * who has a workout on that local date that is not a rest day, not done
--     (`manually_completed` or `completed_run_id`, the same test as
--     isWorkoutCompleted) and not skipped;
--   * who has not muted the kind: only the literal
--     `prefs.notify_workout_reminder = 'off'` mutes.
--
-- The mute is applied HERE, before the row exists, rather than only on the
-- outbound channels the way the other per-kind mutes are. Those mutes guard a
-- notification someone else's action raised, where the inbox row is the
-- record of that action. This one is raised by a clock, every morning; a
-- runner who turned it off and still found one in the bell each day would
-- read the switch as broken. The worker's kindMuted map carries the same key
-- as well, so a mute set between the insert and the drain still holds.
--
-- Idempotent per user per local day, whatever the cron does:
-- `private.workout_reminder_claims` has one row per (user, local date), and a
-- reminder is inserted only for a claim the same statement won. A second
-- workout on the same day, a re-run, or a workout moved onto today after the
-- morning's reminder raises nothing more. The claim table, not a unique index
-- on `notifications`, carries the key: building an index on that populated
-- table takes a lock that blocks the fan-out for the build
-- (docs/backend/migration_locks.md), and the claim outlives the runner
-- deleting the notification, which a unique index on the row would not.
--
-- The `notifications_kind_check` widen is the DROP + ADD ... NOT VALID half
-- only; the VALIDATE is 20270909000002 in its own transaction.
--
-- Locks: the CHECK swap takes a brief ACCESS EXCLUSIVE on notifications with
-- no scan; CREATE TABLE, its index, and the functions are catalogue-only.

-- ─────────────── 1. notification kind ───────────────

alter table notifications drop constraint notifications_kind_check;
alter table notifications
  add constraint notifications_kind_check
  check (
    kind in (
      'kudos', 'comment', 'comment_reply', 'follow',
      'event_rsvp', 'event_cancel', 'plan_update', 'message',
      'club_post', 'run_completed', 'event_reminder', 'plan_assigned',
      'achievement', 'challenge_complete', 'content_hidden',
      'data_export_ready', 'refund_failed', 'event_waitlist_slot',
      'follow_request',
      'reaction', 'comment_like', 'mention',
      'workout_reminder'
    )
  )
  not valid;

-- ─────────────── 2. per-day claim ───────────────

-- In `private`, so PostgREST never exposes it and no client role holds a
-- grant. Not in the Art 20 export: it is a delivery throttle, not something
-- the subject provided, and the notification it gates is exported. The FK
-- cascades, so deleting the account removes the rows; the daily sweep below
-- removes a row once its date can no longer come round again.
create table private.workout_reminder_claims (
  user_id      uuid not null references auth.users(id) on delete cascade,
  workout_date date not null,
  claimed_at   timestamptz not null default now(),
  primary key (user_id, workout_date)
);

create index workout_reminder_claims_workout_date_idx
  on private.workout_reminder_claims (workout_date);

comment on table private.workout_reminder_claims is
  'One row per (user, local date) a workout_reminder was raised for; '
  'enqueue_workout_reminders inserts a reminder only for a claim it wins. '
  'Swept daily once the date is past. 20270909000001.';

alter table private.workout_reminder_claims enable row level security;
revoke all on table private.workout_reminder_claims
  from public, anon, authenticated, service_role;

-- ─────────────── 3. scheduler ───────────────

-- p_now exists so the selection can be tested at a chosen instant; cron calls
-- it with no argument. SECURITY DEFINER so it can write notifications (whose
-- INSERT is closed to clients) and the private claim table. Returns the
-- number of reminders raised so a manual run is observable.
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
           (p_now at time zone coalesce(z.name, 'UTC')) as local_ts
      from training_plans tp
      left join user_settings us on us.user_id = tp.user_id
      left join zones z on z.name = us.prefs ->> 'time_zone'
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

-- Hourly at :07, off the top of the hour the event and digest crons share.
-- cron.schedule is idempotent on name.
select cron.schedule(
  'enqueue-workout-reminders',
  '7 * * * *',
  $$select public.enqueue_workout_reminders()$$
);

-- ─────────────── 4. claim sweep ───────────────

-- A claim can suppress nothing once its date has passed in every zone; two
-- days back from the server date is past that in all of them (UTC+14 is the
-- furthest ahead).
create or replace function private.cleanup_stale_workout_reminder_claims()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
begin
  delete from private.workout_reminder_claims
   where workout_date < current_date - 2;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke all on function private.cleanup_stale_workout_reminder_claims() from public, anon, authenticated;

select cron.schedule(
  'cleanup-stale-workout-reminder-claims',
  '23 3 * * *',
  $$select private.cleanup_stale_workout_reminder_claims()$$
);

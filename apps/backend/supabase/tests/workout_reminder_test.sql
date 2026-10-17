-- Pins migration 20270909000001: enqueue_workout_reminders() raises one
-- `workout_reminder` per runner per LOCAL morning (07:00-11:59 in
-- prefs.time_zone, UTC when unset), only for the active plan (a template
-- can never be active: training_plans_template_status), never on a rest day
-- or for a done / skipped workout, never for a runner who muted the kind, and
-- never twice for the same local day.
--
-- Every call passes p_now, so nothing here depends on the wall clock.
begin;
select plan(24);

set local timezone = 'UTC';

create function pg_temp.mk_user(p_id uuid, p_prefs jsonb) returns uuid
language plpgsql as $$
begin
  insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
  values (p_id, 'authenticated', 'authenticated', p_id::text || '@remind.local', '', now(), now());
  insert into user_profiles (id, display_name) values (p_id, 'Reminded') on conflict (id) do nothing;
  if p_prefs is not null then
    insert into user_settings (user_id, prefs) values (p_id, p_prefs)
      on conflict (user_id) do update set prefs = excluded.prefs;
  end if;
  return p_id;
end;
$$;

-- One plan with a single week; returns the week id.
create function pg_temp.mk_plan(p_user uuid, p_status text)
returns uuid
language plpgsql as $$
declare
  v_plan uuid;
  v_week uuid;
begin
  insert into training_plans (user_id, name, goal_event, goal_distance_m, start_date, end_date,
                              days_per_week, status)
  values (p_user, 'Plan', 'distance_10k', 10000, '2031-01-05', '2031-02-28', 4, p_status)
  returning id into v_plan;
  insert into plan_weeks (plan_id, week_index) values (v_plan, 0) returning id into v_week;
  return v_week;
end;
$$;

create function pg_temp.mk_workout(p_week uuid, p_day date, p_kind workout_kind default 'easy')
returns uuid
language sql as $$
  insert into plan_workouts (week_id, scheduled_date, kind, target_distance_m)
  values (p_week, p_day, p_kind, 8000)
  returning id;
$$;

create function pg_temp.reminders(p_user uuid) returns int
language sql as $$
  select count(*)::int from notifications where user_id = p_user and kind = 'workout_reminder'
$$;

do $$
declare
  w uuid;
  wo uuid;
begin
  -- UTC, workout on the 16th. The control.
  perform pg_temp.mk_user('11860909-0000-0000-0000-0000000000a1', null);
  w := pg_temp.mk_plan('11860909-0000-0000-0000-0000000000a1', 'active');
  perform pg_temp.mk_workout(w, '2031-01-16');

  -- Brisbane (UTC+10, no DST): 07:00 local on the 16th is 21:00 UTC on the 15th.
  perform pg_temp.mk_user('11860909-0000-0000-0000-0000000000b1', '{"time_zone":"Australia/Brisbane"}');
  w := pg_temp.mk_plan('11860909-0000-0000-0000-0000000000b1', 'active');
  perform pg_temp.mk_workout(w, '2031-01-16');

  -- Rest day only.
  perform pg_temp.mk_user('11860909-0000-0000-0000-0000000000c1', null);
  w := pg_temp.mk_plan('11860909-0000-0000-0000-0000000000c1', 'active');
  perform pg_temp.mk_workout(w, '2031-01-16', 'rest');

  -- Done by hand.
  perform pg_temp.mk_user('11860909-0000-0000-0000-0000000000c2', null);
  w := pg_temp.mk_plan('11860909-0000-0000-0000-0000000000c2', 'active');
  wo := pg_temp.mk_workout(w, '2031-01-16');
  update plan_workouts set manually_completed = true, completed_at = now() where id = wo;

  -- Skipped.
  perform pg_temp.mk_user('11860909-0000-0000-0000-0000000000c3', null);
  w := pg_temp.mk_plan('11860909-0000-0000-0000-0000000000c3', 'active');
  wo := pg_temp.mk_workout(w, '2031-01-16');
  update plan_workouts set skipped_at = now() where id = wo;

  -- Paused plan.
  perform pg_temp.mk_user('11860909-0000-0000-0000-0000000000c4', null);
  w := pg_temp.mk_plan('11860909-0000-0000-0000-0000000000c4', 'paused');
  perform pg_temp.mk_workout(w, '2031-01-16');

  -- Muted.
  perform pg_temp.mk_user('11860909-0000-0000-0000-0000000000c6', '{"notify_workout_reminder":"off"}');
  w := pg_temp.mk_plan('11860909-0000-0000-0000-0000000000c6', 'active');
  perform pg_temp.mk_workout(w, '2031-01-16');

  -- A non-'off' value does not mute.
  perform pg_temp.mk_user('11860909-0000-0000-0000-0000000000c7', '{"notify_workout_reminder":false}');
  w := pg_temp.mk_plan('11860909-0000-0000-0000-0000000000c7', 'active');
  perform pg_temp.mk_workout(w, '2031-01-16');

  -- Workout on the 17th only.
  perform pg_temp.mk_user('11860909-0000-0000-0000-0000000000c8', null);
  w := pg_temp.mk_plan('11860909-0000-0000-0000-0000000000c8', 'active');
  perform pg_temp.mk_workout(w, '2031-01-17');
end;
$$;

-- ─────────── before the window ───────────

select is(public.enqueue_workout_reminders('2031-01-16 06:59:00+00'), 0,
  '06:59 local raises nothing');

-- Brisbane at 21:00 UTC on the 15th is 07:00 local on the 16th.
select is(public.enqueue_workout_reminders('2031-01-15 21:00:00+00'), 1,
  '07:00 Brisbane raises exactly one reminder');
select is(pg_temp.reminders('11860909-0000-0000-0000-0000000000b1'), 1,
  'the Brisbane runner is reminded on their local morning');
select is(pg_temp.reminders('11860909-0000-0000-0000-0000000000a1'), 0,
  'the UTC runner is not: it is 21:00 on the 15th for them');

-- ─────────── inside the window, UTC ───────────

select is(public.enqueue_workout_reminders('2031-01-16 07:30:00+00'), 2,
  '07:30 UTC raises the control and the non-off value, nothing else');
select is(pg_temp.reminders('11860909-0000-0000-0000-0000000000a1'), 1,
  'the UTC runner is reminded once on their local morning');
select is(
  (select plan_id from notifications
    where user_id = '11860909-0000-0000-0000-0000000000a1' and kind = 'workout_reminder'),
  (select id from training_plans where user_id = '11860909-0000-0000-0000-0000000000a1'),
  'the reminder carries the plan it is for');
select is(pg_temp.reminders('11860909-0000-0000-0000-0000000000c1'), 0, 'a rest day reminds nobody');
select is(pg_temp.reminders('11860909-0000-0000-0000-0000000000c2'), 0, 'a done workout reminds nobody');
select is(pg_temp.reminders('11860909-0000-0000-0000-0000000000c3'), 0, 'a skipped workout reminds nobody');
select is(pg_temp.reminders('11860909-0000-0000-0000-0000000000c4'), 0, 'a paused plan reminds nobody');
select is(pg_temp.reminders('11860909-0000-0000-0000-0000000000c6'), 0,
  'notify_workout_reminder = off withholds the row itself');
select is(pg_temp.reminders('11860909-0000-0000-0000-0000000000c7'), 1,
  'only the literal off mutes');
select is(pg_temp.reminders('11860909-0000-0000-0000-0000000000c8'), 0,
  'a workout tomorrow does not remind today');

-- ─────────── idempotent per local day ───────────

select is(public.enqueue_workout_reminders('2031-01-16 08:07:00+00'), 0,
  'the next tick the same morning raises nothing');

-- Deleting the bell row does not re-arm the day: the claim outlives it.
delete from notifications
 where user_id = '11860909-0000-0000-0000-0000000000a1' and kind = 'workout_reminder';
select is(public.enqueue_workout_reminders('2031-01-16 09:07:00+00'), 0,
  'a deleted reminder is not raised again the same day');

-- A day that has had its reminder stays reminded, whatever changes on it.
update plan_workouts pw set kind = 'tempo'
  from plan_weeks w join training_plans tp on tp.id = w.plan_id
 where pw.week_id = w.id and tp.user_id = '11860909-0000-0000-0000-0000000000b1';
select is(public.enqueue_workout_reminders('2031-01-15 22:07:00+00'), 0,
  'editing an already-reminded day does not remind again');

-- A rest day turned into a run later in the morning was never reminded, so it is now.
update plan_workouts pw set kind = 'easy'
  from plan_weeks w join training_plans tp on tp.id = w.plan_id
 where pw.week_id = w.id and tp.user_id = '11860909-0000-0000-0000-0000000000c1';
select is(public.enqueue_workout_reminders('2031-01-16 10:07:00+00'), 1,
  'a workout that appears on today mid-morning is reminded on the next tick');

-- ─────────── after the window ───────────

select is(public.enqueue_workout_reminders('2031-01-17 12:00:00+00'), 0,
  '12:00 local is past the window, even with a workout due that day');
select is(pg_temp.reminders('11860909-0000-0000-0000-0000000000c8'), 0,
  'the afternoon tick did not remind the runner whose workout is today');
select is(public.enqueue_workout_reminders('2031-01-17 11:59:00+00'), 1,
  '11:59 local is still inside it');

-- ─────────── delivery hand-off ───────────

select ok(
  exists (
    select 1 from public.jobs j
      join notifications n on n.id::text = j.payload ->> 'notification_id'
     where j.kind = 'notification_email' and n.kind = 'workout_reminder'
  ),
  'the existing fan-out trigger enqueues the email leg for a reminder');

-- ─────────── sweep + grants ───────────

insert into private.workout_reminder_claims (user_id, workout_date)
values ('11860909-0000-0000-0000-0000000000c1', current_date - 3);
select cmp_ok(private.cleanup_stale_workout_reminder_claims(), '>=', 1,
  'the sweep removes a claim whose date has passed everywhere');

select ok(
  not has_function_privilege('authenticated', 'public.enqueue_workout_reminders(timestamptz)', 'execute'),
  'a signed-in client cannot raise reminders');

select * from finish();
rollback;

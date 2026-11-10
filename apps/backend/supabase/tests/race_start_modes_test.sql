-- Pins migrations 20271121002400 and 20271121100001-100007 (#1306, decisions
-- § 2400-§ 2401): race start modes, the per-minute job and the Self-timed
-- result rules.
--
--   1-2.   The event mode CHECK and the per-mode settings CHECK.
--   3-5.   ensure_race_session answers true, creates a scheduled session from the offsets and
--          refuses a key that is not an occurrence.
--   6.     The session's instants follow a BUG-015 reschedule.
--   7.     A client cannot fire a scheduled race.
--   8-10.   Delay moves the start and the auto-end, tells everyone going, and is
--          refused once the start has passed.
--   11-12. A scheduled session accepts pings before the job runs, as sent.
--   13.    Cancel is refused after the scheduled instant, though stored armed.
--   14.    race_sessions_redacted says running by the clock.
--   15-16. The job fires GO at the scheduled instant, not at its own time.
--   17-18. The job warns ~10 min before, and not after a recent event_reminder.
--   19-20. The job closes the window at its close and files the host DNFs.
--   21-22. The job opens a self-timed window and freezes its lines.
--   23-25. An old-client Self-timed result is normalised (no gun time, the chip
--          time ranks) and kept pending with needs_review, not refused.
--   26-27. A gate-timed attempt inside the window that matches the pings is
--          clean; the chip time is the span between the crossings.
--   28.    The lock rule: a slower attempt leaves the gate-timed finish.
--   29.    A faster attempt replaces it.
--   30.    A DNF never replaces it.
--   31.    A DNF row is replaced by a later finish.
--   32.    A start outside the window needs review.
--   33.    Crossings the pings do not support need review.
--   34.    Self-timed pings are kept past 48 h until close + 24 h.
--   35.    An edit of a runner's own time on a non-auto-approve race resets
--          approval and flags it for review.
--   36.    my_race_sessions lists the runner's live race.
--   37.    Extend refused past 7 days from the opening.
--   38.    Every new CHECK was validated (20271121002401, 20271121100007).

begin;
select plan(38);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('e7306000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
   'sm-owner@evt.local', '', now(), now()),
  ('e7306000-0000-0000-0000-000000000002', 'authenticated', 'authenticated',
   'sm-racer-a@evt.local', '', now(), now()),
  ('e7306000-0000-0000-0000-000000000003', 'authenticated', 'authenticated',
   'sm-racer-b@evt.local', '', now(), now());

set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';

insert into clubs (id, owner_id, name, slug, is_public)
values ('e7306000-0000-0000-0000-0000000000c1',
        'e7306000-0000-0000-0000-000000000001', 'Start Club', 'race-start-modes-c', true);

insert into club_members (club_id, user_id, role, status)
values
  ('e7306000-0000-0000-0000-0000000000c1', 'e7306000-0000-0000-0000-000000000002', 'member', 'active'),
  ('e7306000-0000-0000-0000-0000000000c1', 'e7306000-0000-0000-0000-000000000003', 'member', 'active')
on conflict do nothing;

-- ── 1-2: CHECKs ─────────────────────────────────────────────────────────────
select throws_ok(
  $$ insert into events (club_id, title, starts_at, author_id, is_public, race_start_mode)
     values ('e7306000-0000-0000-0000-0000000000c1', 'Bad', now(),
             'e7306000-0000-0000-0000-000000000001', true, 'flying') $$,
  '23514', null,
  'race_start_mode is one of host_go / scheduled / self_timed'
);

select throws_ok(
  $$ insert into events (club_id, title, starts_at, author_id, is_public, race_start_mode)
     values ('e7306000-0000-0000-0000-0000000000c1', 'Bad', now(),
             'e7306000-0000-0000-0000-000000000001', true, 'scheduled') $$,
  '23514', null,
  'a scheduled race needs its offset and window length'
);

-- e1: scheduled, starting in 2 h (GO at +0, auto-end 1 h later)
-- e2: scheduled, GO 5 minutes ago
-- e3: scheduled, GO in 5 minutes
-- e4: self-timed, window opened 10 minutes ago, one course with both lines
-- e5: scheduled, window closed 1 minute ago, still stored running
-- e6: host GO, not auto-approved
insert into events (id, club_id, title, starts_at, author_id, is_public,
                    race_start_mode, race_scheduled_offset_s, race_window_open_offset_s,
                    race_window_length_s, race_auto_approve)
values
  ('e7306000-0000-0000-0000-0000000000e1', 'e7306000-0000-0000-0000-0000000000c1',
   'Later race', now() + interval '2 hours', 'e7306000-0000-0000-0000-000000000001', true,
   'scheduled', 0, null, 3600, null),
  ('e7306000-0000-0000-0000-0000000000e2', 'e7306000-0000-0000-0000-0000000000c1',
   'Gone race', now() - interval '5 minutes', 'e7306000-0000-0000-0000-000000000001', true,
   'scheduled', 0, null, 3600, null),
  ('e7306000-0000-0000-0000-0000000000e3', 'e7306000-0000-0000-0000-0000000000c1',
   'Soon race', now() + interval '5 minutes', 'e7306000-0000-0000-0000-000000000001', true,
   'scheduled', 0, null, 3600, null),
  ('e7306000-0000-0000-0000-0000000000e4', 'e7306000-0000-0000-0000-0000000000c1',
   'Time trial', now() - interval '10 minutes', 'e7306000-0000-0000-0000-000000000001', true,
   'self_timed', null, 0, 86400, true),
  ('e7306000-0000-0000-0000-0000000000e5', 'e7306000-0000-0000-0000-0000000000c1',
   'Closing race', now() - interval '61 minutes', 'e7306000-0000-0000-0000-000000000001', true,
   'scheduled', 0, null, 3600, null),
  ('e7306000-0000-0000-0000-0000000000e6', 'e7306000-0000-0000-0000-0000000000c1',
   'Host race', now() - interval '30 minutes', 'e7306000-0000-0000-0000-000000000001', true,
   'host_go', null, null, null, null);

insert into event_courses (id, event_id, name, distance_m, sort_order,
                           start_gate_lat, start_gate_lng, start_gate_bearing_deg,
                           start_gate_half_width_m, start_gate_source,
                           finish_gate_lat, finish_gate_lng, finish_gate_bearing_deg,
                           finish_gate_half_width_m, finish_gate_source)
values ('e7306000-0000-0000-0000-0000000000a4', 'e7306000-0000-0000-0000-0000000000e4',
        '5K', 5000, 0,
        51.5000, -0.1000, 90, 15, 'organiser',
        51.5000, -0.0300, 90, 15, 'organiser');

insert into event_attendees (event_id, user_id, status, instance_start)
select e.id, u.id, 'going', e.starts_at
  from events e
  cross join (values ('e7306000-0000-0000-0000-000000000002'::uuid),
                     ('e7306000-0000-0000-0000-000000000003'::uuid)) u(id)
 where e.club_id = 'e7306000-0000-0000-0000-0000000000c1';

-- ── 3-4: ensure_race_session ────────────────────────────────────────────────
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"e7306000-0000-0000-0000-000000000002","role":"authenticated"}';

select is(
  public.ensure_race_session('e7306000-0000-0000-0000-0000000000e1',
    (select starts_at from events where id = 'e7306000-0000-0000-0000-0000000000e1')),
  true,
  'ensure_race_session answers true for a scheduled occurrence due within a day'
);

select ok(
  (select scheduled_start_at = instance_start
              and window_closes_at = instance_start + interval '1 hour'
              and start_mode = 'scheduled' and status = 'armed'
         from race_sessions where event_id = 'e7306000-0000-0000-0000-0000000000e1'),
  'ensure_race_session creates the scheduled session from the event''s offsets'
);

select throws_ok(
  $$ select public.ensure_race_session('e7306000-0000-0000-0000-0000000000e1',
       now() + interval '3 hours') $$,
  '23514', null,
  'ensure_race_session refuses a key that is not an occurrence'
);

-- ── 5: offsets follow a reschedule ──────────────────────────────────────────
set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';

update events set starts_at = starts_at + interval '30 minutes'
 where id = 'e7306000-0000-0000-0000-0000000000e1';

select is(
  (select scheduled_start_at from race_sessions
    where event_id = 'e7306000-0000-0000-0000-0000000000e1'),
  (select starts_at from events where id = 'e7306000-0000-0000-0000-0000000000e1'),
  'a moved occurrence carries its scheduled start with it'
);

-- Sessions for the rest, as the job would create them.
reset role;
set local "request.jwt.claims" = '';

select private.ensure_race_session_due(id, starts_at, interval '1 day')
  from events
 where id in ('e7306000-0000-0000-0000-0000000000e2', 'e7306000-0000-0000-0000-0000000000e3',
              'e7306000-0000-0000-0000-0000000000e4');

insert into race_sessions (event_id, instance_start, status)
select id, starts_at, 'armed' from events
 where id in ('e7306000-0000-0000-0000-0000000000e5', 'e7306000-0000-0000-0000-0000000000e6');

update race_sessions set status = 'running'
 where event_id = 'e7306000-0000-0000-0000-0000000000e5';
update race_sessions set is_auto_approve = false
 where event_id = 'e7306000-0000-0000-0000-0000000000e6';

insert into race_pings (event_id, instance_start, user_id, lat, lng, elapsed_s, distance_m)
select id, starts_at, 'e7306000-0000-0000-0000-000000000002', 51.5, -0.1, 3000, 9000
  from events where id = 'e7306000-0000-0000-0000-0000000000e5';

-- ── 6-9: the organiser ──────────────────────────────────────────────────────
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"e7306000-0000-0000-0000-000000000001","role":"authenticated"}';

select throws_ok(
  $$ update race_sessions set status = 'running'
      where event_id = 'e7306000-0000-0000-0000-0000000000e3' $$,
  '23514', null,
  'a client cannot fire a scheduled race; the server does'
);

update race_sessions set scheduled_start_at = scheduled_start_at + interval '15 minutes'
 where event_id = 'e7306000-0000-0000-0000-0000000000e3';

select ok(
  (select scheduled_start_at = instance_start + interval '15 minutes'
          and window_closes_at = instance_start + interval '75 minutes'
     from race_sessions where event_id = 'e7306000-0000-0000-0000-0000000000e3'),
  'Delay moves the scheduled start and the auto-end with it'
);

set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';

select is(
  (select count(*)::int from notifications
    where kind = 'race_start_moved' and event_id = 'e7306000-0000-0000-0000-0000000000e3'),
  2,
  'a Delay tells everyone going that the start moved'
);

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"e7306000-0000-0000-0000-000000000001","role":"authenticated"}';

select throws_ok(
  $$ update race_sessions set scheduled_start_at = now() + interval '1 hour'
      where event_id = 'e7306000-0000-0000-0000-0000000000e2' $$,
  '23514', null,
  'Delay is refused once the scheduled start has passed'
);

-- ── 10-12: live by the clock ────────────────────────────────────────────────
set local "request.jwt.claims" = '{"sub":"e7306000-0000-0000-0000-000000000002","role":"authenticated"}';

select lives_ok(
  $$ insert into race_pings (event_id, instance_start, user_id, lat, lng)
     select id, starts_at, 'e7306000-0000-0000-0000-000000000002', 51.5, -0.1
       from events where id = 'e7306000-0000-0000-0000-0000000000e2' $$,
  'a scheduled race whose start passed takes pings before the job moves it'
);

select ok(
  exists (select 1 from race_pings
           where event_id = 'e7306000-0000-0000-0000-0000000000e2'
             and user_id = 'e7306000-0000-0000-0000-000000000002'
             and lat = 51.5 and lng = -0.1),
  'the early ping lands where it was sent'
);

set local "request.jwt.claims" = '{"sub":"e7306000-0000-0000-0000-000000000001","role":"authenticated"}';

select throws_ok(
  $$ update race_sessions set status = 'cancelled'
      where event_id = 'e7306000-0000-0000-0000-0000000000e2' $$,
  '23514', null,
  'Cancel is refused after the scheduled instant even while stored armed'
);

select is(
  (select effective_status from race_sessions_redacted
    where event_id = 'e7306000-0000-0000-0000-0000000000e2'),
  'running',
  'race_sessions_redacted reports a passed scheduled start as running'
);

-- ── 13-20: the job ──────────────────────────────────────────────────────────
reset role;
set local "request.jwt.claims" = '';

-- e3 moved to +20 min above; put it back inside the 10-minute warning.
update race_sessions set scheduled_start_at = now() + interval '8 minutes',
                         window_closes_at = now() + interval '68 minutes'
 where event_id = 'e7306000-0000-0000-0000-0000000000e3';

insert into notifications (user_id, kind, event_id, event_instance_start, created_at)
select 'e7306000-0000-0000-0000-000000000003', 'event_reminder', id, starts_at, now() - interval '20 minutes'
  from events where id = 'e7306000-0000-0000-0000-0000000000e3';

select public.race_sessions_tick();

select is(
  (select status from race_sessions where event_id = 'e7306000-0000-0000-0000-0000000000e2'),
  'running',
  'the job fires a scheduled race whose instant has passed'
);

select is(
  (select started_at from race_sessions where event_id = 'e7306000-0000-0000-0000-0000000000e2'),
  (select scheduled_start_at from race_sessions where event_id = 'e7306000-0000-0000-0000-0000000000e2'),
  'GO is the scheduled instant, not the job''s clock'
);

select is(
  (select count(*)::int from notifications
    where kind = 'race_starting_soon' and event_id = 'e7306000-0000-0000-0000-0000000000e3'
      and user_id = 'e7306000-0000-0000-0000-000000000002'),
  1,
  'the job warns a runner going about 10 minutes before GO'
);

select is(
  (select count(*)::int from notifications
    where kind = 'race_starting_soon' and event_id = 'e7306000-0000-0000-0000-0000000000e3'
      and user_id = 'e7306000-0000-0000-0000-000000000003'),
  0,
  'no starting-soon warning after an event reminder within the hour'
);

select ok(
  (select status = 'finished' and finished_at = window_closes_at
     from race_sessions where event_id = 'e7306000-0000-0000-0000-0000000000e5'),
  'the job ends a scheduled race at its window close'
);

select ok(
  exists (select 1 from event_results
           where event_id = 'e7306000-0000-0000-0000-0000000000e5'
             and user_id = 'e7306000-0000-0000-0000-000000000002'
             and finisher_status = 'dnf' and finish_method = 'host'),
  'closing the window files a host DNF for a runner who pinged and filed nothing'
);

select ok(
  (select status = 'running' and started_at = window_opens_at
     from race_sessions where event_id = 'e7306000-0000-0000-0000-0000000000e4'),
  'the job opens a self-timed window, with GO at the opening'
);

select ok(
  exists (select 1 from race_session_courses
           where event_id = 'e7306000-0000-0000-0000-0000000000e4'
             and start_gate_lat = 51.5),
  'the window''s lines are frozen when it opens'
);

-- ── 21-31: Self-timed results ───────────────────────────────────────────────
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"e7306000-0000-0000-0000-000000000002","role":"authenticated"}';

insert into event_results (event_id, instance_start, user_id, duration_s, distance_m,
                           gun_time_s, chip_time_s, finish_method)
select id, starts_at, 'e7306000-0000-0000-0000-000000000002', 1500, 5000, 1700, 1500, 'auto'
  from events where id = 'e7306000-0000-0000-0000-0000000000e4';

select ok(
  (select gun_time_s is null and duration_s = 1500 and chip_time_s = 1500
     from event_results where event_id = 'e7306000-0000-0000-0000-0000000000e4'
                          and user_id = 'e7306000-0000-0000-0000-000000000002'),
  'a Self-timed result keeps no gun time and ranks by its chip time'
);

select ok(
  (select needs_review from event_results
    where event_id = 'e7306000-0000-0000-0000-0000000000e4'
      and user_id = 'e7306000-0000-0000-0000-000000000002'),
  'a Self-timed result without a gate start needs review'
);

select ok(
  (select not organiser_approved from event_results
    where event_id = 'e7306000-0000-0000-0000-0000000000e4'
      and user_id = 'e7306000-0000-0000-0000-000000000002'),
  'a needs-review result is pending even on an auto-approved race'
);

-- Pings that place the runner on the start line 5 min ago and on the finish
-- line 1 min ago.
set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';
insert into race_pings (event_id, instance_start, user_id, at, lat, lng)
select id, starts_at, 'e7306000-0000-0000-0000-000000000002'::uuid, now() - interval '300 seconds', 51.5, -0.1
  from events where id = 'e7306000-0000-0000-0000-0000000000e4'
union all
select id, starts_at, 'e7306000-0000-0000-0000-000000000002'::uuid, now() - interval '60 seconds', 51.5, -0.03
  from events where id = 'e7306000-0000-0000-0000-0000000000e4';

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"e7306000-0000-0000-0000-000000000002","role":"authenticated"}';

update event_results
   set duration_s = 999, chip_time_s = 999, finish_method = 'auto',
       start_at = now() - interval '300 seconds', finish_at = now() - interval '60 seconds',
       start_detection = 'gate', finish_detection = 'gate'
 where event_id = 'e7306000-0000-0000-0000-0000000000e4'
   and user_id = 'e7306000-0000-0000-0000-000000000002';

select ok(
  (select not needs_review and organiser_approved
     from event_results where event_id = 'e7306000-0000-0000-0000-0000000000e4'
                          and user_id = 'e7306000-0000-0000-0000-000000000002'),
  'a gate-timed attempt inside the window that the pings support is clean'
);

select is(
  (select duration_s from event_results where event_id = 'e7306000-0000-0000-0000-0000000000e4'
                                         and user_id = 'e7306000-0000-0000-0000-000000000002'),
  240,
  'the chip time is the span between the crossings, whatever the device sent'
);

update event_results
   set duration_s = 300, chip_time_s = 300,
       start_at = now() - interval '360 seconds', finish_at = now() - interval '60 seconds'
 where event_id = 'e7306000-0000-0000-0000-0000000000e4'
   and user_id = 'e7306000-0000-0000-0000-000000000002';

select is(
  (select duration_s from event_results where event_id = 'e7306000-0000-0000-0000-0000000000e4'
                                         and user_id = 'e7306000-0000-0000-0000-000000000002'),
  240,
  'a slower attempt leaves a gate-timed finish in place, without an error'
);

update event_results
   set start_at = now() - interval '290 seconds', finish_at = now() - interval '70 seconds'
 where event_id = 'e7306000-0000-0000-0000-0000000000e4'
   and user_id = 'e7306000-0000-0000-0000-000000000002';

select is(
  (select duration_s from event_results where event_id = 'e7306000-0000-0000-0000-0000000000e4'
                                         and user_id = 'e7306000-0000-0000-0000-000000000002'),
  220,
  'a faster gate-timed attempt replaces it'
);

update event_results set finisher_status = 'dnf', duration_s = 100
 where event_id = 'e7306000-0000-0000-0000-0000000000e4'
   and user_id = 'e7306000-0000-0000-0000-000000000002';

select is(
  (select finisher_status from event_results where event_id = 'e7306000-0000-0000-0000-0000000000e4'
                                              and user_id = 'e7306000-0000-0000-0000-000000000002'),
  'finished',
  'a DNF never replaces a gate-timed finish'
);

set local "request.jwt.claims" = '{"sub":"e7306000-0000-0000-0000-000000000003","role":"authenticated"}';

insert into event_results (event_id, instance_start, user_id, duration_s, distance_m, finisher_status)
select id, starts_at, 'e7306000-0000-0000-0000-000000000003', 600, 2000, 'dnf'
  from events where id = 'e7306000-0000-0000-0000-0000000000e4';

update event_results
   set finisher_status = 'finished', duration_s = 1400, chip_time_s = 1400, finish_method = 'auto',
       start_at = window_start.at - interval '1 hour', finish_at = window_start.at,
       start_detection = 'gate', finish_detection = 'gate'
  from (select now() as at) window_start
 where event_id = 'e7306000-0000-0000-0000-0000000000e4'
   and user_id = 'e7306000-0000-0000-0000-000000000003';

select is(
  (select finisher_status from event_results where event_id = 'e7306000-0000-0000-0000-0000000000e4'
                                              and user_id = 'e7306000-0000-0000-0000-000000000003'),
  'finished',
  'a DNF is replaced by a later finish'
);

select ok(
  (select needs_review from event_results where event_id = 'e7306000-0000-0000-0000-0000000000e4'
                                           and user_id = 'e7306000-0000-0000-0000-000000000003'),
  'a start-line crossing before the window opened needs review'
);

update event_results
   set start_at = now() - interval '200 seconds', finish_at = now() - interval '20 seconds'
 where event_id = 'e7306000-0000-0000-0000-0000000000e4'
   and user_id = 'e7306000-0000-0000-0000-000000000003';

select ok(
  (select needs_review from event_results where event_id = 'e7306000-0000-0000-0000-0000000000e4'
                                           and user_id = 'e7306000-0000-0000-0000-000000000003'),
  'crossings the runner''s pings do not support need review'
);

-- ── 32: retention ───────────────────────────────────────────────────────────
reset role;
set local "request.jwt.claims" = '';

insert into race_pings (event_id, instance_start, user_id, at, lat, lng)
select id, starts_at, 'e7306000-0000-0000-0000-000000000003'::uuid, now() - interval '3 days', 51.5, -0.1
  from events where id = 'e7306000-0000-0000-0000-0000000000e4'
union all
select id, starts_at, 'e7306000-0000-0000-0000-000000000003'::uuid, now() - interval '3 days', 51.5, -0.1
  from events where id = 'e7306000-0000-0000-0000-0000000000e6';

select public.cleanup_stale_race_pings();

select ok(
  exists (select 1 from race_pings where event_id = 'e7306000-0000-0000-0000-0000000000e4'
                                     and at < now() - interval '2 days')
  and not exists (select 1 from race_pings where event_id = 'e7306000-0000-0000-0000-0000000000e6'
                                             and at < now() - interval '2 days'),
  'an open self-timed window keeps its pings past 48 h; a Host GO race does not'
);

-- ── 33: an edit resets approval ─────────────────────────────────────────────
insert into event_results (event_id, instance_start, user_id, duration_s, distance_m)
select id, starts_at, 'e7306000-0000-0000-0000-000000000002', 2000, 10000
  from events where id = 'e7306000-0000-0000-0000-0000000000e6';
update event_results set organiser_approved = true
 where event_id = 'e7306000-0000-0000-0000-0000000000e6';

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"e7306000-0000-0000-0000-000000000002","role":"authenticated"}';

update event_results set duration_s = 1800
 where event_id = 'e7306000-0000-0000-0000-0000000000e6'
   and user_id = 'e7306000-0000-0000-0000-000000000002';

select ok(
  (select not organiser_approved and needs_review from event_results
    where event_id = 'e7306000-0000-0000-0000-0000000000e6'
      and user_id = 'e7306000-0000-0000-0000-000000000002'),
  'editing your own time on a race that is not auto-approved resets approval and flags review'
);

-- ── 34: my_race_sessions ────────────────────────────────────────────────────
select ok(
  exists (select 1 from public.my_race_sessions()
           where event_id = 'e7306000-0000-0000-0000-0000000000e4'
             and effective_status = 'running' and start_mode = 'self_timed'),
  'my_race_sessions lists the open self-timed window the runner is going to'
);

-- ── 35: Extend is bounded ───────────────────────────────────────────────────
set local "request.jwt.claims" = '{"sub":"e7306000-0000-0000-0000-000000000001","role":"authenticated"}';

select throws_ok(
  $$ update race_sessions set window_closes_at = window_opens_at + interval '8 days'
      where event_id = 'e7306000-0000-0000-0000-0000000000e4' $$,
  '23514', null,
  'a window cannot be extended past 7 days from its opening'
);

-- ── 36: validated ───────────────────────────────────────────────────────────
reset role;
select is(
  (select count(*)::int from pg_constraint
    where conname in ('events_race_start_mode_check', 'events_race_start_settings_check',
                      'race_sessions_start_mode_check', 'race_sessions_start_mode_times_check',
                      'event_results_start_detection_check', 'event_results_finish_detection_check',
                      'event_results_finish_detection_auto_check',
                      'events_race_scheduled_offset_s_check', 'events_race_window_open_offset_s_check',
                      'events_race_window_length_s_check',
                      'race_pings_since_start_line_s_check', 'notifications_kind_check')
      and not convalidated),
  0,
  'every new CHECK is validated'
);

select * from finish();
rollback;

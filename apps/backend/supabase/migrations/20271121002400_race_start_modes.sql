-- Race start modes (#1306, timing lines phase 3, decisions § 2400-§ 2401).
--
-- A race starts one of three ways, chosen per event:
--
--   * host_go     (default; what every race did before): the organiser arms
--                 the race, presses GO and ends it.
--   * scheduled   the server fires GO at a scheduled offset from the
--                 occurrence's start. The organiser can arm early, delay or
--                 cancel until the instant passes; the race ends itself at
--                 window close unless the organiser ends it first.
--   * self_timed  a window opens at an offset from the occurrence and stays
--                 open for up to 7 days. Each runner times their own attempt
--                 from the start line to the finish line; there is no gun.
--
-- Times are stored on the event as OFFSETS from the occurrence (B5), so a
-- moved occurrence keeps its race times relative to the new start. Each race
-- session copies the mode and turns the offsets into absolute instants when it
-- is created; an organiser's per-occurrence delay or extension lives on that
-- session only. A BEFORE UPDATE trigger shifts a not-yet-started session's
-- instants with its instance_start, so the BUG-015 mover (§ 2353) and the
-- § 1918 remap carry them without a second mover.
--
-- Sessions for scheduled and self-timed races are created lazily by
-- private.ensure_race_session_due: from the per-minute race_sessions_tick job
-- (a short way ahead of each opening instant), from my_race_sessions() (the
-- participant read the phone and Wear OS poll) and from ensure_race_session()
-- (the event page). Host GO sessions are still created by Arm.
--
-- The result columns #1307 specifies (start_at / finish_at / start_detection /
-- finish_detection / needs_review) land here, because the Self-timed result
-- rules read them; devices start writing them with #1307.
--
-- This file now holds only the notifications kind_check swap. The rest of the
-- change is split one table per file (docs/backend/migration_locks.md § One
-- table per migration), because each file is one transaction and every lock
-- it takes is held to its commit:
--
--   20271121100001  events columns + CHECKs + index
--   20271121100002  race_sessions columns + CHECKs
--   20271121100003  event_results columns + CHECKs
--   20271121100004  notifications_race_starting_soon_uniq, built alone
--   20271121100005  functions, triggers, the per-minute job, redacted views
--   20271121100006  race_pings column + CHECK + insert policy
--   20271121100007  validates the CHECKs of 100001-100003 and 100006
--
-- Locks: the swap drops and re-adds the CHECK NOT VALID, a brief ACCESS
-- EXCLUSIVE on notifications with no scan; 20271121002401 validates it in its
-- own transaction.

set search_path = public;

-- ─── notifications: the two race kinds ─────────────────────────────────────

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
      'workout_reminder',
      'plan_ai_edit',
      'personal_record',
      'club_join_request', 'club_join_approved', 'event_updated',
      'plan_change_request', 'plan_change_decision',
      'club_verification',
      'race_starting_soon', 'race_start_moved'
    )
  )
  not valid;

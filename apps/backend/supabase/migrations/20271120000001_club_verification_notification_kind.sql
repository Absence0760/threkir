-- The `club_verification` notification kind (issue #1190 § 2, decisions
-- § 2398). Its CHECK and the validate are this file and 20271120000002; the
-- table, RPCs and triggers that raise it are 20271120000004, so the ACCESS
-- EXCLUSIVE taken here on `notifications` is never held while a CREATE
-- TRIGGER on `clubs` waits (docs/backend/migration_locks.md § One table per
-- migration).
--
-- One kind for every change to a club's verification (approved, rejected,
-- revoked, lapsed), sent to the club's owner and active admins with the club
-- id. The copy says the status changed and links the club page, where the
-- verification card says what changed and why.
--
-- Locks: the CHECK swap is NOT VALID (ACCESS EXCLUSIVE for an O(1) catalogue
-- change, no scan); 20271120000002 validates it under SHARE UPDATE EXCLUSIVE.

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
      'club_verification'
    )
  )
  not valid;

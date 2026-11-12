-- Organiser name disputes, part 2: the `organiser_dispute` notification kind
-- (issue #1363, decisions § 2441).
--
-- A reviewer's action on a dispute (hide, rename notice, dismiss) notifies
-- both sides: the owner of the disputed content and the reporting club's
-- owner and active admins. notifications.club_id names the reporting club;
-- the reviewer is never named (actor_id null). The rows are written by
-- resolve_organiser_dispute in 20271202000003.
--
-- notifications_kind_check is the full list from 20271124002408 plus
-- 'organiser_dispute'. Locks: notifications is a high-volume table, so the
-- widened CHECK is added NOT VALID (brief ACCESS EXCLUSIVE, no scan) and
-- validated in 20271202000004.

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
      'race_starting_soon', 'race_start_moved',
      'course_alert',
      'organiser_dispute'
    )
  )
  not valid;

-- Park course problem reports, part 2: the `park_course_report` notification
-- kind (issue #1346, decisions § 2447).
--
-- A report on a park course notifies every app admin (app_admins), so the
-- operator sees it without watching the queue: on the first pending report on
-- a course, and on every land-manager request, which carries a two-business-
-- day deadline. The rows carry no actor and no target; the notice links to
-- /admin/reports. Written by submit_park_course_report in 20271212000003.
--
-- notifications_kind_check is the full list from 20271202000002 plus
-- 'park_course_report'. Locks: notifications is a high-volume table, so the
-- widened CHECK is added NOT VALID (brief ACCESS EXCLUSIVE, no scan) and
-- validated in 20271212000004.

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
      'organiser_dispute',
      'park_course_report'
    )
  )
  not valid;

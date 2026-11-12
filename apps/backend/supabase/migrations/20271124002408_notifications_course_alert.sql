-- The `course_alert` notification kind and its link column (issue #1190,
-- decisions § 2407). The alerts table and the RPC that raises these rows are
-- 20271124002407.
--
--   * notifications.course_alert_id names the alert. It cascades, so
--     delete_course_alert withdraws the notices with the alert. The worker's
--     projection carries only this id, so email and push deep-link to the
--     web resolver /course-alerts/{id}, which opens the race or route, the
--     way /events/{id} resolves an event.
--   * notifications_kind_check gains 'course_alert'. The list is the full one
--     from 20271121002400 (which added the two race-start kinds after
--     20271120000001 added 'club_verification') plus that value.
--
-- Locks: ADD COLUMN of a nullable column with no default is catalogue-only.
-- The FK and the CHECK are added NOT VALID (brief ACCESS EXCLUSIVE, no scan)
-- and validated in 20271124002409 under SHARE UPDATE EXCLUSIVE. The covering
-- index is built by 20271124100001 in its own transaction: here the ADD
-- COLUMN's ACCESS EXCLUSIVE would still be held while the build reads the
-- heap, so readers would wait for the scan too.

alter table notifications add column course_alert_id uuid;

alter table notifications
  add constraint notifications_course_alert_id_fkey
  foreign key (course_alert_id) references course_alerts (id) on delete cascade
  not valid;

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
      'course_alert'
    )
  )
  not valid;

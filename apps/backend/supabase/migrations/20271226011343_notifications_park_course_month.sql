-- Month-close notice, part 1: the `park_course_month_closed` notification kind
-- and the three columns its row carries (issue #1343 phase 3, decisions
-- § 2426 / § 2511).
--
--   notifications.kind 'park_course_month_closed'  one row per runner, course
--       and month, raised by public.enqueue_park_course_month_notices
--       (20271226041343) once the month has closed where the park is. Bell-
--       only by default: it is in neither of the worker's default sets.
--   notifications.park_course_id       the course. ON DELETE CASCADE: a course
--       the catalogue removes takes its notices with it, so none links to a
--       course page that no longer exists.
--   notifications.park_course_month    the month, as the local 1st (a date),
--       which is the `?period=YYYY-MM` the notice deep-links to.
--   notifications.park_course_time_s   the runner's best time on the course
--       that month, in whole seconds. No rank: a rank depends on who is
--       looking, and the job has no caller (decisions § 2426).
-- All three are null on every other row.
--
-- notifications_kind_check is the full list from 20271217000001 plus
-- 'park_course_month_closed'. Locks: notifications is a high-volume table
-- (docs/backend/migration_locks.md), so the widened CHECK and the FK are added
-- NOT VALID (brief ACCESS EXCLUSIVE, no scan) and validated in
-- 20271226021343; the ADD COLUMNs have no default, so they are catalogue-only.
-- The FK's covering index is built alone in 20271226031343.

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
      'park_course_report',
      'group_invite',
      'park_course_month_closed'
    )
  )
  not valid;

alter table notifications add column park_course_id uuid;
alter table notifications add column park_course_month date;
alter table notifications add column park_course_time_s integer;

alter table notifications
  add constraint notifications_park_course_id_fkey
  foreign key (park_course_id) references park_courses (id) on delete cascade
  not valid;

comment on column notifications.park_course_id is
  'The park course a ''park_course_month_closed'' notice is about (20271226011343); null on every other row. Cascades with the course.';
comment on column notifications.park_course_month is
  'The closed month of a ''park_course_month_closed'' notice, as the 1st of that month in the park''s timezone; null on every other row.';
comment on column notifications.park_course_time_s is
  'The recipient''s best time on the course in that month, whole seconds, on a ''park_course_month_closed'' notice; never a rank. Null on every other row.';

-- Group conversations, slice 2 (issue #1365, docs/features/group_messages.md,
-- decisions § 2463): the notification columns the group surfaces open.
--
--   notifications.kind 'group_invite'   one row to the invitee when an owner or
--       admin invites them (private.group_invite, 20271217000006). It names
--       the inviter and the conversation and nothing else: the invitee reads
--       the title and the member count through group_invites(), never the
--       roster (memo C5).
--   notifications.conversation_id       the group a 'message' or 'group_invite'
--       row is about, so the bell opens that group rather than a 1:1 thread
--       with the sender. Null on every other row. ON DELETE CASCADE: a group
--       the purge erases takes its notices with it, so none outlives the
--       conversation it points at.
--
-- A group message reuses kind 'message' rather than a kind of its own: the
-- worker already sends it as the generic, content-free "you have a new
-- message" on every channel and under the same mute, and copyKeyFor picks the
-- group wording from conversation_id.
--
-- notifications_kind_check is the full list from 20271213000002 plus
-- 'group_invite'. Locks: notifications is a high-volume table
-- (docs/backend/migration_locks.md), so the widened CHECK and the FK are added
-- NOT VALID (brief ACCESS EXCLUSIVE, no scan) and validated in
-- 20271217000002; the ADD COLUMN has no default, so it is catalogue-only. The
-- covering index is built alone in 20271217000003.

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
      'group_invite'
    )
  )
  not valid;

alter table notifications add column conversation_id uuid;

alter table notifications
  add constraint notifications_conversation_id_fkey
  foreign key (conversation_id) references conversations (id) on delete cascade
  not valid;

comment on column notifications.conversation_id is
  'The group a ''message'' or ''group_invite'' notification is about (20271217000001); null on every other row and on a 1:1 message. Cascades with the conversation.';

-- Organisers hear about join requests and RSVPs, members hear when they are
-- let in, and attendees hear when an event they are going to is edited or
-- deleted (decisions § 2358, issue #1300 BUG-009 / BUG-010 / BUG-016).
--
--   1. Three kinds: `club_join_request` (to the club's owner and admins, the
--      people who can approve), `club_join_approved` (to the member), and
--      `event_updated` (to the upcoming attendees).
--   2. `notify_event_rsvp` widens to the club's owner and admins, keys each
--      notice to the occurrence (`event_instance_start`), and replaces the
--      once-per-event unique index with a 24 h window per occurrence, so a
--      member's RSVP to next week's run notifies like their first one did and
--      a going / not going / going flip inside a day still notifies once.
--   3. `private.notify_event_updated` (AFTER UPDATE on events) tells everyone
--      holding a place on an upcoming occurrence that the time, place or
--      description changed. It runs after `events_move_rescheduled_rows`
--      (20271111000001; triggers fire in name order), so on a reschedule it
--      reads the attendees at their moved instants. One notice per attendee
--      per event per 15 minutes: an organiser saving three edits in a row
--      raises one.
--   4. `private.notify_event_deleted` (BEFORE DELETE on events) sends the
--      upcoming attendees an `event_cancel` that is NOT linked to the event:
--      `notifications.event_id` cascades, so a linked row would be erased by
--      the delete it reports. The row carries the club and a snapshot of the
--      title in the new `notifications.event_title`. A delete stays a hard
--      delete; § 2358 records why a soft delete was not taken.
--
-- This file is the `notifications` half only: the column, the two CHECKs and
-- the dropped RSVP index. The functions and triggers that write the new rows
-- are 20271112000012 (club_members) and 20271112000013 (events, RSVPs), each
-- in its own transaction, so the ACCESS EXCLUSIVE held here on
-- `notifications` is never held while a CREATE TRIGGER waits on a table whose
-- writers insert into `notifications` (docs/backend/migration_locks.md § One
-- table per migration).
--
-- Locks: ADD COLUMN of a nullable column with no default is catalogue-only.
-- Both CHECKs are added NOT VALID (ACCESS EXCLUSIVE for an O(1) catalogue
-- change, no scan) and validated in 20271112000011 under SHARE UPDATE
-- EXCLUSIVE. DROP INDEX takes ACCESS EXCLUSIVE for the catalogue change only.
-- Until 20271112000013 replaces it, the old `notify_event_rsvp` runs without
-- the index, so a member flipping an RSVP inside that deploy gap can raise a
-- second notice; nothing else changes.

alter table notifications add column event_title text;

alter table notifications
  add constraint notifications_event_title_len_chk
  check (event_title is null or char_length(event_title) <= 120)
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
      'club_join_request', 'club_join_approved', 'event_updated'
    )
  )
  not valid;

drop index notifications_event_rsvp_uniq;

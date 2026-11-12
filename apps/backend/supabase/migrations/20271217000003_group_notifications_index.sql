-- The covering index for notifications.conversation_id (20271217000001), built
-- alone so the read of the notifications heap holds no ACCESS EXCLUSIVE. It
-- serves the FK's cascade when the purge erases a group, and the group message
-- burst check in notify_direct_message (20271217000006). The predicate is false
-- on every existing row, so the index is tiny; the scan is not.

create index if not exists notifications_conversation_id
  on notifications (conversation_id, user_id)
  where conversation_id is not null;

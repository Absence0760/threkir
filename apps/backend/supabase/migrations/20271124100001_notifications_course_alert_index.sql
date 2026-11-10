-- The covering index for notifications.course_alert_id (decisions § 2407),
-- moved out of 20271124002408 so it is built alone.
--
-- Locks: the build reads the notifications heap once under SHARE, so the
-- fan-out's inserts wait for that read and readers do not. In 20271124002408
-- it ran after the ADD COLUMN, whose ACCESS EXCLUSIVE was still held, which
-- made readers wait as well. The predicate is false on every existing row, so
-- the index is tiny; the scan is not. IF NOT EXISTS keeps it a no-op on a
-- database that built it from the earlier form of 20271124002408.

create index if not exists notifications_course_alert_id
  on notifications (course_alert_id)
  where course_alert_id is not null;

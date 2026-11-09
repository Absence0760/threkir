-- Second half of 20271124002408: validate the FK and the kind CHECK it added
-- NOT VALID, in their own transaction under SHARE UPDATE EXCLUSIVE, so the
-- notification fan-out keeps inserting while the scans run
-- (docs/backend/migration_locks.md § CHECK constraints). The kind set only
-- widened and course_alert_id is null on every existing row, so neither scan
-- can find a violation.

alter table notifications validate constraint notifications_course_alert_id_fkey;
alter table notifications validate constraint notifications_kind_check;

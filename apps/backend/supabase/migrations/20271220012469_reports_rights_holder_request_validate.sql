-- Validates the two reports constraints 20271220002469 re-added NOT VALID, in
-- this file's own transaction (docs/backend/migration_locks.md): the scans
-- run under SHARE UPDATE EXCLUSIVE, so reads and writes on reports proceed.
-- Every existing row satisfies them, since both lists only widened.

alter table reports validate constraint reports_reason_check;
alter table reports validate constraint reports_park_course_check;

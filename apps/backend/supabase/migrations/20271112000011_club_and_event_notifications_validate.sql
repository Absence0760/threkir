-- Second half of 20271112000010: validate the two notifications CHECKs it
-- added NOT VALID.
--
-- VALIDATE CONSTRAINT scans under SHARE UPDATE EXCLUSIVE, so the notification
-- fan-out keeps inserting while it runs, in its own transaction apart from
-- the ACCESS EXCLUSIVE the constraint swap took
-- (docs/backend/migration_locks.md § CHECK constraints). The kind set only
-- widened and `event_title` is new and null on every existing row, so neither
-- scan can find a violation.

alter table notifications validate constraint notifications_kind_check;
alter table notifications validate constraint notifications_event_title_len_chk;

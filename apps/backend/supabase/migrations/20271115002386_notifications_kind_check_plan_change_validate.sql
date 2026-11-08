-- Second half of 20271115002382: validate the notifications kind CHECK it
-- widened NOT VALID.
--
-- VALIDATE CONSTRAINT scans under SHARE UPDATE EXCLUSIVE, so the notification
-- fan-out keeps inserting while it runs, in its own transaction apart from the
-- ACCESS EXCLUSIVE the constraint swap took (docs/backend/migration_locks.md
-- § CHECK constraints). The kind set only widened, so the scan cannot find a
-- violation.

alter table notifications validate constraint notifications_kind_check;

-- Second half of 20271104000002: validate the widened notifications_kind_check.
--
-- 20271104000002 re-emitted the kind union with `personal_record` added, as
-- `ADD ... NOT VALID`, so new rows were checked at once and no existing row was
-- scanned under the ACCESS EXCLUSIVE its DROP CONSTRAINT took. This file is the
-- scan, in its own transaction: VALIDATE CONSTRAINT holds SHARE UPDATE
-- EXCLUSIVE, so the notification fan-out keeps inserting while it runs
-- (docs/backend/migration_locks.md § CHECK constraints). The set only widened,
-- so the scan cannot find a violation.

alter table notifications validate constraint notifications_kind_check;

-- Second half of 20271021000050: validate the widened notifications_kind_check.
--
-- 20271021000050 re-emitted the kind union with `plan_ai_edit` added, as
-- `ADD ... NOT VALID`, so new rows were checked at once and no existing row was
-- scanned under the ACCESS EXCLUSIVE its DROP CONSTRAINT took. This file is the
-- scan, in its own transaction: VALIDATE CONSTRAINT holds SHARE UPDATE
-- EXCLUSIVE, so the notification fan-out keeps inserting while it runs
-- (docs/backend/migration_locks.md § CHECK constraints). The set only widened,
-- so the scan cannot find a violation.

alter table notifications validate constraint notifications_kind_check;

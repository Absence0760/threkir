-- Second half of 20270726000002: validate the widened notifications_kind_check.
--
-- 20270726000002 re-emitted the kind union with `event_waitlist_slot` added,
-- as `ADD ... NOT VALID`, so new rows were checked at once and no existing row
-- was scanned under the ACCESS EXCLUSIVE its DROP CONSTRAINT took. This file
-- is the scan, in its own transaction: VALIDATE CONSTRAINT holds SHARE UPDATE
-- EXCLUSIVE, so the notification fan-out keeps inserting while it runs
-- (docs/backend/migration_locks.md § CHECK constraints).
--
-- No pre-flight: the set only widened, and every row already in the table was
-- admitted by the narrower list it replaced, so the scan cannot find a
-- violation. It is run anyway because an unvalidated constraint is not one the
-- planner may rely on, and because leaving it NOT VALID would be a state no
-- later reader of the schema could tell from a forgotten step.

alter table notifications validate constraint notifications_kind_check;

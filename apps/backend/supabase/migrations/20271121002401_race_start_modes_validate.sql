-- Second half of 20271121002400: validate the notifications kind CHECK it
-- added NOT VALID.
--
-- VALIDATE CONSTRAINT scans under SHARE UPDATE EXCLUSIVE, so reads and writes
-- keep flowing, in its own transaction apart from the ACCESS EXCLUSIVE the
-- swap took (docs/backend/migration_locks.md § CHECK constraints). The kind
-- set only widened, so no scan can find a violation. The other race start
-- CHECKs moved with their tables and are validated by 20271121100007.

alter table notifications validate constraint notifications_kind_check;

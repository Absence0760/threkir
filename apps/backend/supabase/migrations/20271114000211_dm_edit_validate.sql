-- Validates the two CHECKs 20271114000210 added NOT VALID (issue #1216,
-- decisions § 2373). A separate file, so each scan runs in its own
-- transaction holding only SHARE UPDATE EXCLUSIVE, which lets reads and writes
-- on direct_messages and reports carry on (docs/backend/migration_locks.md).

alter table direct_messages validate constraint direct_messages_original_body_check;
alter table reports validate constraint reports_snapshot_original_body_check;

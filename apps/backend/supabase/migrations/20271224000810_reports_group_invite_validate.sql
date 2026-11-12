-- Validates the reports constraints 20271224000800 added NOT VALID, in this
-- file's own transaction (docs/backend/migration_locks.md): the scans run
-- under SHARE UPDATE EXCLUSIVE, so reads and writes on reports proceed. Every
-- existing row satisfies both: the kind list only widened, and no earlier row
-- could carry the new kind.

alter table reports validate constraint reports_target_kind_check;
alter table reports validate constraint reports_group_invite_snapshot_check;

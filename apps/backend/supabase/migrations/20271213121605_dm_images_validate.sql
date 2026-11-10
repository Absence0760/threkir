-- Validates what 20271213121604 added NOT VALID, each in this file's own
-- transaction so the scans run under SHARE UPDATE EXCLUSIVE, which neither
-- readers nor writers wait on, and indexes reports.snapshot_image_id alone
-- here rather than under that file's ACCESS EXCLUSIVE on reports
-- (docs/backend/migration_locks.md § Index builds). reports is a small,
-- bounded table, so the plain build is a brief write pause.

alter table direct_messages validate constraint direct_messages_body_check;
alter table reports validate constraint reports_snapshot_image_id_fkey;
alter table reports validate constraint reports_snapshot_image_check;

create index if not exists reports_snapshot_image_id on reports (snapshot_image_id)
  where snapshot_image_id is not null;

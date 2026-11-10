-- Validates the constraints 20271212000001 and 20271212000002 added NOT VALID,
-- in this file's own transaction (docs/backend/migration_locks.md): the scans
-- run under SHARE UPDATE EXCLUSIVE, so reads and writes on reports and
-- notifications proceed. Every existing row satisfies them: the lists only
-- widened, and no earlier row could carry a park course kind or reason, a
-- contact email or the signed-out flag. Then the index the signed-out hourly
-- cap in submit_park_course_report reads, which no earlier file in this set
-- may build while it held ACCESS EXCLUSIVE on reports.

alter table reports validate constraint reports_reason_check;
alter table reports validate constraint reports_target_kind_check;
alter table reports validate constraint reports_park_course_check;
alter table reports validate constraint reports_contact_email_shape;
alter table notifications validate constraint notifications_kind_check;

create index if not exists reports_signed_out_created
  on reports (created_at) where signed_out;

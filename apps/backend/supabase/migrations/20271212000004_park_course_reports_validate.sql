-- Validates the reports constraints 20271212000001 added NOT VALID, in this
-- file's own transaction (docs/backend/migration_locks.md): the scans run
-- under SHARE UPDATE EXCLUSIVE, so reads and writes on reports proceed. Every
-- existing row satisfies them: the lists only widened, and no earlier row
-- could carry a park course kind or reason, a contact email or the signed-out
-- flag. Then the index the signed-out hourly cap in submit_park_course_report
-- reads, which 20271212000001 may not build while it held ACCESS EXCLUSIVE on
-- reports. The notifications CHECK is validated alone in 20271212000005.

alter table reports validate constraint reports_reason_check;
alter table reports validate constraint reports_target_kind_check;
alter table reports validate constraint reports_park_course_check;
alter table reports validate constraint reports_contact_email_shape;

create index if not exists reports_signed_out_created
  on reports (created_at) where signed_out;

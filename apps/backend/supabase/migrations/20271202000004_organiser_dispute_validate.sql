-- Validates the constraints 20271202000001 and 20271202000002 added NOT VALID,
-- each in this file's own transaction (docs/backend/migration_locks.md): the
-- scans run under SHARE UPDATE EXCLUSIVE, so reads and writes on reports and
-- notifications proceed. Every existing row satisfies them: the lists only
-- widened, and no earlier row could carry the dispute reason, a new target
-- kind or an organiser club. Then the covering index for the new FK, which
-- no earlier file in this set may build while it held ACCESS EXCLUSIVE on
-- reports.

alter table reports validate constraint reports_organiser_club_id_fkey;
alter table reports validate constraint reports_reason_check;
alter table reports validate constraint reports_target_kind_check;
alter table reports validate constraint reports_organiser_dispute_check;
alter table notifications validate constraint notifications_kind_check;

create index if not exists reports_organiser_club_id
  on reports (organiser_club_id) where organiser_club_id is not null;

-- Validates the notifications_kind_check 20271212000002 widened NOT VALID, in
-- its own file so the scan of a high-volume table holds nothing on any other
-- (docs/backend/migration_locks.md § One table per migration). VALIDATE runs
-- under SHARE UPDATE EXCLUSIVE, so inserts proceed; the list only widened, so
-- every existing row passes.

alter table notifications validate constraint notifications_kind_check;

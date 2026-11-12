-- VALIDATE half of run_photos_runless_has_occurrence (added NOT VALID in
-- 20270807000001). Its own file so the scan runs under SHARE UPDATE EXCLUSIVE
-- in its own transaction, with reads and writes proceeding
-- (docs/backend/migration_locks.md). Every existing row has a run_id, so the
-- scan finds nothing to reject.

alter table public.run_photos
  validate constraint run_photos_runless_has_occurrence;

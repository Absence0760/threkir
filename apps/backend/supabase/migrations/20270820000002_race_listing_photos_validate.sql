-- VALIDATE half of run_photos_race_gallery_needs_run (added NOT VALID in
-- 20270820000001). Its own file so the scan runs under SHARE UPDATE EXCLUSIVE
-- in its own transaction, with reads and writes proceeding
-- (docs/backend/migration_locks.md). Every existing row has race_gallery =
-- false, so the scan finds nothing to reject.

alter table public.run_photos
  validate constraint run_photos_race_gallery_needs_run;

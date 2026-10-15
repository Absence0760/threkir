-- Validate the user_profiles.parkrun_number format CHECK added NOT VALID in
-- 20270818000001.
--
-- In its own migration, and therefore its own transaction, so the scan runs
-- under SHARE UPDATE EXCLUSIVE and reads and writes proceed during it
-- (migration_locks.md). The previous migration's backfill left only canonical
-- values or NULL behind, and its trigger has normalised every write since, so
-- the scan finds nothing to refuse.
alter table public.user_profiles
  validate constraint user_profiles_parkrun_number_format_chk;

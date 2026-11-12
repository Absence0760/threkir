-- Validate the routes.tags set invariant added NOT VALID in 20270816000011.
--
-- In its own migration, and therefore its own transaction, so the scan runs
-- under SHARE UPDATE EXCLUSIVE and reads and writes proceed during it
-- (migration_locks.md). The previous migration's backfill left no duplicate
-- behind, and its trigger normalised every write since, so the scan finds
-- nothing to refuse.
alter table public.routes
  validate constraint routes_tags_distinct_check;

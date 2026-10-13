-- Validate events_one_class_content (added NOT VALID in 20270803000001), in a
-- transaction of its own so the scan runs under SHARE UPDATE EXCLUSIVE and
-- event writes proceed during it (docs/backend/migration_locks.md). Every
-- existing row passes: gym_routine_id did not exist before that migration.

alter table public.events validate constraint events_one_class_content;

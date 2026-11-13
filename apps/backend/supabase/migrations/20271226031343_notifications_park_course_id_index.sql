-- The covering index for notifications.park_course_id (20271226011343), built
-- alone so the read of the notifications heap holds no ACCESS EXCLUSIVE
-- (docs/backend/migration_locks.md § Index builds). It serves the FK's cascade
-- when a park course is deleted. The predicate is false on every existing row,
-- so the index is tiny; the scan is not.

create index if not exists notifications_park_course_id
  on notifications (park_course_id)
  where park_course_id is not null;

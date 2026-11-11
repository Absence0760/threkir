-- Validates the race_session_courses lap-count CHECK 20271222002472 added NOT
-- VALID (decisions § 2472), in a transaction of its own so the scan holds no
-- stronger lock than VALIDATE's SHARE UPDATE EXCLUSIVE
-- (docs/backend/migration_locks.md).

alter table public.race_session_courses
  validate constraint race_session_courses_finish_lap_count_check;

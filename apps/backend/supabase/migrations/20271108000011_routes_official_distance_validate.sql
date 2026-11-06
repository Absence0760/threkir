-- Validates the CHECK 20271108000010 added NOT VALID, in its own transaction
-- so the scan runs under SHARE UPDATE EXCLUSIVE and writers proceed
-- (docs/backend/migration_locks.md). Every row is null at this point.

alter table routes validate constraint routes_official_distance_m_check;

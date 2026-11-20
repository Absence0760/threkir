-- Validates the parks_agency_check that 20280103001431 widened NOT VALID, in
-- this file's own transaction so the scan runs under SHARE UPDATE EXCLUSIVE
-- (docs/backend/migration_locks.md). Every existing row holds one of the four
-- values the narrower CHECK allowed, all of which the wider one keeps.

alter table public.parks validate constraint parks_agency_check;

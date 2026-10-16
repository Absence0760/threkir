-- Second half of 20270829000041: validate clubs_strava_club_id_check.
--
-- VALIDATE CONSTRAINT scans under SHARE UPDATE EXCLUSIVE, so club reads and
-- writes proceed while it runs (docs/backend/migration_locks.md § CHECK
-- constraints). The only writer has refused a non-positive id since the column
-- landed, so the scan cannot find a violation.

alter table clubs validate constraint clubs_strava_club_id_check;

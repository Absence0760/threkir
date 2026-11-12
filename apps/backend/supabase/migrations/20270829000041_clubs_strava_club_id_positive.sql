-- Bound `clubs.strava_club_id` (added by 20270819001953) to a positive id.
--
-- Strava club ids are positive integers, and the column's only writer,
-- `set_club_strava_link`, already refuses `p_strava_club_id <= 0`. That refusal
-- lives in one function body; the column itself admitted a zero or a negative
-- from any other service-role write, and `numeric_bounds_reject_nan_test`'s
-- coverage rule fails on a numeric column with no single-column CHECK. The
-- constraint makes the RPC's guard equivalent rather than load-bearing, the
-- same move 20270705000004 made for the integer family. NULL stays legal: it
-- is "not linked".
--
-- Online safety (docs/backend/migration_locks.md § CHECK constraints): added
-- NOT VALID here, a catalogue flip with no scan, and validated in
-- 20270829000042 in its own transaction under SHARE UPDATE EXCLUSIVE.
--
-- Run before applying to a populated instance — must return 0, or the
-- VALIDATE fails:
--
--   select count(*) from clubs where strava_club_id <= 0;
--
-- No column type, nullability or default moves, so neither row-type generator
-- has anything to regenerate.

alter table clubs
  add constraint clubs_strava_club_id_check
    check (strava_club_id is null or strava_club_id > 0) not valid;

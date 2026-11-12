-- Validates runs_duration_s_max_check (added NOT VALID by 20271112000020).
--
-- 20271218000002 capped every row above the bound, so the scan finds none.
-- The duration_repair jobs it enqueued do not have to drain first: each one
-- only ever lowers a capped duration to a track span under the bound.
--
-- Its own file (docs/backend/migration_locks.md § CHECK constraints): VALIDATE
-- takes SHARE UPDATE EXCLUSIVE, so reads and writes on `runs` carry on during
-- the scan, which only holds when no stronger lock from an earlier statement
-- in the same transaction is still held.

alter table runs validate constraint runs_duration_s_max_check;

comment on constraint runs_duration_s_max_check on runs is
  'A run lasts at most ten days (864000 s). Validated by 20271218000003 after '
  '20271218000002 capped the rows above it (decisions § 2359, § 2464).';

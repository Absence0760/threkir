-- Validates the reporter FK 20271021000040 re-pointed NOT VALID, in its own
-- transaction (docs/backend/migration_locks.md): the scan runs under SHARE
-- UPDATE EXCLUSIVE, so reads and writes on reports proceed while it runs.
-- Every existing row already satisfies it — the old FK was the same reference
-- with a different delete action — so nothing here can fail on data.

alter table reports validate constraint reports_reporter_id_fkey;

-- `runs.updated_at` becomes a server-owned modification clock (decisions
-- § 2118). Until now it was an insert default and nothing else: no trigger
-- moved it on UPDATE, and the web restore wrote an archive's old value straight
-- in. The phone's delta pull therefore keyed on `metadata.last_modified_at`, a
-- stamp only the phone writes, so an edit made on web to a run the phone
-- already held never reached the phone (the gap § 2116 left open).
--
-- The trigger stamps every INSERT and UPDATE with `now()`, unconditionally: a
-- value the client or an archive supplies is overwritten, not honoured, because
-- a client-chosen clock is exactly what the delta cannot trust. `now()` is the
-- transaction's start, so every row a statement writes shares one value; the
-- puller pages on (updated_at, id) for that reason, and re-reads an overlap
-- window behind its cursor because a transaction can commit after a later-
-- starting one that the cursor has already passed.
--
-- Nothing deliberately writes `runs.updated_at` today: no migration, Edge
-- Function, job_worker path or web call sets it outside the restore, and the
-- restore's value is the one this is meant to ignore. `public_runs` does not
-- project it (20260807_001), so no public surface changes. The column-scoped
-- triggers (`update of distance_m, …`) key on the statement's SET list, which a
-- BEFORE trigger's NEW assignment does not extend, so none of them starts
-- firing on rows it did not fire on before.
--
-- No backfill: rows written before this migration keep the value they have.
-- The puller heals stale copies itself by walking every owned row once under a
-- new cursor key (see § 2118), so no historical value needs to be right.
--
-- No index. The pull is `user_id = $1 and updated_at > $2`, which the existing
-- `runs_user_started_at (user_id, started_at desc)` already bounds to one
-- runner's rows, a few thousand at most, once per Runs-tab open. An index on
-- `updated_at` would make EVERY run update non-HOT (the column now changes on
-- each one), and building it is a write-blocking `CREATE INDEX` on a populated
-- table — `CONCURRENTLY` cannot run in a migration's transaction
-- (docs/backend/migration_locks.md). Neither cost is worth a per-user scan that
-- is already cheap.
--
-- Locks: CREATE TRIGGER takes SHARE ROW EXCLUSIVE on `runs` for a
-- catalogue-only change — readers proceed, writers wait for an O(1) step, no
-- scan, no rewrite. CREATE OR REPLACE FUNCTION locks no table.

create or replace function private.stamp_updated_at()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

revoke execute on function private.stamp_updated_at() from public, anon, authenticated;

drop trigger if exists runs_stamp_updated_at on runs;
create trigger runs_stamp_updated_at
  before insert or update on runs
  for each row execute function private.stamp_updated_at();

-- runs: a non-partial unique index on (user_id, external_id), so the import
-- upsert can name it (decisions § 2548).
--
-- 20260528000003 scoped external_id uniqueness to the runner with a PARTIAL
-- index (`where external_id is not null`). Postgres infers a partial index as
-- an ON CONFLICT arbiter only when the statement carries a WHERE matching the
-- predicate, and PostgREST's `on_conflict=` never emits one. So every mobile
-- push of an imported run (Health Connect, Strava ZIP, CSV, the watch
-- bridges: `ApiClient.saveRunsBatch` / `saveRun` upsert them on
-- `user_id,external_id`) raised 42P10 "there is no unique or exclusion
-- constraint matching the ON CONFLICT specification", 100% of the time. The
-- run stayed on the phone, unsynced, retried every cycle, and the runner saw
-- "Something went wrong" (the owner's Richmond Marathon, 2026-11-15).
--
-- The predicate bought nothing: a unique index treats NULLs as distinct, so
-- the native recordings with no external_id never collide in a non-partial
-- index either. The invariant is unchanged, one row per runner per upstream
-- id, and the existing rows already satisfy it (the partial index enforced
-- it). Fixed on the server, so every app build already in the field syncs
-- again without an update.
--
-- Lock: CREATE INDEX alone in its file takes SHARE on runs for the build
-- (writers wait for the heap scan, readers do not;
-- docs/backend/migration_locks.md § Index builds). The partial index is
-- dropped in the next file.

create unique index if not exists runs_user_external_id_arbiter
  on runs (user_id, external_id);

comment on index runs_user_external_id_arbiter is
  'One run per runner per upstream id. Non-partial so ON CONFLICT '
  '(user_id, external_id) can infer it: the partial index it replaces made '
  'every client upsert of an imported run fail with 42P10 (decisions § 2548). '
  'NULL external_ids never collide.';

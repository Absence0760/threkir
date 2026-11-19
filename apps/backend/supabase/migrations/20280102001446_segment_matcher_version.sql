-- The catalogue matcher version the backend deploys (issue #1446, decisions
-- § 2583). Matcher version 4 times a park course by its drawn start and
-- finish boxes; the release ops task
-- apps/backend/ops/tasks/20280102001446_rematch_segments_matcher_v4.sql
-- re-matches old efforts with it, and reads this function so that a sync
-- dispatched before this release (whose functions still carry version 3)
-- fails, rolls back and leaves the task pending, as version 3's task did by
-- reading the helper its own release created (decisions § 2465). The release
-- applies migrations, then deploys the functions, then runs the sync.
--
-- Bump the returned number in a new migration with the next matcher version.
--
-- Locks (docs/backend/migration_locks.md): one new function, no table.

create function private.segment_matcher_version()
  returns integer
  language sql
  immutable
  set search_path = ''
as $$ select 4 $$;

revoke execute on function private.segment_matcher_version() from public, anon, authenticated;

comment on function private.segment_matcher_version() is
  'The GLOBAL_SEGMENT_MATCHER_VERSION the deployed segment-match function carries; read by the release ops task '
  'that re-matches efforts after a matcher change (decisions § 2583).';

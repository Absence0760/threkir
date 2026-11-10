-- jobs_dedupe_segment_match (decisions § 2392), moved out of
-- 20271117002392 so it is built alone.
--
-- One QUEUED per-run job at a time, not one queued-or-running: a track
-- rewritten while its job runs must still get a job of its own, or the
-- dedupe would swallow the enqueue and leave the efforts describing the old
-- bytes. Two jobs for one run can then overlap; record_segment_match refuses
-- the one whose bytes are no longer stored, and the write is idempotent.
--
-- Locks: the build reads the jobs heap once under SHARE, so enqueues wait for
-- that read and the worker's claims (reads) do not. In 20271117002392 it ran
-- under the jobs_kind_chk swap's ACCESS EXCLUSIVE, which stopped reads too.
-- Its predicate matches no existing row. IF NOT EXISTS keeps it a no-op on a
-- database that built it from the earlier form of 20271117002392.

create unique index if not exists jobs_dedupe_segment_match
  on jobs (kind, ((payload->>'run_id')::uuid))
  where kind = 'segment_match' and status = 'queued' and payload ? 'run_id';

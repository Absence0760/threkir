-- The two segment_match enqueue triggers (decisions § 2392), moved out of
-- 20271117002392 so that no transaction holds jobs and runs together. Their
-- functions are defined there.
--
-- Locks: DROP TRIGGER takes ACCESS EXCLUSIVE on its table, and CREATE TRIGGER
-- SHARE ROW EXCLUSIVE, each held to this file's commit, which follows at once:
-- nothing here scans. storage.objects is owned by supabase_storage_admin;
-- CREATE TRIGGER needs only the TRIGGER privilege, which postgres holds on it
-- (the precedent is runs_track_object_rewritten, 20270719000020). Both are
-- drop-then-create, so a database that ran the earlier form of
-- 20271117002392 ends in the same state.

drop trigger if exists runs_enqueue_segment_match on public.runs;
create trigger runs_enqueue_segment_match
  after insert or update of track_url on public.runs
  for each row execute function public.runs_enqueue_segment_match();

drop trigger if exists runs_track_object_enqueue_segment_match on storage.objects;
create trigger runs_track_object_enqueue_segment_match
  after insert or update on storage.objects
  for each row
  when (new.bucket_id = 'runs')
  execute function public.runs_track_object_enqueue_segment_match();

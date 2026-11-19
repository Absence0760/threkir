-- Re-match every run near an open catalogue segment with the matcher this
-- release deploys (matcher version 4: a course is timed by its drawn start
-- and finish boxes, with GPS slack at either end of the recording and a
-- longer gap across the finish; issue #1446, decisions § 2589). The web
-- fallback already re-matches a run its owner opens (its metadata stamp is
-- behind); this reaches the runs nobody opens, the way version 3's task did
-- (20271219001313_rematch_segments_matcher_v3, decisions § 2465).
--
-- It must run after the segment-match function carrying version 4 is live.
-- It reads private.segment_matcher_version(), which migration
-- 20280102001446 creates, so on any database that migration has not reached
-- (a sync dispatched before that release) the task fails, rolls back and
-- stays pending; the release that applies the migration deploys the functions
-- before its sync runs this.
--
-- A closed course is skipped: it takes no new effort. A backfill already
-- queued for a segment is returned rather than queued twice.
with queued as (
  select public.enqueue_segment_backfill(gs.id) as job_id
    from public.global_segments gs
   where gs.is_active
     and not private.global_segment_course_closed(gs.id)
     and private.segment_matcher_version() >= 4
)
select private.set_ops_task_result(jsonb_build_object(
  'segments', (select count(*) from queued),
  'matcher_version', private.segment_matcher_version()
));

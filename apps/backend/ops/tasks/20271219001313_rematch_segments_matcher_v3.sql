-- Re-match every run near an open catalogue segment with the matcher this
-- release deploys (matcher version 3: every complete lap of a loop timed, the
-- fastest counting; issue #1313, decisions § 2465). The web fallback already
-- re-matches a run its owner opens (its metadata stamp is behind); this
-- reaches the runs nobody opens. It also stands in for the one-off
-- `enqueue_segment_backfill` over every active segment that § 2403 left as an
-- operator step.
--
-- It must run after the segment-match function carrying version 3 is live.
-- It calls private.global_segment_course_closed, which migration
-- 20271219001313 creates, so on any database that migration has not reached
-- (a sync dispatched before that release) the task fails, rolls back and
-- stays pending; the release that applies the migration deploys the functions
-- before its sync runs this.
--
-- A closed course is skipped: it takes no new effort. A backfill already
-- queued for a segment (the park sync's, for a redrawn course) is returned
-- rather than queued twice.
with queued as (
  select public.enqueue_segment_backfill(gs.id) as job_id
    from public.global_segments gs
   where gs.is_active
     and not private.global_segment_course_closed(gs.id)
)
select private.set_ops_task_result(jsonb_build_object('segments', (select count(*) from queued)));

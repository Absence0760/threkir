-- A watch run is recomputed automatically only when its stored track is
-- complete.
--
-- Since spec v1.4 the Wear OS and watchOS recorders feed their distance
-- estimator every fix stated up to 50 m but stored on the track only the
-- fixes within their 30 m track gate. The `distance_recompute` replay then
-- saw each stretch under tree canopy as a gap and credited only its chord,
-- where the wrist had credited it from Doppler: the bench (reference.py +
-- bench.py, canopy half of every 180 s) read the recompute 3.7-4.5% below the
-- watch's own figure. Recorders now store every fix the estimator took,
-- flagging the ones past the track gate `offTrack: true`, and stamp
-- `metadata.track_complete = true` on such a run (docs/features/gps_distance.md
-- § Waypoint fields). The replay reads every fix; the line, route match,
-- elevation, privacy clip and road matcher skip the flagged ones.
--
-- This replaces the trigger function from 20270828000001 so it queues a watch
-- run only when `track_complete` is the JSON boolean true, the same reading
-- the worker's `metaIsTrue` gives it (a string "true" is not). A watch build
-- from before track_complete keeps its wrist figure; Recalculate distance
-- still offers a run its track can reproduce. Everything else is the
-- 20270828000001 body unchanged, written out whole (bare-body rule,
-- apps/backend/CLAUDE.md).
--
-- Locks (docs/backend/migration_locks.md): CREATE OR REPLACE FUNCTION takes no
-- table lock and keeps the trigger bound to it, so the trigger is not
-- recreated. No column, constraint, scan, rewrite or backfill, so no type
-- regeneration.

create or replace function public.runs_enqueue_watch_distance_recompute()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_meta jsonb := coalesce(new.metadata, '{}'::jsonb);
begin
  if new.source is distinct from 'watch'
     or new.track_url is null or new.track_url = '' then
    return null;
  end if;

  if tg_op = 'UPDATE' and new.track_url is not distinct from old.track_url then
    return null;
  end if;

  if not (v_meta ? 'distance_estimator')
     or v_meta -> 'track_complete' is distinct from 'true'::jsonb
     or v_meta ? 'distance_recomputed_at'
     or v_meta -> 'in_progress' = 'true'::jsonb
     or v_meta -> 'manual_entry' = 'true'::jsonb
     or v_meta -> 'indoor' = 'true'::jsonb
     or v_meta -> 'indoor_estimated' = 'true'::jsonb
     or coalesce(v_meta ->> 'distance_source', '') <> '' then
    return null;
  end if;

  begin
    insert into jobs (kind, payload, scheduled_at)
    values (
      'distance_recompute',
      jsonb_build_object('run_id', new.id, 'user_id', new.user_id),
      job_scheduled_at_for_user(new.user_id)
    )
    on conflict do nothing;
  exception when others then
    raise warning 'runs_enqueue_watch_distance_recompute: run % not queued: % (%)',
      new.id, sqlerrm, sqlstate;
  end;

  return null;
end;
$$;

revoke execute on function public.runs_enqueue_watch_distance_recompute() from public, anon, authenticated;

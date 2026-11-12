-- A Wear OS or watchOS run gets the server's smoother automatically.
--
-- The phone saves the spec-v1.3 smoother's figure at stop(); the watches
-- keep their forward filter (the smoother needs the whole run in memory) and
-- the phone's ingest takes their `distance_m` as sent. The `distance_recompute`
-- job (20270719000001) already replays a stored track through the smoother,
-- and a watch track holds every fix the wrist's filter took, with Doppler, so
-- it keeps the smoothed pass. Until now only the owner could ask for it
-- (`request_distance_recompute`). This trigger queues it when a watch run's
-- track lands (issue #1172, decisions § 1991).
--
-- Which runs: `source = 'watch'` with a track, stamped
-- `metadata.distance_estimator` by the recorder (Wear OS and watchOS stamp
-- every run they record), and not yet recomputed. The custom watch also
-- syncs as `source = 'watch'` but stamps no estimator: its flash track is a
-- decimated breadcrumb, which a replay would under-read, so it is left to
-- its own figure. The worker's skips (in progress, manual, indoor, a
-- non-GPS distance_source) are repeated here so no job is queued only to be
-- skipped; the worker still re-checks every one.
--
-- When: AFTER INSERT, or AFTER UPDATE OF track_url when the value actually
-- changed — a watch row can land before its track (the track is uploaded and
-- then named on the row), and `UPDATE OF track_url` fires on any write that
-- names the column, changed or not. A second enqueue for the same run is a
-- no-op while one is queued or running (jobs_dedupe_distance_recompute), and
-- a recomputed run carries distance_recomputed_at, so a later write never
-- queues it again. No backfill: existing runs stay as their owner left them,
-- as 20270719000001 decided for every recompute (a changed distance moves
-- PRs, goals and leaderboards); Recalculate distance still offers them.
--
-- The enqueue sits in its own exception block, so a failure is logged and
-- never fails the run's write (the run is L1, the recompute auxiliary).
--
-- Locks (docs/backend/migration_locks.md): CREATE TRIGGER takes SHARE ROW
-- EXCLUSIVE on runs — catalogue-only, O(1), blocking concurrent writes for
-- the instant of the change. CREATE OR REPLACE FUNCTION takes none. No
-- column, constraint, scan, rewrite or backfill, so no type regeneration.

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

drop trigger if exists runs_enqueue_watch_distance_recompute on public.runs;
create trigger runs_enqueue_watch_distance_recompute
  after insert or update of track_url on public.runs
  for each row
  when (new.source = 'watch')
  execute function public.runs_enqueue_watch_distance_recompute();

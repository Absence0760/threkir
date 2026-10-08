-- runs_keep_distance_recompute (20270719000003) also carries forward
-- metadata.distance_map_matched_m, the road-matched length the job_worker's
-- map_match step writes beside distance_m.
--
-- The trigger carried forward only its own recompute keys, so a stale client
-- copy dropped the road distance on its next edit or sync, and so did every
-- client that never had it. No client writes the key: the road matcher owns
-- it and writes it asynchronously after the run is saved, so a bag a
-- signed-in client sends without it is, by construction, one loaded before
-- the matcher ran. Two rules, the second the existing one widened:
--
--   1. A write under a user JWT (auth.uid() set) that omits a key the stored
--      row has keeps it, unless the write also replaces track_url — a new
--      track is matched again, and its road distance is not the old one's.
--      The worker writes as the service role with no user, so it can still
--      clear the key when a run stops qualifying.
--   2. A stale copy of a recomputed run (stored row has distance_recomputed_at,
--      incoming bag does not) carries the key with the recompute's keys,
--      whoever wrote it.
--
-- Locks: CREATE OR REPLACE FUNCTION is a catalogue-only change; the trigger
-- itself is unchanged. No scan, no rewrite, no backfill.

create or replace function public.runs_keep_distance_recompute()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_recorded numeric;
  v_old jsonb := coalesce(old.metadata, '{}'::jsonb);
begin
  if v_old ? 'distance_map_matched_m'
     and not (coalesce(new.metadata, '{}'::jsonb) ? 'distance_map_matched_m')
     and auth.uid() is not null
     and new.track_url is not distinct from old.track_url then
    new.metadata := coalesce(new.metadata, '{}'::jsonb)
      || jsonb_build_object('distance_map_matched_m', v_old -> 'distance_map_matched_m');
  end if;

  if not (v_old ? 'distance_recomputed_at')
     or coalesce(new.metadata, '{}'::jsonb) ? 'distance_recomputed_at' then
    return new;
  end if;

  new.metadata := coalesce(new.metadata, '{}'::jsonb) || jsonb_strip_nulls(jsonb_build_object(
    'distance_recomputed_at', v_old -> 'distance_recomputed_at',
    'distance_recorded_m', v_old -> 'distance_recorded_m',
    'distance_estimator', v_old -> 'distance_estimator',
    'distance_map_matched_m', v_old -> 'distance_map_matched_m'
  ));

  new.fastest_5k_s := old.fastest_5k_s;
  new.fastest_10k_s := old.fastest_10k_s;
  new.fastest_half_marathon_s := old.fastest_half_marathon_s;
  new.fastest_marathon_s := old.fastest_marathon_s;

  if jsonb_typeof(v_old -> 'distance_recorded_m') = 'number' then
    v_recorded := (v_old ->> 'distance_recorded_m')::numeric;
    if new.distance_m is distinct from old.distance_m
       and abs(new.distance_m - v_recorded) < 0.5 then
      new.distance_m := old.distance_m;
    end if;
  end if;

  return new;
end;
$$;

revoke execute on function public.runs_keep_distance_recompute() from public, anon, authenticated;

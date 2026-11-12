-- runs_keep_distance_recompute (20270719000003, widened by 20270719000004
-- and 20270719000006) also carries forward metadata.smoothed_sidecar_sha256.
--
-- The job_worker records the hash of the track a smoothed-position sidecar
-- was built for (`{user_id}/{run_id}.smoothed.json.gz`) in this key while the
-- sidecar is stored, and every reader fetches the sidecar only when the key
-- names the track bytes it holds (docs/features/gps_distance.md § Waypoint
-- fields). Two writers set it, as distance_map_matched_m has: the
-- distance_recompute job, in the same conditional PATCH as
-- distance_recomputed_at, and the map_match job for a watch run, through its
-- own track_url + metadata CAS. So it takes both of that key's carries: a
-- signed-in write that omits it keeps the stored value unless the same write
-- replaces track_url, and a stale copy of a recomputed run gets it back with
-- the recompute's keys. The worker, writing as the service role with
-- distance_recomputed_at in the bag, can still remove it (a forward-pass
-- recompute does). A carried hash that no longer matches a re-uploaded track
-- is harmless: readers compare it with the bytes they hold.
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
  v_key text;
begin
  foreach v_key in array array['distance_map_matched_m', 'smoothed_sidecar_sha256'] loop
    if v_old ? v_key
       and not (coalesce(new.metadata, '{}'::jsonb) ? v_key)
       and auth.uid() is not null
       and new.track_url is not distinct from old.track_url then
      new.metadata := coalesce(new.metadata, '{}'::jsonb)
        || jsonb_build_object(v_key, v_old -> v_key);
    end if;
  end loop;

  if not (v_old ? 'distance_recomputed_at')
     or coalesce(new.metadata, '{}'::jsonb) ? 'distance_recomputed_at' then
    return new;
  end if;

  new.metadata := coalesce(new.metadata, '{}'::jsonb) || jsonb_strip_nulls(jsonb_build_object(
    'distance_recomputed_at', v_old -> 'distance_recomputed_at',
    'distance_recorded_m', v_old -> 'distance_recorded_m',
    'distance_estimator', v_old -> 'distance_estimator',
    'distance_estimator_pass', v_old -> 'distance_estimator_pass',
    'distance_map_matched_m', v_old -> 'distance_map_matched_m',
    'smoothed_sidecar_sha256', v_old -> 'smoothed_sidecar_sha256'
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

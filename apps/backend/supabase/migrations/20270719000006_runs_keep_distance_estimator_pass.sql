-- runs_keep_distance_recompute (20270719000003, widened by 20270719000004)
-- also carries forward metadata.distance_estimator_pass.
--
-- The distance_recompute job now records which of the smoother's passes it
-- kept beside distance_estimator: "smoothed", or "forward" for a track with
-- no Doppler speed that is not a road run (docs/features/gps_distance.md
-- § Server recompute). It is one of the recompute's own keys, written in the
-- same conditional PATCH as distance_recomputed_at, so a stale client copy
-- that drops distance_recomputed_at drops it too and must get it back with
-- the others. jsonb_strip_nulls keeps a run recomputed before this key
-- existed from gaining a null.
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
    'distance_estimator_pass', v_old -> 'distance_estimator_pass',
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

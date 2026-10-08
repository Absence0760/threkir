-- A client holding a copy of a run from before its distance was recomputed
-- (20270716000001) cannot write the inflated figure back.
--
-- The mobile run-detail edit (ApiClient.updateRunFields) and the web saveEdit
-- PATCH distance_m and the WHOLE metadata bag from whatever the screen loaded,
-- and the batch sync upserts the local row, fastest_* columns included. The
-- recompute lands asynchronously, so the copy on screen when the owner taps
-- Recalculate is, by construction, the pre-recompute one: an edit made before
-- the next refresh would put the hop-summed distance back and drop the
-- recompute's metadata keys, which also re-offers the action.
--
-- A stale write is recognisable without any client cooperation: the stored
-- row carries metadata.distance_recomputed_at and the incoming bag does not,
-- because no client that loaded the row after the recompute could have lost
-- the key. For such a write the recompute's keys are carried forward, the
-- fastest_* columns keep their recomputed values, and distance_m keeps the
-- recomputed value when the incoming figure is the original recorded one
-- (metadata.distance_recorded_m, within half a metre). A distance the owner
-- deliberately typed is a different figure and is kept.
--
-- BEFORE UPDATE, so the AFTER triggers (personal records, achievements) see
-- the corrected row. The recompute job's own write carries the key and never
-- matches.
--
-- Locks: CREATE TRIGGER on runs takes SHARE ROW EXCLUSIVE for a
-- catalogue-only change; no scan, no rewrite, no backfill.

create or replace function public.runs_keep_distance_recompute()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_recorded numeric;
begin
  if not (coalesce(old.metadata, '{}'::jsonb) ? 'distance_recomputed_at')
     or coalesce(new.metadata, '{}'::jsonb) ? 'distance_recomputed_at' then
    return new;
  end if;

  new.metadata := coalesce(new.metadata, '{}'::jsonb) || jsonb_strip_nulls(jsonb_build_object(
    'distance_recomputed_at', old.metadata -> 'distance_recomputed_at',
    'distance_recorded_m', old.metadata -> 'distance_recorded_m',
    'distance_estimator', old.metadata -> 'distance_estimator'
  ));

  new.fastest_5k_s := old.fastest_5k_s;
  new.fastest_10k_s := old.fastest_10k_s;
  new.fastest_half_marathon_s := old.fastest_half_marathon_s;
  new.fastest_marathon_s := old.fastest_marathon_s;

  if jsonb_typeof(old.metadata -> 'distance_recorded_m') = 'number' then
    v_recorded := (old.metadata ->> 'distance_recorded_m')::numeric;
    if new.distance_m is distinct from old.distance_m
       and abs(new.distance_m - v_recorded) < 0.5 then
      new.distance_m := old.distance_m;
    end if;
  end if;

  return new;
end;
$$;

revoke execute on function public.runs_keep_distance_recompute() from public, anon, authenticated;

create trigger runs_keep_distance_recompute
  before update on public.runs
  for each row execute function public.runs_keep_distance_recompute();

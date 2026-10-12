-- clip_track_for_user: a fix with no usable position no longer ends the
-- privacy-zone trim.
--
-- The leading and trailing walks stopped at the first fix NOT in a zone, and
-- a fix with no position at all (lat / lng missing, null, or not JSON
-- numbers, and no usable smoothed pair either) tested "not in a zone":
-- `privacy_in_any_zone(null, null, …)` compares a null distance and returns
-- false. One such fix at the head of a track — a recorder's placeholder
-- before the first GPS lock, a corrupted element — ended the walk there, and
-- every real fix behind it inside the zone was served to non-owners. That is
-- the home location decisions §33 exists to withhold.
--
-- Fix: a fix is placed when its raw pair or its smoothed pair is two JSON
-- numbers, the same usable-pair test every reader applies (web
-- `track_line.ts`, Dart `Waypoint`). An unplaced fix draws nothing, so the
-- walks drop it and keep going; only a placed fix outside every zone, in
-- both of its positions, ends a walk. Both clients' `clipPointsToZones`
-- apply the same rule. The in-zone test is a CASE so a non-numeric `lat`
-- is never cast (a cast of a string like "abc" used to raise and 500 the
-- clip). Interior fixes, the no-zones path, the 50k downsample and the
-- output shape are unchanged. `create or replace` takes no table lock
-- (docs/backend/migration_locks.md) and keeps the ACL; the grants are
-- restated below so the text states the state it leaves.

create or replace function clip_track_for_user(target_user_id uuid, points jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  zones jsonb;
  working jsonb;
  arr_len int;
  start_idx int;
  end_idx int;
  pt jsonb;
  hidden boolean;
begin
  if points is null or jsonb_typeof(points) <> 'array' then
    return '[]'::jsonb;
  end if;

  arr_len := jsonb_array_length(points);
  if arr_len = 0 then return '[]'::jsonb; end if;

  if arr_len > 50000 then
    working := _privacy_downsample(points, 50000);
    arr_len := jsonb_array_length(working);
  else
    working := points;
  end if;

  select prefs->'privacy_zones' into zones
    from user_settings where user_id = target_user_id;

  if zones is null or jsonb_typeof(zones) <> 'array' or jsonb_array_length(zones) = 0 then
    return working;
  end if;

  start_idx := 0;
  while start_idx < arr_len loop
    pt := working -> start_idx;
    -- Dropped when unplaced, or when its raw or smoothed position is in a zone.
    hidden := case
      when jsonb_typeof(pt) is distinct from 'object' then true
      when jsonb_typeof(pt->'smoothedLat') = 'number'
           and jsonb_typeof(pt->'smoothedLng') = 'number'
           and privacy_in_any_zone(
             (pt->>'smoothedLat')::float, (pt->>'smoothedLng')::float, zones)
        then true
      when jsonb_typeof(pt->'lat') = 'number' and jsonb_typeof(pt->'lng') = 'number'
        then privacy_in_any_zone((pt->>'lat')::float, (pt->>'lng')::float, zones)
      when jsonb_typeof(pt->'smoothedLat') = 'number'
           and jsonb_typeof(pt->'smoothedLng') = 'number'
        then false
      else true
    end;
    exit when not hidden;
    start_idx := start_idx + 1;
  end loop;

  if start_idx >= arr_len then return '[]'::jsonb; end if;

  end_idx := arr_len - 1;
  while end_idx > start_idx loop
    pt := working -> end_idx;
    hidden := case
      when jsonb_typeof(pt) is distinct from 'object' then true
      when jsonb_typeof(pt->'smoothedLat') = 'number'
           and jsonb_typeof(pt->'smoothedLng') = 'number'
           and privacy_in_any_zone(
             (pt->>'smoothedLat')::float, (pt->>'smoothedLng')::float, zones)
        then true
      when jsonb_typeof(pt->'lat') = 'number' and jsonb_typeof(pt->'lng') = 'number'
        then privacy_in_any_zone((pt->>'lat')::float, (pt->>'lng')::float, zones)
      when jsonb_typeof(pt->'smoothedLat') = 'number'
           and jsonb_typeof(pt->'smoothedLng') = 'number'
        then false
      else true
    end;
    exit when not hidden;
    end_idx := end_idx - 1;
  end loop;

  return (
    select coalesce(jsonb_agg(working -> idx order by idx), '[]'::jsonb)
    from generate_series(start_idx, end_idx) as g(idx)
  );
end;
$$;

revoke execute on function clip_track_for_user(uuid, jsonb) from public, anon, authenticated;
grant execute on function clip_track_for_user(uuid, jsonb) to service_role;

-- clip_track_for_user: withhold each point's credited distance (`distM`)
-- from the non-owner output.
--
-- Since spec v1.4 every recorded waypoint carries `distM`, the run's distance
-- credited up to and including that fix (docs/features/gps_distance.md
-- § Waypoint fields, decisions § 1997). The clip trimmed the leading and
-- trailing in-zone fixes but served every surviving point whole, so the first
-- visible point's `distM` stated exactly how far the runner went inside the
-- start zone, and `distance_m` minus the last visible `distM` stated the same
-- for the end zone. With the zone exit already on the map, that distance and
-- the polyline's bearing narrow the home location decisions § 33 withholds.
--
-- Fix: every point this function returns has `distM` removed, on every path,
-- including the no-zones path, so the key's presence never signals whether a
-- zone exists. Every caller of this function serves a non-owner (the
-- clip-public-track Edge Function after its owner return, clip_route_for_viewer
-- after its owner return, the public route geometry, the event course
-- endpoints), so the owner's raw `distM` is untouched: the owner reads the
-- track straight from Storage. No non-owner surface reads `distM`; splits and
-- moving time are computed on owner surfaces only, and `trackCumulativeMetres`
-- falls back to the line's hop-sum when the key is absent, which starts at 0
-- on the first served point. Dropping is chosen over rebasing because a
-- rebased figure still carries the credit of any stretch a future interior
-- clip removed, and nothing a viewer sees needs it.
--
-- Non-object elements pass through unchanged, as before. The in-zone walks,
-- the 50k downsample and the grants are unchanged. `create or replace` takes
-- no table lock (docs/backend/migration_locks.md) and keeps the ACL; the
-- grants are restated below so the text states the state it leaves.

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

  start_idx := 0;
  end_idx := arr_len - 1;

  if zones is not null and jsonb_typeof(zones) = 'array' and jsonb_array_length(zones) > 0 then
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
  end if;

  return (
    select coalesce(
      jsonb_agg(
        case when jsonb_typeof(working -> idx) = 'object'
          then (working -> idx) - 'distM'
          else working -> idx
        end
        order by idx),
      '[]'::jsonb)
    from generate_series(start_idx, end_idx) as g(idx)
  );
end;
$$;

revoke execute on function clip_track_for_user(uuid, jsonb) from public, anon, authenticated;
grant execute on function clip_track_for_user(uuid, jsonb) to service_role;

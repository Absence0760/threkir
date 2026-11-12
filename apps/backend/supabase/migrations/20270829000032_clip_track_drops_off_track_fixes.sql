-- clip_track_for_user: serve a non-owner no off-track fix.
--
-- Since spec v1.4 a recorder stores every fix its distance estimator took and
-- flags the ones that failed its track gate `offTrack: true` (a 30-50 m canopy
-- fix on a watch), so the server's distance replay sees them
-- (docs/features/gps_distance.md § Waypoint fields). They are distance input,
-- not line: no surface draws them. The clip walked leading and trailing fixes
-- and stopped at the first one outside every zone, so an off-track fix sitting
-- just outside a zone could have ended the walk and left in-zone on-track
-- fixes after it on the served line, and any off-track fix would have reached
-- a viewer.
--
-- Fix: drop every element that is an object carrying `offTrack: true` before
-- anything else, then clip what is left exactly as before. An off-track fix
-- inside a zone is therefore never served, nor one outside it, and the walk
-- decides on the fixes a viewer is shown. `offTrack: false` and an absent key
-- are on-track (every track recorded before the flag). Non-object elements
-- still pass through unchanged. The 50k downsample now counts the served
-- fixes. `distM` is still removed from every returned point (20270829000021);
-- the rest of that body is unchanged, written out whole (bare-body rule,
-- apps/backend/CLAUDE.md). `create or replace` takes no table lock
-- (docs/backend/migration_locks.md) and keeps the ACL; the grants are restated
-- so the text states the state it leaves. Privacy-boundary change: CISO /
-- Security Analyst sign-off before deploy.

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

  select coalesce(jsonb_agg(e order by i), '[]'::jsonb)
    into working
    from jsonb_array_elements(points) with ordinality as a(e, i)
   where e -> 'offTrack' is distinct from 'true'::jsonb;

  arr_len := jsonb_array_length(working);
  if arr_len = 0 then return '[]'::jsonb; end if;

  if arr_len > 50000 then
    working := _privacy_downsample(working, 50000);
    arr_len := jsonb_array_length(working);
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

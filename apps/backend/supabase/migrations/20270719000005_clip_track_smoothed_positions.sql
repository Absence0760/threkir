-- clip_track_for_user: a fix is in a privacy zone when its smoothed position
-- is, not only its raw one.
--
-- Since GPS distance spec v1.2 a stored track waypoint may carry
-- `smoothedLat` / `smoothedLng` beside the raw `lat` / `lng`: the RTS
-- smoother's position for that fix (docs/features/gps_distance.md). Every
-- reader that draws the run line prefers that pair when both halves are
-- present (web `lib/runs/track_line.ts`, Dart `Waypoint.lineLat`), and this
-- function returns surviving points whole, so the pair reaches a non-owner
-- through the clip-public-track Edge Function. It decided in-zone on the raw
-- position alone. The smoother pulls a fix toward its neighbours, so a fix
-- just outside the zone edge can carry a smoothed position just inside it —
-- the first and last vertices a non-owner's map drew could sit inside the
-- zone, which is the coordinate decisions §33 exists to withhold.
--
-- Fix: the leading and trailing walks treat a fix as in-zone when EITHER its
-- raw position or its smoothed position (both halves JSON numbers, the same
-- "usable pair" test the readers apply) is inside any zone. Such a fix is
-- dropped exactly as a raw in-zone fix always was, so the first and last
-- surviving points are outside every zone in both positions. Interior points
-- are untouched, as before: the clipper deliberately keeps a mid-run pass
-- through a zone (a loop that returns home), raw and smoothed alike, so a
-- smoothed interior point inside a zone discloses nothing its raw neighbours
-- do not. A half pair, or a non-numeric one, is ignored here as every reader
-- ignores it, and the raw position decides.
--
-- The no-zones path, the 50k downsample and the output shape are unchanged.
-- `create or replace` takes no table lock (docs/backend/migration_locks.md),
-- and keeps the function's ACL; the grants are restated below anyway so the
-- migration text states the state it leaves: service_role only, as
-- 20270521_001 left it (the function is a one-bit zone oracle to anyone who
-- can call it).

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
    exit when not (
      privacy_in_any_zone((pt->>'lat')::float, (pt->>'lng')::float, zones)
      or (
        jsonb_typeof(pt->'smoothedLat') = 'number'
        and jsonb_typeof(pt->'smoothedLng') = 'number'
        and privacy_in_any_zone(
          (pt->>'smoothedLat')::float, (pt->>'smoothedLng')::float, zones)
      )
    );
    start_idx := start_idx + 1;
  end loop;

  if start_idx >= arr_len then return '[]'::jsonb; end if;

  end_idx := arr_len - 1;
  while end_idx > start_idx loop
    pt := working -> end_idx;
    exit when not (
      privacy_in_any_zone((pt->>'lat')::float, (pt->>'lng')::float, zones)
      or (
        jsonb_typeof(pt->'smoothedLat') = 'number'
        and jsonb_typeof(pt->'smoothedLng') = 'number'
        and privacy_in_any_zone(
          (pt->>'smoothedLat')::float, (pt->>'smoothedLng')::float, zones)
      )
    );
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

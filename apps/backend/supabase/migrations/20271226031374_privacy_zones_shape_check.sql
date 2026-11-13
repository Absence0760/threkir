-- A stored privacy-zone list must be a list of points (issue #1374 round 4,
-- L1 of the legal pre-review).
--
-- 20271226001374 made `privacy_in_any_zone` answer "not in a zone" for a
-- `privacy_zones` value that is not an array, where it used to raise. Most
-- readers already treated that value as "no zones" before calling it
-- (clip_track_for_user, the live and race ping triggers, route start points,
-- strip_stored_in_zone_points), but three did not: route_markers_for_viewer,
-- the route-conditions reads and heatmap_points_in_bbox. For those the
-- failure moved from an error to showing the point.
--
-- Nothing a client sends has that shape (web and both apps write an array of
-- {lat, lng, radius_m}), so the fix is to refuse it on the way in rather than
-- to guard each reader: a new or changed `privacy_zones` must be null or an
-- array whose every element is an object with numeric `lat` and `lng`, and a
-- numeric `radius_m` when it has one. Rows already stored are not touched;
-- the trigger checks only a write that changes the key.

set search_path = public;

create or replace function private.check_privacy_zones_shape()
returns trigger
language plpgsql
set search_path = public, pg_catalog
as $$
declare
  v_zones jsonb := new.prefs -> 'privacy_zones';
begin
  if tg_op = 'UPDATE' and v_zones is not distinct from (old.prefs -> 'privacy_zones') then
    return new;
  end if;
  if v_zones is null or v_zones = 'null'::jsonb then
    return new;
  end if;
  if jsonb_typeof(v_zones) <> 'array' or exists (
    select 1
      from jsonb_array_elements(v_zones) as z(v)
     where jsonb_typeof(z.v) <> 'object'
        or jsonb_typeof(z.v -> 'lat') is distinct from 'number'
        or jsonb_typeof(z.v -> 'lng') is distinct from 'number'
        or (z.v ? 'radius_m' and jsonb_typeof(z.v -> 'radius_m') <> 'number')
  ) then
    raise exception using
      errcode = 'invalid_parameter_value',
      message = 'user_settings.prefs.privacy_zones must be an array of {lat, lng, radius_m} with numeric values';
  end if;
  return new;
end;
$$;

revoke execute on function private.check_privacy_zones_shape() from public, anon, authenticated;

create trigger user_settings_check_privacy_zones_shape
  before insert or update of prefs on user_settings
  for each row execute function private.check_privacy_zones_shape();

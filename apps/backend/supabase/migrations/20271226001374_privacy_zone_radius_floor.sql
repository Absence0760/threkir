-- Privacy zones cover at least 100 m (issue #1374 round 3).
--
-- Web created zones of 100-1000 m and the phone 50-500 m. Both now offer
-- 100-1000 m, the more private floor. A zone the phone saved under 100 m must
-- not keep covering less than a new one can, and must never shrink, so:
--
-- 1. `privacy_in_any_zone` reads every zone's radius as at least 100 m. Every
--    server-side zone test goes through it (clip_track_for_user, the live and
--    race ping triggers, route start point / geom, route markers and
--    conditions, heatmap points, event course endpoints), so the floor holds
--    for a row a stale client writes back later, too. The phone, web and the
--    live hub apply the same floor (`effectiveZoneRadius` / `EffectiveRadiusM`).
--
-- 2. Stored zones under 100 m are rewritten to 100 m. The change to
--    `prefs.privacy_zones` fires the existing recompute triggers
--    (`user_settings_privacy_zones_trigger`,
--    `user_settings_refresh_event_course_endpoints_upd`), so a route start
--    point or course endpoint computed against the old, smaller radius is
--    recomputed against the floor. Only rows holding such a zone are touched.

set search_path = public, extensions;

create or replace function privacy_in_any_zone(lat float, lng float, zones_json jsonb)
returns boolean
language plpgsql
immutable
parallel safe
set search_path = public, extensions
as $$
declare
  zone jsonb;
begin
  if zones_json is null or jsonb_typeof(zones_json) <> 'array'
     or jsonb_array_length(zones_json) = 0 then
    return false;
  end if;
  for zone in select * from jsonb_array_elements(zones_json) loop
    if privacy_distance_m(
      lat, lng,
      (zone->>'lat')::float,
      (zone->>'lng')::float
    ) <= greatest(coalesce((zone->>'radius_m')::float, 100), 100) then
      return true;
    end if;
  end loop;
  return false;
end;
$$;

revoke execute on function privacy_in_any_zone(float, float, jsonb) from public, anon, authenticated;

update user_settings
set prefs = jsonb_set(
  prefs,
  '{privacy_zones}',
  (
    select jsonb_agg(
      case
        when jsonb_typeof(z) = 'object'
             and jsonb_typeof(z->'radius_m') = 'number'
             and (z->>'radius_m')::float < 100
          then jsonb_set(z, '{radius_m}', '100'::jsonb)
        else z
      end
      order by ord
    )
    from jsonb_array_elements(prefs->'privacy_zones') with ordinality as e(z, ord)
  )
)
where jsonb_typeof(prefs->'privacy_zones') = 'array'
  and exists (
    select 1
    from jsonb_array_elements(prefs->'privacy_zones') as e(z)
    where jsonb_typeof(z) = 'object'
      and jsonb_typeof(z->'radius_m') = 'number'
      and (z->>'radius_m')::float < 100
  );

-- Apply every runner's current privacy zones, with the 100 m floor of
-- 20271226001374, to the points stored before it (issue #1374 round 4).
-- The function and its triggers are in 20271226021374; this file only calls
-- it, so the user_settings trigger DDL there is not held for the duration.
--
-- Locks (docs/backend/migration_locks.md): row locks on the in-zone precise
-- pings it deletes (live_run_pings and race_pings keep 48 hours, longer for an
-- open self-timed window) and on the frozen course copies of the zone owners'
-- routes. It reads pings through their user_id indexes, one runner at a time,
-- and only for runners who have a zone.

set search_path = public, extensions;

select private.strip_stored_in_zone_points(s.user_id)
  from user_settings s
 where jsonb_typeof(s.prefs -> 'privacy_zones') = 'array'
   and jsonb_array_length(s.prefs -> 'privacy_zones') > 0;

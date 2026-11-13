-- A privacy-zone change reaches the stored points as well as the computed
-- ones (issue #1374 round 4, L2 of the legal pre-review).
--
-- 20271226001374 raised every stored zone under 100 m to 100 m, and its
-- change to `prefs.privacy_zones` fired the two recompute triggers that
-- already existed: route start points and public geometry, and event course
-- endpoints with their derived gates. Every reader that clips at read time
-- (clip_track_for_user, heatmap points, route markers and conditions) picks
-- the floor up by itself. Three stored copies did not:
--
--   * `live_run_pings` and `race_pings`. Their BEFORE-INSERT triggers drop a
--     ping inside a zone (or keep one coarse last-seen point), but that runs
--     once, against the zones of the moment. A ping stored before a zone was
--     added or widened kept its exact position. Pings live 48 hours, longer
--     for a self-timed race window.
--   * `race_session_courses`, the copy of each course frozen when a race is
--     armed. It copies the endpoints and derived gates of `event_courses`, so
--     a point that was outside a zone at freeze time stayed in the copy after
--     the live row lost it.
--
-- `private.strip_stored_in_zone_points` applies a runner's current zones to
-- all three, and new triggers run it on every change to their zones:
--
--   * a precise ping inside a zone is deleted, as the insert trigger would
--     have dropped it. Coarse last-seen points are kept: they already carry
--     no more than a ~1 km cell.
--   * the copy of a race that has not started (armed, and before a scheduled
--     start or a self-timed window opens) is frozen again from `event_courses`, which the
--     existing trigger has already recomputed (this trigger's name sorts after
--     `user_settings_refresh_event_course_endpoints_*`, and same-event
--     triggers fire in name order).
--   * a started or finished race's copy is the record its results were timed
--     against, so it is not refrozen. Only its derived points that now fall
--     inside a zone are cleared: the start gate, the finish gate (with the lap
--     count and self-cross flag read from it) and the finish point. A gate the
--     organiser placed is theirs and stays.
--
-- 20271226021375 runs the function once for every runner with zones, which
-- applies the 100 m floor to what was stored before it.

set search_path = public, extensions;

create or replace function private.strip_stored_in_zone_points(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_zones jsonb;
  v_session record;
begin
  select s.prefs -> 'privacy_zones' into v_zones
    from user_settings s
   where s.user_id = p_user_id;
  if v_zones is null or jsonb_typeof(v_zones) <> 'array'
     or jsonb_array_length(v_zones) = 0 then
    return;
  end if;

  delete from live_run_pings p
   where p.user_id = p_user_id
     and not p.coarse
     and privacy_in_any_zone(p.lat, p.lng, v_zones);

  delete from race_pings p
   where p.user_id = p_user_id
     and not p.coarse
     and privacy_in_any_zone(p.lat, p.lng, v_zones);

  for v_session in
    select distinct rs.event_id, rs.instance_start
      from race_session_courses rc
      join race_sessions rs
        on rs.event_id = rc.event_id and rs.instance_start = rc.instance_start
      join event_courses c on c.id = rc.course_id
      join routes r on r.id = c.route_id
     where r.user_id = p_user_id
       and private.race_session_effective_status(rs.status, rs.start_mode, rs.scheduled_start_at,
                                              rs.window_opens_at, rs.window_closes_at) = 'armed'
  loop
    perform private.snapshot_race_session_courses(v_session.event_id, v_session.instance_start);
  end loop;

  update race_session_courses rc
     set start_gate_lat = null,
         start_gate_lng = null,
         start_gate_bearing_deg = null,
         start_gate_half_width_m = null
    from event_courses c, routes r, race_sessions rs
   where c.id = rc.course_id
     and r.id = c.route_id
     and r.user_id = p_user_id
     and rs.event_id = rc.event_id
     and rs.instance_start = rc.instance_start
     and private.race_session_effective_status(rs.status, rs.start_mode, rs.scheduled_start_at,
                                              rs.window_opens_at, rs.window_closes_at) <> 'armed'
     and c.start_gate_source is distinct from 'organiser'
     and rc.start_gate_lat is not null
     and privacy_in_any_zone(rc.start_gate_lat, rc.start_gate_lng, v_zones);

  update race_session_courses rc
     set finish_gate_lat = null,
         finish_gate_lng = null,
         finish_gate_bearing_deg = null,
         finish_gate_half_width_m = null,
         finish_line_self_cross = false,
         finish_lap_count = null
    from event_courses c, routes r, race_sessions rs
   where c.id = rc.course_id
     and r.id = c.route_id
     and r.user_id = p_user_id
     and rs.event_id = rc.event_id
     and rs.instance_start = rc.instance_start
     and private.race_session_effective_status(rs.status, rs.start_mode, rs.scheduled_start_at,
                                              rs.window_opens_at, rs.window_closes_at) <> 'armed'
     and c.finish_gate_source is distinct from 'organiser'
     and rc.finish_gate_lat is not null
     and privacy_in_any_zone(rc.finish_gate_lat, rc.finish_gate_lng, v_zones);

  update race_session_courses rc
     set finish_lat = null,
         finish_lng = null
    from event_courses c, routes r, race_sessions rs
   where c.id = rc.course_id
     and r.id = c.route_id
     and r.user_id = p_user_id
     and rs.event_id = rc.event_id
     and rs.instance_start = rc.instance_start
     and private.race_session_effective_status(rs.status, rs.start_mode, rs.scheduled_start_at,
                                              rs.window_opens_at, rs.window_closes_at) <> 'armed'
     and rc.finish_lat is not null
     and privacy_in_any_zone(rc.finish_lat, rc.finish_lng, v_zones);
end;
$$;

revoke execute on function private.strip_stored_in_zone_points(uuid)
  from public, anon, authenticated;

create or replace function public.user_settings_strip_stored_in_zone_points()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform private.strip_stored_in_zone_points(new.user_id);
  return null;
end;
$$;

revoke execute on function public.user_settings_strip_stored_in_zone_points()
  from public, anon, authenticated;

create trigger user_settings_strip_stored_in_zone_points_ins
  after insert on public.user_settings
  for each row
  when (new.prefs ? 'privacy_zones')
  execute function public.user_settings_strip_stored_in_zone_points();

create trigger user_settings_strip_stored_in_zone_points_upd
  after update of prefs on public.user_settings
  for each row
  when (old.prefs -> 'privacy_zones' is distinct from new.prefs -> 'privacy_zones')
  execute function public.user_settings_strip_stored_in_zone_points();

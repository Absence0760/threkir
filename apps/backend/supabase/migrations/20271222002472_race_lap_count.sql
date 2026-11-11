-- A lap course's lap count, frozen per race (#1304, decisions § 2472).
--
-- A course of k laps through its finish line used to finish at lap
-- ceil(0.6 k): the line finish only asked for 60 % of the course from the
-- committed start. When a race freezes its courses,
-- race_session_courses.finish_lap_count now holds how many times the course
-- passes its finish line forward, read off the course route, and the devices
-- and the web re-time finish on that pass, counted from the committed start,
-- keeping the 60 % share only as a floor against a cut course. Counting passes
-- rather than metres is what keeps a GPS that under-reads every lap from
-- finishing a lap late: a distance rule's margin shrinks as the lap count
-- grows, a count's does not.
--
-- A pass is what the detectors count (race_finish v3): a forward crossing of
-- the effective finish line at least the two lines' separation (centre to
-- centre, 0 without a start line) plus 50 m (RACE_START_COMMIT_M) along the
-- route, so the start's own pass is not one, and 50 m past the previous pass,
-- so two crossings a few metres apart are one. private.course_finish_lap_count
-- counts them over the privacy-clipped route geometry (event_course_endpoints,
-- the clip the lines come from):
--   * a closed route (its first point within the finish line's half-width,
--     or 30 m, of the line, and its last point as close to its first) whose
--     distance is at least 1.5 times the drawn length G is one lap raced
--     round(D / G) times: that many times the passes one lap makes, counted
--     around the loop so a finish line placed past the route's end still
--     meets it. A start line further than that from the finish line puts an
--     undrawn lead-in before the laps: no count;
--   * otherwise the passes along the route as drawn (a route drawn with its
--     laps, or one crossing its finish mid-race).
-- A lap under 50 m, or a count under 2, is null: today's rule. A course with
-- no route is null too, since no geometry carries a lap; the detectors then
-- scale the share's floor by the runner's own measured lap (§ 2472).
--
-- Backfill: a session frozen before this migration and still `armed` (no GO,
-- so no runner has been timed against its copy) takes the count, computed
-- against its own frozen finish line and distance, only where the course's
-- live finish line and distance still equal the frozen ones, so the count
-- belongs to the geometry the copy was taken from as far as the server can
-- tell. A running, finished or cancelled session is left as it was frozen.
--
-- Locks (docs/backend/migration_locks.md): a nullable column with no default
-- is catalogue-only; its CHECK lands NOT VALID and 20271222012472 validates
-- it in its own transaction. The backfill touches the armed sessions' rows of
-- race_session_courses only, a handful at a time. The function bodies are
-- replaced in place.

set search_path = public;

alter table public.race_session_courses
  add column finish_lap_count integer;

alter table public.race_session_courses
  add constraint race_session_courses_finish_lap_count_check
    check (finish_lap_count is null
           or (finish_lap_count >= 2 and finish_lap_count <= 1000)) not valid;

-- Forward crossings of a line along p_geom, the way gate_crossing v1 crosses
-- (s from < 0 to >= 0, the interpolated offset within the half-width), whose
-- distance along the route lies in [p_lo_m, p_hi_m] and is at least 50 m
-- (START_COMMIT_M in fixtures/race_finish_cases.json) past the previous one
-- counted: the lap passes a detector counts.
create or replace function private.course_line_passes(
  p_geom jsonb,
  p_lat double precision,
  p_lng double precision,
  p_bearing_deg double precision,
  p_half_width_m double precision,
  p_lo_m double precision,
  p_hi_m double precision
)
returns integer
language plpgsql
immutable
set search_path = public
as $$
declare
  c_pass_m constant double precision := 50;
  v_n int := coalesce(jsonb_array_length(p_geom), 0);
  v_sin double precision := sin(radians(p_bearing_deg));
  v_cos double precision := cos(radians(p_bearing_deg));
  v_i int;
  v_x double precision;
  v_y double precision;
  v_s double precision;
  v_u double precision;
  v_ps double precision;
  v_pu double precision;
  v_lat double precision;
  v_lng double precision;
  v_plat double precision;
  v_plng double precision;
  v_seg double precision;
  v_cum double precision := 0;
  v_f double precision;
  v_c double precision;
  v_last double precision;
  v_passes int := 0;
begin
  for v_i in 0 .. v_n - 1 loop
    v_lat := (p_geom -> v_i ->> 0)::float8;
    v_lng := (p_geom -> v_i ->> 1)::float8;
    select g.x, g.y into v_x, v_y from private.gate_plane_xy(p_lat, p_lng, v_lat, v_lng) g;
    v_s := v_x * v_sin + v_y * v_cos;
    v_u := v_x * v_cos - v_y * v_sin;
    if v_i > 0 then
      select sqrt(g.x ^ 2 + g.y ^ 2) into v_seg
        from private.gate_plane_xy(v_plat, v_plng, v_lat, v_lng) g;
      if v_ps < 0 and v_s >= 0 then
        v_f := -v_ps / (v_s - v_ps);
        v_c := v_cum + v_f * v_seg;
        if abs(v_pu + v_f * (v_u - v_pu)) <= p_half_width_m
           and v_c >= p_lo_m and v_c <= p_hi_m
           and (v_last is null or v_c - v_last >= c_pass_m) then
          v_passes := v_passes + 1;
          v_last := v_c;
        end if;
      end if;
      v_cum := v_cum + v_seg;
    end if;
    v_ps := v_s;
    v_pu := v_u;
    v_plat := v_lat;
    v_plng := v_lng;
  end loop;
  return v_passes;
end;
$$;

revoke execute on function private.course_line_passes(jsonb, double precision, double precision, double precision, double precision, double precision, double precision)
  from public, anon, authenticated;

-- The lap count a race freezes for one course (see the header); null when
-- the course is not a lap course, or the geometry cannot say.
create or replace function private.course_finish_lap_count(
  p_geom jsonb,
  p_lat double precision,
  p_lng double precision,
  p_bearing_deg double precision,
  p_half_width_m double precision,
  p_start_lat double precision,
  p_start_lng double precision,
  p_distance_m double precision
)
returns integer
language plpgsql
immutable
set search_path = public
as $$
declare
  c_pass_m constant double precision := 50;
  c_closed_m constant double precision := 30;
  v_n int := coalesce(jsonb_array_length(p_geom), 0);
  v_i int;
  v_g double precision := 0;
  v_seg double precision;
  v_sep double precision := 0;
  v_first_off double precision;
  v_ends_off double precision;
  v_close double precision;
  v_d double precision;
  v_loop jsonb;
  v_passes int;
  v_k bigint;
begin
  if v_n < 2 or p_lat is null or p_lng is null or p_bearing_deg is null
     or p_half_width_m is null then
    return null;
  end if;
  v_d := case when p_distance_m > 0 then p_distance_m end;
  v_close := greatest(p_half_width_m, c_closed_m);
  if p_start_lat is not null and p_start_lng is not null then
    select sqrt(g.x ^ 2 + g.y ^ 2) into v_sep
      from private.gate_plane_xy(p_start_lat, p_start_lng, p_lat, p_lng) g;
  end if;
  for v_i in 1 .. v_n - 1 loop
    select sqrt(g.x ^ 2 + g.y ^ 2) into v_seg
      from private.gate_plane_xy((p_geom -> (v_i - 1) ->> 0)::float8, (p_geom -> (v_i - 1) ->> 1)::float8,
                                 (p_geom -> v_i ->> 0)::float8, (p_geom -> v_i ->> 1)::float8) g;
    v_g := v_g + v_seg;
  end loop;
  if v_g <= 0 then
    return null;
  end if;
  select sqrt(g.x ^ 2 + g.y ^ 2) into v_first_off
    from private.gate_plane_xy(p_lat, p_lng, (p_geom -> 0 ->> 0)::float8, (p_geom -> 0 ->> 1)::float8) g;
  select sqrt(g.x ^ 2 + g.y ^ 2) into v_ends_off
    from private.gate_plane_xy((p_geom -> 0 ->> 0)::float8, (p_geom -> 0 ->> 1)::float8,
                               (p_geom -> (v_n - 1) ->> 0)::float8, (p_geom -> (v_n - 1) ->> 1)::float8) g;

  if v_d is not null and v_d >= 1.5 * v_g
     and v_first_off <= v_close and v_ends_off <= v_close then
    -- One closed lap raced round(D / G) times. A start line away from the lap
    -- puts a lead-in the route does not draw before it, which a device would
    -- count as a pass: no count.
    if v_sep > v_close then
      return null;
    end if;
    -- Counted around the loop (the route twice, one lap's worth in the
    -- middle), so a finish line placed a few metres past the route's end
    -- still meets the lap once.
    select p_geom || coalesce(jsonb_agg(e order by i), '[]'::jsonb) into v_loop
      from jsonb_array_elements(p_geom) with ordinality as a(e, i)
     where i > 1;
    v_passes := private.course_line_passes(v_loop, p_lat, p_lng, p_bearing_deg, p_half_width_m,
                                           0.5 * v_g, 1.5 * v_g);
    if v_passes = 0 or v_g / v_passes < c_pass_m then
      return null;
    end if;
    v_k := round(v_d / v_g)::bigint * v_passes;
  else
    v_k := private.course_line_passes(p_geom, p_lat, p_lng, p_bearing_deg, p_half_width_m,
                                      v_sep + c_pass_m, 'Infinity'::float8);
  end if;

  if v_k < 2 or v_k > 1000 then
    return null;
  end if;
  return v_k::int;
end;
$$;

revoke execute on function private.course_finish_lap_count(jsonb, double precision, double precision, double precision, double precision, double precision, double precision, double precision)
  from public, anon, authenticated;

-- Fill the lap count of every armed session's frozen copy that has none, for
-- a course whose live finish line and distance still equal the frozen ones
-- (see the header). Run once below; kept as a function so the rule is tested.
create or replace function private.backfill_race_lap_counts()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rows int;
begin
  update race_session_courses rc
     set finish_lap_count = private.course_finish_lap_count(
           (select e.geometry from private.event_course_endpoints(c.route_id) e),
           rc.finish_gate_lat, rc.finish_gate_lng, rc.finish_gate_bearing_deg,
           rc.finish_gate_half_width_m, rc.start_gate_lat, rc.start_gate_lng, rc.distance_m)
    from event_courses c, race_sessions s
   where c.id = rc.course_id
     and s.event_id = rc.event_id
     and s.instance_start = rc.instance_start
     and s.status = 'armed'
     and rc.finish_lap_count is null
     and c.route_id is not null
     and c.finish_gate_lat is not distinct from rc.finish_gate_lat
     and c.finish_gate_lng is not distinct from rc.finish_gate_lng
     and c.finish_gate_bearing_deg is not distinct from rc.finish_gate_bearing_deg
     and c.finish_gate_half_width_m is not distinct from rc.finish_gate_half_width_m
     and c.distance_m is not distinct from rc.distance_m;
  get diagnostics v_rows = row_count;
  return v_rows;
end;
$$;

revoke execute on function private.backfill_race_lap_counts() from public, anon, authenticated;

-- The body of 20271116002390 with the lap count added: each course's clipped
-- geometry is read once, at freeze, against its effective lines.
create or replace function private.snapshot_race_session_courses(
  p_event_id uuid,
  p_instance_start timestamptz
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from race_session_courses
   where event_id = p_event_id and instance_start = p_instance_start;

  insert into race_session_courses (
    event_id, instance_start, course_id,
    start_gate_lat, start_gate_lng, start_gate_bearing_deg, start_gate_half_width_m,
    finish_gate_lat, finish_gate_lng, finish_gate_bearing_deg, finish_gate_half_width_m,
    finish_lat, finish_lng, distance_m, finish_line_self_cross, finish_lap_count
  )
  select
    p_event_id, p_instance_start, c.id,
    c.start_gate_lat, c.start_gate_lng, c.start_gate_bearing_deg, c.start_gate_half_width_m,
    c.finish_gate_lat, c.finish_gate_lng, c.finish_gate_bearing_deg, c.finish_gate_half_width_m,
    c.finish_lat, c.finish_lng, c.distance_m, c.finish_line_self_cross,
    case when c.route_id is not null then
      private.course_finish_lap_count(
        (select e.geometry from private.event_course_endpoints(c.route_id) e),
        c.finish_gate_lat, c.finish_gate_lng, c.finish_gate_bearing_deg,
        c.finish_gate_half_width_m, c.start_gate_lat, c.start_gate_lng, c.distance_m)
    end
  from event_courses c
  where c.event_id = p_event_id;

  update race_sessions
     set courses_frozen_at = now()
   where event_id = p_event_id and instance_start = p_instance_start;
end;
$$;

revoke execute on function private.snapshot_race_session_courses(uuid, timestamptz)
  from public, anon, authenticated;

-- Sessions frozen before this migration and still armed (see the header).
select private.backfill_race_lap_counts();

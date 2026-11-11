-- A lap course's minimum covered distance, frozen per race (#1304, decisions
-- § 2472).
--
-- A course of k laps through its finish line used to finish at lap
-- ceil(0.6 k): the line finish only asked for 60 % of the course from the
-- committed start. When a race freezes its courses, the lap length L now comes
-- from the course route, and race_session_courses.finish_min_coverage_m holds
-- max(0.6 D, D - L / 2): every pass before the last falls at least half a lap
-- short of it, and the last clears it with half a lap of GPS under-read to
-- spare. The devices and the web re-time gate every finish on it.
--
-- private.course_finish_min_coverage_m derives L from the privacy-clipped
-- route geometry (event_course_endpoints, the same clip the lines come from):
--   * a closed route (its first point within the finish line's half-width,
--     or 30 m, of the line) whose distance is at least 1.5 times the drawn
--     length is one lap raced D / G times: L is the drawn length G;
--   * otherwise, a route crossing its finish line forward twice or more
--     (past the half-width from its start) is drawn with its laps: L is the
--     spacing of the last two crossings, scaled from the drawn length to the
--     course distance.
-- Anything else is null, today's rule. A course with no route is null too: no
-- geometry carries a lap, and the detectors measure it themselves from the
-- first finish pass that does not count (§ 2472).
--
-- Locks (docs/backend/migration_locks.md): a nullable column with no default
-- is catalogue-only; its CHECK lands NOT VALID and 20271222012472 validates
-- it in its own transaction. The function bodies are replaced in place.

set search_path = public;

alter table public.race_session_courses
  add column finish_min_coverage_m double precision;

alter table public.race_session_courses
  add constraint race_session_courses_finish_min_coverage_m_check
    check (finish_min_coverage_m is null
           or (finish_min_coverage_m > 0 and finish_min_coverage_m <= 1000000)) not valid;

-- 0.6 is MIN_COVERAGE_WITH_START in fixtures/race_finish_cases.json, the
-- share every detector already asks of a finish with a committed start.
create or replace function private.course_finish_min_coverage_m(
  p_geom jsonb,
  p_lat double precision,
  p_lng double precision,
  p_bearing_deg double precision,
  p_half_width_m double precision,
  p_distance_m double precision
)
returns double precision
language plpgsql
immutable
set search_path = public
as $$
declare
  c_share constant double precision := 0.6;
  c_closed_m constant double precision := 30;
  v_n int := coalesce(jsonb_array_length(p_geom), 0);
  v_sin double precision;
  v_cos double precision;
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
  v_crossings double precision[] := '{}';
  v_first_off double precision;
  v_d double precision;
  v_lap double precision;
  v_k int;
begin
  if v_n < 2 or p_lat is null or p_lng is null or p_bearing_deg is null
     or p_half_width_m is null then
    return null;
  end if;
  v_d := case when p_distance_m > 0 then p_distance_m end;
  v_sin := sin(radians(p_bearing_deg));
  v_cos := cos(radians(p_bearing_deg));

  for v_i in 0 .. v_n - 1 loop
    v_lat := (p_geom -> v_i ->> 0)::float8;
    v_lng := (p_geom -> v_i ->> 1)::float8;
    select g.x, g.y into v_x, v_y from private.gate_plane_xy(p_lat, p_lng, v_lat, v_lng) g;
    v_s := v_x * v_sin + v_y * v_cos;
    v_u := v_x * v_cos - v_y * v_sin;
    if v_i = 0 then
      v_first_off := sqrt(v_x ^ 2 + v_y ^ 2);
    else
      select sqrt(g.x ^ 2 + g.y ^ 2) into v_seg
        from private.gate_plane_xy(v_plat, v_plng, v_lat, v_lng) g;
      if v_ps < 0 and v_s >= 0 then
        v_f := -v_ps / (v_s - v_ps);
        v_c := v_cum + v_f * v_seg;
        if abs(v_pu + v_f * (v_u - v_pu)) <= p_half_width_m and v_c > p_half_width_m then
          v_crossings := v_crossings || v_c;
        end if;
      end if;
      v_cum := v_cum + v_seg;
    end if;
    v_ps := v_s;
    v_pu := v_u;
    v_plat := v_lat;
    v_plng := v_lng;
  end loop;

  if v_cum <= 0 then
    return null;
  end if;

  if v_d is not null and v_d >= 1.5 * v_cum
     and v_first_off <= greatest(p_half_width_m, c_closed_m) then
    v_lap := v_cum;
  else
    v_k := cardinality(v_crossings);
    if v_k < 2 then
      return null;
    end if;
    v_d := coalesce(v_d, v_cum);
    v_lap := (v_crossings[v_k] - v_crossings[v_k - 1]) * v_d / v_cum;
  end if;

  if v_lap <= 0 then
    return null;
  end if;
  return least(greatest(c_share * v_d, v_d - v_lap / 2), 1000000);
end;
$$;

revoke execute on function private.course_finish_min_coverage_m(jsonb, double precision, double precision, double precision, double precision, double precision)
  from public, anon, authenticated;

-- The body of 20271116002390 with the lap minimum added: each course's
-- clipped geometry is read once, at freeze, against its effective finish line.
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
    finish_lat, finish_lng, distance_m, finish_line_self_cross, finish_min_coverage_m
  )
  select
    p_event_id, p_instance_start, c.id,
    c.start_gate_lat, c.start_gate_lng, c.start_gate_bearing_deg, c.start_gate_half_width_m,
    c.finish_gate_lat, c.finish_gate_lng, c.finish_gate_bearing_deg, c.finish_gate_half_width_m,
    c.finish_lat, c.finish_lng, c.distance_m, c.finish_line_self_cross,
    case when c.route_id is not null then
      private.course_finish_min_coverage_m(
        (select e.geometry from private.event_course_endpoints(c.route_id) e),
        c.finish_gate_lat, c.finish_gate_lng, c.finish_gate_bearing_deg,
        c.finish_gate_half_width_m, c.distance_m)
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

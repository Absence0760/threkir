-- Course start and finish lines (#1305, timing lines phase 2, decisions § 2390).
--
-- A course gets a start line and a finish line: a centre, a direction of travel
-- and a half-width, the shape `gate_crossing v1` crosses (§ 2377).
--
--   * event_courses.start_gate_* / finish_gate_* hold each line, with a
--     `source`: `derived` from the course route, or placed by an `organiser`.
--   * Derived lines come from the route OWNER's privacy-clipped geometry, the
--     same clip the endpoints already use (§ 1848): the start line sits on the
--     published start point facing the point about 25 m along, the finish line
--     on the published finish point facing from the point about 25 m before.
--     An end whose point the clip trimmed, or with under about 10 m of line
--     surviving at it, gets no line. They are recomputed wherever the
--     endpoints are: course writes, route waypoint edits, owner zone edits.
--     An organiser's line is never touched by a recompute.
--   * finish_line_self_cross: the route crosses its own finish line forward
--     earlier than its final crossing, with at least half its distance behind
--     it, so a line finish could fire a lap early (short laps, track races).
--   * set_event_course_gate / reset_event_course_gate are the only way a client
--     moves a line. Neither checks privacy zones: an organiser's line is their
--     own coordinate, and a refusal would hand them one bit about someone
--     else's zone per call (amends § 1848, recorded in § 2390).
--   * race_session_courses freezes each course's effective lines, finish
--     point, distance and self-cross flag when a race session is created
--     (Arm, for Host GO). Devices, the spectator page and the plausibility
--     check read the frozen copy, so a route or zone edit mid-race changes
--     only the next race. race_sessions.courses_frozen_at says the copy exists.
--
-- Locks (docs/backend/migration_locks.md): the new columns are nullable, or
-- NOT NULL with a constant default, which is catalogue-only. Every CHECK lands
-- NOT VALID and is validated by 20271116002391 in its own transaction.
-- race_session_courses is new and empty. CREATE TRIGGER on race_sessions and
-- event_courses is SHARE ROW EXCLUSIVE, catalogue-only. The backfill rewrites
-- event_courses, a bounded config table (one row per course).

set search_path = public;

-- ─── event_courses columns ─────────────────────────────────────────────────

alter table public.event_courses
  add column start_gate_lat double precision,
  add column start_gate_lng double precision,
  add column start_gate_bearing_deg double precision,
  add column start_gate_half_width_m double precision,
  add column start_gate_source text,
  add column finish_gate_lat double precision,
  add column finish_gate_lng double precision,
  add column finish_gate_bearing_deg double precision,
  add column finish_gate_half_width_m double precision,
  add column finish_gate_source text,
  add column finish_line_self_cross boolean not null default false;

alter table public.event_courses
  add constraint event_courses_start_gate_lat_check
    check (start_gate_lat is null or start_gate_lat between -90 and 90) not valid,
  add constraint event_courses_start_gate_lng_check
    check (start_gate_lng is null or start_gate_lng between -180 and 180) not valid,
  add constraint event_courses_start_gate_bearing_deg_check
    check (start_gate_bearing_deg is null
           or (start_gate_bearing_deg >= 0 and start_gate_bearing_deg < 360)) not valid,
  add constraint event_courses_start_gate_half_width_m_check
    check (start_gate_half_width_m is null
           or start_gate_half_width_m between 5 and 100) not valid,
  add constraint event_courses_start_gate_source_check
    check (start_gate_source in ('derived', 'organiser')) not valid,
  add constraint event_courses_start_gate_complete_check
    check (num_nulls(start_gate_lat, start_gate_lng, start_gate_bearing_deg,
                     start_gate_half_width_m, start_gate_source) in (0, 5)) not valid,
  add constraint event_courses_finish_gate_lat_check
    check (finish_gate_lat is null or finish_gate_lat between -90 and 90) not valid,
  add constraint event_courses_finish_gate_lng_check
    check (finish_gate_lng is null or finish_gate_lng between -180 and 180) not valid,
  add constraint event_courses_finish_gate_bearing_deg_check
    check (finish_gate_bearing_deg is null
           or (finish_gate_bearing_deg >= 0 and finish_gate_bearing_deg < 360)) not valid,
  add constraint event_courses_finish_gate_half_width_m_check
    check (finish_gate_half_width_m is null
           or finish_gate_half_width_m between 5 and 100) not valid,
  add constraint event_courses_finish_gate_source_check
    check (finish_gate_source in ('derived', 'organiser')) not valid,
  add constraint event_courses_finish_gate_complete_check
    check (num_nulls(finish_gate_lat, finish_gate_lng, finish_gate_bearing_deg,
                     finish_gate_half_width_m, finish_gate_source) in (0, 5)) not valid;

-- ─── geometry helpers ──────────────────────────────────────────────────────
--
-- The tangent plane at an origin, as gate_crossing projects
-- (docs/features/gps_distance.md: R = 6371008.8, longitude difference wrapped
-- into [-180, 180)). At 25 m the plane and the sphere agree to well under a
-- millimetre.

create or replace function private.gate_plane_xy(
  p_lat0 double precision, p_lng0 double precision,
  p_lat double precision, p_lng double precision,
  out x double precision, out y double precision
)
language sql
immutable
set search_path = public
as $$
  select
    radians(case
      when p_lng - p_lng0 >= 180 then p_lng - p_lng0 - 360
      when p_lng - p_lng0 < -180 then p_lng - p_lng0 + 360
      else p_lng - p_lng0
    end) * 6371008.8 * cos(radians(p_lat0)),
    radians(p_lat - p_lat0) * 6371008.8;
$$;

-- Degrees clockwise from north of (x, y), in [0, 360).
create or replace function private.gate_bearing_of(p_x double precision, p_y double precision)
returns double precision
language sql
immutable
set search_path = public
as $$
  select case when b >= 360 then b - 360 else b end
  from (select mod(degrees(atan2(p_x, p_y))::numeric + 360, 360)::float8 as b) s;
$$;

-- The direction a line takes at one end of a clipped geometry: from the end
-- point toward the point about 25 m along it (the start), or from the point
-- about 25 m before it toward the end point (the finish). NULL when under
-- about 10 m of line survives at that end. p_geom is an array of [lat, lng].
create or replace function private.course_end_bearing(p_geom jsonb, p_finish boolean)
returns double precision
language plpgsql
immutable
set search_path = public
as $$
declare
  c_along constant double precision := 25;
  c_min constant double precision := 10;
  v_n int := coalesce(jsonb_array_length(p_geom), 0);
  v_i int;
  v_idx int;
  v_lat0 double precision;
  v_lng0 double precision;
  v_px double precision := 0;
  v_py double precision := 0;
  v_cx double precision;
  v_cy double precision;
  v_acc double precision := 0;
  v_d double precision;
  v_f double precision;
  v_tx double precision;
  v_ty double precision;
begin
  if v_n < 2 then
    return null;
  end if;
  v_idx := case when p_finish then v_n - 1 else 0 end;
  v_lat0 := (p_geom -> v_idx ->> 0)::float8;
  v_lng0 := (p_geom -> v_idx ->> 1)::float8;
  v_tx := 0;
  v_ty := 0;
  for v_i in 1 .. v_n - 1 loop
    v_idx := case when p_finish then v_n - 1 - v_i else v_i end;
    select g.x, g.y into v_cx, v_cy
      from private.gate_plane_xy(v_lat0, v_lng0,
                                 (p_geom -> v_idx ->> 0)::float8,
                                 (p_geom -> v_idx ->> 1)::float8) g;
    v_d := sqrt((v_cx - v_px) ^ 2 + (v_cy - v_py) ^ 2);
    if v_d > 0 then
      if v_acc + v_d >= c_along then
        v_f := (c_along - v_acc) / v_d;
        v_tx := v_px + v_f * (v_cx - v_px);
        v_ty := v_py + v_f * (v_cy - v_py);
        v_acc := c_along;
        exit;
      end if;
      v_acc := v_acc + v_d;
      v_tx := v_cx;
      v_ty := v_cy;
    end if;
    v_px := v_cx;
    v_py := v_cy;
  end loop;

  if v_acc < c_min then
    return null;
  end if;
  if p_finish then
    return private.gate_bearing_of(-v_tx, -v_ty);
  end if;
  return private.gate_bearing_of(v_tx, v_ty);
end;
$$;

-- Whether p_geom crosses the line forward earlier than its final forward
-- crossing, with at least half its own length behind it at that crossing.
-- Crossings are gate_crossing v1's: s goes from < 0 to >= 0 and the
-- interpolated lateral offset is within the half-width.
create or replace function private.course_line_self_crosses(
  p_geom jsonb,
  p_lat double precision,
  p_lng double precision,
  p_bearing_deg double precision,
  p_half_width_m double precision
)
returns boolean
language plpgsql
immutable
set search_path = public
as $$
declare
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
  v_px double precision;
  v_py double precision;
  v_lat double precision;
  v_lng double precision;
  v_plat double precision;
  v_plng double precision;
  v_seg double precision;
  v_cum double precision := 0;
  v_f double precision;
  v_crossings double precision[] := '{}';
  v_last double precision;
begin
  if v_n < 2 or p_lat is null or p_lng is null or p_bearing_deg is null
     or p_half_width_m is null then
    return false;
  end if;
  v_sin := sin(radians(p_bearing_deg));
  v_cos := cos(radians(p_bearing_deg));

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
        if abs(v_pu + v_f * (v_u - v_pu)) <= p_half_width_m then
          v_crossings := v_crossings || (v_cum + v_f * v_seg);
        end if;
      end if;
      v_cum := v_cum + v_seg;
    end if;
    v_ps := v_s;
    v_pu := v_u;
    v_plat := v_lat;
    v_plng := v_lng;
  end loop;

  if cardinality(v_crossings) < 2 or v_cum <= 0 then
    return false;
  end if;
  v_last := v_crossings[cardinality(v_crossings)];
  return exists (
    select 1 from unnest(v_crossings) c
    where c < v_last and c >= 0.5 * v_cum
  );
end;
$$;

revoke execute on function private.gate_plane_xy(double precision, double precision, double precision, double precision)
  from public, anon, authenticated;
revoke execute on function private.gate_bearing_of(double precision, double precision)
  from public, anon, authenticated;
revoke execute on function private.course_end_bearing(jsonb, boolean)
  from public, anon, authenticated;
revoke execute on function private.course_line_self_crosses(jsonb, double precision, double precision, double precision, double precision)
  from public, anon, authenticated;

-- ─── endpoints, now with a direction per end ───────────────────────────────
--
-- The body of 20270728000001 with three outputs added: the direction at each
-- end, and the clipped geometry itself (an array of [lat, lng], positions
-- only) for the self-cross check. The clip trims only leading and trailing
-- points (clip_track_for_user), so the geometry is one unbroken line. The
-- return type changes, so the function is dropped and recreated; the two
-- callers are recreated below.

drop function private.event_course_endpoints(uuid);

create function private.event_course_endpoints(p_route_id uuid)
returns table (
  start_lat double precision,
  start_lng double precision,
  finish_lat double precision,
  finish_lng double precision,
  start_bearing_deg double precision,
  finish_bearing_deg double precision,
  geometry jsonb
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_owner uuid;
  v_raw jsonb;
  v_clipped jsonb;
  v_n int;
  v_first jsonb;
  v_last jsonb;
  v_geom jsonb;
begin
  select r.user_id, r.waypoints into v_owner, v_raw
  from routes r
  where r.id = p_route_id;

  if v_owner is null
     or jsonb_typeof(v_raw) is distinct from 'array'
     or jsonb_array_length(v_raw) = 0
  then
    return query select null::float8, null::float8, null::float8, null::float8,
                        null::float8, null::float8, '[]'::jsonb;
    return;
  end if;

  v_clipped := clip_track_for_user(v_owner, v_raw);
  v_n := jsonb_array_length(v_clipped);

  if v_n > 0 and v_clipped -> 0 = v_raw -> 0 then
    v_first := v_raw -> 0;
  end if;
  if v_n > 0 and v_clipped -> (v_n - 1) = v_raw -> (jsonb_array_length(v_raw) - 1) then
    v_last := v_raw -> (jsonb_array_length(v_raw) - 1);
  end if;

  v_first := case
    when jsonb_typeof(v_first -> 'lat') = 'number' and jsonb_typeof(v_first -> 'lng') = 'number'
      then v_first
  end;
  v_last := case
    when jsonb_typeof(v_last -> 'lat') = 'number' and jsonb_typeof(v_last -> 'lng') = 'number'
      then v_last
  end;
  if v_first is not null
     and not ((v_first ->> 'lat')::float8 between -90 and 90
              and (v_first ->> 'lng')::float8 between -180 and 180)
  then
    v_first := null;
  end if;
  if v_last is not null
     and not ((v_last ->> 'lat')::float8 between -90 and 90
              and (v_last ->> 'lng')::float8 between -180 and 180)
  then
    v_last := null;
  end if;

  select coalesce(jsonb_agg(jsonb_build_array(e -> 'lat', e -> 'lng') order by i), '[]'::jsonb)
    into v_geom
    from jsonb_array_elements(v_clipped) with ordinality as a(e, i)
   where jsonb_typeof(e -> 'lat') = 'number'
     and jsonb_typeof(e -> 'lng') = 'number'
     and (e ->> 'lat')::float8 between -90 and 90
     and (e ->> 'lng')::float8 between -180 and 180;

  return query select
    (v_first ->> 'lat')::float8,
    (v_first ->> 'lng')::float8,
    (v_last ->> 'lat')::float8,
    (v_last ->> 'lng')::float8,
    case when v_first is not null then private.course_end_bearing(v_geom, false) end,
    case when v_last is not null then private.course_end_bearing(v_geom, true) end,
    v_geom;
end;
$$;

revoke execute on function private.event_course_endpoints(uuid)
  from public, anon, authenticated;

-- ─── a client cannot write a line directly ────────────────────────────────
--
-- An invoker trigger, so current_user is the caller's role: a PostgREST write
-- runs as anon / authenticated, while set_event_course_gate and the refresh
-- run as their definer. It sorts before event_courses_set_endpoints_trg, so a
-- client's insert starts with no organiser line and a client's update keeps
-- the lines the row had; the derivation below then fills every derived end.

create or replace function public.event_courses_guard_gates()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if current_user not in ('anon', 'authenticated') then
    return new;
  end if;
  if tg_op = 'INSERT' then
    new.start_gate_lat := null;
    new.start_gate_lng := null;
    new.start_gate_bearing_deg := null;
    new.start_gate_half_width_m := null;
    new.start_gate_source := null;
    new.finish_gate_lat := null;
    new.finish_gate_lng := null;
    new.finish_gate_bearing_deg := null;
    new.finish_gate_half_width_m := null;
    new.finish_gate_source := null;
  else
    new.start_gate_lat := old.start_gate_lat;
    new.start_gate_lng := old.start_gate_lng;
    new.start_gate_bearing_deg := old.start_gate_bearing_deg;
    new.start_gate_half_width_m := old.start_gate_half_width_m;
    new.start_gate_source := old.start_gate_source;
    new.finish_gate_lat := old.finish_gate_lat;
    new.finish_gate_lng := old.finish_gate_lng;
    new.finish_gate_bearing_deg := old.finish_gate_bearing_deg;
    new.finish_gate_half_width_m := old.finish_gate_half_width_m;
    new.finish_gate_source := old.finish_gate_source;
  end if;
  return new;
end;
$$;

revoke execute on function public.event_courses_guard_gates() from public, anon, authenticated;

create trigger event_courses_guard_gates_trg
  before insert or update on public.event_courses
  for each row execute function public.event_courses_guard_gates();

-- ─── derivation on every course write ──────────────────────────────────────
--
-- The body of 20270728000001's event_courses_set_endpoints, plus: each end
-- whose line is not the organiser's takes the derived line (or none), and the
-- self-cross flag is recomputed against the effective finish line. The
-- default half-width is GATE_HALF_WIDTH_RACE_M, 15 m (§ 2377), in every port.

create or replace function public.event_courses_set_endpoints()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ends record;
  c_half_width constant double precision := 15;
begin
  if new.route_id is not null
     and auth.uid() is not null
     and (tg_op = 'INSERT' or new.route_id is distinct from old.route_id)
     and not private.is_route_visible_to(new.route_id, auth.uid())
  then
    raise exception 'event_course_route_not_visible: route % is not visible to you', new.route_id
      using errcode = 'insufficient_privilege';
  end if;

  if new.route_id is null then
    select null::float8 as start_lat, null::float8 as start_lng,
           null::float8 as finish_lat, null::float8 as finish_lng,
           null::float8 as start_bearing_deg, null::float8 as finish_bearing_deg,
           '[]'::jsonb as geometry
      into v_ends;
  else
    select * into v_ends from private.event_course_endpoints(new.route_id);
  end if;

  new.start_lat := v_ends.start_lat;
  new.start_lng := v_ends.start_lng;
  new.finish_lat := v_ends.finish_lat;
  new.finish_lng := v_ends.finish_lng;

  if new.start_gate_source is distinct from 'organiser' then
    if v_ends.start_lat is not null and v_ends.start_bearing_deg is not null then
      new.start_gate_lat := v_ends.start_lat;
      new.start_gate_lng := v_ends.start_lng;
      new.start_gate_bearing_deg := v_ends.start_bearing_deg;
      new.start_gate_half_width_m := c_half_width;
      new.start_gate_source := 'derived';
    else
      new.start_gate_lat := null;
      new.start_gate_lng := null;
      new.start_gate_bearing_deg := null;
      new.start_gate_half_width_m := null;
      new.start_gate_source := null;
    end if;
  end if;

  if new.finish_gate_source is distinct from 'organiser' then
    if v_ends.finish_lat is not null and v_ends.finish_bearing_deg is not null then
      new.finish_gate_lat := v_ends.finish_lat;
      new.finish_gate_lng := v_ends.finish_lng;
      new.finish_gate_bearing_deg := v_ends.finish_bearing_deg;
      new.finish_gate_half_width_m := c_half_width;
      new.finish_gate_source := 'derived';
    else
      new.finish_gate_lat := null;
      new.finish_gate_lng := null;
      new.finish_gate_bearing_deg := null;
      new.finish_gate_half_width_m := null;
      new.finish_gate_source := null;
    end if;
  end if;

  new.finish_line_self_cross := private.course_line_self_crosses(
    v_ends.geometry, new.finish_gate_lat, new.finish_gate_lng,
    new.finish_gate_bearing_deg, new.finish_gate_half_width_m);
  return new;
end;
$$;

-- The body of 20270728000001 against the new return type. The BEFORE trigger
-- above recomputes the same endpoints and every derived line on the way in.
create or replace function private.refresh_event_course_endpoints(p_route_ids uuid[])
returns void
language sql
security definer
set search_path = public
as $$
  update event_courses c
     set (start_lat, start_lng, finish_lat, finish_lng) = (
       select e.start_lat, e.start_lng, e.finish_lat, e.finish_lng
       from private.event_course_endpoints(c.route_id) e
     )
   where c.route_id = any (p_route_ids);
$$;

revoke execute on function private.refresh_event_course_endpoints(uuid[])
  from public, anon, authenticated;

-- ─── organiser-placed lines ────────────────────────────────────────────────

create or replace function public.set_event_course_gate(
  p_course_id uuid,
  p_which text,
  p_lat double precision,
  p_lng double precision,
  p_bearing_deg double precision,
  p_half_width_m double precision
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_club uuid;
  v_bearing double precision;
begin
  if (select auth.uid()) is null then
    raise exception 'sign in to place a timing line' using errcode = '42501';
  end if;
  if p_which is null or p_which not in ('start', 'finish') then
    raise exception 'which must be start or finish' using errcode = '22023';
  end if;
  select e.club_id into v_club
    from event_courses c
    join events e on e.id = c.event_id
   where c.id = p_course_id;
  if not found then
    raise exception 'course not found' using errcode = 'P0002';
  end if;
  if not private.is_event_organiser(v_club) then
    raise exception 'only an event organiser can place a timing line' using errcode = '42501';
  end if;
  if p_lat is null or p_lng is null or p_bearing_deg is null or p_half_width_m is null
     or not (p_lat between -90 and 90) or not (p_lng between -180 and 180)
     or p_lat = 'NaN'::float8 or p_lng = 'NaN'::float8
     or p_bearing_deg = 'NaN'::float8 or p_half_width_m = 'NaN'::float8
     or not (p_half_width_m between 5 and 100)
     or p_bearing_deg in ('Infinity'::float8, '-Infinity'::float8)
  then
    raise exception 'a timing line needs a position, a direction and a half-width of 5 to 100 m'
      using errcode = '22023';
  end if;

  v_bearing := ((p_bearing_deg::numeric % 360 + 360) % 360)::float8;

  if p_which = 'start' then
    update event_courses
       set start_gate_lat = p_lat,
           start_gate_lng = p_lng,
           start_gate_bearing_deg = v_bearing,
           start_gate_half_width_m = p_half_width_m,
           start_gate_source = 'organiser'
     where id = p_course_id;
  else
    update event_courses
       set finish_gate_lat = p_lat,
           finish_gate_lng = p_lng,
           finish_gate_bearing_deg = v_bearing,
           finish_gate_half_width_m = p_half_width_m,
           finish_gate_source = 'organiser'
     where id = p_course_id;
  end if;
end;
$$;

revoke execute on function public.set_event_course_gate(uuid, text, double precision, double precision, double precision, double precision)
  from public, anon;
grant execute on function public.set_event_course_gate(uuid, text, double precision, double precision, double precision, double precision)
  to authenticated;

-- Back to the route's line: clearing the source lets the derivation take the
-- end again (or leave it empty on a routeless course).
create or replace function public.reset_event_course_gate(p_course_id uuid, p_which text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_club uuid;
begin
  if (select auth.uid()) is null then
    raise exception 'sign in to reset a timing line' using errcode = '42501';
  end if;
  if p_which is null or p_which not in ('start', 'finish') then
    raise exception 'which must be start or finish' using errcode = '22023';
  end if;
  select e.club_id into v_club
    from event_courses c
    join events e on e.id = c.event_id
   where c.id = p_course_id;
  if not found then
    raise exception 'course not found' using errcode = 'P0002';
  end if;
  if not private.is_event_organiser(v_club) then
    raise exception 'only an event organiser can reset a timing line' using errcode = '42501';
  end if;

  if p_which = 'start' then
    update event_courses
       set start_gate_lat = null, start_gate_lng = null, start_gate_bearing_deg = null,
           start_gate_half_width_m = null, start_gate_source = null
     where id = p_course_id;
  else
    update event_courses
       set finish_gate_lat = null, finish_gate_lng = null, finish_gate_bearing_deg = null,
           finish_gate_half_width_m = null, finish_gate_source = null
     where id = p_course_id;
  end if;
end;
$$;

revoke execute on function public.reset_event_course_gate(uuid, text) from public, anon;
grant execute on function public.reset_event_course_gate(uuid, text) to authenticated;

-- ─── the per-race frozen copy ─────────────────────────────────────────────

alter table public.race_sessions add column courses_frozen_at timestamptz;

create table public.race_session_courses (
  event_id uuid not null,
  instance_start timestamptz not null,
  course_id uuid not null references public.event_courses(id) on delete cascade,
  start_gate_lat double precision,
  start_gate_lng double precision,
  start_gate_bearing_deg double precision,
  start_gate_half_width_m double precision,
  finish_gate_lat double precision,
  finish_gate_lng double precision,
  finish_gate_bearing_deg double precision,
  finish_gate_half_width_m double precision,
  finish_lat double precision,
  finish_lng double precision,
  distance_m double precision,
  finish_line_self_cross boolean not null default false,
  frozen_at timestamptz not null default now(),
  primary key (event_id, instance_start, course_id),
  -- A reschedule moves race_sessions.instance_start (recurrence_move_key);
  -- the frozen copy moves with it.
  constraint race_session_courses_session_fkey
    foreign key (event_id, instance_start)
    references public.race_sessions (event_id, instance_start)
    on update cascade on delete cascade,
  constraint race_session_courses_start_gate_lat_check
    check (start_gate_lat is null or start_gate_lat between -90 and 90),
  constraint race_session_courses_start_gate_lng_check
    check (start_gate_lng is null or start_gate_lng between -180 and 180),
  constraint race_session_courses_start_gate_bearing_deg_check
    check (start_gate_bearing_deg is null
           or (start_gate_bearing_deg >= 0 and start_gate_bearing_deg < 360)),
  constraint race_session_courses_start_gate_half_width_m_check
    check (start_gate_half_width_m is null or start_gate_half_width_m between 5 and 100),
  constraint race_session_courses_start_gate_complete_check
    check (num_nulls(start_gate_lat, start_gate_lng, start_gate_bearing_deg,
                     start_gate_half_width_m) in (0, 4)),
  constraint race_session_courses_finish_gate_lat_check
    check (finish_gate_lat is null or finish_gate_lat between -90 and 90),
  constraint race_session_courses_finish_gate_lng_check
    check (finish_gate_lng is null or finish_gate_lng between -180 and 180),
  constraint race_session_courses_finish_gate_bearing_deg_check
    check (finish_gate_bearing_deg is null
           or (finish_gate_bearing_deg >= 0 and finish_gate_bearing_deg < 360)),
  constraint race_session_courses_finish_gate_half_width_m_check
    check (finish_gate_half_width_m is null or finish_gate_half_width_m between 5 and 100),
  constraint race_session_courses_finish_gate_complete_check
    check (num_nulls(finish_gate_lat, finish_gate_lng, finish_gate_bearing_deg,
                     finish_gate_half_width_m) in (0, 4)),
  constraint race_session_courses_finish_lat_check
    check (finish_lat is null or finish_lat between -90 and 90),
  constraint race_session_courses_finish_lng_check
    check (finish_lng is null or finish_lng between -180 and 180),
  constraint race_session_courses_finish_pair_check
    check ((finish_lat is null) = (finish_lng is null)),
  constraint race_session_courses_distance_m_check
    check (distance_m is null or (distance_m > 0 and distance_m <= 1000000))
);

create index race_session_courses_course_id on public.race_session_courses (course_id);

alter table public.race_session_courses enable row level security;

-- Read follows the parent event, as event_courses does: the subquery is itself
-- filtered by the events SELECT policy. No client writes it; the snapshot is
-- the server's.
create policy race_session_courses_visible_with_event
  on public.race_session_courses for select
  using (exists (select 1 from public.events e where e.id = race_session_courses.event_id));

grant select on public.race_session_courses to anon;
grant select on public.race_session_courses to authenticated;
grant select, insert, update, delete on public.race_session_courses to service_role;

-- Freeze one session's courses. Called when a session is created (Arm, for
-- Host GO); a later start mode that opens a window calls it at window open.
-- A second call replaces the copy, so the caller decides when it may move.
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
    finish_lat, finish_lng, distance_m, finish_line_self_cross
  )
  select
    p_event_id, p_instance_start, c.id,
    c.start_gate_lat, c.start_gate_lng, c.start_gate_bearing_deg, c.start_gate_half_width_m,
    c.finish_gate_lat, c.finish_gate_lng, c.finish_gate_bearing_deg, c.finish_gate_half_width_m,
    c.finish_lat, c.finish_lng, c.distance_m, c.finish_line_self_cross
  from event_courses c
  where c.event_id = p_event_id;

  update race_sessions
     set courses_frozen_at = now()
   where event_id = p_event_id and instance_start = p_instance_start;
end;
$$;

revoke execute on function private.snapshot_race_session_courses(uuid, timestamptz)
  from public, anon, authenticated;

create or replace function public.race_sessions_freeze_courses()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform private.snapshot_race_session_courses(new.event_id, new.instance_start);
  return null;
end;
$$;

revoke execute on function public.race_sessions_freeze_courses() from public, anon, authenticated;

create trigger race_sessions_freeze_courses_trg
  after insert on public.race_sessions
  for each row execute function public.race_sessions_freeze_courses();

-- courses_frozen_at is the server's: a client cannot set or clear it. A
-- trusted caller (the snapshot, the service role, direct SQL) writes it.
create or replace function public.race_sessions_guard_frozen_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if current_user in ('anon', 'authenticated') then
    if tg_op = 'INSERT' then
      new.courses_frozen_at := null;
    else
      new.courses_frozen_at := old.courses_frozen_at;
    end if;
  end if;
  return new;
end;
$$;

revoke execute on function public.race_sessions_guard_frozen_at() from public, anon, authenticated;

create trigger race_sessions_guard_frozen_at_trg
  before insert or update on public.race_sessions
  for each row execute function public.race_sessions_guard_frozen_at();

-- The spectator read surface gains the frozen-copy link, appended so the
-- existing columns keep their order (create or replace view requires it).
create or replace view public.race_sessions_redacted as
select
  event_id,
  instance_start,
  status,
  started_at,
  finished_at,
  created_at,
  updated_at,
  case
    when private.is_club_admin(
      (select club_id from events where id = race_sessions.event_id)
    ) then started_by
    else null
  end as started_by,
  case
    when private.is_club_admin(
      (select club_id from events where id = race_sessions.event_id)
    ) then is_auto_approve
    else null
  end as is_auto_approve,
  courses_frozen_at
from race_sessions;

alter view public.race_sessions_redacted set (security_invoker = on);

revoke all on public.race_sessions_redacted from public, anon, authenticated;
grant select on public.race_sessions_redacted to anon, authenticated;

-- ─── backfill ──────────────────────────────────────────────────────────────

-- Every course with a route takes its derived lines.
select private.refresh_event_course_endpoints(array(
  select distinct c.route_id from public.event_courses c where c.route_id is not null
));

-- A session already armed or running freezes what its courses hold now, which
-- is what its devices were reading.
select private.snapshot_race_session_courses(s.event_id, s.instance_start)
from public.race_sessions s
where s.status in ('armed', 'running');

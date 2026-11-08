-- Catalogue segments timed by a start line and an end line (#1308, timing
-- lines phase 5, decisions § 2402).
--
--   * global_segments.start_gate_* / end_gate_* hold each line in
--     gate_crossing v1's shape (§ 2377): a centre, a direction of travel in
--     [0, 360), a reach of 5-100 m each side, and a `source`: `derived` from
--     the segment's own polyline, or placed by a `curator`.
--   * Derived lines sit on the polyline's first point facing the point about
--     25 m along it, and on its last point facing from the point about 25 m
--     before it, with the segment reach GATE_HALF_WIDTH_SEGMENT_M (15 m). They
--     reuse private.course_end_bearing, the course derivation of § 2390, so a
--     course and a segment place a line the same way. An end with under about
--     10 m of readable line gets no line. The catalogue is curated public
--     geometry, so there is no privacy clip (a course derives from the clipped
--     route because the route is someone's own, § 1848).
--   * A curator overrides an end by writing its five columns with source
--     `curator` (the table's admin-only write policies apply; no RPC is
--     needed because nobody but a curator can write the row at all), and
--     resets it by writing source `derived`. A curator's line is never
--     recomputed, not even when the polyline is redrawn.
--   * A park course is one catalogue segment (§ 2383), so it inherits these
--     lines with no column of its own; its checkpoints still apply between
--     the start and end crossings.
--   * global_segment_efforts.matched_by: `gate` when the effort was timed
--     between the two lines, `zone` when by the 35 m circles (a segment with
--     no usable pair of lines, and every effort written before this). Added
--     `not null default 'zone'`, catalogue-only, with no backfill: every
--     existing effort WAS matched by the circles (m10).
--   * record_segment_match writes matched_by from the payload, `zone` when the
--     payload predates it.
--
-- Locks (docs/backend/migration_locks.md): the new columns are nullable, or
-- NOT NULL with a constant default, which is catalogue-only. Every CHECK lands
-- NOT VALID and is validated by 20271122002403 in its own transaction. CREATE
-- TRIGGER on global_segments is SHARE ROW EXCLUSIVE for an instant. The
-- derivation backfill rewrites global_segments, a small curated table; it
-- never touches global_segment_efforts.

set search_path = public;

-- ─── global_segments columns ───────────────────────────────────────────────

alter table public.global_segments
  add column start_gate_lat double precision,
  add column start_gate_lng double precision,
  add column start_gate_bearing_deg double precision,
  add column start_gate_half_width_m double precision,
  add column start_gate_source text,
  add column end_gate_lat double precision,
  add column end_gate_lng double precision,
  add column end_gate_bearing_deg double precision,
  add column end_gate_half_width_m double precision,
  add column end_gate_source text;

alter table public.global_segments
  add constraint global_segments_start_gate_lat_check
    check (start_gate_lat is null or start_gate_lat between -90 and 90) not valid,
  add constraint global_segments_start_gate_lng_check
    check (start_gate_lng is null or start_gate_lng between -180 and 180) not valid,
  add constraint global_segments_start_gate_bearing_deg_check
    check (start_gate_bearing_deg is null
           or (start_gate_bearing_deg >= 0 and start_gate_bearing_deg < 360)) not valid,
  add constraint global_segments_start_gate_half_width_m_check
    check (start_gate_half_width_m is null
           or start_gate_half_width_m between 5 and 100) not valid,
  add constraint global_segments_start_gate_source_check
    check (start_gate_source in ('derived', 'curator')) not valid,
  add constraint global_segments_start_gate_complete_check
    check (num_nulls(start_gate_lat, start_gate_lng, start_gate_bearing_deg,
                     start_gate_half_width_m, start_gate_source) in (0, 5)) not valid,
  add constraint global_segments_end_gate_lat_check
    check (end_gate_lat is null or end_gate_lat between -90 and 90) not valid,
  add constraint global_segments_end_gate_lng_check
    check (end_gate_lng is null or end_gate_lng between -180 and 180) not valid,
  add constraint global_segments_end_gate_bearing_deg_check
    check (end_gate_bearing_deg is null
           or (end_gate_bearing_deg >= 0 and end_gate_bearing_deg < 360)) not valid,
  add constraint global_segments_end_gate_half_width_m_check
    check (end_gate_half_width_m is null
           or end_gate_half_width_m between 5 and 100) not valid,
  add constraint global_segments_end_gate_source_check
    check (end_gate_source in ('derived', 'curator')) not valid,
  add constraint global_segments_end_gate_complete_check
    check (num_nulls(end_gate_lat, end_gate_lng, end_gate_bearing_deg,
                     end_gate_half_width_m, end_gate_source) in (0, 5)) not valid;

-- ─── global_segment_efforts.matched_by ─────────────────────────────────────

alter table public.global_segment_efforts
  add column matched_by text not null default 'zone';

alter table public.global_segment_efforts
  add constraint global_segment_efforts_matched_by_check
    check (matched_by in ('zone', 'gate')) not valid;

-- ─── derivation ────────────────────────────────────────────────────────────

-- The readable points of a catalogue polyline as [[lat, lng], ...], the shape
-- private.course_end_bearing takes. An element is read exactly as
-- private.waypoints_box reads it (a JSON number or a numeric string, in
-- range), and one that is not is skipped, so a malformed row gets fewer
-- points or none rather than failing the write.
create or replace function private.global_segment_line(p_waypoints jsonb)
returns jsonb
language sql
immutable
parallel safe
set search_path = pg_catalog
as $$
  select coalesce(jsonb_agg(jsonb_build_array(p.lat, p.lng) order by p.ord), '[]'::jsonb)
    from (
      select
        w.ord,
        case
          when jsonb_typeof(w.value -> 'lat') = 'number'
            or (w.value ->> 'lat') ~ '^\s*-?[0-9]+(\.[0-9]+)?\s*$'
            then (w.value ->> 'lat')::double precision
        end as lat,
        case
          when jsonb_typeof(w.value -> 'lng') = 'number'
            or (w.value ->> 'lng') ~ '^\s*-?[0-9]+(\.[0-9]+)?\s*$'
            then (w.value ->> 'lng')::double precision
        end as lng
        from jsonb_array_elements(
               case when jsonb_typeof(p_waypoints) = 'array' then p_waypoints else '[]'::jsonb end
             ) with ordinality w(value, ord)
       where jsonb_typeof(w.value) = 'object'
    ) p
   where p.lat between -90 and 90
     and p.lng between -180 and 180;
$$;

revoke execute on function private.global_segment_line(jsonb) from public, anon, authenticated;

-- Fills every end whose source is `derived` or unset with the derived line,
-- or none. Any other source is left for the CHECK to judge, so a mistyped
-- source is refused rather than quietly reset. A curator's bearing is wrapped into [0, 360) so a curator can type
-- -90 or 450; every other value is left to the CHECKs. SECURITY DEFINER
-- because the derivation helpers are not executable by `authenticated`, the
-- role an admin's write arrives as.
create or replace function public.global_segments_set_gates()
returns trigger
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  c_half_width constant double precision := 15;
  v_line jsonb;
  v_n int;
  v_bearing double precision;
begin
  if coalesce(new.start_gate_source, 'derived') = 'derived'
     or coalesce(new.end_gate_source, 'derived') = 'derived' then
    v_line := private.global_segment_line(new.waypoints);
    v_n := jsonb_array_length(v_line);
  end if;

  if new.start_gate_source = 'curator' then
    new.start_gate_bearing_deg := ((new.start_gate_bearing_deg::numeric % 360 + 360) % 360)::float8;
  elsif coalesce(new.start_gate_source, 'derived') = 'derived' then
    v_bearing := case when v_n >= 2 then private.course_end_bearing(v_line, false) end;
    if v_bearing is not null then
      new.start_gate_lat := (v_line -> 0 ->> 0)::float8;
      new.start_gate_lng := (v_line -> 0 ->> 1)::float8;
      new.start_gate_bearing_deg := v_bearing;
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

  if new.end_gate_source = 'curator' then
    new.end_gate_bearing_deg := ((new.end_gate_bearing_deg::numeric % 360 + 360) % 360)::float8;
  elsif coalesce(new.end_gate_source, 'derived') = 'derived' then
    v_bearing := case when v_n >= 2 then private.course_end_bearing(v_line, true) end;
    if v_bearing is not null then
      new.end_gate_lat := (v_line -> (v_n - 1) ->> 0)::float8;
      new.end_gate_lng := (v_line -> (v_n - 1) ->> 1)::float8;
      new.end_gate_bearing_deg := v_bearing;
      new.end_gate_half_width_m := c_half_width;
      new.end_gate_source := 'derived';
    else
      new.end_gate_lat := null;
      new.end_gate_lng := null;
      new.end_gate_bearing_deg := null;
      new.end_gate_half_width_m := null;
      new.end_gate_source := null;
    end if;
  end if;

  return new;
end;
$$;

revoke execute on function public.global_segments_set_gates() from public, anon, authenticated;

drop trigger if exists global_segments_set_gates_trg on public.global_segments;
create trigger global_segments_set_gates_trg
  before insert or update on public.global_segments
  for each row execute function public.global_segments_set_gates();

-- Every existing segment takes its derived lines. A no-op assignment is
-- enough: the trigger derives every non-curator end.
update public.global_segments set start_gate_source = start_gate_source;

-- ─── record_segment_match writes matched_by ────────────────────────────────
--
-- 20271117002392's body, with `matched_by` read from each effort and written
-- on insert and on correction. A payload without it (a processor deployed
-- before this migration) is a circle match, which is what that processor ran.

create or replace function public.record_segment_match(
  p_run_id uuid,
  p_track_version text,
  p_min_lat double precision,
  p_min_lng double precision,
  p_max_lat double precision,
  p_max_lng double precision,
  p_candidates uuid[],
  p_efforts jsonb
)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid;
  v_track_url text;
begin
  if p_efforts is null or jsonb_typeof(p_efforts) <> 'array' then
    raise exception 'record_segment_match: p_efforts must be an array' using errcode = '22023';
  end if;

  select r.user_id, r.track_url into v_user_id, v_track_url
    from public.runs r
   where r.id = p_run_id
   for share;
  if not found then
    return 'missing';
  end if;

  if v_track_url is null
     or p_track_version is null
     or public.runs_track_object_version(v_track_url) is distinct from p_track_version then
    return 'stale';
  end if;

  insert into public.run_track_extents (run_id, track_version, min_lat, min_lng, max_lat, max_lng, scored_at)
  values (p_run_id, p_track_version, p_min_lat, p_min_lng, p_max_lat, p_max_lng, now())
  on conflict (run_id) do update
     set track_version = excluded.track_version,
         min_lat = excluded.min_lat,
         min_lng = excluded.min_lng,
         max_lat = excluded.max_lat,
         max_lng = excluded.max_lng,
         scored_at = excluded.scored_at;

  delete from public.global_segment_efforts e
   where e.run_id = p_run_id
     and e.global_segment_id = any (coalesce(p_candidates, '{}'::uuid[]))
     and not exists (
       select 1 from jsonb_array_elements(p_efforts) m
        where m ->> 'global_segment_id' = e.global_segment_id::text
     );

  insert into public.global_segment_efforts
    (global_segment_id, run_id, user_id, time_seconds, started_at, matched_by)
  select gs.id, p_run_id, v_user_id, (m ->> 'time_seconds')::numeric, (m ->> 'started_at')::timestamptz,
         coalesce(m ->> 'matched_by', 'zone')
    from jsonb_array_elements(p_efforts) m
    join public.global_segments gs
      on gs.id = (m ->> 'global_segment_id')::uuid
     and gs.is_active = true
   where gs.id = any (coalesce(p_candidates, '{}'::uuid[]))
  on conflict (global_segment_id, run_id) do update
     set time_seconds = excluded.time_seconds,
         started_at = excluded.started_at,
         matched_by = excluded.matched_by;

  return 'recorded';
end;
$$;

revoke execute on function public.record_segment_match(uuid, text, double precision, double precision, double precision, double precision, uuid[], jsonb)
  from public, anon, authenticated;
grant execute on function public.record_segment_match(uuid, text, double precision, double precision, double precision, double precision, uuid[], jsonb)
  to service_role;

-- The park catalogue loads itself on every backend release (issue #1349,
-- decisions § 2429), so `private.load_park_catalogue` becomes safe to call
-- with an unchanged catalogue, any number of times.
--
-- The body is 20271126002425's, with four changes:
--
--   * `unchanged`: every write is an UPDATE guarded by `is distinct from`
--     against what is stored, and the park upsert's `do update` carries the
--     same guard, so a course whose segment, route and course row already
--     match the payload writes nothing and reports `unchanged`. A course with
--     any difference reports `updated`.
--   * Backfill on change only: `p_enqueue_backfill` now queues
--     `enqueue_segment_backfill` for a course that was `created`, or whose
--     matching geometry changed: the segment line, either start or end line
--     (curator values, or a curator line going back to derived), or the
--     checkpoints. A metadata change (name, description, difficulty, source)
--     queues nothing, because the matcher would score every run the same way.
--   * `closed`: a course of the park the payload no longer names is set
--     `status = 'closed'` with the note `c_removed_note`, never deleted, so its
--     segment and every effort on it stay. It is reported once, on the load
--     that closes it; a course already closed (by this or by an operator) is
--     left alone and not reported.
--   * Reopening: a course the payload names again whose status is the closure
--     this function wrote (status `closed` and note `c_removed_note`) goes back
--     to `open` and reports `updated`. Any other status, an operator's closure
--     included, is still never written.
--
-- The function now runs with `timezone = UTC`, so `source_checked_at`
-- ('YYYY-MM-DD') casts to the same instant whichever session calls it, and the
-- comparison does not depend on the caller's TimeZone. The hosted project's
-- default is UTC, so rows loaded by the previous body compare equal.
--
-- The return shape is unchanged; `action` gains `unchanged` and `closed`.
--
-- Locks (docs/backend/migration_locks.md): one function replaced in place.

create or replace function private.load_park_catalogue(
  p_manifest jsonb,
  p_club_id uuid,
  p_author_id uuid,
  p_enqueue_backfill boolean default false
)
returns table (
  course_slug text,
  park_course_id uuid,
  global_segment_id uuid,
  route_id uuid,
  action text,
  backfill_job_id bigint
)
language plpgsql
security definer
set search_path = public, private, pg_temp
set timezone = 'UTC'
as $$
#variable_conflict use_column
declare
  c_removed_note constant text := 'Removed from the park catalogue.';
  v_park jsonb := p_manifest -> 'park';
  v_courses jsonb := p_manifest -> 'courses';
  v_attribution text := nullif(btrim(p_manifest ->> 'attribution'), '');
  v_park_id uuid;
  v_course jsonb;
  v_waypoints jsonb;
  v_description text;
  v_checkpoints jsonb;
  v_existing record;
  v_segment_id uuid;
  v_route_id uuid;
  v_course_id uuid;
  v_action text;
  v_geometry_changed boolean;
  v_rows int;
  v_written int;
  v_job bigint;
  v_box record;
  v_start jsonb;
  v_end jsonb;
  v_closed record;
begin
  if not private.is_official_publisher(p_club_id, p_author_id) then
    raise exception 'load_park_catalogue: % is not an active owner or admin of the verified public club %',
      p_author_id, p_club_id
      using errcode = '42501';
  end if;

  if jsonb_typeof(v_park) is distinct from 'object' or nullif(v_park ->> 'slug', '') is null then
    raise exception 'load_park_catalogue: the manifest names no park slug' using errcode = '22023';
  end if;
  if jsonb_typeof(v_courses) is distinct from 'array' or jsonb_array_length(v_courses) = 0 then
    raise exception 'load_park_catalogue: the manifest has no courses' using errcode = '22023';
  end if;
  if v_attribution is null then
    raise exception 'load_park_catalogue: the manifest carries no attribution' using errcode = '22023';
  end if;
  if (select count(distinct c ->> 'slug') from jsonb_array_elements(v_courses) c)
     <> jsonb_array_length(v_courses) then
    raise exception 'load_park_catalogue: course slugs must be present and unique' using errcode = '22023';
  end if;

  for v_course in select * from jsonb_array_elements(v_courses) loop
    v_waypoints := v_course -> 'waypoints';
    if jsonb_typeof(v_waypoints) is distinct from 'array'
       or jsonb_array_length(v_waypoints) < 2
       or jsonb_array_length(private.global_segment_line(v_waypoints)) <> jsonb_array_length(v_waypoints) then
      raise exception 'load_park_catalogue: course % needs at least two waypoints, each a lat and lng in range',
        v_course ->> 'slug'
        using errcode = '22023';
    end if;
    if jsonb_typeof(coalesce(v_course -> 'start_gate', 'null')) not in ('object', 'null')
       or jsonb_typeof(coalesce(v_course -> 'end_gate', 'null')) not in ('object', 'null') then
      raise exception 'load_park_catalogue: course % has a start_gate or end_gate that is not an object',
        v_course ->> 'slug'
        using errcode = '22023';
    end if;
  end loop;

  select min((p ->> 0)::float8) as min_lat, max((p ->> 0)::float8) as max_lat,
         min((p ->> 1)::float8) as min_lng, max((p ->> 1)::float8) as max_lng
    into v_box
    from jsonb_array_elements(v_courses) c,
         jsonb_array_elements(private.global_segment_line(c -> 'waypoints')) p;

  insert into parks as pk (slug, name, description, agency, region_code, country_code, timezone, website_url,
                           centroid_lat, centroid_lng, bbox_min_lat, bbox_min_lng, bbox_max_lat, bbox_max_lng)
  values (
    v_park ->> 'slug', v_park ->> 'name', v_park ->> 'description', v_park ->> 'agency',
    v_park ->> 'region_code', v_park ->> 'country_code', v_park ->> 'timezone', v_park ->> 'website_url',
    (v_box.min_lat + v_box.max_lat) / 2, (v_box.min_lng + v_box.max_lng) / 2,
    v_box.min_lat, v_box.min_lng, v_box.max_lat, v_box.max_lng
  )
  on conflict (slug) do update set
    name = excluded.name,
    description = coalesce(excluded.description, pk.description),
    agency = excluded.agency,
    region_code = excluded.region_code,
    country_code = excluded.country_code,
    timezone = excluded.timezone,
    website_url = excluded.website_url,
    centroid_lat = excluded.centroid_lat,
    centroid_lng = excluded.centroid_lng,
    bbox_min_lat = excluded.bbox_min_lat,
    bbox_min_lng = excluded.bbox_min_lng,
    bbox_max_lat = excluded.bbox_max_lat,
    bbox_max_lng = excluded.bbox_max_lng
  where (pk.name, pk.description, pk.agency, pk.region_code, pk.country_code, pk.timezone, pk.website_url,
         pk.centroid_lat, pk.centroid_lng, pk.bbox_min_lat, pk.bbox_min_lng, pk.bbox_max_lat, pk.bbox_max_lng)
        is distinct from
        (excluded.name, coalesce(excluded.description, pk.description), excluded.agency, excluded.region_code,
         excluded.country_code, excluded.timezone, excluded.website_url,
         excluded.centroid_lat, excluded.centroid_lng, excluded.bbox_min_lat, excluded.bbox_min_lng,
         excluded.bbox_max_lat, excluded.bbox_max_lng)
  returning pk.id into v_park_id;

  -- The guarded `do update` returns no row when nothing differed.
  if v_park_id is null then
    select pk.id into v_park_id from parks pk where pk.slug = v_park ->> 'slug';
  end if;

  for v_course in select * from jsonb_array_elements(v_courses) loop
    v_description := concat_ws(E'\n\n', nullif(btrim(v_course ->> 'description'), ''), v_attribution);
    v_checkpoints := coalesce(v_course -> 'checkpoints', jsonb_build_array());
    v_start := nullif(v_course -> 'start_gate', 'null'::jsonb);
    v_end := nullif(v_course -> 'end_gate', 'null'::jsonb);
    v_written := 0;

    select pc.id, pc.global_segment_id, pc.route_id, pc.checkpoints, pc.status, pc.status_note,
           gs.waypoints,
           gs.start_gate_source, gs.start_gate_lat, gs.start_gate_lng,
           gs.start_gate_bearing_deg, gs.start_gate_half_width_m,
           gs.end_gate_source, gs.end_gate_lat, gs.end_gate_lng,
           gs.end_gate_bearing_deg, gs.end_gate_half_width_m
      into v_existing
      from park_courses pc
      join global_segments gs on gs.id = pc.global_segment_id
     where pc.park_id = v_park_id and pc.slug = v_course ->> 'slug'
       for update of pc, gs;

    if found then
      v_action := 'updated';
      v_course_id := v_existing.id;
      v_segment_id := v_existing.global_segment_id;

      -- A derived end is compared by its source only: the gates trigger
      -- derives its values from the line, which is compared on its own. A
      -- curator end is compared value for value, its bearing wrapped the way
      -- the trigger stores it.
      v_geometry_changed :=
        v_existing.waypoints is distinct from v_course -> 'waypoints'
        or v_existing.checkpoints is distinct from v_checkpoints
        or case
             when v_start is null then coalesce(v_existing.start_gate_source, 'derived') <> 'derived'
             else (v_existing.start_gate_source, v_existing.start_gate_lat, v_existing.start_gate_lng,
                   v_existing.start_gate_bearing_deg, v_existing.start_gate_half_width_m)
                  is distinct from
                  ('curator'::text, (v_start ->> 'lat')::float8, (v_start ->> 'lng')::float8,
                   (((v_start ->> 'bearing_deg')::numeric % 360 + 360) % 360)::float8,
                   (v_start ->> 'half_width_m')::float8)
           end
        or case
             when v_end is null then coalesce(v_existing.end_gate_source, 'derived') <> 'derived'
             else (v_existing.end_gate_source, v_existing.end_gate_lat, v_existing.end_gate_lng,
                   v_existing.end_gate_bearing_deg, v_existing.end_gate_half_width_m)
                  is distinct from
                  ('curator'::text, (v_end ->> 'lat')::float8, (v_end ->> 'lng')::float8,
                   (((v_end ->> 'bearing_deg')::numeric % 360 + 360) % 360)::float8,
                   (v_end ->> 'half_width_m')::float8)
           end;

      update global_segments gs set
        name = v_course ->> 'name',
        description = v_description,
        waypoints = v_course -> 'waypoints',
        distance_m = (v_course ->> 'distance_m')::numeric,
        elevation_m = (v_course ->> 'elevation_m')::numeric,
        surface = v_course ->> 'surface',
        region = p_manifest ->> 'region',
        country_code = v_park ->> 'country_code',
        start_gate_lat = (v_start ->> 'lat')::float8,
        start_gate_lng = (v_start ->> 'lng')::float8,
        start_gate_bearing_deg = (v_start ->> 'bearing_deg')::float8,
        start_gate_half_width_m = (v_start ->> 'half_width_m')::float8,
        start_gate_source = case when v_start is null then 'derived' else 'curator' end,
        end_gate_lat = (v_end ->> 'lat')::float8,
        end_gate_lng = (v_end ->> 'lng')::float8,
        end_gate_bearing_deg = (v_end ->> 'bearing_deg')::float8,
        end_gate_half_width_m = (v_end ->> 'half_width_m')::float8,
        end_gate_source = case when v_end is null then 'derived' else 'curator' end
       where gs.id = v_segment_id
         and (v_geometry_changed
              or (gs.name, gs.description, gs.distance_m, gs.elevation_m, gs.surface, gs.region, gs.country_code)
                 is distinct from
                 (v_course ->> 'name', v_description, (v_course ->> 'distance_m')::numeric,
                  (v_course ->> 'elevation_m')::numeric, v_course ->> 'surface', p_manifest ->> 'region',
                  v_park ->> 'country_code'));
      get diagnostics v_rows = row_count;
      v_written := v_written + v_rows;
      v_route_id := v_existing.route_id;
    else
      v_action := 'created';
      v_geometry_changed := true;
      v_course_id := null;
      insert into global_segments (name, description, waypoints, distance_m, elevation_m, surface, region,
                                   country_code, created_by,
                                   start_gate_lat, start_gate_lng, start_gate_bearing_deg,
                                   start_gate_half_width_m, start_gate_source,
                                   end_gate_lat, end_gate_lng, end_gate_bearing_deg,
                                   end_gate_half_width_m, end_gate_source)
      values (
        v_course ->> 'name', v_description, v_course -> 'waypoints', (v_course ->> 'distance_m')::numeric,
        (v_course ->> 'elevation_m')::numeric, v_course ->> 'surface', p_manifest ->> 'region',
        v_park ->> 'country_code', p_author_id,
        (v_start ->> 'lat')::float8, (v_start ->> 'lng')::float8, (v_start ->> 'bearing_deg')::float8,
        (v_start ->> 'half_width_m')::float8, case when v_start is null then 'derived' else 'curator' end,
        (v_end ->> 'lat')::float8, (v_end ->> 'lng')::float8, (v_end ->> 'bearing_deg')::float8,
        (v_end ->> 'half_width_m')::float8, case when v_end is null then 'derived' else 'curator' end
      )
      returning id into v_segment_id;
      v_route_id := null;
    end if;

    if v_route_id is not null then
      update routes r set
        user_id = p_author_id,
        club_id = p_club_id,
        name = v_course ->> 'name',
        description = v_description,
        waypoints = v_course -> 'waypoints',
        distance_m = (v_course ->> 'distance_m')::numeric,
        elevation_m = (v_course ->> 'elevation_m')::numeric,
        official_distance_m = (v_course ->> 'official_distance_m')::numeric,
        surface = v_course ->> 'surface',
        is_public = true,
        updated_at = now()
       where r.id = v_route_id
         and (r.user_id, r.club_id, r.name, r.description, r.waypoints, r.distance_m, r.elevation_m,
              r.official_distance_m, r.surface, r.is_public)
             is distinct from
             (p_author_id, p_club_id, v_course ->> 'name', v_description, v_course -> 'waypoints',
              (v_course ->> 'distance_m')::numeric, (v_course ->> 'elevation_m')::numeric,
              (v_course ->> 'official_distance_m')::numeric, v_course ->> 'surface', true);
      get diagnostics v_rows = row_count;
      v_written := v_written + v_rows;
    else
      insert into routes (user_id, club_id, name, description, waypoints, distance_m, elevation_m,
                          official_distance_m, surface, is_public)
      values (
        p_author_id, p_club_id, v_course ->> 'name', v_description, v_course -> 'waypoints',
        (v_course ->> 'distance_m')::numeric, (v_course ->> 'elevation_m')::numeric,
        (v_course ->> 'official_distance_m')::numeric, v_course ->> 'surface', true
      )
      returning id into v_route_id;
      v_written := v_written + 1;
    end if;

    if v_course_id is not null then
      update park_courses pc set
        route_id = v_route_id,
        course_shape = v_course ->> 'course_shape',
        geometry_source = v_course ->> 'geometry_source',
        source_ref = v_course ->> 'source_ref',
        source_checked_at = (v_course ->> 'source_checked_at')::timestamptz,
        difficulty = v_course ->> 'difficulty',
        checkpoints = v_checkpoints,
        status = case when pc.status = 'closed' and pc.status_note = c_removed_note then 'open' else pc.status end,
        status_note = case when pc.status = 'closed' and pc.status_note = c_removed_note then null
                           else pc.status_note end,
        status_checked_at = case when pc.status = 'closed' and pc.status_note = c_removed_note then now()
                                 else pc.status_checked_at end
       where pc.id = v_course_id
         and ((pc.route_id, pc.course_shape, pc.geometry_source, pc.source_ref, pc.source_checked_at,
               pc.difficulty, pc.checkpoints)
              is distinct from
              (v_route_id, v_course ->> 'course_shape', v_course ->> 'geometry_source', v_course ->> 'source_ref',
               (v_course ->> 'source_checked_at')::timestamptz, v_course ->> 'difficulty', v_checkpoints)
              or (pc.status = 'closed' and pc.status_note = c_removed_note));
      get diagnostics v_rows = row_count;
      v_written := v_written + v_rows;
      if v_written = 0 then
        v_action := 'unchanged';
      end if;
    else
      insert into park_courses (park_id, global_segment_id, route_id, slug, course_shape, geometry_source,
                                source_ref, source_checked_at, difficulty, checkpoints)
      values (
        v_park_id, v_segment_id, v_route_id, v_course ->> 'slug', v_course ->> 'course_shape',
        v_course ->> 'geometry_source', v_course ->> 'source_ref',
        (v_course ->> 'source_checked_at')::timestamptz, v_course ->> 'difficulty', v_checkpoints
      )
      returning id into v_course_id;
    end if;

    v_job := case when p_enqueue_backfill and v_geometry_changed
                  then public.enqueue_segment_backfill(v_segment_id) end;

    course_slug := v_course ->> 'slug';
    park_course_id := v_course_id;
    global_segment_id := v_segment_id;
    route_id := v_route_id;
    action := v_action;
    backfill_job_id := v_job;
    return next;
  end loop;

  for v_closed in
    update park_courses pc set
      status = 'closed',
      status_note = c_removed_note,
      status_checked_at = now()
     where pc.park_id = v_park_id
       and pc.status <> 'closed'
       and not exists (select 1 from jsonb_array_elements(v_courses) c where c ->> 'slug' = pc.slug)
    returning pc.slug, pc.id, pc.global_segment_id, pc.route_id
  loop
    course_slug := v_closed.slug;
    park_course_id := v_closed.id;
    global_segment_id := v_closed.global_segment_id;
    route_id := v_closed.route_id;
    action := 'closed';
    backfill_job_id := null;
    return next;
  end loop;
end;
$$;

comment on function private.load_park_catalogue(jsonb, uuid, uuid, boolean) is
  'Upserts one park and its courses (catalogue segment, park_courses row, public official route) from the '
  'payload scripts/parks/load.mjs and sync.mjs print, updating existing rows in place so ids and efforts survive. '
  'Idempotent: a course that already matches reports unchanged and writes nothing; the backfill flag queues a '
  'backfill only for a created course or changed matching geometry; a course the payload no longer names is '
  'closed, never deleted. Service role only; refuses an author who is not an official publisher of the club '
  '(decisions § 2425, § 2429).';

revoke execute on function private.load_park_catalogue(jsonb, uuid, uuid, boolean) from public, anon, authenticated;
grant execute on function private.load_park_catalogue(jsonb, uuid, uuid, boolean) to service_role;

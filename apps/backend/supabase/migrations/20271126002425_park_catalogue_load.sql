-- The operator load of a park's reviewed course catalogue (issue #1342 step 1,
-- decisions § 2425).
--
-- `scripts/parks/load.mjs` turns a park's committed `manifest.json` and its
-- course GeoJSON into ONE call of this function, which the operator runs as
-- the service role. The load logic lives here, once, so a later sync job can
-- call the same function rather than re-implement it.
--
-- One transaction, keyed so a re-run never duplicates anything:
--
--   * the park by `slug`, with its centroid and bounding box taken from every
--     course line in the payload;
--   * each course by (park, course slug): its catalogue segment, the
--     `park_courses` row and the public official route are UPDATED IN PLACE
--     when the course already exists, so their ids, and every effort on the
--     segment, survive a re-run with changed geometry. A course whose route
--     was deleted (`route_id` set null by its FK) gets a new route.
--   * Status and `is_active` are never written on an existing row: closures
--     are an operator or a closures-job decision, not the geometry's.
--   * A course the payload no longer names is left alone.
--
-- The route is official because its author must be an active owner or admin
-- of the verified, public club (`private.is_official_publisher`, § 2228); the
-- function refuses otherwise, before writing anything. The segment's lines
-- are derived from the new polyline by `global_segments_set_gates_trg`
-- (§ 2402); a curator's line is kept, as that trigger always does.
--
-- `p_enqueue_backfill` also queues `enqueue_segment_backfill` for every
-- course. It defaults off: the launch backfill is a separate operator step.
--
-- `park_courses.source_ref` lists every OSM way a course follows. A
-- race-distance course over a trail network names 40 to 60 of them (the Swift
-- Creek 50K's list is 782 characters), past the 500 the column was created
-- with, so its length CHECK is widened to 8000.
--
-- Locks (docs/backend/migration_locks.md): the CHECK is replaced in one step,
-- a brief ACCESS EXCLUSIVE and a scan of `park_courses`, a small curated table
-- outside the guarded set. Otherwise one new function and its grants.

alter table public.park_courses
  drop constraint park_courses_source_ref_len_chk,
  add constraint park_courses_source_ref_len_chk
    check (source_ref is null or length(source_ref) <= 8000);

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
as $$
#variable_conflict use_column
declare
  v_park jsonb := p_manifest -> 'park';
  v_courses jsonb := p_manifest -> 'courses';
  v_attribution text := nullif(btrim(p_manifest ->> 'attribution'), '');
  v_park_id uuid;
  v_course jsonb;
  v_waypoints jsonb;
  v_description text;
  v_existing record;
  v_segment_id uuid;
  v_route_id uuid;
  v_course_id uuid;
  v_action text;
  v_job bigint;
  v_box record;
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
  returning pk.id into v_park_id;

  for v_course in select * from jsonb_array_elements(v_courses) loop
    v_description := concat_ws(E'\n\n', nullif(btrim(v_course ->> 'description'), ''), v_attribution);

    select pc.id, pc.global_segment_id, pc.route_id into v_existing
      from park_courses pc
     where pc.park_id = v_park_id and pc.slug = v_course ->> 'slug'
       for update;

    if found then
      v_action := 'updated';
      v_course_id := v_existing.id;
      v_segment_id := v_existing.global_segment_id;
      update global_segments gs set
        name = v_course ->> 'name',
        description = v_description,
        waypoints = v_course -> 'waypoints',
        distance_m = (v_course ->> 'distance_m')::numeric,
        elevation_m = (v_course ->> 'elevation_m')::numeric,
        surface = v_course ->> 'surface',
        region = p_manifest ->> 'region',
        country_code = v_park ->> 'country_code'
       where gs.id = v_segment_id;
      v_route_id := v_existing.route_id;
    else
      v_action := 'created';
      v_course_id := null;
      insert into global_segments (name, description, waypoints, distance_m, elevation_m, surface, region,
                                   country_code, created_by)
      values (
        v_course ->> 'name', v_description, v_course -> 'waypoints', (v_course ->> 'distance_m')::numeric,
        (v_course ->> 'elevation_m')::numeric, v_course ->> 'surface', p_manifest ->> 'region',
        v_park ->> 'country_code', p_author_id
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
       where r.id = v_route_id;
    else
      insert into routes (user_id, club_id, name, description, waypoints, distance_m, elevation_m,
                          official_distance_m, surface, is_public)
      values (
        p_author_id, p_club_id, v_course ->> 'name', v_description, v_course -> 'waypoints',
        (v_course ->> 'distance_m')::numeric, (v_course ->> 'elevation_m')::numeric,
        (v_course ->> 'official_distance_m')::numeric, v_course ->> 'surface', true
      )
      returning id into v_route_id;
    end if;

    if v_course_id is not null then
      update park_courses pc set
        route_id = v_route_id,
        course_shape = v_course ->> 'course_shape',
        geometry_source = v_course ->> 'geometry_source',
        source_ref = v_course ->> 'source_ref',
        source_checked_at = (v_course ->> 'source_checked_at')::timestamptz,
        difficulty = v_course ->> 'difficulty',
        checkpoints = coalesce(v_course -> 'checkpoints', jsonb_build_array())
       where pc.id = v_course_id;
    else
      insert into park_courses (park_id, global_segment_id, route_id, slug, course_shape, geometry_source,
                                source_ref, source_checked_at, difficulty, checkpoints)
      values (
        v_park_id, v_segment_id, v_route_id, v_course ->> 'slug', v_course ->> 'course_shape',
        v_course ->> 'geometry_source', v_course ->> 'source_ref',
        (v_course ->> 'source_checked_at')::timestamptz, v_course ->> 'difficulty',
        coalesce(v_course -> 'checkpoints', jsonb_build_array())
      )
      returning id into v_course_id;
    end if;

    v_job := case when p_enqueue_backfill then public.enqueue_segment_backfill(v_segment_id) end;

    course_slug := v_course ->> 'slug';
    park_course_id := v_course_id;
    global_segment_id := v_segment_id;
    route_id := v_route_id;
    action := v_action;
    backfill_job_id := v_job;
    return next;
  end loop;
end;
$$;

comment on function private.load_park_catalogue(jsonb, uuid, uuid, boolean) is
  'Upserts one park and its courses (catalogue segment, park_courses row, public official route) from the '
  'payload scripts/parks/load.mjs prints, updating existing rows in place so ids and efforts survive. '
  'Service role only; refuses an author who is not an official publisher of the club (decisions § 2425).';

revoke execute on function private.load_park_catalogue(jsonb, uuid, uuid, boolean) from public, anon, authenticated;
grant execute on function private.load_park_catalogue(jsonb, uuid, uuid, boolean) to service_role;

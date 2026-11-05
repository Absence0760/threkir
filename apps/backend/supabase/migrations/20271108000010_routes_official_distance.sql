-- A route can carry the race's official distance (issue #1291).
--
-- A course traced on street centre lines measures long against its
-- certified distance, because certification measures the shortest legal line
-- with the corners cut: Richmond's traced marathon reads 42.67 km against a
-- certified 42.195 km. routes.official_distance_m holds the certified figure.
-- When it is set every surface shows it as the route's distance, the measured
-- distance_m stays the length of the line, and the km markers and the 3D
-- preview scale distance along the line by official / measured so km 42
-- lands where the race's own sign does. Null means "no official distance":
-- every reader falls back to distance_m.
--
-- Bounds. The CHECK holds the hard range (positive, at most 1,000 km, the
-- bound event_courses.distance_m uses). The tighter rule, within 10% of the
-- measured distance, is not a CHECK: distance_m moves whenever the owner
-- redraws the route, and a constraint across the two columns would refuse
-- that redraw. The edit form and the race-link prefill below apply it.
--
-- Prefill. A race listing's route_id is written by service_role only
-- (20270924000002), and when it links a route that has no official distance
-- yet, the listing's distance becomes the route's official distance, if it is
-- within the same 10%. A listing linked to the wrong route by mistake (a 50 km
-- listing on a marathon course) therefore writes nothing. The owner can clear
-- or change the value afterwards; a cleared value is not prefilled again until
-- the link itself changes.
--
-- Reads. public_routes and shared_routes gain the column at the end, as
-- create or replace view requires (bodies re-emitted from 20271021000030). The
-- race calendar's course_distance_m and the explore map's
-- discoverable_routes_in_bbox return the shown distance, so their column types
-- and names do not change and nothing that reads them needs to. The bbox
-- function's distance bands filter on the same shown distance, so a traced
-- 42.67 km marathon sits in the marathon band beside a certified one.
--
-- Locks. routes is not one of the high-volume tables migration_locks.md
-- names, but the CHECK is added NOT VALID here and validated in
-- 20271108000011 so the scan runs outside this migration's ACCESS EXCLUSIVE.
-- The nullable add-column is a catalogue change.

set search_path = public, extensions;

alter table routes add column official_distance_m numeric;

alter table routes
  add constraint routes_official_distance_m_check
  check (official_distance_m is null or (official_distance_m > 0 and official_distance_m <= 1000000))
  not valid;

create or replace function prefill_route_official_distance()
  returns trigger language plpgsql security invoker
  set search_path = public
as $$
begin
  if new.route_id is not null
     and new.distance_m is not null
     and (tg_op = 'INSERT' or new.route_id is distinct from old.route_id) then
    update routes r
       set official_distance_m = new.distance_m
     where r.id = new.route_id
       and r.official_distance_m is null
       and r.distance_m > 0
       and new.distance_m between r.distance_m * 0.9 and r.distance_m * 1.1;
  end if;
  return null;
end;
$$;

create trigger race_listings_prefill_route_official_distance
  after insert or update of route_id on race_listings
  for each row execute function prefill_route_official_distance();

create or replace view public_routes as
  select
    r.id,
    r.user_id,
    r.name,
    r.distance_m,
    r.elevation_m,
    r.surface,
    r.is_public,
    r.slug,
    r.created_at,
    r.updated_at,
    r.tags,
    r.is_featured,
    r.featured_at,
    r.run_count,
    case when is_public_club_by_id(r.club_id) then r.club_id else null::uuid end as club_id,
    (r.club_id is not null and private.is_official_publisher(r.club_id, r.user_id)) as is_official,
    r.official_distance_m
  from routes r
  where r.is_public = true
    and r.shadow_hidden = false;

create or replace view shared_routes as
  select
    r.id,
    r.user_id,
    r.name,
    r.distance_m,
    r.elevation_m,
    r.surface,
    r.is_public,
    r.slug,
    r.created_at,
    r.updated_at,
    r.tags,
    r.is_featured,
    r.featured_at,
    r.run_count,
    case when is_public_club_by_id(r.club_id) then r.club_id else null::uuid end as club_id,
    (r.club_id is not null and private.is_official_publisher(r.club_id, r.user_id)) as is_official,
    r.official_distance_m
  from routes r
  where r.is_public = false
    and r.shadow_hidden = false
    and private.route_audience_admits(r.id, r.user_id, r.followers_only, (select auth.uid()));

create or replace view public_race_listings as
select
  l.id,
  l.provider,
  l.provider_race_id,
  l.name,
  l.race_date,
  l.distance_m,
  l.location_label,
  l.location_point,
  l.entry_url,
  l.results_url,
  l.is_verified,
  l.created_at,
  l.updated_at,
  coalesce(c.official_distance_m, c.distance_m) as course_distance_m,
  c.elevation_m as course_elevation_m,
  c.surface as course_surface,
  c.id as course_route_id
from race_listings l
left join public_routes c on c.id = l.route_id;

create or replace function discoverable_routes_in_bbox(
  p_min_lng double precision,
  p_min_lat double precision,
  p_max_lng double precision,
  p_max_lat double precision,
  p_limit integer default 100,
  p_filter text default 'popular',
  p_dist_min numeric[] default null,
  p_dist_max numeric[] default null
)
returns table (
  id uuid,
  name text,
  slug text,
  is_featured boolean,
  distance_m numeric,
  elevation_m numeric,
  surface text,
  run_count integer,
  lng double precision,
  lat double precision,
  is_official boolean
)
language sql
stable
parallel safe
security definer
set search_path = public, extensions
as $$
  with bbox as (
    select ST_MakeEnvelope(p_min_lng, p_min_lat, p_max_lng, p_max_lat, 4326) as g
  ),
  in_view as (
    select
      r.id,
      r.name,
      r.slug,
      r.is_featured,
      coalesce(r.official_distance_m, r.distance_m) as distance_m,
      r.elevation_m,
      r.surface,
      r.run_count,
      r.user_id,
      r.created_at,
      r.start_point,
      -- The null test short-circuits the definer call for every clubless
      -- community route in view.
      (r.club_id is not null and private.is_official_publisher(r.club_id, r.user_id)) as is_official
    from routes r, bbox
    where r.is_public = true
      and r.shadow_hidden = false
      and r.start_point is not null
      and r.start_point::geometry && bbox.g
      and (
        p_dist_min is null
        or cardinality(p_dist_min) = 0
        or exists (
          select 1
          from unnest(p_dist_min, p_dist_max) as band(lo, hi)
          where coalesce(r.official_distance_m, r.distance_m) >= band.lo
            and (band.hi is null or coalesce(r.official_distance_m, r.distance_m) < band.hi)
        )
      )
  ),
  lensed as (
    select
      v.*,
      row_number() over (
        partition by v.is_official
        order by v.is_featured desc, v.run_count desc, v.created_at desc, v.id
      ) as official_rank
    from in_view v
    where case p_filter
      when 'official' then v.is_official
      when 'featured' then v.is_featured = true
      when 'friends' then v.user_id in (
        select uf.followee_id from user_follows uf where uf.follower_id = auth.uid()
      )
      when 'hidden_gems' then
        v.is_official = false
        and v.is_featured = false
        and coalesce(v.run_count, 0) = 0
        and v.distance_m >= 1000
      else
        (v.is_official or v.is_featured = true or v.run_count > 0)
    end
  )
  select
    l.id,
    l.name,
    l.slug,
    l.is_featured,
    l.distance_m,
    l.elevation_m,
    l.surface,
    l.run_count,
    ST_X(l.start_point::geometry) as lng,
    ST_Y(l.start_point::geometry) as lat,
    l.is_official
  from lensed l
  order by
    case
      when l.is_official
        and (p_filter = 'official' or l.official_rank <= greatest(1, coalesce(p_limit, 100) / 4))
        then 0
      when not l.is_official then 1
      else 2
    end,
    l.is_featured desc, l.run_count desc, l.created_at desc, l.id
  limit p_limit;
$$;


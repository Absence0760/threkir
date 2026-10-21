-- Discovery ranks official content and verified clubs first (issue #1190 § 4,
-- decisions § 2227).
--
-- discoverable_routes_in_bbox:
--   * an OFFICIAL route (private.is_official_publisher, 20271021000030) always
--     qualifies for a pin under the default `popular` lens, even with no runs
--     and no editorial pick — a verified organiser's course on day one has
--     run_count = 0, and the old `is_featured or run_count > 0` gate hid it;
--   * a new `official` lens returns only official routes;
--   * official routes rank first (then featured, then run_count, as before);
--   * every lens but `official` caps official pins at a quarter of p_limit
--     (25 of the clients' 100). Ranking official first without a cap would let
--     one organiser with a few hundred traced courses in a city fill the whole
--     viewport and hide every community route; a quarter keeps the organiser's
--     courses visible while leaving at least three quarters of the slots to the
--     community whenever the community has that many routes in view. The
--     `official` lens is uncapped because asking for official routes is the
--     point of it;
--   * `hidden_gems` excludes official routes, the way it excludes featured
--     ones: an official route is always surfaced by `popular`, so it is not
--     hidden.
--   * the row gains `is_official` so the pin and list can carry the badge.
--
-- clubs_in_bbox ranks verified clubs above unverified ones (then member_count
-- as before), so a large fan club no longer outranks the new official one, and
-- returns `is_verified` for the pin's badge.
--
-- Both return types grow a column, so the old signatures are dropped first;
-- the drop takes the grants with it, so they are restated.
--
-- Locks: function DDL only — no table lock, scan or rewrite.

drop function if exists discoverable_routes_in_bbox(
  double precision, double precision, double precision, double precision,
  integer, text, numeric[], numeric[]
);
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
      r.distance_m,
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
          where r.distance_m >= band.lo
            and (band.hi is null or r.distance_m < band.hi)
        )
      )
  ),
  lensed as (
    select
      v.*,
      row_number() over (
        partition by v.is_official
        order by v.is_featured desc, v.run_count desc, v.created_at desc
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
  where p_filter = 'official'
    or l.is_official = false
    or l.official_rank <= greatest(1, coalesce(p_limit, 100) / 4)
  order by l.is_official desc, l.is_featured desc, l.run_count desc, l.created_at desc
  limit p_limit;
$$;

grant execute on function discoverable_routes_in_bbox(
  double precision, double precision, double precision, double precision,
  integer, text, numeric[], numeric[]
) to anon, authenticated;

drop function if exists clubs_in_bbox(
  double precision, double precision, double precision, double precision, integer
);
create or replace function clubs_in_bbox(
  p_min_lng double precision,
  p_min_lat double precision,
  p_max_lng double precision,
  p_max_lat double precision,
  p_limit integer default 100
)
returns table (
  id uuid,
  name text,
  slug text,
  avatar_url text,
  location_label text,
  member_count integer,
  lng double precision,
  lat double precision,
  is_verified boolean
)
language sql
stable
parallel safe
security definer
set search_path = public, extensions
as $$
  with bbox as (
    select ST_MakeEnvelope(p_min_lng, p_min_lat, p_max_lng, p_max_lat, 4326) as g
  )
  select
    c.id,
    c.name,
    c.slug,
    c.avatar_url,
    c.location_label,
    c.member_count,
    ST_X(c.location_point::geometry) as lng,
    ST_Y(c.location_point::geometry) as lat,
    c.is_verified
  from clubs c, bbox
  where c.is_public = true
    and c.shadow_hidden = false
    and c.location_point is not null
    and c.location_point::geometry && bbox.g
  order by c.is_verified desc, c.member_count desc, c.created_at desc
  limit p_limit;
$$;

grant execute on function clubs_in_bbox(
  double precision, double precision, double precision, double precision, integer
) to anon, authenticated;

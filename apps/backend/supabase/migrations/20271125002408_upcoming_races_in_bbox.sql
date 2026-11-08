-- Upcoming verified races as discovery-map pins (issue #1190 § 4, decisions
-- § 2408).
--
-- The heatmap gains a third pin type beside clubs and routes: verified races
-- in the next ~6 months, so a runner browsing a city sees what is on there.
-- upcoming_races_in_bbox returns them for a viewport.
--
--   * Only `race_listings.is_verified` rows: a provider sync (RunSignUp, …)
--     or a verified organiser's claim (claim_race_listing, 20271114002381)
--     sets it, and force_unverified_listing keeps a client from setting it.
--     A crowd-submitted, unverified listing is still on /races; it gets no
--     map pin, so a fan's copy never sits on the map beside the real race.
--   * The pin sits at the course start when the race has a course that is
--     shown publicly (the public_routes join, the same gate
--     public_race_listings uses for course_route_id), and at the listing's
--     location_point otherwise. routes.start_point is the point
--     discoverable_routes_in_bbox already pins every public route at, so
--     nothing new is exposed. A listing with neither has no pin.
--   * "Upcoming" is race_date from today through today + p_days (default 183,
--     clamped to 1..366). p_limit is clamped to 1..200.
--   * p_official_only narrows to races claimed by an official organiser,
--     for the map's Official lens.
--   * Official races rank first, then soonest, then id, so a viewport past
--     the limit keeps the organisers' own races and the order is stable
--     across calls. An official race is one whose organiser club is
--     verified, public and not shadow-hidden: the club-level half of
--     private.is_official_publisher (20271021000030). A listing has no author,
--     and the claim RPC already required an owner/admin to claim it; reading
--     the club's CURRENT state means revoking its badge drops the rank at
--     once, as it does for every other official row. No cap like the route
--     lens's: every pin here is a verified race, so there is no community
--     layer for official rows to crowd out.
--
-- security definer, as the sibling *_in_bbox RPCs are: it reads routes for
-- start_point, but only through the public_routes gate. Every listing column
-- returned is already anon-readable through public_race_listings.
--
-- Locks: function DDL only. The date window rides race_listings_date_idx
-- (20270214_001), so a call reads the verified races of the next p_days, not
-- the calendar's history; the bbox is then tested on the resolved pin point
-- as a planar geometry overlap, the form 20270128_001 settled on for every
-- heatmap RPC.

set search_path = public, extensions;

create or replace function upcoming_races_in_bbox(
  p_min_lng double precision,
  p_min_lat double precision,
  p_max_lng double precision,
  p_max_lat double precision,
  p_limit integer default 100,
  p_days integer default 183,
  p_official_only boolean default false
)
returns table (
  id uuid,
  name text,
  race_date date,
  distance_m integer,
  location_label text,
  is_official boolean,
  has_course boolean,
  lng double precision,
  lat double precision
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
  upcoming as (
    select
      l.id,
      l.name,
      l.race_date,
      l.distance_m,
      l.location_label,
      coalesce(oc.is_verified and oc.is_public and not oc.shadow_hidden, false) as is_official,
      pr.id is not null as has_course,
      coalesce(r.start_point, l.location_point)::geometry as pt
    from race_listings l
    left join public_routes pr on pr.id = l.route_id
    left join routes r on r.id = pr.id
    left join clubs oc on oc.id = l.organiser_club_id
    where l.is_verified = true
      and l.race_date >= current_date
      and l.race_date <= current_date + least(greatest(coalesce(p_days, 183), 1), 366)
  )
  select
    u.id,
    u.name,
    u.race_date,
    u.distance_m,
    u.location_label,
    u.is_official,
    u.has_course,
    ST_X(u.pt) as lng,
    ST_Y(u.pt) as lat
  from upcoming u, bbox
  where u.pt is not null
    and u.pt && bbox.g
    and (not coalesce(p_official_only, false) or u.is_official)
  order by u.is_official desc, u.race_date, u.id
  limit least(greatest(coalesce(p_limit, 100), 1), 200);
$$;

revoke execute on function upcoming_races_in_bbox(
  double precision, double precision, double precision, double precision,
  integer, integer, boolean
) from public;
grant execute on function upcoming_races_in_bbox(
  double precision, double precision, double precision, double precision,
  integer, integer, boolean
) to anon, authenticated;

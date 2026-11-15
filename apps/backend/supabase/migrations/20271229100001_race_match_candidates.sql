-- "Is this your race?" candidates for one run (issue #1389).
--
-- The auto-match seam asked search_race_listings for the listings dated on
-- the run's UTC calendar day, with no centre, so every race in the country
-- that day came back without a distance from the run and without its course.
-- The pure scorer (race_match.ts / race_match.dart) then had only the date and
-- a distance band to go on, and a listing with no distance scored a perfect 1
-- on the date alone.
--
-- This returns what the scorer needs to decide properly: listings dated
-- within a day either side of the run's UTC start (the scorer applies the
-- exact window, the race's calendar day in any time zone) and within 50 km
-- of the run's start, nearest first and then nearest in date, each with its
-- location, its course distance and, when it has a public course, the
-- course's start and finish lines as course_timing_lines derives them
-- (decisions § 2390): the route owner's privacy-clipped ends, facing along
-- the route, half-width 15 m.
--
-- A run with no start point gets no candidates. Without one the window is
-- every race in the country across three days: nothing can rank the 50 rows
-- kept, so a busy weekend cuts the right race arbitrarily, and the scorer would
-- have only the date and a distance to agree on, which is the Turkey Trot
-- failure again. The 50 rows are taken after ordering by distance from the
-- start, then by days from the run's UTC date, so the cap drops the farthest
-- listings first rather than whichever the calendar happened to list last.
--
-- SECURITY DEFINER because private.event_course_endpoints is revoked from
-- every client role. It reads public_race_listings, whose course_route_id is
-- non-null only while the route is public, so a private, hidden or deleted
-- course yields no lines, and the clipped ends are what an event course on the
-- same route already publishes. Function DDL only; no table lock.

create or replace function public.race_match_candidates(
  p_started_at timestamptz,
  p_start_lat double precision default null,
  p_start_lng double precision default null
) returns table (
  id uuid,
  provider text,
  provider_race_id text,
  name text,
  race_date date,
  distance_m integer,
  course_distance_m double precision,
  location_label text,
  entry_url text,
  results_url text,
  is_verified boolean,
  organiser_is_official boolean,
  location_lat double precision,
  location_lng double precision,
  distance_m_away double precision,
  start_gate_lat double precision,
  start_gate_lng double precision,
  start_gate_bearing_deg double precision,
  finish_gate_lat double precision,
  finish_gate_lng double precision,
  finish_gate_bearing_deg double precision,
  gate_half_width_m double precision
)
language sql
stable
security definer
set search_path = public, extensions
as $$
  with run_start as (
    select case
      when p_start_lat between -90 and 90 and p_start_lng between -180 and 180
      then ST_SetSRID(ST_MakePoint(p_start_lng, p_start_lat), 4326)::geography
    end as pt,
    (p_started_at at time zone 'UTC')::date as day
  ),
  picked as (
    select
      l.*,
      case when l.location_point is not null
        then ST_Distance(l.location_point, s.pt)
      end as away,
      abs(l.race_date - s.day) as days_off
    from public_race_listings l
    cross join run_start s
    where p_started_at is not null
      and s.pt is not null
      and l.race_date between s.day - 1 and s.day + 1
      and (
        l.location_point is null
        or ST_DWithin(l.location_point, s.pt, 50000)
      )
    order by away asc nulls last, days_off asc, l.created_at desc
    limit 50
  )
  select
    p.id,
    p.provider,
    p.provider_race_id,
    p.name,
    p.race_date,
    p.distance_m,
    p.course_distance_m::float8,
    p.location_label,
    p.entry_url,
    p.results_url,
    p.is_verified,
    coalesce(p.organiser_is_official, false),
    case when p.location_point is not null then ST_Y(p.location_point::geometry) end,
    case when p.location_point is not null then ST_X(p.location_point::geometry) end,
    p.away,
    e.start_lat,
    e.start_lng,
    e.start_bearing_deg,
    e.finish_lat,
    e.finish_lng,
    e.finish_bearing_deg,
    case when e.start_bearing_deg is not null or e.finish_bearing_deg is not null
      then 15::float8
    end
  from picked p
  left join lateral (
    select * from private.event_course_endpoints(p.course_route_id)
    where p.course_route_id is not null
  ) e on true
  order by p.away asc nulls last, p.days_off asc, p.created_at desc;
$$;

revoke execute on function public.race_match_candidates(timestamptz, double precision, double precision)
  from public, anon;
grant execute on function public.race_match_candidates(timestamptz, double precision, double precision)
  to authenticated;

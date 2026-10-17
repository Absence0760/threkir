-- p_newest_first: a past window must be sorted newest first BEFORE the
-- p_limit cap, or the cap keeps the oldest races and drops the recent ones a
-- client reverse could never recover. The old signature is dropped first
-- because a second overload would leave PostgREST unable to resolve the call.

drop function if exists search_race_listings(
  text, text, date, date, double precision, double precision, double precision, int
);

create or replace function search_race_listings(
  p_query      text default null,
  p_distance   text default null,
  p_from       date default null,
  p_to         date default null,
  p_center_lng double precision default null,
  p_center_lat double precision default null,
  p_radius_m   double precision default 50000,
  p_limit      int  default 60,
  p_newest_first boolean default false
) returns table (
  id               uuid,
  provider         text,
  provider_race_id text,
  name             text,
  race_date        date,
  distance_m       integer,
  location_label   text,
  entry_url        text,
  results_url      text,
  is_verified      boolean,
  distance_m_away  double precision
) language sql stable security invoker
  set search_path = public, extensions as $$
  with center as (
    select case
      when p_center_lng is not null and p_center_lat is not null
      then ST_SetSRID(ST_MakePoint(p_center_lng, p_center_lat), 4326)::geography
    end as pt
  )
  select
    l.id,
    l.provider,
    l.provider_race_id,
    l.name,
    l.race_date,
    l.distance_m,
    l.location_label,
    l.entry_url,
    l.results_url,
    l.is_verified,
    case when center.pt is not null and l.location_point is not null
      then ST_Distance(l.location_point, center.pt)
      else null
    end as distance_m_away
  from public_race_listings l
  cross join center
  where
    (p_from is not null or p_to is not null or l.race_date >= current_date)
    and (p_from is null or l.race_date >= p_from)
    and (p_to is null or l.race_date <= p_to)
    and (
      p_query is null
      or l.name ilike '%' || private.like_escape(p_query) || '%'
    )
    and (
      p_distance is null
      or (p_distance = '5k'       and l.distance_m between 4500 and 5500)
      or (p_distance = '10k'      and l.distance_m between 9000 and 11000)
      or (p_distance = 'half'     and l.distance_m between 20000 and 22000)
      or (p_distance = 'marathon' and l.distance_m between 41000 and 43000)
      or (p_distance = 'ultra'    and l.distance_m > 43000)
    )
    and (
      center.pt is null
      or (
        l.location_point is not null
        and ST_DWithin(l.location_point, center.pt, p_radius_m)
      )
    )
  order by
    case when center.pt is not null and l.location_point is not null
      then ST_Distance(l.location_point, center.pt)
      else null
    end asc nulls last,
    case when p_newest_first then l.race_date end desc,
    case when not p_newest_first then l.race_date end asc,
    l.created_at desc
  limit greatest(1, least(p_limit, 200));
$$;

grant execute on function search_race_listings(
  text, text, date, date, double precision, double precision, double precision, int, boolean
) to authenticated, anon;

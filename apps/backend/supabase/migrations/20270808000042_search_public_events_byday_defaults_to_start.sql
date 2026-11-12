-- p_byday never matched a weekly or biweekly series saved with an empty
-- `recurrence_byday` (decisions § 1921).
--
-- Both clients' `expandInstances` read an empty or null byday on a weekly /
-- biweekly series as "the weekday of starts_at", so such a series meets every
-- week on that day — but this filter only matched a series through
-- `recurrence_byday @> array[p_byday]`, which an empty array never satisfies.
-- Filtering Discover to the series' own weekday hid it.
--
-- The rule now, stated once through the `wd` lateral:
--   * weekly / biweekly: `coalesce(nullif(recurrence_byday, '{}'), [wd])`
--     contains the requested day — the stored days when there are any, else
--     the series' own weekday.
--   * one-off: its own weekday, unchanged from 20270527_002.
--   * monthly: never matched. A monthly series repeats on a day of the month,
--     which falls on a different weekday month to month, and both clients
--     ignore byday for it — so a stale byday on a monthly row no longer
--     files it under a weekday it does not keep.
-- `wd` is the weekday of `starts_at` on the EVENT's wall clock (`at time
-- zone coalesce(timezone, 'UTC')`), the reading p_time and the one-off branch
-- already use: a Sunday-evening New York class is a Sunday class, whatever
-- UTC says. A legacy series with no timezone has no canonical wall clock (its
-- clients expanded it in each viewer's zone), so it reads on UTC, the same
-- fallback p_time gives it.
--
-- Recreated with the COMPLETE body of 20270527_002 (bare-body rule) and the
-- search_path pin it carries. Signature unchanged, so no drop and the grants
-- are preserved; the grant is restated as 20270527_002 did.

create or replace function search_public_events(
  p_query      text default null,
  p_category   text default null,
  p_cadence    text default null,
  p_byday      text default null,
  p_paid       text default null,
  p_time       text default null,
  p_center_lng double precision default null,
  p_center_lat double precision default null,
  p_radius_m   double precision default 50000,
  p_limit      int  default 60
) returns table (
  id              uuid,
  club_id         uuid,
  club_name       text,
  club_slug       text,
  title           text,
  category        text,
  discipline      text,
  starts_at       timestamptz,
  timezone        text,
  duration_min    integer,
  recurrence_freq text,
  recurrence_byday text[],
  capacity        integer,
  price_cents     integer,
  currency        text,
  distance_m      double precision
) language sql stable security invoker set search_path = public, extensions as $$
  with center as (
    select case
      when p_center_lng is not null and p_center_lat is not null
      then ST_SetSRID(ST_MakePoint(p_center_lng, p_center_lat), 4326)::geography
    end as pt
  )
  select
    e.id,
    e.club_id,
    c.name,
    c.slug,
    e.title,
    e.category,
    e.discipline,
    e.starts_at,
    e.timezone,
    e.duration_min,
    e.recurrence_freq,
    e.recurrence_byday,
    e.capacity,
    pr.price_cents,
    pr.currency,
    case when center.pt is not null and c.location_point is not null
      then ST_Distance(c.location_point, center.pt)
      else null
    end as distance_m
  from events e
  join clubs c on c.id = e.club_id and c.is_public = true
  cross join center
  cross join lateral (
    select case extract(
                  isodow from e.starts_at at time zone coalesce(e.timezone, 'UTC')
                )::int
             when 1 then 'MO' when 2 then 'TU' when 3 then 'WE'
             when 4 then 'TH' when 5 then 'FR' when 6 then 'SA'
             when 7 then 'SU' end as code
  ) wd
  left join lateral (
    select min(price_cents) as price_cents,
           (array_agg(currency order by price_cents))[1] as currency
    from event_pricing ep
    where ep.event_id = e.id
  ) pr on true
  where
    e.is_public = true
    and (e.recurrence_freq is not null or e.starts_at >= now())
    and (
      p_query is null
      or e.discipline ilike '%' || p_query || '%'
      or e.title ilike '%' || p_query || '%'
    )
    and (p_category is null or e.category = p_category)
    and (
      p_cadence is null
      or (p_cadence = 'one_off' and e.recurrence_freq is null)
      or (p_cadence <> 'one_off' and e.recurrence_freq = p_cadence)
    )
    and (
      p_byday is null
      or (
        e.recurrence_freq in ('weekly', 'biweekly')
        and coalesce(nullif(e.recurrence_byday, '{}'::text[]), array[wd.code]) @> array[p_byday]
      )
      or (e.recurrence_freq is null and wd.code = p_byday)
    )
    and (
      p_paid is null
      or (p_paid = 'paid' and pr.price_cents is not null)
      or (p_paid = 'free' and pr.price_cents is null)
    )
    and (
      p_time is null
      or case
           when extract(hour from e.starts_at at time zone coalesce(e.timezone, 'UTC'))::int
                between 5 and 11 then 'morning'
           when extract(hour from e.starts_at at time zone coalesce(e.timezone, 'UTC'))::int
                between 12 and 16 then 'afternoon'
           else 'evening'
         end = p_time
    )
    and (
      center.pt is null
      or (
        c.location_point is not null
        and ST_DWithin(c.location_point, center.pt, p_radius_m)
      )
    )
  order by
    case when center.pt is not null and c.location_point is not null
      then ST_Distance(c.location_point, center.pt)
      else null
    end asc nulls last,
    e.starts_at asc nulls last,
    e.created_at desc
  limit greatest(1, least(p_limit, 200));
$$;

grant execute on function search_public_events(
  text, text, text, text, text, text, double precision, double precision, double precision, int
) to authenticated, anon;

-- The text-search RPCs match the typed term literally (decisions § 1930).
--
-- Five functions build `<col> ilike '%' || p_query || '%'` with the term
-- interpolated raw: search_clubs, search_public_events, search_race_listings,
-- browse_public_challenges and search_user_profiles. Inside a LIKE pattern `%`
-- and `_` are wildcards and `\` is the escape character, so a search for
-- `100%` matched every name containing `100`, `5_k` matched `5_k` / `5-k` /
-- `5xk`, and a backslash escaped whatever followed it. A trailing one escaped
-- the closing `%` itself: `k\` became `'%k\%'`, "ends in the two characters
-- k%", and a lone `\` became "contains a percent sign". (The appended `%`
-- is also why no input reaches 22025 "LIKE pattern must not end with escape
-- character"; the failure is a silently wrong result, not an error.) The
-- clients already match literally (§ 1926 / § 1928); this closes the server
-- half.
--
--   1. `private.like_escape(text)` prefixes each `\`, `%` and `_` with `\`,
--      the default LIKE escape character, so the result inside `'%' || … ||
--      '%'` matches exactly the characters typed, anywhere in the value.
--      Backslash is escaped first so the escapes it adds are not doubled. A
--      pure text transform reading no table: immutable, `search_path = ''`,
--      strict (NULL in, NULL out — every caller's `p_query is null` branch
--      and search_user_profiles' null-matches-nothing behaviour are kept).
--      search_clubs, search_public_events and search_race_listings are
--      SECURITY INVOKER, so anon and authenticated must be able to execute it;
--      it is granted to PUBLIC as `private.distinct_text_array` is
--      (20270816000011). `private` is not a PostgREST-exposed schema, so the
--      grant exposes no RPC.
--   2. Each function is re-emitted with the COMPLETE body of its live
--      definition (bare-body rule) and only the pattern changed:
--        search_clubs             20270218_001 (search_path pin 20270415_001)
--        search_public_events     20270808000042
--        search_race_listings     20270320_001 (search_path pin 20270415_001)
--        browse_public_challenges 20270308_001
--        search_user_profiles     20270424000002
--      CREATE OR REPLACE resets a function's SET clauses to what the new
--      statement names, so the two pins 20270415_001 applied by ALTER are
--      written inline here. Signatures are unchanged, so nothing is dropped,
--      ACLs carry over, and database.types.ts is unaffected; the grants are
--      restated as each source migration stated them.
--
-- The trigram GIN indexes (clubs_name_trgm, clubs_location_label_trgm,
-- events_discipline_trgm, events_title_trgm, race_listings_name_trgm,
-- challenges_title_trgm, challenges_description_trgm,
-- user_profiles_display_name_trgm) still serve these predicates: pg_trgm
-- extracts trigrams from an ILIKE pattern honouring `\` escapes, and the
-- pattern is a non-volatile expression, which is all an index qual needs.
--
-- Lock profile: CREATE [OR REPLACE] FUNCTION and GRANT lock no table.

create or replace function private.like_escape(p_text text)
returns text
language sql
immutable
parallel safe
returns null on null input
set search_path = ''
as $$
  select pg_catalog.replace(
    pg_catalog.replace(
      pg_catalog.replace(p_text, '\', '\\'),
      '%', '\%'),
    '_', '\_');
$$;

comment on function private.like_escape(text) is
  'Escapes \, % and _ with \ (the default LIKE escape) so the text matches literally inside a LIKE / ILIKE pattern. Used by the text-search RPCs as ilike ''%'' || private.like_escape(p_query) || ''%''.';

grant execute on function private.like_escape(text) to public;

-- ── search_clubs (20270218_001) ─────────────────────────────────────────────
create or replace function search_clubs(
  p_query text default null,
  p_center_lng double precision default null,
  p_center_lat double precision default null,
  p_radius_m double precision default 80000,
  p_limit int default 60
) returns setof clubs language sql stable security invoker
  set search_path = public, extensions as $$
  with center as (
    select case
      when p_center_lng is not null and p_center_lat is not null
      then ST_SetSRID(ST_MakePoint(p_center_lng, p_center_lat), 4326)::geography
    end as pt
  )
  select
    c.id,
    c.owner_id,
    c.name,
    c.slug,
    c.description,
    c.avatar_url,
    c.location_label,
    c.is_public,
    c.created_at,
    c.updated_at,
    c.join_policy,
    null::text,
    c.location_point,
    c.member_count,
    c.is_verified,
    c.requires_activity_waiver,
    c.website_url,
    c.instagram_url,
    c.strava_url,
    c.facebook_url,
    c.shadow_hidden
  from clubs c, center
  where c.is_public = true
    and c.shadow_hidden = false
    and (
      p_query is null
      or c.name ilike '%' || private.like_escape(p_query) || '%'
      or c.location_label ilike '%' || private.like_escape(p_query) || '%'
      or (
        center.pt is not null
        and c.location_point is not null
        and ST_DWithin(c.location_point, center.pt, p_radius_m)
      )
    )
  order by
    case when center.pt is not null and c.location_point is not null
      then ST_Distance(c.location_point, center.pt)
      else null
    end asc nulls last,
    c.member_count desc,
    c.created_at desc
  limit p_limit;
$$;

grant execute on function search_clubs(
  text, double precision, double precision, double precision, int
) to authenticated, anon;

-- ── search_public_events (20270808000042) ───────────────────────────────────
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
      or e.discipline ilike '%' || private.like_escape(p_query) || '%'
      or e.title ilike '%' || private.like_escape(p_query) || '%'
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

-- ── search_race_listings (20270320_001) ─────────────────────────────────────
create or replace function search_race_listings(
  p_query      text default null,
  p_distance   text default null,
  p_from       date default null,
  p_to         date default null,
  p_center_lng double precision default null,
  p_center_lat double precision default null,
  p_radius_m   double precision default 50000,
  p_limit      int  default 60
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
    l.race_date asc,
    l.created_at desc
  limit greatest(1, least(p_limit, 200));
$$;

grant execute on function search_race_listings(
  text, text, date, date, double precision, double precision, double precision, int
) to authenticated, anon;

-- ── browse_public_challenges (20270308_001) ─────────────────────────────────
create or replace function browse_public_challenges(
  p_search text default null,
  p_limit integer default 24,
  p_offset integer default 0
)
returns table (
  id uuid,
  creator_id uuid,
  club_id uuid,
  title text,
  description text,
  metric text,
  scope text,
  goal_value numeric,
  activity_type text,
  starts_at timestamptz,
  ends_at timestamptz,
  is_public boolean,
  created_at timestamptz,
  participant_count integer
)
language sql
stable
security definer
set search_path = public
as $$
  with eligible as (
    select
      c.*,
      (
        select count(*) from challenge_participants p
        where p.challenge_id = c.id
          and p.joined_at >= now() - interval '7 days'
      ) as joins_7d
    from challenges c
    where c.is_public = true
      -- still open to join
      and c.ends_at > now()
      -- not one the caller already joined (those live in My challenges)
      and not exists (
        select 1 from challenge_participants pj
        where pj.challenge_id = c.id and pj.user_id = auth.uid()
      )
      -- throwaway suppression: hide dead boards (no participants past a 7-day
      -- grace window) unless the caller created them, so a new challenge still
      -- gets a fair shot at gaining traction.
      and (
        c.participant_count > 0
        or c.created_at >= now() - interval '7 days'
        or c.creator_id = auth.uid()
      )
      and (
        p_search is null
        or btrim(p_search) = ''
        or c.title ilike '%' || private.like_escape(btrim(p_search)) || '%'
        or c.description ilike '%' || private.like_escape(btrim(p_search)) || '%'
      )
  )
  select
    id, creator_id, club_id, title, description, metric, scope, goal_value,
    activity_type, starts_at, ends_at, is_public, created_at, participant_count
  from eligible
  order by (participant_count + joins_7d * 2) desc, ends_at asc, created_at desc, id
  limit greatest(0, least(coalesce(p_limit, 24), 100))
  offset greatest(0, coalesce(p_offset, 0));
$$;

grant execute on function browse_public_challenges(text, integer, integer) to authenticated, anon;

-- ── search_user_profiles (20270424000002) ───────────────────────────────────
create or replace function search_user_profiles(
  p_query text,
  p_limit int default 60
)
returns table (
  id uuid,
  display_name text,
  avatar_url text
)
language sql
security definer
set search_path = public
stable
as $$
  with capped as (
    select least(greatest(coalesce(p_limit, 60), 1), 200) as v
  )
  select
    u.id,
    u.display_name,
    u.avatar_url
  from user_profiles u
  left join user_settings s on s.user_id = u.id
  where (
      u.display_name ilike '%' || private.like_escape(p_query) || '%'
      or (
        u.handle is not null
        and ltrim(p_query, '@') <> ''
        and starts_with(u.handle, lower(ltrim(p_query, '@')))
      )
    )
    and u.shadow_hidden = false
    and coalesce(s.prefs->>'discoverable_in_search', 'true') <> 'false'
    and not (
      (u.date_of_birth is not null
        and u.date_of_birth > (current_date - interval '18 years'))
      or coalesce(
        s.prefs ? 'date_of_birth'
        and (s.prefs->>'date_of_birth') ~ '^\d{4}-\d{2}-\d{2}$'
        and (s.prefs->>'date_of_birth')::date > (current_date - interval '18 years'),
        false
      )
    )
  order by
    (u.handle is not null and u.handle = lower(ltrim(p_query, '@'))) desc,
    u.display_name
  limit (select v from capped);
$$;

revoke all on function search_user_profiles(text, int) from public;
revoke execute on function search_user_profiles(text, int) from anon;
grant execute on function search_user_profiles(text, int) to authenticated;

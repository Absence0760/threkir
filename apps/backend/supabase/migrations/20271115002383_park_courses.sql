-- Park courses: standing time-trial courses in state and national parks, with
-- yearly leaderboards (issue #1313, decisions § 2383).
--
-- A park course is a catalogue segment (`global_segments`, 20270411_001) that
-- belongs to a park. The course lives in its OWN table rather than as columns
-- on `global_segments`, so the catalogue stays free-standing (decisions § 232)
-- and one park can hold several courses. Every run that covers the course is
-- timed by the existing catalogue matcher; the course adds the ordered
-- `checkpoints` the matcher must also pass (the `segments` parity pair), so a
-- shortcut across a trail network never earns a time.
--
-- Data, not here. The issue's Virginia pilot is an operator load: a course's
-- route must belong to the official account (`routes.user_id` is not null, so
-- no migration can own one) and its geometry comes from the reviewed
-- `scripts/parks/` manifest, loaded as the service role. This migration ships
-- the schema, the season leaderboard and the completions board only.
--
-- Seasons store nothing. A season is the calendar year in the PARK's timezone,
-- computed from the effort's `started_at` at read time, so the board resets
-- on January 1 where the park is, not where the reader is.
--
-- ── Online safety (docs/backend/migration_locks.md) ──
-- Two new, empty tables, their indexes and policies, and function bodies. The
-- only existing object touched is `global_segment_leaderboard`, which is
-- dropped and recreated with a trailing defaulted `p_season` argument, so a
-- caller passing the old five named arguments resolves unchanged. No table
-- lock on any populated table, no scan.

-- ─────────────────────────────── parks ───────────────────────────────

create table public.parks (
  id            uuid primary key default gen_random_uuid(),
  slug          text not null unique
                  constraint parks_slug_len_chk
                  check (length(slug) between 1 and 80 and slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  name          text not null
                  constraint parks_name_len_chk check (length(name) between 1 and 120),
  description   text
                  constraint parks_description_len_chk
                  check (description is null or length(description) <= 2000),
  agency        text not null
                  constraint parks_agency_check
                  check (agency in ('nps', 'state', 'county', 'other')),
  -- ISO 3166-2, e.g. US-VA. The URL segment is its lower-cased form.
  region_code   text not null
                  constraint parks_region_code_len_chk
                  check (length(region_code) <= 6 and region_code ~ '^[A-Z]{2}-[A-Z0-9]{1,3}$'),
  country_code  text not null
                  constraint parks_country_code_len_chk
                  check (length(country_code) = 2 and country_code ~ '^[A-Z]{2}$'),
  -- IANA zone; validated against pg_timezone_names by the trigger below,
  -- because a CHECK cannot read a catalogue view.
  timezone      text not null
                  constraint parks_timezone_len_chk check (length(timezone) between 1 and 64),
  website_url   text
                  constraint parks_website_url_len_chk
                  check (website_url is null or (length(website_url) <= 500 and website_url ~ '^https://')),
  centroid_lat  double precision
                  constraint parks_centroid_lat_bounds check (centroid_lat between -90 and 90),
  centroid_lng  double precision
                  constraint parks_centroid_lng_bounds check (centroid_lng between -180 and 180),
  bbox_min_lat  double precision
                  constraint parks_bbox_min_lat_bounds check (bbox_min_lat between -90 and 90),
  bbox_min_lng  double precision
                  constraint parks_bbox_min_lng_bounds check (bbox_min_lng between -180 and 180),
  bbox_max_lat  double precision
                  constraint parks_bbox_max_lat_bounds check (bbox_max_lat between -90 and 90),
  bbox_max_lng  double precision
                  constraint parks_bbox_max_lng_bounds check (bbox_max_lng between -180 and 180),
  is_active     boolean not null default true,
  created_at    timestamptz not null default now(),
  constraint parks_bbox_order check (
    (bbox_min_lat is null and bbox_max_lat is null and bbox_min_lng is null and bbox_max_lng is null)
    or (bbox_min_lat <= bbox_max_lat and bbox_min_lng <= bbox_max_lng)
  )
);

create index parks_region on public.parks (region_code, name) where is_active = true;

create or replace function private.parks_validate_timezone()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if not exists (select 1 from pg_catalog.pg_timezone_names where name = new.timezone) then
    raise exception 'parks.timezone % is not an IANA zone', new.timezone
      using errcode = '22023';
  end if;
  return new;
end;
$$;

create trigger parks_validate_timezone
  before insert or update of timezone on public.parks
  for each row execute function private.parks_validate_timezone();

alter table public.parks enable row level security;

create policy "active parks are world-readable"
  on public.parks for select
  using (is_active = true);

create policy "admins insert parks"
  on public.parks for insert
  with check (private.is_admin((select auth.uid())));

create policy "admins edit parks"
  on public.parks for update
  using (private.is_admin((select auth.uid())))
  with check (private.is_admin((select auth.uid())));

create policy "admins delete parks"
  on public.parks for delete
  using (private.is_admin((select auth.uid())));

grant select on public.parks to anon;
grant select, insert, update, delete on public.parks to authenticated;
grant select, insert, update, delete on public.parks to service_role;

-- ──────────────────────────── park_courses ────────────────────────────

create table public.park_courses (
  id                 uuid primary key default gen_random_uuid(),
  park_id            uuid not null references public.parks(id) on delete cascade,
  -- One course per catalogue segment: the segment carries the polyline, the
  -- length guard and every effort; the course says where it is and how to run it.
  global_segment_id  uuid not null unique references public.global_segments(id) on delete cascade,
  -- The public official route a runner follows (trail navigation, GPX, offline
  -- tiles). Nullable: a route needs an owning account, so it is loaded by the
  -- operator after the course row, and a deleted route must not take the
  -- course and its boards with it.
  route_id           uuid references public.routes(id) on delete set null,
  slug               text not null
                       constraint park_courses_slug_len_chk
                       check (length(slug) between 1 and 80 and slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  course_shape       text not null
                       constraint park_courses_course_shape_check
                       check (course_shape in ('loop', 'out_and_back', 'point_to_point')),
  status             text not null default 'open'
                       constraint park_courses_status_check
                       check (status in ('open', 'closed', 'seasonal')),
  status_note        text
                       constraint park_courses_status_note_len_chk
                       check (status_note is null or length(status_note) <= 500),
  status_checked_at  timestamptz,
  geometry_source    text not null
                       constraint park_courses_geometry_source_check
                       check (geometry_source in ('osm', 'nps', 'agency', 'traced')),
  source_ref         text
                       constraint park_courses_source_ref_len_chk
                       check (source_ref is null or length(source_ref) <= 500),
  source_checked_at  timestamptz,
  surface            text
                       constraint park_courses_surface_check
                       check (surface is null or surface in ('paved', 'gravel', 'trail', 'mixed')),
  difficulty         text
                       constraint park_courses_difficulty_check
                       check (difficulty is null or difficulty in ('easy', 'moderate', 'hard')),
  -- Ordered [{lat, lng}] the run must pass, in order, within the matcher's
  -- tolerance between the start and end crossings. Point shape is validated by
  -- the clients' `parseCourseCheckpoints`, which refuses to score a course
  -- whose list it cannot read (fail closed).
  checkpoints        jsonb not null default jsonb_build_array()
                       constraint park_courses_checkpoints_shape
                       check (jsonb_typeof(checkpoints) = 'array' and jsonb_array_length(checkpoints) <= 50),
  created_at         timestamptz not null default now(),
  unique (park_id, slug)
);

create index park_courses_route_id on public.park_courses (route_id) where route_id is not null;

alter table public.park_courses enable row level security;

create policy "courses of active parks are world-readable"
  on public.park_courses for select
  using (
    exists (
      select 1 from public.parks p
      where p.id = park_courses.park_id
        and p.is_active = true
    )
  );

create policy "admins insert park courses"
  on public.park_courses for insert
  with check (private.is_admin((select auth.uid())));

create policy "admins edit park courses"
  on public.park_courses for update
  using (private.is_admin((select auth.uid())))
  with check (private.is_admin((select auth.uid())));

create policy "admins delete park courses"
  on public.park_courses for delete
  using (private.is_admin((select auth.uid())));

grant select on public.park_courses to anon;
grant select, insert, update, delete on public.park_courses to authenticated;
grant select, insert, update, delete on public.park_courses to service_role;

-- ───────────────────── current season (computed field) ─────────────────────

-- `select *, park_season` on parks: the calendar year it is NOW where the park
-- is. Clients pass it back as `p_season` for the default "this year" board, so
-- no client carries a timezone database to agree with the server's.
create or replace function public.park_season(p public.parks)
returns integer
language sql
stable
set search_path = public
as $$
  select extract(year from (now() at time zone p.timezone))::integer;
$$;

revoke execute on function public.park_season(public.parks) from public;
grant execute on function public.park_season(public.parks) to anon, authenticated, service_role;

-- ───────────── global_segment_leaderboard: optional season ─────────────

-- The COMPLETE live body of 20270606_001 (per-athlete reduction, block filter,
-- run visibility, club filter, shadow-hidden masking, consent-gated age band
-- and own-row demographics), plus one filter: with `p_season`, only efforts
-- whose `started_at` falls in that calendar year in the course's park
-- timezone (UTC for a catalogue segment no park owns). Null is all time.
drop function public.global_segment_leaderboard(uuid, text, text, integer, uuid);

create function public.global_segment_leaderboard(
  p_segment_id uuid,
  p_gender text default null,
  p_age_band text default null,
  p_limit integer default 50,
  p_club_id uuid default null,
  p_season integer default null
)
returns table (
  effort_id uuid,
  user_id uuid,
  run_id uuid,
  time_seconds integer,
  started_at timestamptz,
  display_name text,
  avatar_url text,
  gender text,
  age integer
)
language plpgsql
stable
security definer
set search_path = public, private
as $$
declare
  age_min integer := null;
  age_max integer := null;
  caller uuid := auth.uid();
  v_tz text;
begin
  if caller is null then
    raise exception 'global_segment_leaderboard requires an authenticated caller'
      using errcode = '42501';
  end if;

  if p_age_band is not null then
    if p_age_band = '75+' then
      age_min := 75;
      age_max := 200;
    elsif p_age_band ~ '^[0-9]+-[0-9]+$' then
      age_min := split_part(p_age_band, '-', 1)::integer;
      age_max := split_part(p_age_band, '-', 2)::integer;
    else
      raise exception 'global_segment_leaderboard: invalid p_age_band %', p_age_band
        using errcode = '22023';
    end if;
  end if;

  if p_season is not null and p_season not between 2000 and 2200 then
    raise exception 'global_segment_leaderboard: invalid p_season %', p_season
      using errcode = '22023';
  end if;

  -- A club filter only applies when the caller is a member of that club;
  -- otherwise it collapses to empty rather than leaking membership.
  if p_club_id is not null and not is_club_member(p_club_id) then
    return;
  end if;

  select p.timezone into v_tz
  from public.park_courses pc
  join public.parks p on p.id = pc.park_id
  where pc.global_segment_id = p_segment_id;
  v_tz := coalesce(v_tz, 'UTC');

  return query
  with best_per_athlete as (
    -- Each athlete's fastest effort the caller is allowed to see. All
    -- gender/age/club/visibility/block/season filters live HERE so the
    -- reduction ranks over the visible set — a hidden faster effort can't
    -- suppress a slower visible one for the same athlete.
    select distinct on (se.user_id)
      se.id           as effort_id,
      se.user_id      as user_id,
      se.run_id       as run_id,
      se.time_seconds as time_seconds,
      se.started_at   as started_at
    from public.global_segment_efforts se
    join public.global_segments      gs on gs.id = se.global_segment_id
    join public.user_profiles        up on up.id = se.user_id
    where se.global_segment_id = p_segment_id
      and gs.is_active = true
      and private.is_run_visible_to(se.run_id, caller)
      -- Block-aware: hide efforts by users the caller has blocked (or who
      -- have blocked the caller). Own effort survives (block of self is false).
      and not is_blocked_either_way(caller, se.user_id)
      and (
        p_season is null
        or extract(year from (se.started_at at time zone v_tz))::integer = p_season
      )
      and (p_gender is null or up.gender = p_gender)
      and (
        p_age_band is null
        or (
          up.date_of_birth is not null
          and up.health_data_consent_at is not null
          and extract(year from age(up.date_of_birth))::integer between age_min and age_max
        )
      )
      and (
        p_club_id is null
        or exists (
          select 1 from public.club_members cm
          where cm.club_id = p_club_id
            and cm.user_id = se.user_id
            and cm.status = 'active'
        )
      )
    order by se.user_id, se.time_seconds asc, se.started_at asc
  )
  select
    b.effort_id,
    b.user_id,
    b.run_id,
    b.time_seconds::integer                                    as time_seconds,
    b.started_at,
    case when up.shadow_hidden = false or up.id = caller
      then up.display_name end                                 as display_name,
    case when up.shadow_hidden = false or up.id = caller
      then up.avatar_url end                                   as avatar_url,
    case when b.user_id = caller then up.gender else null end  as gender,
    case
      when b.user_id = caller
       and up.date_of_birth is not null
       and up.health_data_consent_at is not null
        then extract(year from age(up.date_of_birth))::integer
      else null
    end                                                        as age
  from best_per_athlete b
  join public.user_profiles up on up.id = b.user_id
  order by b.time_seconds asc, b.started_at asc
  limit p_limit;
end;
$$;

-- anon keeps EXECUTE so the call enters the body and hits the in-body 42501,
-- exactly as the five-argument function it replaces (anon_execute_contract).
revoke execute on function public.global_segment_leaderboard(uuid, text, text, integer, uuid, integer) from public;
grant  execute on function public.global_segment_leaderboard(uuid, text, text, integer, uuid, integer) to anon, authenticated, service_role;

-- ─────────────────── most completions board ───────────────────

-- Rewards regulars, not only the fast: one row per athlete, counting DISTINCT
-- local days (park timezone) with a visible effort, so laps on one day can't
-- pad the count. Same visibility, block and shadow-hidden rules as the time
-- board. No demographic filters — a count of visits needs no age tier.
create or replace function public.global_segment_completions(
  p_segment_id uuid,
  p_season integer default null,
  p_limit integer default 50
)
returns table (
  user_id uuid,
  completions integer,
  last_completed_at timestamptz,
  display_name text,
  avatar_url text
)
language plpgsql
stable
security definer
set search_path = public, private
as $$
declare
  caller uuid := auth.uid();
  v_tz text;
begin
  if caller is null then
    raise exception 'global_segment_completions requires an authenticated caller'
      using errcode = '42501';
  end if;

  if p_season is not null and p_season not between 2000 and 2200 then
    raise exception 'global_segment_completions: invalid p_season %', p_season
      using errcode = '22023';
  end if;

  select p.timezone into v_tz
  from public.park_courses pc
  join public.parks p on p.id = pc.park_id
  where pc.global_segment_id = p_segment_id;
  v_tz := coalesce(v_tz, 'UTC');

  return query
  with per_athlete as (
    select
      se.user_id,
      count(distinct (se.started_at at time zone v_tz)::date)::integer as completions,
      max(se.started_at)                                              as last_completed_at
    from public.global_segment_efforts se
    join public.global_segments gs on gs.id = se.global_segment_id
    where se.global_segment_id = p_segment_id
      and gs.is_active = true
      and private.is_run_visible_to(se.run_id, caller)
      and not is_blocked_either_way(caller, se.user_id)
      and (
        p_season is null
        or extract(year from (se.started_at at time zone v_tz))::integer = p_season
      )
    group by se.user_id
  )
  select
    a.user_id,
    a.completions,
    a.last_completed_at,
    case when up.shadow_hidden = false or up.id = caller
      then up.display_name end as display_name,
    case when up.shadow_hidden = false or up.id = caller
      then up.avatar_url end   as avatar_url
  from per_athlete a
  join public.user_profiles up on up.id = a.user_id
  order by a.completions desc, a.last_completed_at asc
  limit greatest(1, least(coalesce(p_limit, 50), 200));
end;
$$;

revoke execute on function public.global_segment_completions(uuid, integer, integer) from public, anon;
grant  execute on function public.global_segment_completions(uuid, integer, integer) to authenticated, service_role;

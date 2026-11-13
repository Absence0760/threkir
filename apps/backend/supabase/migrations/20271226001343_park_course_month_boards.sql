-- Monthly park course boards (issue #1343, decisions § 2426): a calendar month
-- is a filter on the existing boards, in the park's timezone, with no entry
-- and nothing stored per month.
--
--   * global_segment_leaderboard and global_segment_completions each take a
--     TRAILING `p_month integer default null` (1-12) after their existing
--     arguments. Trailing on both, so every older call shape still resolves,
--     named or positional: the issue sketched the completions board as
--     (p_segment_id, p_season, p_month, p_limit), which would bind an existing
--     positional (segment, season, limit) call's limit as the month.
--     A month without a season, or outside 1-12, raises 22023.
--   * A month is the calendar month of the effort's `started_at` in the
--     course's park timezone (UTC for a catalogue segment no park owns), read
--     with the same `at time zone` the season filter uses, so it runs from
--     00:00 local on the 1st up to 00:00 local on the next 1st across DST.
--   * park_month(parks) sits beside park_season(parks), so a client reads
--     both in one select and carries no timezone database. now() is the
--     transaction time, so the pair agrees at midnight on 1 January.
--   * run_park_course_times gains `month` and `month_rank` after its existing
--     columns, read from the monthly board the way `season_rank` is read from
--     the yearly one, so it is the place the owner sees on the course page.
--     Still owner-only.
--
-- Each board is dropped and recreated with its COMPLETE live body (the
-- leaderboard and completions from 20271115002383, run_park_course_times from
-- 20271123002404) plus the month filter, so every rule is inherited: run
-- visibility, the block filter, the club filter, shadow-hidden masking, the
-- consent-gated age band and own-row demographics; anon keeps the in-body
-- 42501 on the leaderboard and holds no EXECUTE on the completions board.
-- park_course_records() (20271129002436) calls the leaderboard positionally
-- with six arguments and resolves to the new function unchanged.
--
-- ── Online safety (docs/backend/migration_locks.md) ──
-- Function DDL only: no table lock, no scan. No index: the month filter rides
-- the same per-segment read the season filter already does (EXPLAIN in
-- decisions § 2511).

-- ───────────────────── current month (computed field) ─────────────────────

create or replace function public.park_month(p public.parks)
returns integer
language sql
stable
set search_path = public
as $$
  select extract(month from (now() at time zone p.timezone))::integer;
$$;

revoke execute on function public.park_month(public.parks) from public;
grant execute on function public.park_month(public.parks) to anon, authenticated, service_role;

-- ───────────── global_segment_leaderboard: optional month ─────────────

drop function public.global_segment_leaderboard(uuid, text, text, integer, uuid, integer);

create function public.global_segment_leaderboard(
  p_segment_id uuid,
  p_gender text default null,
  p_age_band text default null,
  p_limit integer default 50,
  p_club_id uuid default null,
  p_season integer default null,
  p_month integer default null
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

  -- A month names one month of one year: alone it would mean "every
  -- November", which no board shows.
  if p_month is not null and (p_season is null or p_month not between 1 and 12) then
    raise exception 'global_segment_leaderboard: invalid p_month % (needs p_season and 1-12)', p_month
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
    -- gender/age/club/visibility/block/season/month filters live HERE so the
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
      and (
        p_month is null
        or extract(month from (se.started_at at time zone v_tz))::integer = p_month
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
-- exactly as the function it replaces (anon_execute_contract).
revoke execute on function public.global_segment_leaderboard(uuid, text, text, integer, uuid, integer, integer) from public;
grant  execute on function public.global_segment_leaderboard(uuid, text, text, integer, uuid, integer, integer) to anon, authenticated, service_role;

-- ─────────────────── most completions board: optional month ───────────────────

drop function public.global_segment_completions(uuid, integer, integer);

create function public.global_segment_completions(
  p_segment_id uuid,
  p_season integer default null,
  p_limit integer default 50,
  p_month integer default null
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

  if p_month is not null and (p_season is null or p_month not between 1 and 12) then
    raise exception 'global_segment_completions: invalid p_month % (needs p_season and 1-12)', p_month
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
      and (
        p_month is null
        or extract(month from (se.started_at at time zone v_tz))::integer = p_month
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

revoke execute on function public.global_segment_completions(uuid, integer, integer, integer) from public, anon;
grant  execute on function public.global_segment_completions(uuid, integer, integer, integer) to authenticated, service_role;

-- ─────────────────── the run's park course times ───────────────────

-- Live body of 20271123002404 plus the month: `month` is the effort's calendar
-- month in the park's timezone, and `month_rank` its place on that month's
-- fastest board when it is the runner's best of the month and inside the top
-- 100, under every rule that board applies. Still only the run's owner gets
-- rows. The return type changes, so it is dropped and recreated.
drop function public.run_park_course_times(uuid);

create function public.run_park_course_times(p_run_id uuid)
returns table (
  effort_id uuid,
  global_segment_id uuid,
  course_name text,
  course_slug text,
  park_name text,
  park_slug text,
  region_code text,
  time_seconds integer,
  started_at timestamptz,
  season integer,
  season_rank integer,
  month integer,
  month_rank integer
)
language sql
stable
security invoker
set search_path = public
as $$
  select
    e.id,
    e.global_segment_id,
    gs.name,
    pc.slug,
    pk.name,
    pk.slug,
    pk.region_code,
    round(e.time_seconds)::integer,
    e.started_at,
    s.season,
    (
      select l.ord::integer
      from public.global_segment_leaderboard(e.global_segment_id, null, null, 100, null, s.season)
        with ordinality as l(effort_id, user_id, run_id, time_seconds, started_at, display_name, avatar_url, gender, age, ord)
      where l.effort_id = e.id
    ),
    s.month,
    (
      select l.ord::integer
      from public.global_segment_leaderboard(e.global_segment_id, null, null, 100, null, s.season, s.month)
        with ordinality as l(effort_id, user_id, run_id, time_seconds, started_at, display_name, avatar_url, gender, age, ord)
      where l.effort_id = e.id
    )
  from public.global_segment_efforts e
  join public.park_courses pc on pc.global_segment_id = e.global_segment_id
  join public.parks pk on pk.id = pc.park_id
  join public.global_segments gs on gs.id = e.global_segment_id
  cross join lateral (
    select
      extract(year from (e.started_at at time zone pk.timezone))::integer as season,
      extract(month from (e.started_at at time zone pk.timezone))::integer as month
  ) s
  where e.run_id = p_run_id
    and e.user_id = (select auth.uid())
  order by e.started_at, gs.name;
$$;

revoke execute on function public.run_park_course_times(uuid) from public, anon;
grant execute on function public.run_park_course_times(uuid) to authenticated, service_role;

-- Park courses, phase 5 (issue #1313, decisions § 2404 / § 2405): badges for
-- park course completions, a `park_courses` challenge metric for the yearly
-- passport, and the run's park course times with their season rank for the
-- share image.
--
-- ── Badges ──
-- Three families join the earned set in achievement_tiers_met(), so the
-- awarder inserts them and the revoker never sees them (it only touches the
-- distance families). They count completions, never rank, so they are durable
-- for the same reason the segment family was deferred (a rank moves; a
-- completion does not):
--   * park_courses  - distinct park courses completed: 1 / 5 / 10 / 25.
--   * park_complete - parks where every course not closed has been completed,
--                     among parks with at least two such courses (a one-course
--                     park would only repeat the first-course badge): 1 / 3 / 10.
--   * park_passport - regions (ISO 3166-2) where a course has been completed in
--                     every active park holding a course not closed, among
--                     regions with at least three such parks: 1 / 3 / 10.
-- A closed course is left out of both "every" counts while it is closed (the
-- issue's closure rule); an award already earned stays.
-- An effort counts when its run is eligible by the rule the other families use
-- (the same source list, not a DNF). Private runs count, as they do for every
-- family: an award names a count, never a course, a park or a run, so
-- source_id stays null and a public badge says nothing about where.
--
-- ── Triggers ──
-- global_segment_efforts gains a statement-level award trigger (the server
-- matcher's record_segment_match and the owner's fallback insert both land
-- there). park_courses gains insert and update triggers, because a course
-- joining a park or closing changes what "every course" means for the runners
-- who already have efforts there. Each award is auxiliary to the write that
-- caused it: a failure is raised as a warning and never fails the effort or the
-- course write (layered resilience).
--
-- ── Challenges ──
-- `park_courses` joins the metric CHECK: distinct park courses (not closed, in
-- an active park) completed on runs inside the window. `park_region_code`
-- narrows it to one region's parks ("Virginia state parks in 2027") and is
-- refused on any other metric. Team boards count distinct courses across the
-- team, as streak_days counts distinct days. A new effort also re-checks the
-- runner's active park_courses challenges, since the effort lands after the
-- run save that normally triggers the opportunistic check; the daily sweep
-- stays the backstop.
--
-- ── Locks ──
-- Function DDL takes nothing a reader or writer waits on. CREATE TRIGGER on
-- global_segment_efforts and park_courses takes SHARE ROW EXCLUSIVE for a
-- catalogue change, no scan. challenges is a small, bounded table (the playbook
-- does not require the NOT VALID split there): the column add is metadata only
-- and the two CHECKs scan it in this transaction. The back-fill at the tail
-- awards for users who already hold park course efforts, which in production
-- is none until the pilot load (no course is loaded yet).

-- ───────────────────────── earned set ─────────────────────────

-- Complete live body (20270719000002) plus the three park branches. The ladder
-- shape (`select '<family>'` then `values (...) as t(...)`) is what
-- scripts/check_shared_constants.mjs reads, so no CTE here selects a quoted
-- literal.
create or replace function achievement_tiers_met(p_user uuid)
returns table (
  badge_key   text,
  tier        text,
  source_kind text,
  source_id   uuid,
  value_num   double precision,
  rank        integer
)
language sql
stable
security invoker
set search_path = public
as $$
  with eligible as (
    select id, distance_m, activity_type, started_at
    from runs
    where user_id = p_user
      and source in ('app', 'watch', 'strava', 'garmin', 'healthkit', 'healthconnect', 'parkrun', 'race')
      and is_dnf = false
  ),
  dist as (
    select
      coalesce(max(distance_m) filter (where activity_type <> 'cycle'), 0)::double precision as longest_m,
      coalesce(sum(distance_m), 0)::double precision as lifetime_m
    from eligible
    where distance_m is not null
  ),
  longest_run as (
    select id
    from eligible
    where activity_type <> 'cycle'
      and distance_m is not null
    order by distance_m desc, started_at asc
    limit 1
  ),
  run_days as (
    select distinct (started_at at time zone 'UTC')::date as d
    from eligible
  ),
  grouped as (
    select d - (row_number() over (order by d))::int as grp
    from run_days
  ),
  streak as (
    select coalesce(max(cnt), 0)::double precision as best
    from (select count(*) as cnt from grouped group by grp) s
  ),
  prs as (
    select count(*)::double precision as n
    from personal_records
    where user_id = p_user
  ),
  plans as (
    select count(*)::double precision as n
    from training_plans
    where user_id = p_user and status = 'completed' and is_template = false
  ),
  done_courses as (
    select distinct pc.id as course_id, pc.park_id, pc.status
    from global_segment_efforts e
    join eligible r on r.id = e.run_id
    join park_courses pc on pc.global_segment_id = e.global_segment_id
    join parks pk on pk.id = pc.park_id and pk.is_active
    where e.user_id = p_user
  ),
  park_totals as (
    select pc.park_id, pk.region_code, count(*) as open_courses
    from park_courses pc
    join parks pk on pk.id = pc.park_id and pk.is_active
    where pc.status <> 'closed'
    group by pc.park_id, pk.region_code
  ),
  park_done as (
    select t.park_id, t.region_code, t.open_courses,
           count(d.course_id) filter (where d.status <> 'closed') as done_open
    from park_totals t
    left join done_courses d on d.park_id = t.park_id
    group by t.park_id, t.region_code, t.open_courses
  ),
  region_done as (
    select region_code
    from park_done
    group by region_code
    having count(*) >= 3 and bool_and(done_open > 0)
  ),
  parks_agg as (
    select
      (select count(*) from done_courses)::double precision as courses,
      (select count(*) from park_done where open_courses >= 2 and done_open = open_courses)::double precision as complete_parks,
      (select count(*) from region_done)::double precision as regions
  )
  select 'distance_single'::text, t.tier, 'distance'::text,
         (select id from longest_run), d.longest_m, t.rank
  from dist d, (values ('bronze',5000,1),('silver',21097,2),('gold',42195,3),('platinum',50000,4)) as t(tier,thr,rank)
  where d.longest_m >= t.thr
  union all
  select 'distance_lifetime', t.tier, 'distance', null::uuid, d.lifetime_m, t.rank
  from dist d, (values ('bronze',100000,1),('silver',500000,2),('gold',1000000,3),('platinum',5000000,4)) as t(tier,thr,rank)
  where d.lifetime_m >= t.thr
  union all
  select 'streak', t.tier, 'streak', null::uuid, s.best, t.rank
  from streak s, (values ('bronze',7,1),('silver',30,2),('gold',100,3),('platinum',365,4)) as t(tier,thr,rank)
  where s.best >= t.thr
  union all
  select 'pr', t.tier, 'pr', null::uuid, p.n, t.rank
  from prs p, (values ('bronze',1,1),('silver',3,2),('gold',5,3)) as t(tier,thr,rank)
  where p.n >= t.thr
  union all
  select 'plan_finisher', t.tier, 'plan', null::uuid, p.n, t.rank
  from plans p, (values ('bronze',1,1),('silver',3,2),('gold',10,3)) as t(tier,thr,rank)
  where p.n >= t.thr
  union all
  select 'park_courses', t.tier, 'segment', null::uuid, a.courses, t.rank
  from parks_agg a, (values ('bronze',1,1),('silver',5,2),('gold',10,3),('platinum',25,4)) as t(tier,thr,rank)
  where a.courses >= t.thr
  union all
  select 'park_complete', t.tier, 'segment', null::uuid, a.complete_parks, t.rank
  from parks_agg a, (values ('bronze',1,1),('silver',3,2),('gold',10,3)) as t(tier,thr,rank)
  where a.complete_parks >= t.thr
  union all
  select 'park_passport', t.tier, 'segment', null::uuid, a.regions, t.rank
  from parks_agg a, (values ('bronze',1,1),('silver',3,2),('gold',10,3)) as t(tier,thr,rank)
  where a.regions >= t.thr
$$;

revoke execute on function achievement_tiers_met(uuid) from public, anon, authenticated;

-- ──────────────────────── award triggers ────────────────────────

create or replace function private.award_park_course_achievements(p_user uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_challenge uuid;
begin
  begin
    perform award_achievements_for_user(p_user);
  exception when others then
    raise warning 'park course achievements for % failed: %', p_user, sqlerrm;
  end;

  for v_challenge in
    select c.id
    from challenges c
    join challenge_participants pp on pp.challenge_id = c.id and pp.user_id = p_user
    where c.metric = 'park_courses'
      and c.goal_value is not null
      and c.ends_at > now() - interval '1 day'
      and pp.completed_at is null
  loop
    begin
      perform recompute_challenge_completion(v_challenge, p_user);
    exception when others then
      raise warning 'park course challenge % for % failed: %', v_challenge, p_user, sqlerrm;
    end;
  end loop;
end;
$$;

revoke execute on function private.award_park_course_achievements(uuid) from public, anon, authenticated;

create or replace function private.trigger_award_park_course_efforts()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
begin
  for v_user_id in
    select distinct n.user_id
    from new_efforts n
    where exists (select 1 from park_courses pc where pc.global_segment_id = n.global_segment_id)
  loop
    perform private.award_park_course_achievements(v_user_id);
  end loop;
  return null;
end;
$$;

create trigger global_segment_efforts_award_park_achievements
  after insert on public.global_segment_efforts
  referencing new table as new_efforts
  for each statement execute function private.trigger_award_park_course_efforts();

-- A course added to a park, moved, re-pointed or closed: re-derive for every
-- runner with an effort on any course of the parks it touched. Two functions,
-- because a statement trigger's body cannot name a transition table its event
-- does not have.
create or replace function private.award_park_course_parks(p_parks uuid[])
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
begin
  for v_user_id in
    select distinct e.user_id
    from park_courses pc
    join global_segment_efforts e on e.global_segment_id = pc.global_segment_id
    where pc.park_id = any (p_parks)
  loop
    perform private.award_park_course_achievements(v_user_id);
  end loop;
end;
$$;

revoke execute on function private.award_park_course_parks(uuid[]) from public, anon, authenticated;

create or replace function private.trigger_award_park_course_inserts()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform private.award_park_course_parks(array(select distinct park_id from new_courses));
  return null;
end;
$$;

create or replace function private.trigger_award_park_course_updates()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform private.award_park_course_parks(array(
    select n.park_id
    from new_courses n
    join old_courses o on o.id = n.id
    where (o.status, o.park_id, o.global_segment_id)
      is distinct from (n.status, n.park_id, n.global_segment_id)
    union
    select o.park_id
    from old_courses o
    join new_courses n on n.id = o.id
    where o.park_id is distinct from n.park_id
  ));
  return null;
end;
$$;

create trigger park_courses_award_achievements_insert
  after insert on public.park_courses
  referencing new table as new_courses
  for each statement execute function private.trigger_award_park_course_inserts();

create trigger park_courses_award_achievements_update
  after update on public.park_courses
  referencing old table as old_courses new table as new_courses
  for each statement execute function private.trigger_award_park_course_updates();

-- ──────────────────── challenge metric: park_courses ────────────────────

alter table challenges add column park_region_code text;

alter table challenges drop constraint challenges_metric_ck;
alter table challenges
  add constraint challenges_metric_ck check (
    metric in ('distance', 'duration', 'vert', 'activity_count', 'streak_days', 'park_courses'));

alter table challenges
  add constraint challenges_park_region_code_ck check (
    park_region_code is null
    or (metric = 'park_courses'
        and length(park_region_code) <= 6
        and park_region_code ~ '^[A-Z]{2}-[A-Z0-9]{1,3}$'));

-- Live body 20271112000020 plus the park_courses branch, which counts distinct
-- park courses (not closed, active park, the challenge's region when set) the
-- participant completed on in-window, non-DNF runs of the challenge's activity
-- type. The team branch counts distinct courses across the team.
create or replace function challenge_leaderboard(
  p_challenge_id uuid,
  p_by_team boolean default false
)
returns table (
  user_id uuid,
  display_name text,
  team_club_id uuid,
  value numeric,
  rank bigint
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_metric        text;
  v_activity_type text;
  v_starts        timestamptz;
  v_ends          timestamptz;
  v_region        text;
begin
  if not is_challenge_visible(p_challenge_id) then
    return;
  end if;

  select c.metric, c.activity_type, c.starts_at, c.ends_at, c.park_region_code
    into v_metric, v_activity_type, v_starts, v_ends, v_region
  from challenges c
  where c.id = p_challenge_id;

  if v_metric is null then
    return;
  end if;

  if p_by_team then
    return query
    with per_team as (
      select
        pp.team_club_id,
        coalesce(
          case v_metric
            when 'distance' then sum(r.distance_m)
            when 'duration' then sum(r.duration_s) filter (where private.run_duration_in_bound(r.duration_s))::numeric
            when 'vert' then sum(coalesce(r.elevation_gain_m, 0))
            when 'activity_count' then count(r.id)::numeric
            when 'streak_days' then count(distinct (r.started_at at time zone 'UTC')::date)::numeric
            when 'park_courses' then (
              select count(distinct pc.id)::numeric
              from challenge_participants tp
              join global_segment_efforts e on e.user_id = tp.user_id
              join runs er
                on er.id = e.run_id
               and er.started_at >= v_starts
               and er.started_at < v_ends
               and er.is_dnf = false
               and (v_activity_type is null or er.activity_type = v_activity_type)
              join park_courses pc on pc.global_segment_id = e.global_segment_id and pc.status <> 'closed'
              join parks pk
                on pk.id = pc.park_id
               and pk.is_active
               and (v_region is null or pk.region_code = v_region)
              where tp.challenge_id = p_challenge_id
                and tp.team_club_id is not distinct from pp.team_club_id
            )
          end,
          0
        ) as value
      from challenge_participants pp
      left join runs r
        on r.user_id = pp.user_id
       and r.started_at >= v_starts
       and r.started_at < v_ends
       and r.is_dnf = false
       and (v_activity_type is null or r.activity_type = v_activity_type)
      where pp.challenge_id = p_challenge_id
      group by pp.team_club_id
    )
    select
      null::uuid as user_id,
      null::text as display_name,
      pt.team_club_id,
      pt.value,
      rank() over (order by pt.value desc) as rank
    from per_team pt
    order by rank, pt.team_club_id nulls last;
  else
    return query
    with per_user as (
      select
        pp.user_id,
        pp.team_club_id,
        coalesce(
          case v_metric
            when 'distance' then sum(r.distance_m)
            when 'duration' then sum(r.duration_s) filter (where private.run_duration_in_bound(r.duration_s))::numeric
            when 'vert' then sum(coalesce(r.elevation_gain_m, 0))
            when 'activity_count' then count(r.id)::numeric
            when 'streak_days' then count(distinct (r.started_at at time zone 'UTC')::date)::numeric
            when 'park_courses' then (
              select count(distinct pc.id)::numeric
              from global_segment_efforts e
              join runs er
                on er.id = e.run_id
               and er.started_at >= v_starts
               and er.started_at < v_ends
               and er.is_dnf = false
               and (v_activity_type is null or er.activity_type = v_activity_type)
              join park_courses pc on pc.global_segment_id = e.global_segment_id and pc.status <> 'closed'
              join parks pk
                on pk.id = pc.park_id
               and pk.is_active
               and (v_region is null or pk.region_code = v_region)
              where e.user_id = pp.user_id
            )
          end,
          0
        ) as value
      from challenge_participants pp
      left join runs r
        on r.user_id = pp.user_id
       and r.started_at >= v_starts
       and r.started_at < v_ends
       and r.is_dnf = false
       and (v_activity_type is null or r.activity_type = v_activity_type)
      where pp.challenge_id = p_challenge_id
      group by pp.user_id, pp.team_club_id
    )
    select
      pu.user_id,
      case when p.id = auth.uid()
             or (p.shadow_hidden = false
                 and private.profile_visible_to(p.id, auth.uid()))
        then p.display_name end as display_name,
      pu.team_club_id,
      pu.value,
      rank() over (order by pu.value desc) as rank
    from per_user pu
    left join user_profiles p on p.id = pu.user_id
    order by rank, pu.user_id nulls last;
  end if;
end;
$$;

-- Live body 20271112000020 plus the same park_courses count.
create or replace function recompute_challenge_completion(p_challenge_id uuid, p_user_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_metric        text;
  v_activity_type text;
  v_goal          numeric;
  v_starts        timestamptz;
  v_ends          timestamptz;
  v_region        text;
  v_value         numeric;
begin
  -- auth.uid() is null for the cron sweep / service-role path. For an
  -- authenticated caller it must match the user whose completion is recomputed
  -- — no driving another user's badge / completed_at / notification.
  if auth.uid() is not null and auth.uid() <> p_user_id then
    raise exception
      'recompute_challenge_completion: caller cannot recompute another user'
      using errcode = '42501';
  end if;

  select c.metric, c.activity_type, c.goal_value, c.starts_at, c.ends_at, c.park_region_code
    into v_metric, v_activity_type, v_goal, v_starts, v_ends, v_region
  from challenges c
  where c.id = p_challenge_id;

  if v_metric is null or v_goal is null then
    return;
  end if;

  if not exists (
    select 1 from challenge_participants pp
    where pp.challenge_id = p_challenge_id and pp.user_id = p_user_id
  ) then
    return;
  end if;

  -- Cheap pre-check: skips the aggregate for the already-awarded common case.
  -- NOT the dedupe — the badge insert below is.
  if exists (
    select 1 from challenge_badges b
    where b.challenge_id = p_challenge_id and b.user_id = p_user_id
  ) then
    return;
  end if;

  if v_metric = 'park_courses' then
    select count(distinct pc.id)::numeric
      into v_value
    from global_segment_efforts e
    join runs r
      on r.id = e.run_id
     and r.started_at >= v_starts
     and r.started_at < v_ends
     and r.is_dnf = false
     and (v_activity_type is null or r.activity_type = v_activity_type)
    join park_courses pc on pc.global_segment_id = e.global_segment_id and pc.status <> 'closed'
    join parks pk
      on pk.id = pc.park_id
     and pk.is_active
     and (v_region is null or pk.region_code = v_region)
    where e.user_id = p_user_id;
  else
    select coalesce(
      case v_metric
        when 'distance' then sum(r.distance_m)
        when 'duration' then sum(r.duration_s) filter (where private.run_duration_in_bound(r.duration_s))::numeric
        when 'vert' then sum(coalesce(r.elevation_gain_m, 0))
        when 'activity_count' then count(r.id)::numeric
        when 'streak_days' then count(distinct (r.started_at at time zone 'UTC')::date)::numeric
      end,
      0
    )
    into v_value
    from runs r
    where r.user_id = p_user_id
      and r.started_at >= v_starts
      and r.started_at < v_ends
      and r.is_dnf = false
      and (v_activity_type is null or r.activity_type = v_activity_type);
  end if;

  if v_value >= v_goal then
    insert into challenge_badges (user_id, challenge_id, metric, final_value)
    values (p_user_id, p_challenge_id, v_metric, v_value)
    on conflict (user_id, challenge_id) do nothing;

    -- The badge insert is the serialization point. On conflict it inserts no
    -- row and FOUND is false, so the caller that lost the race stops here
    -- rather than emitting a second `challenge_complete` for the same award.
    if not found then
      return;
    end if;

    update challenge_participants
    set completed_at = now()
    where challenge_id = p_challenge_id
      and user_id = p_user_id
      and completed_at is null;

    insert into notifications (user_id, kind, challenge_id)
    values (p_user_id, 'challenge_complete', p_challenge_id);
  end if;
end;
$$;

-- ─────────────────── the run's park course times ───────────────────

-- The share image's course sticker: each park course the caller's own run
-- completed, with the season it falls in (the calendar year in the park's
-- timezone) and the effort's place on that season's fastest board when it is
-- the runner's best of the season and inside the top 100. The rank comes from
-- global_segment_leaderboard itself, so it is the rank the caller sees on the
-- course page, under every rule that board applies. Only the run's owner gets
-- rows: the image is theirs to make.
create or replace function public.run_park_course_times(p_run_id uuid)
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
  season_rank integer
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
    )
  from public.global_segment_efforts e
  join public.park_courses pc on pc.global_segment_id = e.global_segment_id
  join public.parks pk on pk.id = pc.park_id
  join public.global_segments gs on gs.id = e.global_segment_id
  cross join lateral (
    select extract(year from (e.started_at at time zone pk.timezone))::integer as season
  ) s
  where e.run_id = p_run_id
    and e.user_id = (select auth.uid())
  order by e.started_at, gs.name;
$$;

revoke execute on function public.run_park_course_times(uuid) from public, anon;
grant execute on function public.run_park_course_times(uuid) to authenticated, service_role;

-- ───────────────────────── back-fill ─────────────────────────

do $$
declare
  v_user_id uuid;
begin
  for v_user_id in
    select distinct e.user_id
    from global_segment_efforts e
    join park_courses pc on pc.global_segment_id = e.global_segment_id
  loop
    perform award_achievements_for_user(v_user_id);
  end loop;
end;
$$;

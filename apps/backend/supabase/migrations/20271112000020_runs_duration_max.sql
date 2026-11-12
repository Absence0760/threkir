-- A run's duration had a floor (`runs_duration_s_check`, 20270704000001) and
-- no ceiling, so a manual entry with "12333" in the Hours box stored a 2 km run
-- lasting 44,400,094 s — 12,333 hours — and every total that summed it read the
-- same absurd number: the weekly summary, the recap, and the `duration`
-- challenge board, where it ranked its author first (issue #1300 § 5,
-- decisions § 2359). That migration chose no upper bound on the grounds that
-- the honest ceiling was unknown; it is known now. The longest single efforts
-- any writer here produces are multi-day ultras — the Moab 240's cutoff is
-- 112 h — so ten days (864,000 s) refuses no real activity.
--
-- Writers checked against the bound: the manual forms (now graded by the
-- `run_duration` parity pair first), the mobile/watch batch push (`api_client`
-- parks an out-of-bound run instead of letting it fail its whole chunk), the
-- Strava ingest (a run-family `moving_time` past ten days is not a run; the
-- backfill counts one refused insert as `failed` and carries on), parkrun and
-- race-results imports (single races), and the web file importers (one run
-- per insert).
--
-- Online-safety (docs/backend/migration_locks.md): `runs` is the
-- highest-volume table, so the constraint is added NOT VALID — a metadata flip
-- under a brief ACCESS EXCLUSIVE, no scan. It binds every INSERT and UPDATE
-- from here on, including an UPDATE of an existing out-of-bound row, which is
-- what makes the repair (edit the duration) the only edit such a row accepts.
--
-- It is deliberately NOT validated here. Unlike 20270704000001's negatives,
-- an out-of-bound duration has no honest automatic repair — clamping a typo to
-- ten days is as wrong as the typo — so the rows are listed for owner review
-- first. The listing query and the VALIDATE step are a deploy checklist item
-- in docs/product/followups.md:
--
--   select id, user_id, started_at, distance_m, duration_s, source
--     from runs where duration_s > 864000 order by started_at;
--
-- Until VALIDATE lands, old rows can still sit above the bound, so the two
-- challenge aggregates that sum `duration_s` skip them through
-- `private.run_duration_in_bound` — the SQL twin of the clients'
-- `isPlausibleRunDuration` — rather than letting one row swamp a board.
--
-- No `started_at` future guard. A CHECK cannot call now() (it is not
-- immutable), and a trigger can, but it would refuse real runs: a watch or
-- phone with a wrong clock records a genuine run stamped in the future, and a
-- refusal there is a permanent sync failure for a real activity. The manual
-- forms refuse a future start, which is the path the issue reached.

create or replace function private.run_duration_in_bound(p_duration_s integer)
returns boolean
language sql
immutable
set search_path = pg_catalog
as $$
  select p_duration_s between 0 and 864000
$$;

revoke execute on function private.run_duration_in_bound(integer) from public, anon, authenticated;

comment on function private.run_duration_in_bound(integer) is
  'The read-side bound on runs.duration_s (0..864000 s, ten days): a duration '
  'aggregate sums only rows inside it, so a row from before '
  'runs_duration_s_max_check was validated cannot swamp a total. SQL twin of '
  'isPlausibleRunDuration in the run_duration parity pair (decisions § 2359).';

alter table runs
  add constraint runs_duration_s_max_check
  check (duration_s <= 864000)
  not valid;

comment on constraint runs_duration_s_max_check on runs is
  'A run lasts at most ten days (864000 s). Added NOT VALID; validate after '
  'the owner has reviewed the rows above it (followups.md, decisions § 2359).';

-- Live body 20270822000001; the duration branch sums only in-bound rows.
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
begin
  if not is_challenge_visible(p_challenge_id) then
    return;
  end if;

  select c.metric, c.activity_type, c.starts_at, c.ends_at
    into v_metric, v_activity_type, v_starts, v_ends
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

-- Live body 20270521_001; the duration branch sums only in-bound rows.
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

  select c.metric, c.activity_type, c.goal_value, c.starts_at, c.ends_at
    into v_metric, v_activity_type, v_goal, v_starts, v_ends
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

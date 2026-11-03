-- Head-to-head: the caller's best attempt against a friend's on the same route
-- or segment, for the share card (issue #1273 item 9, decisions § 2267).
--
-- One read, `head_to_head(kind, target, friend?)`. With no friend it lists
-- every friend the caller may be compared against on that target, each row
-- carrying both sides, so the picker only ever offers a friend with a result.
-- With a friend it returns that one row or none.
--
-- A row exists only when ALL of these hold, and every failure returns the same
-- nothing, so the call cannot be used to tell "not allowed" from "no data":
--   * the caller and the friend follow each other (both user_follows edges);
--   * neither has blocked the other;
--   * the friend's profile is not private and not shadow-hidden;
--   * the target is visible to the caller (private.is_route_visible_to for a
--     route or a route segment; an active catalogue segment otherwise);
--   * each side's attempt is on a PUBLIC run: is_public, not followers_only,
--     not a DNF, more than 100 m, of the requested activity type. The caller's
--     own run is held to the same rule because the card publishes both times.
--
-- What it does not read: `personal_records` (owner-only; the best attempt is
-- computed here from runs and efforts the caller could already read), any
-- track or waypoint (the card draws no line), and `date_of_birth` / `gender`:
-- no age band is derived, which is the strictest reading of the age-band
-- consent rule `segment_leaderboard_tiered` applies (20270606_001).
--
-- Why no feature flag: every number it returns is already readable by this
-- caller. A public run's duration and route are on the friend's public
-- profile, and a public run's segment effort is on the segment leaderboards
-- every signed-in user reads; this read is narrower than both (mutual follows
-- only, no private profile). Decisions § 2267.
--
-- Locks: a new function and its grants, catalogue-only.

create or replace function public.head_to_head(
  p_kind text,
  p_target_id uuid,
  p_friend_id uuid default null,
  p_activity_type text default 'run'
)
returns table (
  friend_id uuid,
  friend_display_name text,
  friend_handle text,
  friend_avatar_url text,
  target_name text,
  my_run_id uuid,
  my_seconds integer,
  my_started_at timestamptz,
  friend_run_id uuid,
  friend_seconds integer,
  friend_started_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public, private
as $$
declare
  v_caller uuid := auth.uid();
  v_name text;
  v_route uuid;
begin
  if v_caller is null then
    raise exception 'head_to_head requires an authenticated caller'
      using errcode = '42501';
  end if;
  if p_kind is null or p_kind not in ('route', 'segment', 'global_segment') then
    raise exception 'head_to_head: invalid p_kind %', p_kind
      using errcode = '22023';
  end if;
  if p_target_id is null or p_friend_id = v_caller then
    return;
  end if;

  if p_kind = 'route' then
    select r.name, r.id into v_name, v_route from public.routes r where r.id = p_target_id;
  elsif p_kind = 'segment' then
    select s.name, s.route_id into v_name, v_route from public.segments s where s.id = p_target_id;
  else
    select gs.name into v_name
      from public.global_segments gs
     where gs.id = p_target_id and gs.is_active = true;
  end if;

  if v_name is null then
    return;
  end if;
  if p_kind <> 'global_segment'
     and (v_route is null or not private.is_route_visible_to(v_route, v_caller)) then
    return;
  end if;

  return query
  with attempts as (
    select r.user_id, r.id as run_id, r.duration_s::integer as seconds, r.started_at
      from public.runs r
     where p_kind = 'route' and r.route_id = p_target_id
       and r.is_public = true and r.followers_only = false and r.is_dnf = false
       and r.distance_m > 100 and r.activity_type = p_activity_type
    union all
    select se.user_id, se.run_id, se.time_seconds::integer, se.started_at
      from public.segment_efforts se
      join public.runs r on r.id = se.run_id
     where p_kind = 'segment' and se.segment_id = p_target_id
       and r.is_public = true and r.followers_only = false and r.is_dnf = false
       and r.activity_type = p_activity_type
    union all
    select ge.user_id, ge.run_id, ge.time_seconds::integer, ge.started_at
      from public.global_segment_efforts ge
      join public.runs r on r.id = ge.run_id
     where p_kind = 'global_segment' and ge.global_segment_id = p_target_id
       and r.is_public = true and r.followers_only = false and r.is_dnf = false
       and r.activity_type = p_activity_type
  ),
  best as (
    select distinct on (a.user_id) a.user_id, a.run_id, a.seconds, a.started_at
      from attempts a
     where a.seconds > 0
     order by a.user_id, a.seconds asc, a.started_at asc
  ),
  mine as (
    select * from best where best.user_id = v_caller
  ),
  friends as (
    select up.id, up.display_name, up.handle, up.avatar_url
      from public.user_profiles up
     where (p_friend_id is null or up.id = p_friend_id)
       and up.id <> v_caller
       and up.profile_private = false
       and up.shadow_hidden = false
       and exists (select 1 from public.user_follows f
                    where f.follower_id = v_caller and f.followee_id = up.id)
       and exists (select 1 from public.user_follows f
                    where f.follower_id = up.id and f.followee_id = v_caller)
       and not exists (select 1 from public.user_blocks b
                        where (b.blocker_id = v_caller and b.blocked_id = up.id)
                           or (b.blocker_id = up.id and b.blocked_id = v_caller))
  )
  select fr.id, fr.display_name, fr.handle, fr.avatar_url, v_name,
         mine.run_id, mine.seconds, mine.started_at,
         fb.run_id, fb.seconds, fb.started_at
    from mine
    cross join friends fr
    join best fb on fb.user_id = fr.id
   order by lower(coalesce(fr.handle, fr.display_name, '')), fr.id
   limit 100;
end;
$$;

revoke execute on function public.head_to_head(text, uuid, uuid, text) from public, anon;
grant execute on function public.head_to_head(text, uuid, uuid, text) to authenticated;

comment on function public.head_to_head(text, uuid, uuid, text) is
  'Caller''s best public attempt vs each mutual-follow friend''s on one route, '
  'route segment or catalogue segment. Mutual follows, no block, friend profile '
  'public and not shadow-hidden, both runs public. Every refusal is an empty '
  'result. Reads no personal_records, track or age. decisions § 2267.';

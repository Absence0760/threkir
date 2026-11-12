-- Private profiles and follower approval (decisions § 1967, reversing § 31 in
-- part).
--
-- § 31 made profiles and the follow graph public to every signed-in user and
-- deferred follower approval. The owner asked (issue #1168 item 5) for a
-- private profile whose activity, feed presence and follower lists are seen
-- only by followers the owner approved.
--
-- 1. user_profiles.profile_private, default false. Every account stays public
--    until its owner flips it, so this file changes nothing for anyone who
--    never touches the switch; that is why the enforcement is not behind a
--    feature flag (§ 1967). The column is cross-user readable (a viewer needs
--    it to render "Request to follow" instead of "Follow").
--
-- 2. follow_requests, a separate table, not a status column on user_follows.
--    Thirty-odd readers treat a user_follows row as "follows": the run audience
--    oracles (§ 1874), dm_recipients, can_share_with, run_completed fan-out
--    (§ 96), the feed, the friends route lens, people suggestions. A pending
--    row inside that table would be a follow to every one of them until each
--    learned a second predicate. In its own table it is nothing to any of
--    them, which is the fail-closed direction. Approval moves the row.
--
-- 3. private.profile_visible_to(owner, viewer): the owner, anyone when the
--    profile is public, an approved follower when it is private. It joins:
--      * user_follows SELECT, the follower and following lists (§ 31's sketch);
--      * the public_runs / public_gym_workouts / public_gym_sets /
--        public_food_log views (inlined there as an anti-join, because the
--        sitemap and share pages scan them unauthenticated);
--      * private.is_run_visible_to + is_run_photo_visible_to, which carry
--        kudos, comments, photos, segment efforts, live pings and gear, and
--        the segment leaderboards that read is_run_visible_to;
--      * public_profile_by_id, the anon projection behind /share/profile and
--        its unfurl, so a private profile is not-found there;
--      * public_run_counts and challenge_leaderboard's names.
--    A live broadcast (the in-progress stub a safety share creates, until it
--    concludes) stays readable on its own link: the runner sent that link to
--    be watched, and a private profile must not switch off the safety net.
--
-- 4. request_follow(target): one call that follows a public profile and asks
--    a private one; approve_follow_request(requester) moves a request into
--    user_follows. A decline or a cancel is a DELETE under RLS. Going public
--    approves everything pending. A block clears requests both ways.
--
-- 5. A `follow_request` notification to the owner, retracted when the request
--    is withdrawn, declined or approved while unread.
--
-- Not changed, deliberately: @handle search (§ 269) still finds a private
-- profile, or nobody could ask to follow it; display name and avatar stay
-- readable for the same reason. Routes, event results, recaps and badges are
-- published individually and keep their own visibility. Nearby discovery is
-- its own opt-in. A run shared to named people (run_shares) or followers
-- (followers_only) already admits only who the owner chose.
--
-- Locks: ADD COLUMN ... NOT NULL DEFAULT false is catalogue-only (PG 11+);
-- CREATE TABLE, functions, views and policies are catalogue-only; the two
-- CREATE TRIGGERs take SHARE ROW EXCLUSIVE on user_profiles / user_blocks
-- briefly. The notifications CHECK is widened NOT VALID here and validated in
-- 20270822000002 (docs/backend/migration_locks.md § CHECK constraints).

-- ─────────────── 1. the flag ───────────────

alter table public.user_profiles
  add column profile_private boolean not null default false;

comment on column public.user_profiles.profile_private is
  'Private profile: runs, gym and food entries, and follower lists are visible '
  'only to approved followers; follows become requests. decisions § 1967.';

-- The cross-user column grant is cumulative; re-emit the full list
-- (20270424000002) plus the new column.
revoke select on public.user_profiles from authenticated, anon;
grant select (
  id,
  display_name,
  avatar_url,
  created_at,
  handle,
  profile_private
) on public.user_profiles to authenticated, anon;

-- ─────────────── 2. the oracle ───────────────

create or replace function private.profile_is_private(p_user uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select u.profile_private from user_profiles u where u.id = p_user),
    false
  );
$$;

revoke execute on function private.profile_is_private(uuid) from public;
grant execute on function private.profile_is_private(uuid)
  to anon, authenticated, service_role;

create or replace function private.profile_visible_to(p_owner uuid, p_viewer uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select p_owner is not null
     and (
       (p_viewer is not null and p_viewer = p_owner)
       or not coalesce(
         (select u.profile_private from user_profiles u where u.id = p_owner),
         false
       )
       or (
         p_viewer is not null
         and exists (
           select 1 from user_follows f
            where f.follower_id = p_viewer and f.followee_id = p_owner
         )
       )
     );
$$;

revoke execute on function private.profile_visible_to(uuid, uuid) from public;
grant execute on function private.profile_visible_to(uuid, uuid)
  to anon, authenticated, service_role;

-- ─────────────── 3. follow_requests ───────────────

create table public.follow_requests (
  requester_id uuid not null references auth.users(id) on delete cascade,
  target_id    uuid not null references auth.users(id) on delete cascade,
  requested_at timestamptz not null default now(),
  primary key (requester_id, target_id),
  constraint follow_requests_not_self check (requester_id <> target_id)
);

create index follow_requests_target_idx
  on public.follow_requests (target_id, requested_at desc);

comment on table public.follow_requests is
  'A pending follow of a private profile. Approval moves it into user_follows; '
  'decline and cancel delete it. decisions § 1967.';

alter table public.follow_requests enable row level security;

create policy "parties read follow requests"
  on public.follow_requests for select
  to authenticated
  using (
    requester_id = (select auth.uid())
    or target_id = (select auth.uid())
  );

create policy "users request to follow a private profile"
  on public.follow_requests for insert
  to authenticated
  with check (
    requester_id = (select auth.uid())
    and requester_id <> target_id
    and private.profile_is_private(target_id)
    and not is_blocked_either_way(requester_id, target_id)
    and not exists (
      select 1 from user_follows f
       where f.follower_id = follow_requests.requester_id
         and f.followee_id = follow_requests.target_id
    )
  );

create policy "parties withdraw or decline follow requests"
  on public.follow_requests for delete
  to authenticated
  using (
    requester_id = (select auth.uid())
    or target_id = (select auth.uid())
  );

revoke all on table public.follow_requests from public, anon, authenticated;
grant select, insert, delete on table public.follow_requests to authenticated;
grant select, insert, update, delete on table public.follow_requests to service_role;

-- ─────────────── 4. user_follows policies ───────────────

drop policy "follows are readable by anyone authenticated" on public.user_follows;
create policy "follows readable within profile privacy"
  on public.user_follows for select
  to authenticated
  using (
    (select auth.uid()) = follower_id
    or (select auth.uid()) = followee_id
    or (
      private.profile_visible_to(follower_id, (select auth.uid()))
      and private.profile_visible_to(followee_id, (select auth.uid()))
    )
  );

-- Live body 20261012_001 (initplan-wrapped by 20270416_001) plus the private
-- profile clause: a private profile is followed only through approval, which
-- inserts as the definer below.
drop policy "users follow on their own behalf" on public.user_follows;
create policy "users follow on their own behalf"
  on public.user_follows for insert
  with check (
    (select auth.uid()) = follower_id
    and follower_id <> followee_id
    and not is_blocked_either_way(follower_id, followee_id)
    and not private.profile_is_private(followee_id)
  );

-- ─────────────── 5. notifications ───────────────

alter table public.notifications drop constraint notifications_kind_check;
alter table public.notifications
  add constraint notifications_kind_check
  check (
    kind in (
      'kudos', 'comment', 'comment_reply', 'follow',
      'event_rsvp', 'event_cancel', 'plan_update', 'message',
      'club_post', 'run_completed', 'event_reminder', 'plan_assigned',
      'achievement', 'challenge_complete', 'content_hidden',
      'data_export_ready', 'refund_failed', 'event_waitlist_slot',
      'follow_request'
    )
  )
  not valid;

create or replace function private.notify_follow_request()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (
    select 1 from notifications
     where user_id = new.target_id
       and actor_id = new.requester_id
       and kind = 'follow_request'
       and read_at is null
  ) then
    return new;
  end if;
  insert into notifications (user_id, actor_id, kind)
    values (new.target_id, new.requester_id, 'follow_request');
  return new;
end;
$$;

create or replace function private.cleanup_follow_request_notification()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from notifications
   where user_id = old.target_id
     and actor_id = old.requester_id
     and kind = 'follow_request'
     and read_at is null;
  return old;
end;
$$;

revoke execute on function private.notify_follow_request() from public, anon, authenticated;
revoke execute on function private.cleanup_follow_request_notification() from public, anon, authenticated;

create trigger follow_requests_notify
  after insert on public.follow_requests
  for each row execute function private.notify_follow_request();

create trigger follow_requests_notify_cleanup
  after delete on public.follow_requests
  for each row execute function private.cleanup_follow_request_notification();

-- Live body 20270310_001 plus one early return: an approved request inserts
-- the follow while its request row still exists, and the owner who just
-- approved it does not need "X started following you" on top.
create or replace function notify_user_follow()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if NEW.follower_id = NEW.followee_id then
    return NEW;
  end if;
  if exists (
    select 1 from follow_requests r
     where r.requester_id = NEW.follower_id
       and r.target_id = NEW.followee_id
  ) then
    return NEW;
  end if;
  -- Coalesce: don't stack a second unread follow notification for the same
  -- pair (rapid re-follow while the first is still unread).
  if exists (
    select 1 from notifications
     where user_id = NEW.followee_id
       and actor_id = NEW.follower_id
       and kind = 'follow'
       and read_at is null
  ) then
    return NEW;
  end if;
  insert into notifications (user_id, actor_id, kind)
    values (NEW.followee_id, NEW.follower_id, 'follow');
  return NEW;
end;
$$;

-- ─────────────── 6. the request / approve RPCs ───────────────

-- Invoker: both inserts go through the RLS above, so a block, a self-follow
-- or a request to a public profile is refused by the same rail a direct
-- write would hit.
create or replace function public.request_follow(p_target uuid)
returns text
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
  v_private boolean;
begin
  if v_me is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  if p_target is null or p_target = v_me then
    raise exception 'cannot follow yourself' using errcode = '22023';
  end if;

  select u.profile_private into v_private
    from user_profiles u
   where u.id = p_target;
  if not found then
    raise exception 'profile not found' using errcode = 'P0002';
  end if;

  if exists (
    select 1 from user_follows f
     where f.follower_id = v_me and f.followee_id = p_target
  ) then
    return 'following';
  end if;

  if v_private then
    insert into follow_requests (requester_id, target_id)
      values (v_me, p_target)
      on conflict do nothing;
    return 'requested';
  end if;

  insert into user_follows (follower_id, followee_id)
    values (v_me, p_target)
    on conflict do nothing;
  return 'following';
end;
$$;

revoke execute on function public.request_follow(uuid) from public, anon;
grant execute on function public.request_follow(uuid) to authenticated;

create or replace function public.approve_follow_request(p_requester uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
begin
  if v_me is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  if not exists (
    select 1 from follow_requests r
     where r.requester_id = p_requester and r.target_id = v_me
  ) then
    raise exception 'follow request not found' using errcode = 'P0002';
  end if;

  if not is_blocked_either_way(v_me, p_requester) then
    insert into user_follows (follower_id, followee_id)
      values (p_requester, v_me)
      on conflict do nothing;
  end if;

  delete from follow_requests
   where requester_id = p_requester and target_id = v_me;
end;
$$;

revoke execute on function public.approve_follow_request(uuid) from public, anon;
grant execute on function public.approve_follow_request(uuid) to authenticated;

-- The profile header in one round trip. A private profile's counts are shown
-- the way they are on every comparable app; the lists behind them are not.
-- No block filter: the profile row itself stays readable to a blocker, who
-- needs the page to unblock from (fetchPublicProfile reads both).
create or replace function public.profile_follow_summary(p_user_id uuid)
returns table (
  profile_private boolean,
  follower_count bigint,
  following_count bigint,
  viewer_follows boolean,
  viewer_requested boolean,
  content_visible boolean
)
language sql
stable
security definer
set search_path = public, private
as $$
  select
    u.profile_private,
    (select count(*) from user_follows f where f.followee_id = u.id),
    (select count(*) from user_follows f where f.follower_id = u.id),
    exists (
      select 1 from user_follows f
       where f.follower_id = auth.uid() and f.followee_id = u.id
    ),
    exists (
      select 1 from follow_requests r
       where r.requester_id = auth.uid() and r.target_id = u.id
    ),
    private.profile_visible_to(u.id, auth.uid())
  from user_profiles u
  where u.id = p_user_id
    and (u.shadow_hidden = false or u.id = auth.uid());
$$;

revoke execute on function public.profile_follow_summary(uuid) from public, anon;
grant execute on function public.profile_follow_summary(uuid) to authenticated;

-- ─────────────── 7. going public, and blocks ───────────────

create or replace function private.release_follow_requests()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into user_follows (follower_id, followee_id)
    select r.requester_id, r.target_id
      from follow_requests r
     where r.target_id = new.id
       and not is_blocked_either_way(r.requester_id, r.target_id)
    on conflict do nothing;
  delete from follow_requests where target_id = new.id;
  return new;
end;
$$;

revoke execute on function private.release_follow_requests() from public, anon, authenticated;

create trigger user_profiles_release_follow_requests
  after update of profile_private on public.user_profiles
  for each row
  when (old.profile_private and not new.profile_private)
  execute function private.release_follow_requests();

create or replace function private.clear_follow_requests_on_block()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from follow_requests
   where (requester_id = new.blocker_id and target_id = new.blocked_id)
      or (requester_id = new.blocked_id and target_id = new.blocker_id);
  return new;
end;
$$;

revoke execute on function private.clear_follow_requests_on_block() from public, anon, authenticated;

create trigger user_blocks_clear_follow_requests
  after insert on public.user_blocks
  for each row execute function private.clear_follow_requests_on_block();

-- ─────────────── 8. run visibility helpers ───────────────

-- Live body 20270802000003 + the profile clause on the public branch, with
-- the live-broadcast carve-out (see the header).
create or replace function private.is_run_visible_to(p_run_id uuid, p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from runs r
    where r.id = p_run_id
      and (
        r.user_id = p_user_id
        or (
          r.is_public = true
          and (
            private.profile_visible_to(r.user_id, p_user_id)
            or (r.concluded_at is null and r.metadata->>'in_progress' = 'true')
          )
        )
        or private.is_active_coach_of(p_user_id, r.user_id)
        or private.run_audience_admits(r.id, r.user_id, r.followers_only, p_user_id)
      )
  );
$$;

-- Live body 20270802000003 + the profile clause. Still no coach branch.
create or replace function private.is_run_photo_visible_to(p_run_id uuid, p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from runs r
    where r.id = p_run_id
      and (
        r.user_id = p_user_id
        or (r.is_public = true and private.profile_visible_to(r.user_id, p_user_id))
        or private.run_audience_admits(r.id, r.user_id, r.followers_only, p_user_id)
      )
  );
$$;

-- ─────────────── 9. the public views ───────────────

-- Live body 20270628000001 (column list and metadata denylist unchanged) plus
-- the profile clause. check_shared_constants.mjs holds this denylist equal to
-- shared_runs'.
create or replace view public_runs as
select
  r.id,
  r.user_id,
  r.started_at,
  r.duration_s,
  r.distance_m,
  r.elevation_gain_m,
  r.source,
  r.activity_type,
  r.is_dnf,
  r.is_public,
  r.created_at,
  case when is_public_route_by_id(r.route_id) then r.route_id else null end as route_id,
  case when is_public_event_by_id(r.event_id) then r.event_id else null end as event_id,
  r.race_listing_id,
  (r.track_url is not null) as has_track,
  r.fastest_5k_s,
  r.fastest_10k_s,
  r.fastest_half_marathon_s,
  r.fastest_marathon_s,
  coalesce(r.metadata, '{}'::jsonb)
    - 'strava_id'
    - 'garmin_id'
    - 'imported_from'
    - 'imported_at'
    - 'health_connect_type'
    - 'strava_activity_type'
    - 'source_file'
    - 'max_bpm'
    - 'plan_workout_id'
    - 'workout_step_results'
    - 'workout_adherence'
    - 'watch_workout'
    - 'guided_run_id'
    - 'indoor_source'
    - 'last_modified_at'
    - 'recovered_from_crash'
    - 'in_progress_saved_at'
    - 'in_progress'
    - 'safety_escalated_at'
    - 'expected_return_at'
    - 'manual_entry'
    - 'indoor_estimated'
    - 'distance_source'
    - 'race_name'
    - 'bib'
    - 'overall_place'
    - 'chip_time'
    - 'gun_time'
    - 'age_group_place'
    - 'age_group'
    - 'perceived_effort'
    - 'run_number'
    as metadata,
  r.concluded_at
from runs r
where r.is_public = true
  and (
    not exists (
      select 1 from user_profiles p
       where p.id = r.user_id and p.profile_private
    )
    or r.user_id = (select auth.uid())
    or exists (
      select 1 from user_follows f
       where f.followee_id = r.user_id and f.follower_id = (select auth.uid())
    )
    or (r.concluded_at is null and r.metadata->>'in_progress' = 'true')
  );

revoke all on public.public_runs from public, anon, authenticated;
grant select on public_runs to anon, authenticated;

-- Live body 20270313_001 + the profile clause.
create or replace view public.public_gym_workouts as
select
  w.id,
  w.user_id,
  w.started_at,
  w.title,
  w.duration_s,
  w.is_public,
  w.set_count,
  w.volume_kg,
  w.created_at
from public.gym_workouts w
where w.is_public = true
  and (
    not exists (
      select 1 from public.user_profiles p
       where p.id = w.user_id and p.profile_private
    )
    or w.user_id = (select auth.uid())
    or exists (
      select 1 from public.user_follows f
       where f.followee_id = w.user_id and f.follower_id = (select auth.uid())
    )
  );

revoke all on public.public_gym_workouts from public, anon, authenticated;
grant select on public.public_gym_workouts to anon, authenticated;

-- Live body 20270313_001 + the profile clause.
create or replace view public.public_food_log as
select
  f.id,
  f.user_id,
  f.started_at,
  f.item_name,
  f.meal_slot,
  f.calories,
  f.protein_g,
  f.carbs_g,
  f.fat_g,
  f.is_public,
  f.created_at
from public.food_log f
where f.is_public = true
  and (
    not exists (
      select 1 from public.user_profiles p
       where p.id = f.user_id and p.profile_private
    )
    or f.user_id = (select auth.uid())
    or exists (
      select 1 from public.user_follows uf
       where uf.followee_id = f.user_id and uf.follower_id = (select auth.uid())
    )
  );

revoke all on public.public_food_log from public, anon, authenticated;
grant select on public.public_food_log to anon, authenticated;

-- Live body 20270327_001 + the profile clause on the parent workout's owner.
create or replace view public.public_gym_sets as
select
  s.id,
  s.workout_id,
  s.set_index,
  s.exercise_name,
  s.reps,
  s.weight_kg,
  s.duration_s
from public.gym_sets s
join public.gym_workouts w on w.id = s.workout_id
where w.is_public = true
  and (
    not exists (
      select 1 from public.user_profiles p
       where p.id = w.user_id and p.profile_private
    )
    or w.user_id = (select auth.uid())
    or exists (
      select 1 from public.user_follows f
       where f.followee_id = w.user_id and f.follower_id = (select auth.uid())
    )
  );

revoke all on public.public_gym_sets from public, anon, authenticated;
grant select on public.public_gym_sets to anon, authenticated;

-- ─────────────── 10. definer readers ───────────────

-- Live body 20270307_001 + the profile clause: /share/profile and its unfurl
-- read this anonymously, so a private profile is not-found there.
create or replace function public_profile_by_id(p_id uuid)
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
  select u.id, u.display_name, u.avatar_url
  from user_profiles u
  where u.id = p_id
    and u.shadow_hidden = false
    and (auth.uid() is null
         or not is_blocked_either_way(auth.uid(), u.id))
    and private.profile_visible_to(u.id, auth.uid());
$$;

revoke all on function public_profile_by_id(uuid) from public;
grant execute on function public_profile_by_id(uuid) to anon, authenticated;

-- Live body 20270118_001 + the profile clause.
create or replace function public_run_counts(p_user_ids uuid[])
returns table (user_id uuid, public_run_count bigint)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select r.user_id, count(*) as public_run_count
  from runs r
  where r.user_id = any(p_user_ids)
    and r.is_public = true
    and private.profile_visible_to(r.user_id, auth.uid())
  group by r.user_id;
$$;

grant execute on function public_run_counts(uuid[]) to authenticated;

-- Live body 20270524_001; the per-athlete branch now withholds the name of a
-- participant whose private profile the caller cannot see, the way it already
-- withholds a shadow-hidden one. The rank and value stay: joining a challenge
-- is the participant's own choice to be counted.
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
            when 'duration' then sum(r.duration_s)::numeric
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
            when 'duration' then sum(r.duration_s)::numeric
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

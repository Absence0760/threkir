-- Challenge invite links (issue #1273 item 4, decisions § 2261).
--
-- A creator posts one link; a follower opens it, sees the challenge, signs up
-- and joins. Today a challenge outside a club that is not public cannot be
-- joined at all: the insert policy on challenge_participants needs the row to
-- be visible first, and nothing makes it visible to a stranger.
--
-- 1. private.challenge_invite_tokens: one revocable token per challenge. The
--    token is NOT a column on public.challenges, though clubs keep theirs on
--    the row. `challenges` carries table-level SELECT for anon and
--    authenticated (20270408_001), every client reads it with `select('*')`,
--    and RLS shows a public challenge to anyone, so a column there would
--    publish every token on the first read. clubs needed a column-grant
--    lockdown, a revert and a redo (20260801_001 → 20260817_001 →
--    20260818_001) to close the same leak. A table in the unexposed private
--    schema cannot reach a client by any read.
--
-- 2. The gate. Who can see and join a non-public challenge changes, so the
--    token path is fail-closed behind a private.feature_flags row that NO
--    MIGRATION WRITES ('challenge_invite_links'). It waits on the CISO /
--    Security Analyst sign-off in docs/features/challenges.md (§ 150);
--    seed.sql opens it for local + CI. The public reader tells both clients
--    whether to offer the link at all.
--
-- 3. RPCs, all SECURITY DEFINER:
--      get_challenge_invite_token(id)    creator / club admin; mints on first call
--      rotate_challenge_invite_token(id) creator / club admin; old link stops working
--      challenge_invite_preview(token)   anon + authenticated; what the link shows
--      join_challenge_by_token(token)    authenticated; rate-limited
--    club_vs_club challenges get no link: their participants pool into a
--    team, and a link has no way to pick one.
--
-- The preview and the leaderboard keep the name rules the rest of the app
-- follows: a creator's name only where private.profile_visible_to admits the
-- caller and the profile is not shadow-hidden, null otherwise. The preview
-- withholds the creator's id under the same rule, so the join page shows the
-- anonymous runner label there rather than a handle derived from the id. challenge_leaderboard is unchanged and
-- already applies the same rule to every participant.
--
-- Locks: a new table in the private schema, its FK to challenges (empty
-- child, so the validating scan is instant; SHARE ROW EXCLUSIVE on challenges
-- for that moment only) and function creation. No populated table is
-- rewritten or scanned.

create table private.challenge_invite_tokens (
  challenge_id uuid primary key references public.challenges(id) on delete cascade,
  token        text not null unique,
  created_at   timestamptz not null default now()
);

comment on table private.challenge_invite_tokens is
  'One revocable invite token per challenge (decisions § 2261). Private schema '
  'so no client read can return it; reached only through the definer RPCs.';

alter table private.challenge_invite_tokens enable row level security;
revoke all on table private.challenge_invite_tokens from public, anon, authenticated;

create or replace function private.challenge_invite_links_enabled()
returns boolean
language sql
stable
security definer
set search_path = public, private
as $$
  select coalesce(
    (select f.enabled from private.feature_flags f where f.name = 'challenge_invite_links'),
    false
  );
$$;

revoke execute on function private.challenge_invite_links_enabled() from public, anon, authenticated;
grant execute on function private.challenge_invite_links_enabled() to service_role;

create or replace function public.challenge_invite_links_enabled()
returns boolean
language sql
stable
security definer
set search_path = public, private
as $$
  select private.challenge_invite_links_enabled();
$$;

revoke execute on function public.challenge_invite_links_enabled() from public;
grant execute on function public.challenge_invite_links_enabled() to anon, authenticated, service_role;

comment on function public.challenge_invite_links_enabled() is
  'Whether challenge invite links are live (decisions § 2261). Clients hide the '
  'invite and join-by-link surfaces when false.';

-- Who may hand out a challenge's link: the creator, or an admin of the club it
-- is anchored to. The same two the update policy admits.
create or replace function private.can_manage_challenge_invite(p_challenge_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, private
as $$
  select exists (
    select 1 from challenges c
    where c.id = p_challenge_id
      and c.scope <> 'club_vs_club'
      and (
        c.creator_id = (select auth.uid())
        or (c.club_id is not null and private.is_club_admin(c.club_id))
      )
  );
$$;

revoke execute on function private.can_manage_challenge_invite(uuid) from public, anon, authenticated;
grant execute on function private.can_manage_challenge_invite(uuid) to service_role;

create or replace function private.new_challenge_invite_token()
returns text
language sql
volatile
set search_path = public, extensions
as $$
  select translate(encode(extensions.gen_random_bytes(18), 'base64'), '+/', '-_');
$$;

revoke execute on function private.new_challenge_invite_token() from public, anon, authenticated;

create or replace function public.get_challenge_invite_token(p_challenge_id uuid)
returns text
language plpgsql
volatile
security definer
set search_path = public, private
as $$
declare
  v_token text;
begin
  if auth.uid() is null
     or not private.challenge_invite_links_enabled()
     or not private.can_manage_challenge_invite(p_challenge_id) then
    return null;
  end if;

  insert into private.challenge_invite_tokens (challenge_id, token)
  values (p_challenge_id, private.new_challenge_invite_token())
  on conflict (challenge_id) do nothing;

  select t.token into v_token
    from private.challenge_invite_tokens t
   where t.challenge_id = p_challenge_id;
  return v_token;
end;
$$;

revoke execute on function public.get_challenge_invite_token(uuid) from public, anon;
grant execute on function public.get_challenge_invite_token(uuid) to authenticated, service_role;

comment on function public.get_challenge_invite_token(uuid) is
  'The challenge''s invite token, minted on first call. Null unless the caller '
  'is the creator or a club admin, the challenge is not club_vs_club, and the '
  'challenge_invite_links gate is open (decisions § 2261).';

create or replace function public.rotate_challenge_invite_token(p_challenge_id uuid)
returns text
language plpgsql
volatile
security definer
set search_path = public, private
as $$
declare
  v_token text := private.new_challenge_invite_token();
begin
  if auth.uid() is null
     or not private.challenge_invite_links_enabled()
     or not private.can_manage_challenge_invite(p_challenge_id) then
    return null;
  end if;

  insert into private.challenge_invite_tokens (challenge_id, token)
  values (p_challenge_id, v_token)
  on conflict (challenge_id) do update
    set token = excluded.token, created_at = now();
  return v_token;
end;
$$;

revoke execute on function public.rotate_challenge_invite_token(uuid) from public, anon;
grant execute on function public.rotate_challenge_invite_token(uuid) to authenticated, service_role;

comment on function public.rotate_challenge_invite_token(uuid) is
  'Replace the challenge''s invite token; the old link stops working at once. '
  'Same caller rule as get_challenge_invite_token.';

-- What a link shows before anyone joins: the challenge's own fields, its
-- participant count (the trigger-maintained cache), and the creator's id and
-- name under the profile-visibility rule. The id is withheld with the name:
-- an anon caller holding a private creator's id could open their profile
-- route and pin the link to a person the name rule was keeping unnamed. No
-- participant list: a private challenge's board stays with its participants.
create or replace function public.challenge_invite_preview(p_token text)
returns table (
  id                uuid,
  title             text,
  description       text,
  metric            text,
  scope             text,
  goal_value        numeric,
  activity_type     text,
  starts_at         timestamptz,
  ends_at           timestamptz,
  is_public         boolean,
  participant_count integer,
  creator_id        uuid,
  creator_name      text,
  joined            boolean
)
language sql
stable
security definer
set search_path = public, private
as $$
  select
    c.id,
    c.title,
    c.description,
    c.metric,
    c.scope,
    c.goal_value,
    c.activity_type,
    c.starts_at,
    c.ends_at,
    c.is_public,
    c.participant_count,
    case when p.id = (select auth.uid())
           or (p.shadow_hidden = false
               and private.profile_visible_to(p.id, (select auth.uid())))
      then c.creator_id end as creator_id,
    case when p.id = (select auth.uid())
           or (p.shadow_hidden = false
               and private.profile_visible_to(p.id, (select auth.uid())))
      then p.display_name end as creator_name,
    exists (
      select 1 from challenge_participants cp
      where cp.challenge_id = c.id and cp.user_id = (select auth.uid())
    ) as joined
  from private.challenge_invite_tokens t
  join challenges c on c.id = t.challenge_id
  left join user_profiles p on p.id = c.creator_id
  where private.challenge_invite_links_enabled()
    and p_token is not null
    and t.token = p_token
    and c.scope <> 'club_vs_club'
    and (c.creator_id = (select auth.uid()) or not coalesce(p.shadow_hidden, false))
    and ((select auth.uid()) is null
         or not is_blocked_either_way((select auth.uid()), c.creator_id));
$$;

revoke execute on function public.challenge_invite_preview(text) from public;
grant execute on function public.challenge_invite_preview(text) to anon, authenticated, service_role;

comment on function public.challenge_invite_preview(text) is
  'The challenge an invite token names, for the join page. Empty for an '
  'unknown or rotated token, a shadow-hidden creator, a block either way '
  'between caller and creator, and while the challenge_invite_links gate is '
  'closed. Creator id and name follow profile_visible_to (decisions § 2261).';

-- Join by link. An unknown token returns NULL rather than raising: a raise
-- would roll back the rate-limit counter with it, and then guessing tokens
-- would cost nothing. 30 attempts per user per hour, hit or miss.
--
-- The insert runs as the definer, so the policy that guards an ordinary join
-- never sees it. The checks a stranger's join needs are written here instead,
-- and each refuses exactly as an unknown token does, so a refusal says
-- nothing about which rule fired: a block either way between joiner and
-- creator, a challenge that has ended, and a shadow-hidden creator (whose
-- challenge the preview no longer shows either).
create or replace function public.join_challenge_by_token(p_token text)
returns uuid
language plpgsql
volatile
security definer
set search_path = public, private
as $$
declare
  v_uid uuid := auth.uid();
  v_challenge uuid;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  if not private.challenge_invite_links_enabled() then
    raise exception 'challenge_invite_links_disabled'
      using errcode = 'P0001',
            hint = 'Challenge invite links are not available yet.';
  end if;

  perform enforce_create_rate_limit('join_challenge_by_token', v_uid, 30, 3600);

  select c.id into v_challenge
    from private.challenge_invite_tokens t
    join challenges c on c.id = t.challenge_id
    left join user_profiles p on p.id = c.creator_id
   where p_token is not null
     and t.token = p_token
     and c.scope <> 'club_vs_club'
     and c.ends_at > now()
     and (c.creator_id = v_uid or not coalesce(p.shadow_hidden, false))
     and not is_blocked_either_way(v_uid, c.creator_id);

  if v_challenge is null then
    return null;
  end if;

  insert into challenge_participants (challenge_id, user_id)
  values (v_challenge, v_uid)
  on conflict (challenge_id, user_id) do nothing;

  return v_challenge;
end;
$$;

revoke execute on function public.join_challenge_by_token(text) from public, anon;
grant execute on function public.join_challenge_by_token(text) to authenticated, service_role;

comment on function public.join_challenge_by_token(text) is
  'Join the challenge an invite token names. Returns its id, or NULL for an '
  'unknown or rotated token, an ended challenge, a shadow-hidden creator or a '
  'block either way between joiner and creator. Raises challenge_invite_links_disabled while the '
  'gate is closed; rate-limited to 30 attempts per user per hour '
  '(decisions § 2261).';

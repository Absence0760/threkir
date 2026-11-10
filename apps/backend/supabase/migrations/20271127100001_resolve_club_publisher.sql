-- The release's park catalogue sync resolves its author at run time
-- (issue #1349, decisions § 2429): the committed config names the official
-- club by slug and id, and this function names the account that publishes as
-- it, so a change of club ownership never breaks a release.
--
-- The author is the club's active owner, or failing that its active admin
-- with the earliest `joined_at` (then the lowest user id, so the pick is
-- deterministic). The same rule as `private.is_official_publisher`, so the
-- account it returns is one `load_park_catalogue` accepts. It refuses, naming
-- the reason: a slug no club has (P0002), a slug whose club is not the
-- committed id (22023), a club that is not verified, public and visible, or
-- one with no active owner or admin (42501).
--
-- Locks (docs/backend/migration_locks.md): one new function and its grants.

create or replace function private.resolve_club_publisher(p_club_slug text, p_club_id uuid)
returns uuid
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_club record;
  v_author uuid;
begin
  select c.id, c.is_verified, c.is_public, c.shadow_hidden
    into v_club
    from clubs c
   where c.slug = p_club_slug;
  if not found then
    raise exception 'resolve_club_publisher: no club has the slug %', p_club_slug using errcode = 'P0002';
  end if;
  if v_club.id is distinct from p_club_id then
    raise exception 'resolve_club_publisher: the club % is %, not the committed %', p_club_slug, v_club.id, p_club_id
      using errcode = '22023';
  end if;
  if not (v_club.is_verified and v_club.is_public and not v_club.shadow_hidden) then
    raise exception 'resolve_club_publisher: the club % is not verified, public and visible', p_club_slug
      using errcode = '42501';
  end if;

  select m.user_id
    into v_author
    from club_members m
   where m.club_id = v_club.id
     and m.status = 'active'
     and m.role in ('owner', 'admin')
   order by (m.role = 'owner') desc, m.joined_at asc nulls last, m.user_id
   limit 1;
  if v_author is null then
    raise exception 'resolve_club_publisher: the club % has no active owner or admin', p_club_slug
      using errcode = '42501';
  end if;
  return v_author;
end;
$$;

comment on function private.resolve_club_publisher(text, uuid) is
  'The account that publishes as the official club: its active owner, else its earliest-joined active admin. '
  'Refuses a slug/id mismatch, a club that is not verified, public and visible, or one with no active owner '
  'or admin. Service role only; the release''s park catalogue sync calls it (decisions § 2429).';

revoke execute on function private.resolve_club_publisher(text, uuid) from public, anon, authenticated;
grant execute on function private.resolve_club_publisher(text, uuid) to service_role;

-- A Threkir club can record which Strava club it is (issue #1151 step 4,
-- decisions § 1953).
--
-- `strava_club_id` is the Strava club's numeric id. It is unique where set,
-- because a link is a claim: two Threkir clubs both saying they are the same
-- Strava club would make "this Strava club is already on Threkir" ambiguous.
--
-- Nothing a client sends writes it. The only writer is `set_club_strava_link`,
-- granted to service_role alone and called by the `strava-clubs` Edge
-- Function after it has checked, with the caller's own Strava token, that the
-- caller is an admin or owner of that Strava club on Strava. The SQL side
-- re-checks that the caller is an active owner/admin of the Threkir club.
-- Neither half alone is enough: without the Strava check any Threkir club
-- admin could squat any Strava club id, and the database cannot ask Strava.
--
-- The client-side write is frozen in the same trigger that already freezes
-- `clubs`' moderation and derived columns (20270704000003), not refused by a
-- column grant: that trigger's header records why a discard beats a 42501 on
-- this table (a whole-row upsert of a club read back earlier must keep
-- working). Its body is re-emitted in full below, unchanged apart from the new
-- column, because `create or replace` replaces the whole definition.
--
-- Online safety: `clubs` is small and bounded and not in the guarded set. The
-- column is nullable with no default (catalogue-only), and the partial unique
-- index is built over a column that is NULL on every existing row. The
-- function statements lock no table.

set search_path = public, extensions;

alter table clubs add column strava_club_id bigint;

create unique index clubs_strava_club_id_key
  on clubs (strava_club_id)
  where strava_club_id is not null;

-- `clubs` SELECT is column-granted (20260801_001 lockdown), so a new column is
-- deny-by-default. The id names a public Strava club, the same fact the
-- already-readable `strava_url` link carries, and the Edge Function's
-- "already on Threkir" lookup runs under the caller's own session.
grant select (strava_club_id) on clubs to authenticated, anon;

create or replace function freeze_club_managed_columns()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if current_user not in ('anon', 'authenticated') then
    return new;
  end if;
  if tg_op = 'INSERT' then
    new.shadow_hidden  := false;
    new.is_verified    := false;
    new.member_count   := 0;
    new.strava_club_id := null;
  else
    new.shadow_hidden  := old.shadow_hidden;
    new.is_verified    := old.is_verified;
    new.member_count   := old.member_count;
    new.strava_club_id := old.strava_club_id;
  end if;
  return new;
end;
$$;

-- Returns a reason rather than raising, so the Edge Function can map each one
-- to its own response without parsing an error message.
create or replace function set_club_strava_link(
  p_actor uuid,
  p_club_id uuid,
  p_strava_club_id bigint
)
returns text
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_actor is null or p_club_id is null then
    return 'not_club_admin';
  end if;
  if p_strava_club_id is null or p_strava_club_id <= 0 then
    return 'invalid_strava_club';
  end if;
  if not exists (
    select 1 from club_members
     where club_id = p_club_id
       and user_id = p_actor
       and status = 'active'
       and role in ('owner', 'admin')
  ) then
    return 'not_club_admin';
  end if;
  update clubs set strava_club_id = p_strava_club_id where id = p_club_id;
  return 'ok';
exception
  when unique_violation then
    return 'already_linked';
end;
$$;

revoke all on function set_club_strava_link(uuid, uuid, bigint) from public, anon, authenticated;
grant execute on function set_club_strava_link(uuid, uuid, bigint) to service_role;

-- Unlinking asks nothing of Strava, so it is an ordinary client RPC gated on
-- the caller being an active owner/admin of the Threkir club. A separate
-- function rather than a NULL to the one above: "no id" meaning "unlink"
-- would turn a dropped argument into a silent unlink.
create or replace function unlink_club_strava(p_club_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if not private.is_club_admin(p_club_id) then
    return false;
  end if;
  update clubs set strava_club_id = null where id = p_club_id;
  return true;
end;
$$;

revoke all on function unlink_club_strava(uuid) from public, anon;
grant execute on function unlink_club_strava(uuid) to authenticated, service_role;

-- `search_clubs` returns `setof clubs` through an explicit column list, so a
-- new `clubs` column makes every call fail with "final statement returns too
-- few columns" until the list grows with it (20261220_001 repaired this same
-- break). Re-emitted with the COMPLETE live body of 20270817000031 and one
-- column appended; the signature is unchanged, so the grant carries over and
-- is restated as the source migration stated it.
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
    c.shadow_hidden,
    c.strava_club_id
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

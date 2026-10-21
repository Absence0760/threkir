-- Official content: derived from the verified club, never stored per row
-- (issue #1190 § 1, decisions § 2227).
--
-- A route, plan, gym routine, challenge or session plan reads as OFFICIAL when
-- it was published BY a verified organiser: its `club_id` names a club with
-- `is_verified = true`, and its author is an active owner or admin of that
-- club. Nothing new is stored on the content row. The flag is computed at read
-- time from two facts a client cannot write:
--
--   * `clubs.is_verified` is service-role only, reverted on any other insert
--     or update (`clubs_protect_is_verified`, `freeze_*_managed_columns`,
--     20270704000003);
--   * the author's role comes from `club_members`, whose role column only a
--     club admin can change, and never for the owner row.
--
-- So no row can forge it, and revoking a club's badge (or demoting the admin
-- who published) removes it from every piece of that club's content at once.
-- `routes.is_featured` stays a separate concept: featured is an editorial pick
-- from anyone; official is publication by the verified organiser.
--
-- The derivation exists ONCE, in `private.is_official_publisher`. Everything
-- else reads it:
--
--   1. PostgREST computed fields `is_official(<table>)` on routes,
--      training_plans, gym_routines, challenges and session_plans, so a client
--      selects `*, is_official` and RLS still decides which rows it sees;
--   2. an `is_official` column appended to the two route read views
--      (public_routes, shared_routes). public_gym_routines gains none: its
--      rows are public templates, and `gym_routines_public_not_club` keeps a
--      public template club-free, so the column could only ever be false. A
--      club's routines reach their members through the base table, where the
--      computed field answers;
--   3. the browse / discovery RPCs (`browse_public_challenges` here,
--      `discoverable_routes_in_bbox` in 20271021000031).
--
-- The club must also be public and not shadow-hidden. `public_routes` already
-- masks `club_id` for a non-public club so a public route never reveals a
-- private-club association; an official flag on such a row would reveal it
-- again. And a club auto-hidden by the report flow (20270218_001) should not
-- lend its badge while it is under review.
--
-- Privacy: the helper answers "is this user an active owner/admin of this
-- public, verified club", which the active roster of a public club already
-- tells any reader (`active members readable with their club`). It reveals
-- nothing about a private club. The computed fields run on rows the caller's
-- RLS already admitted, so an official flag never surfaces a private row.
--
-- Locks: function and view DDL only. `create or replace view` with a trailing
-- column takes a brief ACCESS EXCLUSIVE on the view (no table scan, rewrite or
-- table lock); the browse RPC is dropped and recreated because its return
-- type grows a column.

-- ── 1. The one derivation ────────────────────────────────────────────────────

create or replace function private.is_official_publisher(p_club_id uuid, p_author_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select p_club_id is not null
    and p_author_id is not null
    and exists (
      select 1
      from clubs c
      join club_members m on m.club_id = c.id
      where c.id = p_club_id
        and c.is_verified = true
        and c.is_public = true
        and c.shadow_hidden = false
        and m.user_id = p_author_id
        and m.status = 'active'
        and m.role in ('owner', 'admin')
    );
$$;

comment on function private.is_official_publisher(uuid, uuid) is
  'True when p_author_id is an active owner/admin of the public, verified, '
  'non-hidden club p_club_id. The single derivation of "official" content '
  '(issue #1190, decisions § 2227); never stored per row.';

grant execute on function private.is_official_publisher(uuid, uuid) to anon, authenticated, service_role;

-- ── 2. Computed fields (select `*, is_official`) ─────────────────────────────

create or replace function public.is_official(r public.routes)
returns boolean
language sql
stable
set search_path = public
as $$ select private.is_official_publisher(r.club_id, r.user_id); $$;

create or replace function public.is_official(p public.training_plans)
returns boolean
language sql
stable
set search_path = public
as $$ select private.is_official_publisher(p.club_id, p.user_id); $$;

create or replace function public.is_official(g public.gym_routines)
returns boolean
language sql
stable
set search_path = public
as $$ select private.is_official_publisher(g.club_id, g.author_id); $$;

create or replace function public.is_official(c public.challenges)
returns boolean
language sql
stable
set search_path = public
as $$ select private.is_official_publisher(c.club_id, c.creator_id); $$;

create or replace function public.is_official(s public.session_plans)
returns boolean
language sql
stable
set search_path = public
as $$ select private.is_official_publisher(s.club_id, s.author_id); $$;

grant execute on function public.is_official(public.routes) to anon, authenticated, service_role;
grant execute on function public.is_official(public.training_plans) to anon, authenticated, service_role;
grant execute on function public.is_official(public.gym_routines) to anon, authenticated, service_role;
grant execute on function public.is_official(public.challenges) to anon, authenticated, service_role;
grant execute on function public.is_official(public.session_plans) to anon, authenticated, service_role;

-- ── 3. Route read views gain a trailing `is_official` ────────────────────────
-- Bodies re-emitted verbatim from their latest definition (20270802000003)
-- with one column appended. Existing grants survive `create or replace view`.

create or replace view public_routes as
  select
    r.id,
    r.user_id,
    r.name,
    r.distance_m,
    r.elevation_m,
    r.surface,
    r.is_public,
    r.slug,
    r.created_at,
    r.updated_at,
    r.tags,
    r.is_featured,
    r.featured_at,
    r.run_count,
    case when is_public_club_by_id(r.club_id) then r.club_id else null::uuid end as club_id,
    private.is_official_publisher(r.club_id, r.user_id) as is_official
  from routes r
  where r.is_public = true
    and r.shadow_hidden = false;

create or replace view shared_routes as
  select
    r.id,
    r.user_id,
    r.name,
    r.distance_m,
    r.elevation_m,
    r.surface,
    r.is_public,
    r.slug,
    r.created_at,
    r.updated_at,
    r.tags,
    r.is_featured,
    r.featured_at,
    r.run_count,
    case when is_public_club_by_id(r.club_id) then r.club_id else null::uuid end as club_id,
    private.is_official_publisher(r.club_id, r.user_id) as is_official
  from routes r
  where r.is_public = false
    and r.shadow_hidden = false
    and private.route_audience_admits(r.id, r.user_id, r.followers_only, (select auth.uid()));

-- ── 4. browse_public_challenges returns is_official ──────────────────────────
-- Full body re-emitted from 20270817000031; only the projection grows. The
-- ranking is unchanged: the challenge browse ranks by recent joins, and the
-- badge alone marks an organiser's challenge. Dropping the old signature takes
-- its grants, so they are restated.

drop function if exists browse_public_challenges(text, integer, integer);
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
  participant_count integer,
  is_official boolean
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
    e.id, e.creator_id, e.club_id, e.title, e.description, e.metric, e.scope, e.goal_value,
    e.activity_type, e.starts_at, e.ends_at, e.is_public, e.created_at, e.participant_count,
    private.is_official_publisher(e.club_id, e.creator_id) as is_official
  from eligible e
  order by (e.participant_count + e.joins_7d * 2) desc, e.ends_at asc, e.created_at desc, e.id
  limit greatest(0, least(coalesce(p_limit, 24), 100))
  offset greatest(0, coalesce(p_offset, 0));
$$;

grant execute on function browse_public_challenges(text, integer, integer) to authenticated, anon;

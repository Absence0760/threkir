-- An official challenge stays in the browse list before anyone joins it
-- (issue #1190, decisions § 2446).
--
-- browse_public_challenges hides a public board with no participants once it
-- is seven days old, so a throwaway challenge does not sit in the list. The
-- official catalogue publishes each recurring challenge ahead of its window
-- (20271211000004), so next month's board would be hidden before the month
-- it is for. A board whose publisher is official
-- (`private.is_official_publisher`, § 2228) is now exempt from that
-- suppression, nothing else. The body is 20271021000030's with that one line;
-- the signature, ranking and grants are unchanged. The `club_id is not null`
-- test short-circuits the definer call for every clubless board.
--
-- Locks (docs/backend/migration_locks.md): one function replaced in place.

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
      -- grace window) unless the caller created them or an official publisher
      -- did, so a new challenge still gets a fair shot at gaining traction.
      and (
        c.participant_count > 0
        or c.created_at >= now() - interval '7 days'
        or c.creator_id = auth.uid()
        or (c.club_id is not null and private.is_official_publisher(c.club_id, c.creator_id))
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

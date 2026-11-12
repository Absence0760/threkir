-- dm_threads(): a group row's preview and unread count read through the
-- conversation index instead of running the read rule over every group
-- message ever sent (issue #1365, decisions § 2461).
--
-- 20271217000006 built the group rows from one CTE that applied
-- private.can_read_message to every message of every group the caller is in
-- and then kept the newest and counted the unread ones. Measured on the local
-- stack with one four-member group (EXPLAIN ANALYZE, viewer the owner): 2,000
-- messages took 176 ms and 50,000 took 4.6 s, all of it a scan of
-- direct_messages through the read rule — the inbox poll, every 30 s, grew
-- with the age of the busiest group.
--
-- Now each group takes bounded reads through direct_messages_conversation
-- (conversation_id, created_at desc):
--   newest  walked newest-first and stopped at the first message the read
--           rule admits; its created_at, in the index's own order so the
--           planner can stop early rather than sort the group;
--   latest  among the messages at that instant, the highest id the rule
--           admits — the previous body's (created_at desc, id desc) tie-break;
--   unread  only messages after the caller's read position (last_read_at,
--           else joined_at).
-- The read rule still decides every row. The extra predicates are ones it
-- already implies — someone else's message is readable only by an active
-- member and only from joined_at — so they narrow the scan, never the
-- result; tests/dm_threads_group_rows_bounded_test.sql pins the rows equal to
-- the previous body's across the cases the rule distinguishes. The direct
-- half is unchanged. The same measurement after: 3 ms at 2,000 and 11 ms at
-- 50,000 (8 ms of it the direct half), each index scan stopping at one row.
--
-- Locking: CREATE OR REPLACE FUNCTION with the same result type takes no
-- table lock, and no client type moves.

create or replace function public.dm_threads()
returns table(
  conversation_id uuid, partner_id uuid, deleted_partner_key uuid, last_body text,
  last_unsent boolean, last_at timestamptz, last_from_me boolean, unread bigint,
  muted boolean, archived boolean, marked_unread boolean, request boolean,
  last_kind text, last_image boolean,
  kind text, title text, member_count integer, membership_state text
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  with my_msgs as (
    select
      m.conversation_id,
      case when m.sender_id = (select auth.uid()) then m.recipient_id else m.sender_id end as partner_id,
      m.deleted_partner_key,
      m.sender_id,
      m.recipient_id,
      m.body,
      m.unsent_at,
      m.created_at,
      m.read_at,
      m.id,
      m.kind,
      m.image_id
    from direct_messages m
    where not m.is_group
      and (m.sender_id = (select auth.uid()) or m.recipient_id = (select auth.uid()))
      and not exists (
        select 1 from conversation_participants hp
         where hp.conversation_id = m.conversation_id
           and hp.user_id = (select auth.uid())
           and hp.hidden_before is not null
           and m.created_at <= hp.hidden_before
      )
  ),
  latest as (
    select distinct on (conversation_id)
      conversation_id,
      partner_id,
      deleted_partner_key,
      body as last_body,
      (unsent_at is not null) as last_unsent,
      created_at as last_at,
      (sender_id = (select auth.uid())) as last_from_me,
      kind as last_kind,
      (image_id is not null) as last_image
    from my_msgs
    order by conversation_id, created_at desc, id desc
  ),
  unread as (
    select conversation_id, count(*) as cnt
    from my_msgs
    where recipient_id = (select auth.uid()) and read_at is null and unsent_at is null
    group by conversation_id
  ),
  direct_rows as (
    select
      l.conversation_id,
      l.partner_id,
      l.deleted_partner_key,
      l.last_body,
      l.last_unsent,
      l.last_at,
      l.last_from_me,
      greatest(coalesce(u.cnt, 0), case when p.marked_unread_at is not null then 1 else 0 end) as unread,
      coalesce(p.muted_at is not null, false) as muted,
      coalesce(p.archived_at is not null and p.archived_at >= l.last_at, false) as archived,
      coalesce(p.marked_unread_at is not null, false) as marked_unread,
      coalesce(p.request_state = 'pending', false) as request,
      l.last_kind,
      l.last_image,
      'direct'::text as kind,
      null::text as title,
      null::integer as member_count,
      null::text as membership_state
    from latest l
    left join unread u using (conversation_id)
    left join conversation_participants p
      on p.conversation_id = l.conversation_id
     and p.user_id = (select auth.uid())
    where p.request_state is distinct from 'declined'
  ),
  my_groups as (
    select g.conversation_id, g.membership_state, g.joined_at, g.last_read_at,
           g.muted_at, g.archived_at, g.marked_unread_at, c.title
      from conversation_participants g
      join conversations c on c.id = g.conversation_id and c.kind = 'group'
     where g.user_id = (select auth.uid())
       and g.membership_state in ('active', 'left')
       and private.group_messages_enabled()
  ),
  group_newest as materialized (
    select g.conversation_id, n.created_at
      from my_groups g
      cross join lateral (
        select m.created_at
          from direct_messages m
         where m.conversation_id = g.conversation_id
           and m.is_group
           and (m.sender_id = (select auth.uid())
                or (g.membership_state = 'active' and m.created_at >= g.joined_at))
           and private.can_read_message(m.conversation_id, m.sender_id, m.recipient_id, m.is_group, m.created_at)
         order by m.created_at desc
         limit 1
      ) n
  ),
  group_latest as materialized (
    select n.conversation_id, l.id, l.sender_id, l.body, l.unsent_at, l.created_at, l.kind, l.image_id
      from group_newest n
      join my_groups g using (conversation_id)
      cross join lateral (
        select m.id, m.sender_id, m.body, m.unsent_at, m.created_at, m.kind, m.image_id
          from direct_messages m
         where m.conversation_id = n.conversation_id
           and m.created_at = n.created_at
           and m.is_group
           and (m.sender_id = (select auth.uid())
                or (g.membership_state = 'active' and m.created_at >= g.joined_at))
           and private.can_read_message(m.conversation_id, m.sender_id, m.recipient_id, m.is_group, m.created_at)
         order by m.id desc
         limit 1
      ) l
  ),
  group_unread as materialized (
    select g.conversation_id, u.cnt
      from my_groups g
      cross join lateral (
        select count(*) as cnt
          from direct_messages m
         where m.conversation_id = g.conversation_id
           and m.is_group
           and m.created_at > coalesce(g.last_read_at, g.joined_at)
           and m.sender_id <> (select auth.uid())
           and m.unsent_at is null
           and private.can_read_message(m.conversation_id, m.sender_id, m.recipient_id, m.is_group, m.created_at)
      ) u
     where g.membership_state = 'active'
  ),
  group_rows as (
    select
      g.conversation_id,
      null::uuid,
      null::uuid,
      gl.body,
      coalesce(gl.unsent_at is not null, false),
      coalesce(gl.created_at, g.joined_at),
      coalesce(gl.sender_id = (select auth.uid()), false),
      greatest(coalesce(u.cnt, 0), case when g.marked_unread_at is not null then 1 else 0 end),
      g.muted_at is not null,
      coalesce(g.archived_at is not null and g.archived_at >= coalesce(gl.created_at, g.joined_at), false),
      g.marked_unread_at is not null,
      false,
      gl.kind,
      coalesce(gl.image_id is not null, false),
      'group'::text,
      g.title,
      case when g.membership_state = 'active' then (
        select count(*)::integer from conversation_participants a
         where a.conversation_id = g.conversation_id
           and a.membership_state = 'active'
      ) end,
      g.membership_state
    from my_groups g
    left join group_latest gl using (conversation_id)
    left join group_unread u using (conversation_id)
    where g.membership_state = 'active' or gl.conversation_id is not null
  )
  select * from (
    select * from direct_rows
    union all
    select * from group_rows
  ) t
  order by t.last_at desc;
$$;
revoke execute on function public.dm_threads() from public, anon;
grant execute on function public.dm_threads() to authenticated, service_role;

-- Pins migration 20271223011359: dm_threads()' group rows read the newest
-- readable message and the unread count through the conversation index, and
-- answer exactly what the previous body (20271217000006) answered.
--
-- Two halves. First, the rows: the previous body is kept below as
-- pg_temp.dm_threads_before() and both are read for one viewer across every
-- case the read rule distinguishes for a group row — history from before the
-- viewer joined, their own message from before it, a blocked sender's newer
-- message, an unsent one, a read position, a hidden_before, two messages at
-- one instant, a group with no messages, a group they left with and without
-- messages of their own.
-- Second, the cost: the read rule is wrapped in a counter and a 300-message
-- group the viewer has read through must cost a handful of calls, where the
-- previous body ran it once per message.

begin;
select plan(4);

insert into private.feature_flags (name, enabled) values ('group_messages', true)
on conflict (name) do update set enabled = true;

insert into auth.users (id, email, encrypted_password, email_confirmed_at, instance_id, aud, role)
select ('b1359000-0000-0000-0000-0000000000' || s)::uuid, 'dtb-' || s || '@example.com', '', now(),
       '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'
  from unnest(array['a0', 'b0', 'c0', 'd0']) as s
on conflict (id) do nothing;
-- a0 the viewer, b0 the owner of every group, c0 someone a0 blocks, d0 another member.

insert into conversations (id, kind, title, created_by)
select ('f1359000-0000-0000-0000-0000000000' || g)::uuid, 'group', 'Group ' || g, 'b1359000-0000-0000-0000-0000000000b0'
  from unnest(array['11', '12', '13', '14', '15', '16']) as g;

-- Everyone active while the messages go in (the send gate checks it).
insert into conversation_participants (conversation_id, user_id, membership_state, role, joined_at)
select ('f1359000-0000-0000-0000-0000000000' || g)::uuid, ('b1359000-0000-0000-0000-0000000000' || u)::uuid,
       'active', case u when 'b0' then 'owner' else 'member' end,
       now() - interval '30 days'
  from unnest(array['11', '12', '13', '14', '15', '16']) as g,
       unnest(array['a0', 'b0', 'c0', 'd0']) as u;

insert into direct_messages (id, sender_id, conversation_id, body, created_at) values
  -- 11: history from before a0 joined, a0's own message from before it, a
  -- read position between, an unsent message and a blocked sender's newer one.
  ('d1359000-0000-0000-0000-000000001101', 'b1359000-0000-0000-0000-0000000000d0', 'f1359000-0000-0000-0000-000000000011', 'before join', now() - interval '8 days'),
  ('d1359000-0000-0000-0000-000000001102', 'b1359000-0000-0000-0000-0000000000a0', 'f1359000-0000-0000-0000-000000000011', 'mine before join', now() - interval '7 days'),
  ('d1359000-0000-0000-0000-000000001103', 'b1359000-0000-0000-0000-0000000000d0', 'f1359000-0000-0000-0000-000000000011', 'after join', now() - interval '4 days'),
  ('d1359000-0000-0000-0000-000000001104', 'b1359000-0000-0000-0000-0000000000a0', 'f1359000-0000-0000-0000-000000000011', 'mine', now() - interval '3 days'),
  ('d1359000-0000-0000-0000-000000001105', 'b1359000-0000-0000-0000-0000000000d0', 'f1359000-0000-0000-0000-000000000011', 'unread one', now() - interval '2 days'),
  ('d1359000-0000-0000-0000-000000001106', 'b1359000-0000-0000-0000-0000000000d0', 'f1359000-0000-0000-0000-000000000011', 'unsent', now() - interval '1 day'),
  ('d1359000-0000-0000-0000-000000001107', 'b1359000-0000-0000-0000-0000000000b0', 'f1359000-0000-0000-0000-000000000011', 'unread two', now() - interval '12 hours'),
  ('d1359000-0000-0000-0000-000000001108', 'b1359000-0000-0000-0000-0000000000c0', 'f1359000-0000-0000-0000-000000000011', 'blocked newest', now() - interval '1 hour'),
  -- 12: a0 leaves after writing; others write on.
  ('d1359000-0000-0000-0000-000000001201', 'b1359000-0000-0000-0000-0000000000a0', 'f1359000-0000-0000-0000-000000000012', 'my last word', now() - interval '6 days'),
  ('d1359000-0000-0000-0000-000000001202', 'b1359000-0000-0000-0000-0000000000d0', 'f1359000-0000-0000-0000-000000000012', 'after I left', now() - interval '2 days'),
  -- 14: a0 hid the conversation through a point; one message after it.
  ('d1359000-0000-0000-0000-000000001401', 'b1359000-0000-0000-0000-0000000000d0', 'f1359000-0000-0000-0000-000000000014', 'hidden', now() - interval '5 days'),
  ('d1359000-0000-0000-0000-000000001402', 'b1359000-0000-0000-0000-0000000000a0', 'f1359000-0000-0000-0000-000000000014', 'hidden mine', now() - interval '4 days'),
  ('d1359000-0000-0000-0000-000000001403', 'b1359000-0000-0000-0000-0000000000d0', 'f1359000-0000-0000-0000-000000000014', 'after hide', now() - interval '1 day'),
  -- Two at one instant: the newer by id is the preview, as before.
  ('d1359000-0000-0000-0000-000000001405', 'b1359000-0000-0000-0000-0000000000d0', 'f1359000-0000-0000-0000-000000000014', 'tie newer id', now() - interval '12 hours'),
  ('d1359000-0000-0000-0000-000000001404', 'b1359000-0000-0000-0000-0000000000b0', 'f1359000-0000-0000-0000-000000000014', 'tie older id', now() - interval '12 hours'),
  -- 15: a0 leaves without having written.
  ('d1359000-0000-0000-0000-000000001501', 'b1359000-0000-0000-0000-0000000000d0', 'f1359000-0000-0000-0000-000000000015', 'not mine', now() - interval '3 days');

-- 16: 300 messages, read through all but the newest two.
insert into direct_messages (sender_id, conversation_id, body, created_at)
select 'b1359000-0000-0000-0000-0000000000d0', 'f1359000-0000-0000-0000-000000000016', 'busy ' || n,
       now() - interval '1 day' + n * interval '1 minute'
  from generate_series(1, 300) n;

update direct_messages set unsent_at = now(), body = null where id = 'd1359000-0000-0000-0000-000000001106';
update conversation_participants set joined_at = now() - interval '5 days', last_read_at = now() - interval '3 days'
 where conversation_id = 'f1359000-0000-0000-0000-000000000011' and user_id = 'b1359000-0000-0000-0000-0000000000a0';
update conversation_participants set membership_state = 'left', left_at = now() - interval '5 days'
 where conversation_id in ('f1359000-0000-0000-0000-000000000012', 'f1359000-0000-0000-0000-000000000015')
   and user_id = 'b1359000-0000-0000-0000-0000000000a0';
update conversation_participants set hidden_before = now() - interval '2 days'
 where conversation_id = 'f1359000-0000-0000-0000-000000000014' and user_id = 'b1359000-0000-0000-0000-0000000000a0';
update conversation_participants set joined_at = now() - interval '2 days', last_read_at = now() - interval '1 day' + interval '298 minutes' + interval '30 seconds'
 where conversation_id = 'f1359000-0000-0000-0000-000000000016' and user_id = 'b1359000-0000-0000-0000-0000000000a0';
insert into user_blocks (blocker_id, blocked_id)
values ('b1359000-0000-0000-0000-0000000000a0', 'b1359000-0000-0000-0000-0000000000c0');

-- The body of dm_threads() as 20271217000006 left it.
create function pg_temp.dm_threads_before()
returns table(
  conversation_id uuid, partner_id uuid, deleted_partner_key uuid, last_body text,
  last_unsent boolean, last_at timestamptz, last_from_me boolean, unread bigint,
  muted boolean, archived boolean, marked_unread boolean, request boolean,
  last_kind text, last_image boolean,
  kind text, title text, member_count integer, membership_state text
)
language sql
stable
set search_path = public, pg_temp
as $before$
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
  group_msgs as (
    select m.conversation_id, m.id, m.sender_id, m.body, m.unsent_at, m.created_at,
           m.kind, m.image_id
      from my_groups g
      join direct_messages m on m.conversation_id = g.conversation_id and m.is_group
     where private.can_read_message(m.conversation_id, m.sender_id, m.recipient_id, m.is_group, m.created_at)
  ),
  group_latest as (
    select distinct on (conversation_id) *
      from group_msgs
     order by conversation_id, created_at desc, id desc
  ),
  group_unread as (
    select m.conversation_id, count(*) as cnt
      from group_msgs m
      join my_groups g using (conversation_id)
     where g.membership_state = 'active'
       and m.sender_id <> (select auth.uid())
       and m.unsent_at is null
       and m.created_at > coalesce(g.last_read_at, g.joined_at)
     group by m.conversation_id
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
$before$;

set local "request.jwt.claims" = '{"sub":"b1359000-0000-0000-0000-0000000000a0","role":"authenticated"}';

select results_eq(
  $$select * from dm_threads() where kind = 'group' order by conversation_id$$,
  $$select * from pg_temp.dm_threads_before() where kind = 'group' order by conversation_id$$,
  'every group row reads as the previous body read it');

select results_eq(
  $$select conversation_id::text, last_body, unread, membership_state from dm_threads()
     where kind = 'group' order by conversation_id$$,
  $$values
      ('f1359000-0000-0000-0000-000000000011', 'unread two', 2::bigint, 'active'),
      ('f1359000-0000-0000-0000-000000000012', 'my last word', 0::bigint, 'left'),
      ('f1359000-0000-0000-0000-000000000013', null, 0::bigint, 'active'),
      ('f1359000-0000-0000-0000-000000000014', 'tie newer id', 3::bigint, 'active'),
      ('f1359000-0000-0000-0000-000000000016', 'busy 300', 2::bigint, 'active')$$,
  'the cases come out as the read rule says: the blocked sender skipped, the leaver''s own word, no row for a leaver with none');

-- The cost: count the read rule's calls through a wrapper under its name.
create temporary sequence read_rule_calls;
alter function private.can_read_message(uuid, uuid, uuid, boolean, timestamptz) rename to can_read_message_counted;
create function private.can_read_message(
  p_conversation_id uuid, p_sender_id uuid, p_recipient_id uuid, p_is_group boolean, p_created_at timestamptz
) returns boolean
language plpgsql
stable
as $$
begin
  perform nextval('pg_temp.read_rule_calls');
  return private.can_read_message_counted(p_conversation_id, p_sender_id, p_recipient_id, p_is_group, p_created_at);
end;
$$;

select ok((select count(*) from dm_threads()) = 5, 'dm_threads() still answers through the wrapped rule');
select diag('read-rule calls: ' || (select last_value from pg_temp.read_rule_calls));
select cmp_ok(
  (select last_value from pg_temp.read_rule_calls), '<', 40::bigint,
  'six groups, one of 300 messages, cost a bounded number of read-rule calls, not one per message');

select * from finish();
rollback;

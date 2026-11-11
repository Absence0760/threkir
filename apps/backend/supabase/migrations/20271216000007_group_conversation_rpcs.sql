-- Group conversations, slice 1 (issue #1365, docs/features/group_messages.md
-- §§ 2-3, decisions § 2458): the group RPCs and the inbox.
--
-- All SECURITY DEFINER with a pinned search_path. A conversation the caller
-- is not an active member of, one that does not exist and one they left all
-- answer the same P0002, so no RPC is an oracle for a group's existence or its
-- roster (memo C5). A member acting above their role gets 42501.
--
--   create_group_conversation(title, invitees[])  any signed-in runner; the
--       creator is the owner and everyone else is INVITED, never added (D1).
--   invite_to_group(conversation, invitees[])     owner and admins.
--   accept_group_invite / decline_group_invite     the invitee.
--   leave_conversation                             any member; an owner's
--       leaving passes ownership to the longest-standing admin, else member.
--   remove_group_member                            owner removes admins and
--       members, an admin removes members; also cancels an invite.
--   set_group_member_role / transfer_group_ownership   the owner.
--   rename_group                                   owner and admins.
--   mark_conversation_read                         a member's read position.
--   group_members(conversation)                    active members only; the
--       pending invites only to the owner and admins.
--   group_invites()                                the caller's own pending
--       invites: title, inviter, invited_at and the active-member count only,
--       never the member names (memo C5).
--   dm_threads()                                   gains kind, title,
--       member_count and membership_state, and a row per group.
--
-- Who may be invited (D1): anyone the inviter could message 1:1 under
-- private.dm_send_admitted, and never across a block either way. A refused
-- invitee, one that does not exist and a blocked pair all answer one 42501.
--
-- Cap (D2): 32 including unexpired invites, c_group_max_members below,
-- counted under a per-conversation advisory lock so two invites cannot both
-- take the last seat. An invite expires 14 days after it was sent: it cannot
-- be accepted, does not count toward the cap, and the purge retires it.
--
-- Rate limits: create_group_conversation 10 a day, invite_to_group 50
-- invitations a day, on top of the send buckets every message spends.
--
-- Locking: functions only; dm_threads is dropped and recreated because its
-- result type grows (no table lock).

create or replace function private.group_rank(p_role text)
returns integer
language sql
immutable
set search_path = public, pg_temp
as $$
  select case p_role when 'owner' then 3 when 'admin' then 2 when 'member' then 1 else 0 end;
$$;
revoke execute on function private.group_rank(text) from public, anon, authenticated;

-- Promote the longest-standing admin, else the longest-standing member, when a
-- group has no active owner. A group with nobody active is left for the purge.
create or replace function private.group_pass_ownership(p_conversation_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if exists (
    select 1 from conversation_participants p
     where p.conversation_id = p_conversation_id
       and p.role = 'owner'
       and p.membership_state = 'active'
  ) then
    return;
  end if;

  update conversation_participants p
     set role = 'owner'
   where (p.conversation_id, p.user_id) = (
     select n.conversation_id, n.user_id
       from conversation_participants n
      where n.conversation_id = p_conversation_id
        and n.membership_state = 'active'
      order by (n.role = 'admin') desc, n.joined_at, n.user_id
      limit 1
   );
end;
$$;
revoke execute on function private.group_pass_ownership(uuid) from public, anon, authenticated;

-- One invitation, by the caller. True when a new invite was written, false
-- when the person is already a member or holds a live invite.
create or replace function private.group_invite(p_conversation_id uuid, p_invitee uuid)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  c_invite_ttl constant interval := interval '14 days';
  v_me uuid := auth.uid();
  v_state text;
  v_invited_at timestamptz;
  v_found boolean;
begin
  if p_invitee is null
     or p_invitee = v_me
     or not exists (select 1 from auth.users u where u.id = p_invitee)
     or is_blocked_either_way(v_me, p_invitee)
     or not private.dm_send_admitted(p_invitee) then
    raise exception 'invite_to_group: you cannot invite this person' using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(private.group_member_lock_key(p_conversation_id, p_invitee));

  select p.membership_state, p.invited_at, true
    into v_state, v_invited_at, v_found
    from conversation_participants p
   where p.conversation_id = p_conversation_id
     and p.user_id = p_invitee
   for update;

  if v_state = 'active'
     or (v_state = 'invited' and v_invited_at > now() - c_invite_ttl) then
    return false;
  end if;

  perform enforce_create_rate_limit('invite_to_group', v_me, 50, 86400);

  if coalesce(v_found, false) then
    update conversation_participants
       set membership_state = 'invited',
           invited_at = now(),
           invited_by = v_me,
           left_at = null,
           removed_by = null,
           role = null
     where conversation_id = p_conversation_id
       and user_id = p_invitee;
  else
    insert into conversation_participants
      (conversation_id, user_id, membership_state, invited_at, invited_by)
    values (p_conversation_id, p_invitee, 'invited', now(), v_me);
  end if;
  return true;
end;
$$;
revoke execute on function private.group_invite(uuid, uuid) from public, anon, authenticated;

create or replace function private.group_check_cap(p_conversation_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  c_group_max_members constant integer := 32;
  c_invite_ttl constant interval := interval '14 days';
begin
  if (
    select count(*)
      from conversation_participants p
     where p.conversation_id = p_conversation_id
       and (
         p.membership_state = 'active'
         or (p.membership_state = 'invited' and p.invited_at > now() - c_invite_ttl)
       )
  ) > c_group_max_members then
    raise exception 'invite_to_group: a group holds at most % people, invites included', c_group_max_members
      using errcode = '54000';
  end if;
end;
$$;
revoke execute on function private.group_check_cap(uuid) from public, anon, authenticated;

create or replace function public.create_group_conversation(p_title text, p_invitees uuid[])
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid := auth.uid();
  v_title text := btrim(coalesce(p_title, ''));
  v_invitees uuid[];
  v_id uuid;
  v_invitee uuid;
begin
  if v_me is null then
    raise exception 'create_group_conversation: not authorized' using errcode = '42501';
  end if;
  if not private.group_messages_enabled() then
    raise exception 'create_group_conversation: group conversations are not available'
      using errcode = '0A000';
  end if;
  if char_length(v_title) not between 1 and 60 then
    raise exception 'create_group_conversation: the title must be 1 to 60 characters'
      using errcode = '22023';
  end if;

  select array_agg(distinct u) into v_invitees
    from unnest(coalesce(p_invitees, '{}'::uuid[])) as u
   where u is not null and u <> v_me;

  if coalesce(array_length(v_invitees, 1), 0) < 2 then
    raise exception 'create_group_conversation: a group needs at least two other people'
      using errcode = '22023';
  end if;

  perform enforce_create_rate_limit('create_group_conversation', v_me, 10, 86400);

  insert into conversations (kind, title, created_by)
  values ('group', v_title, v_me)
  returning id into v_id;

  insert into conversation_participants
    (conversation_id, user_id, membership_state, role, joined_at, last_read_at)
  values (v_id, v_me, 'active', 'owner', now(), now());

  perform pg_advisory_xact_lock(hashtextextended('group_roster:' || v_id::text, 0));
  foreach v_invitee in array v_invitees loop
    perform private.group_invite(v_id, v_invitee);
  end loop;
  perform private.group_check_cap(v_id);

  return v_id;
end;
$$;
revoke execute on function public.create_group_conversation(text, uuid[]) from public, anon;
grant execute on function public.create_group_conversation(text, uuid[]) to authenticated, service_role;

create or replace function public.invite_to_group(p_conversation_id uuid, p_invitees uuid[])
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid := auth.uid();
  v_role text;
  v_invitee uuid;
  v_count integer := 0;
begin
  if v_me is null then
    raise exception 'invite_to_group: not authorized' using errcode = '42501';
  end if;
  if not private.group_messages_enabled() then
    raise exception 'invite_to_group: group conversations are not available' using errcode = '0A000';
  end if;

  v_role := private.group_my_role(p_conversation_id);
  if v_role is null then
    raise exception 'invite_to_group: conversation not found' using errcode = 'P0002';
  end if;
  if v_role not in ('owner', 'admin') then
    raise exception 'invite_to_group: only the owner and admins invite' using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('group_roster:' || p_conversation_id::text, 0));
  for v_invitee in
    select distinct u from unnest(coalesce(p_invitees, '{}'::uuid[])) as u
  loop
    if private.group_invite(p_conversation_id, v_invitee) then
      v_count := v_count + 1;
    end if;
  end loop;
  perform private.group_check_cap(p_conversation_id);

  return v_count;
end;
$$;
revoke execute on function public.invite_to_group(uuid, uuid[]) from public, anon;
grant execute on function public.invite_to_group(uuid, uuid[]) to authenticated, service_role;

create or replace function public.accept_group_invite(p_conversation_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  c_invite_ttl constant interval := interval '14 days';
  v_me uuid := auth.uid();
begin
  if v_me is null then
    raise exception 'accept_group_invite: not authorized' using errcode = '42501';
  end if;
  if not private.group_messages_enabled() then
    raise exception 'accept_group_invite: group conversations are not available' using errcode = '0A000';
  end if;

  perform pg_advisory_xact_lock(private.group_member_lock_key(p_conversation_id, v_me));

  -- joined_at is the server's clock at acceptance: the start of the readable
  -- window, which no client can backdate, and a fresh one on every re-join.
  update conversation_participants p
     set membership_state = 'active',
         role = 'member',
         joined_at = now(),
         last_read_at = now(),
         left_at = null,
         removed_by = null
    from conversations c
   where c.id = p.conversation_id
     and c.kind = 'group'
     and p.conversation_id = p_conversation_id
     and p.user_id = v_me
     and p.membership_state = 'invited'
     and p.invited_at > now() - c_invite_ttl;

  if not found then
    raise exception 'accept_group_invite: invite not found' using errcode = 'P0002';
  end if;
end;
$$;
revoke execute on function public.accept_group_invite(uuid) from public, anon;
grant execute on function public.accept_group_invite(uuid) to authenticated, service_role;

create or replace function public.decline_group_invite(p_conversation_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid := auth.uid();
begin
  if v_me is null then
    raise exception 'decline_group_invite: not authorized' using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(private.group_member_lock_key(p_conversation_id, v_me));

  update conversation_participants p
     set membership_state = 'left',
         left_at = now()
    from conversations c
   where c.id = p.conversation_id
     and c.kind = 'group'
     and p.conversation_id = p_conversation_id
     and p.user_id = v_me
     and p.membership_state = 'invited';

  if not found then
    raise exception 'decline_group_invite: invite not found' using errcode = 'P0002';
  end if;
end;
$$;
revoke execute on function public.decline_group_invite(uuid) from public, anon;
grant execute on function public.decline_group_invite(uuid) to authenticated, service_role;

-- Leaving is allowed with the flag off: it only narrows who reads what.
create or replace function public.leave_conversation(p_conversation_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid := auth.uid();
  v_role text;
begin
  if v_me is null then
    raise exception 'leave_conversation: not authorized' using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(private.group_member_lock_key(p_conversation_id, v_me));

  update conversation_participants p
     set membership_state = 'left',
         left_at = now(),
         removed_by = null
    from conversations c
   where c.id = p.conversation_id
     and c.kind = 'group'
     and p.conversation_id = p_conversation_id
     and p.user_id = v_me
     and p.membership_state in ('active', 'invited')
  returning p.role into v_role;

  if not found then
    raise exception 'leave_conversation: conversation not found' using errcode = 'P0002';
  end if;

  if v_role = 'owner' then
    perform private.group_pass_ownership(p_conversation_id);
  end if;
end;
$$;
revoke execute on function public.leave_conversation(uuid) from public, anon;
grant execute on function public.leave_conversation(uuid) to authenticated, service_role;

create or replace function public.remove_group_member(p_conversation_id uuid, p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid := auth.uid();
  v_role text;
  v_target_role text;
  v_target_state text;
begin
  if v_me is null then
    raise exception 'remove_group_member: not authorized' using errcode = '42501';
  end if;
  if not private.group_messages_enabled() then
    raise exception 'remove_group_member: group conversations are not available' using errcode = '0A000';
  end if;

  v_role := private.group_my_role(p_conversation_id);
  if v_role is null then
    raise exception 'remove_group_member: conversation not found' using errcode = 'P0002';
  end if;

  -- Exclusive against the target's sends: a send either commits before this
  -- removal or is refused by direct_messages_set_conversation after it.
  perform pg_advisory_xact_lock(private.group_member_lock_key(p_conversation_id, p_user_id));

  select p.role, p.membership_state into v_target_role, v_target_state
    from conversation_participants p
   where p.conversation_id = p_conversation_id
     and p.user_id = p_user_id
     and p.membership_state in ('active', 'invited')
   for update;

  if v_target_state is null then
    raise exception 'remove_group_member: member not found' using errcode = 'P0002';
  end if;
  if p_user_id = v_me
     or private.group_rank(v_role) < 2
     or private.group_rank(v_role) <= private.group_rank(case when v_target_state = 'active' then v_target_role end) then
    raise exception 'remove_group_member: you cannot remove this member' using errcode = '42501';
  end if;

  update conversation_participants
     set membership_state = 'left',
         left_at = now(),
         removed_by = v_me
   where conversation_id = p_conversation_id
     and user_id = p_user_id;
end;
$$;
revoke execute on function public.remove_group_member(uuid, uuid) from public, anon;
grant execute on function public.remove_group_member(uuid, uuid) to authenticated, service_role;

create or replace function public.set_group_member_role(p_conversation_id uuid, p_user_id uuid, p_role text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid := auth.uid();
  v_role text;
begin
  if v_me is null then
    raise exception 'set_group_member_role: not authorized' using errcode = '42501';
  end if;
  if not private.group_messages_enabled() then
    raise exception 'set_group_member_role: group conversations are not available' using errcode = '0A000';
  end if;
  if p_role is null or p_role not in ('admin', 'member') then
    raise exception 'set_group_member_role: role must be admin or member' using errcode = '22023';
  end if;

  v_role := private.group_my_role(p_conversation_id);
  if v_role is null then
    raise exception 'set_group_member_role: conversation not found' using errcode = 'P0002';
  end if;
  if v_role <> 'owner' then
    raise exception 'set_group_member_role: only the owner changes roles' using errcode = '42501';
  end if;

  update conversation_participants
     set role = p_role
   where conversation_id = p_conversation_id
     and user_id = p_user_id
     and user_id <> v_me
     and membership_state = 'active';

  if not found then
    raise exception 'set_group_member_role: member not found' using errcode = 'P0002';
  end if;
end;
$$;
revoke execute on function public.set_group_member_role(uuid, uuid, text) from public, anon;
grant execute on function public.set_group_member_role(uuid, uuid, text) to authenticated, service_role;

create or replace function public.transfer_group_ownership(p_conversation_id uuid, p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid := auth.uid();
  v_role text;
begin
  if v_me is null then
    raise exception 'transfer_group_ownership: not authorized' using errcode = '42501';
  end if;
  if not private.group_messages_enabled() then
    raise exception 'transfer_group_ownership: group conversations are not available' using errcode = '0A000';
  end if;

  v_role := private.group_my_role(p_conversation_id);
  if v_role is null then
    raise exception 'transfer_group_ownership: conversation not found' using errcode = 'P0002';
  end if;
  if v_role <> 'owner' then
    raise exception 'transfer_group_ownership: only the owner transfers ownership' using errcode = '42501';
  end if;

  if p_user_id is null or p_user_id = v_me or not exists (
    select 1 from conversation_participants p
     where p.conversation_id = p_conversation_id
       and p.user_id = p_user_id
       and p.membership_state = 'active'
  ) then
    raise exception 'transfer_group_ownership: member not found' using errcode = 'P0002';
  end if;

  -- Demote first: the one-owner index holds at every statement.
  update conversation_participants
     set role = 'admin'
   where conversation_id = p_conversation_id
     and user_id = v_me;
  update conversation_participants
     set role = 'owner'
   where conversation_id = p_conversation_id
     and user_id = p_user_id;
end;
$$;
revoke execute on function public.transfer_group_ownership(uuid, uuid) from public, anon;
grant execute on function public.transfer_group_ownership(uuid, uuid) to authenticated, service_role;

create or replace function public.rename_group(p_conversation_id uuid, p_title text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid := auth.uid();
  v_title text := btrim(coalesce(p_title, ''));
  v_role text;
begin
  if v_me is null then
    raise exception 'rename_group: not authorized' using errcode = '42501';
  end if;
  if not private.group_messages_enabled() then
    raise exception 'rename_group: group conversations are not available' using errcode = '0A000';
  end if;

  v_role := private.group_my_role(p_conversation_id);
  if v_role is null then
    raise exception 'rename_group: conversation not found' using errcode = 'P0002';
  end if;
  if v_role not in ('owner', 'admin') then
    raise exception 'rename_group: only the owner and admins rename' using errcode = '42501';
  end if;
  if char_length(v_title) not between 1 and 60 then
    raise exception 'rename_group: the title must be 1 to 60 characters' using errcode = '22023';
  end if;

  update conversations set title = v_title where id = p_conversation_id;
end;
$$;
revoke execute on function public.rename_group(uuid, text) from public, anon;
grant execute on function public.rename_group(uuid, text) to authenticated, service_role;

create or replace function public.mark_conversation_read(p_conversation_id uuid, p_through_message_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid := auth.uid();
  v_at timestamptz;
begin
  if v_me is null then
    raise exception 'mark_conversation_read: not authorized' using errcode = '42501';
  end if;
  if private.group_my_role(p_conversation_id) is null then
    raise exception 'mark_conversation_read: conversation not found' using errcode = 'P0002';
  end if;

  select m.created_at into v_at
    from direct_messages m
   where m.id = p_through_message_id
     and m.conversation_id = p_conversation_id
     and private.can_read_message(m.conversation_id, m.sender_id, m.recipient_id, m.is_group, m.created_at);

  if v_at is null then
    raise exception 'mark_conversation_read: message not found' using errcode = 'P0002';
  end if;

  update conversation_participants
     set last_read_at = greatest(last_read_at, v_at),
         marked_unread_at = null
   where conversation_id = p_conversation_id
     and user_id = v_me;
end;
$$;
revoke execute on function public.mark_conversation_read(uuid, uuid) from public, anon;
grant execute on function public.mark_conversation_read(uuid, uuid) to authenticated, service_role;

create or replace function public.group_members(p_conversation_id uuid)
returns table(user_id uuid, role text, membership_state text, joined_at timestamptz, invited_at timestamptz)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_role text := private.group_my_role(p_conversation_id);
begin
  if v_role is null then
    raise exception 'group_members: conversation not found' using errcode = 'P0002';
  end if;

  return query
    select p.user_id, p.role, p.membership_state,
           case when p.membership_state = 'active' then p.joined_at end,
           case when p.membership_state = 'invited' then p.invited_at end
      from conversation_participants p
     where p.conversation_id = p_conversation_id
       and (
         p.membership_state = 'active'
         or (
           p.membership_state = 'invited'
           and v_role in ('owner', 'admin')
           and p.invited_at > now() - interval '14 days'
         )
       )
     order by p.membership_state, p.joined_at, p.user_id;
end;
$$;
revoke execute on function public.group_members(uuid) from public, anon;
grant execute on function public.group_members(uuid) to authenticated, service_role;

create or replace function public.group_invites()
returns table(conversation_id uuid, title text, invited_by uuid, invited_at timestamptz, member_count integer)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select p.conversation_id, c.title, p.invited_by, p.invited_at,
         (select count(*)::integer from conversation_participants a
           where a.conversation_id = p.conversation_id
             and a.membership_state = 'active')
    from conversation_participants p
    join conversations c on c.id = p.conversation_id and c.kind = 'group'
   where p.user_id = (select auth.uid())
     and p.membership_state = 'invited'
     and p.invited_at > now() - interval '14 days'
   order by p.invited_at desc;
$$;
revoke execute on function public.group_invites() from public, anon;
grant execute on function public.group_invites() to authenticated, service_role;

-- ── The inbox ───────────────────────────────────────────────────────────
--
-- The direct half is unchanged but for `not m.is_group`. A group row lists
-- every group the caller is active in (even before its first message) and a
-- group they left while it still holds a message of theirs ("You left …",
-- their own messages only). Its unread count is the readable messages from
-- others after last_read_at; member_count is shown only to an active member.

drop function if exists public.dm_threads();
create function public.dm_threads()
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
$$;
revoke execute on function public.dm_threads() from public, anon;
grant execute on function public.dm_threads() to authenticated, service_role;

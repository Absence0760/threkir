-- Group conversations, slice 2 (issue #1365, docs/features/group_messages.md,
-- decisions § 2463): what the web surfaces need from the server.
--
-- ── Notifications ───────────────────────────────────────────────────────
--
-- notify_direct_message gains its group branch. A group message raises one
-- kind 'message' row, naming the conversation, for each ACTIVE member other
-- than the sender whose window holds it and who has not muted the group
-- (group_messages.md § 3, "Mute in a group suppresses the message notification
-- for that participant only"), and never for a member who blocked the sender:
-- they do not read that message, so being told of it would be the one leak the
-- block filter exists to prevent. A member already holding a message notice
-- for this group that is unread in the bell AND newer than their read
-- position gets no second one: the 1:1 burst rule at group scale. Keying on
-- the read position (mark_conversation_read) as well as the bell is what
-- makes opening the thread re-arm it, as opening a 1:1 thread does through
-- direct_messages.read_at; on the bell alone, a member who reads in the app
-- and never opens the bell would never be told again.
-- Nothing is read about anyone's reading (D6: no read receipts). An invitee
-- and a member who left or was removed get nothing. The rename system line
-- notifies nobody.
--
-- private.group_invite raises one 'group_invite' row to the invitee, naming
-- the inviter and the conversation only.
--
-- ── The rename system line ──────────────────────────────────────────────
--
-- rename_group writes a kind 'group_renamed' message as the renamer, body =
-- the new title, after the update. edit_direct_message refuses every kind but
-- 'text' and 'ai_assisted', so the line cannot be edited into other words.
--
-- ── Blocked placeholders ────────────────────────────────────────────────
--
-- group_blocked_placeholders(conversation, since) lists the id and time of
-- each live message in the group that the caller would read but for their own
-- block of its sender, so the thread can show "Message from someone you
-- blocked" in its place. No body, no sender, no reactions. It reads only the
-- CALLER's blocks, so it returns nothing to anyone else, and the blocked
-- person is told nothing (group_messages.md § 3, memo § 2.3).
--
-- ── The admin reports queue ─────────────────────────────────────────────
--
-- admin_report_conversation(message) tells a site admin which audience a
-- reported message went to: the conversation's kind, a group's title and its
-- active member count (group_messages.md § 6). Admin-only, 42501 otherwise.
--
-- ── The flag ────────────────────────────────────────────────────────────
--
-- dm_threads() and group_invites() list no group while the group_messages
-- flag is off, so a client that ignored group_messages_enabled() still draws
-- nothing; the RPCs that act on a group already refuse with it off.
--
-- Locks: functions only (no table lock).

-- ── notify_direct_message ───────────────────────────────────────────────

create or replace function public.notify_direct_message()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_hidden_before timestamptz;
  v_muted boolean;
  v_request_state text;
begin
  if new.is_group then
    if new.kind <> 'text' or not private.group_messages_enabled() then
      return new;
    end if;
    insert into notifications (user_id, actor_id, kind, conversation_id)
    select p.user_id, new.sender_id, 'message', new.conversation_id
      from conversation_participants p
     where p.conversation_id = new.conversation_id
       and p.user_id <> new.sender_id
       and p.membership_state = 'active'
       and p.muted_at is null
       and p.joined_at <= new.created_at
       and not exists (
         select 1 from user_blocks b
          where b.blocker_id = p.user_id
            and b.blocked_id = new.sender_id
       )
       and not exists (
         select 1 from notifications n
          where n.conversation_id = new.conversation_id
            and n.user_id = p.user_id
            and n.kind = 'message'
            and n.read_at is null
            and n.created_at > coalesce(p.last_read_at, p.joined_at)
       );
    return new;
  end if;

  select p.hidden_before, p.muted_at is not null, p.request_state
    into v_hidden_before, v_muted, v_request_state
    from conversation_participants p
   where p.conversation_id = new.conversation_id
     and p.user_id = new.recipient_id;

  if coalesce(v_muted, false) then
    return new;
  end if;

  -- A request the recipient has not accepted tells them nothing until they
  -- open their Requests list.
  if v_request_state in ('pending', 'declined') then
    return new;
  end if;

  -- Only notify on the first unread message of a burst — if the
  -- recipient already has an unread message from this sender, the bell
  -- is already lit, so don't stack another row.
  if exists (
    select 1 from direct_messages m
    where m.sender_id = new.sender_id
      and m.recipient_id = new.recipient_id
      and m.read_at is null
      and m.id <> new.id
      and (v_hidden_before is null or m.created_at > v_hidden_before)
  ) then
    return new;
  end if;
  insert into notifications (user_id, actor_id, kind)
    values (new.recipient_id, new.sender_id, 'message');
  return new;
end;
$$;

-- ── private.group_invite: the invite notification ───────────────────────
--
-- Body as 20271216000007, with the notification after the write.

create or replace function private.group_invite(p_conversation_id uuid, p_invitee uuid)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  c_invite_ttl constant interval := interval '14 days';
  c_reinvite_cooldown constant interval := interval '14 days';
  v_me uuid := auth.uid();
  v_state text;
  v_invited_at timestamptz;
  v_left_at timestamptz;
  v_removed_by uuid;
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

  select p.membership_state, p.invited_at, p.left_at, p.removed_by, true
    into v_state, v_invited_at, v_left_at, v_removed_by, v_found
    from conversation_participants p
   where p.conversation_id = p_conversation_id
     and p.user_id = p_invitee
   for update;

  if v_state = 'active'
     or (v_state = 'invited' and v_invited_at > now() - c_invite_ttl) then
    return false;
  end if;

  -- Someone who declined, left or let an invite lapse said no; they cannot be
  -- invited back into the same group for 14 days, by anyone, and the refusal
  -- is the same 42501 as any other. A removal was the group's choice, not
  -- theirs, so it does not hold them out.
  if (v_state = 'left' and v_removed_by is null and v_left_at > now() - c_reinvite_cooldown)
     or (v_state = 'invited' and v_invited_at > now() - c_invite_ttl - c_reinvite_cooldown) then
    raise exception 'invite_to_group: you cannot invite this person' using errcode = '42501';
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

  insert into notifications (user_id, actor_id, kind, conversation_id)
  values (p_invitee, v_me, 'group_invite', p_conversation_id);
  return true;
end;
$$;
revoke execute on function private.group_invite(uuid, uuid) from public, anon, authenticated;

-- ── rename_group: the system line ───────────────────────────────────────
--
-- Body as 20271216000007, with the line written after the update. A rename to
-- the title the group already has changes nothing and writes no line.

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

  update conversations
     set title = v_title
   where id = p_conversation_id
     and title is distinct from v_title;

  if found then
    insert into direct_messages (sender_id, conversation_id, body, kind)
    values (v_me, p_conversation_id, v_title, 'group_renamed');
  end if;
end;
$$;
revoke execute on function public.rename_group(uuid, text) from public, anon;
grant execute on function public.rename_group(uuid, text) to authenticated, service_role;

-- ── edit_direct_message: a system line is not editable ──────────────────
--
-- Body as 20271216000006, with the kind refusal widened from coach_share to
-- every kind but text and ai_assisted.

create or replace function public.edit_direct_message(p_message_id uuid, p_body text)
returns direct_messages
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  c_window constant interval := interval '15 minutes';
  v_me uuid := auth.uid();
  v_body text := btrim(coalesce(p_body, ''));
  v_row direct_messages;
begin
  if v_me is null then
    raise exception 'edit_direct_message: not authorized' using errcode = '42501';
  end if;

  if char_length(v_body) not between 1 and 4000 then
    raise exception 'edit_direct_message: body must be 1 to 4000 characters'
      using errcode = '22023';
  end if;

  select * into v_row
    from direct_messages m
   where m.id = p_message_id
     and m.sender_id = v_me
     and private.can_read_message(m.conversation_id, m.sender_id, m.recipient_id, m.is_group, m.created_at)
   for update;

  if v_row.id is null then
    raise exception 'edit_direct_message: message not found' using errcode = 'P0002';
  end if;

  -- In a group only an active member edits, and only while the flag is on: a
  -- leaver keeps unsend (D11), not edit.
  if v_row.unsent_at is not null
     or v_row.kind not in ('text', 'ai_assisted')
     or v_row.created_at < now() - c_window
     or (v_row.recipient_id is not null and is_blocked_either_way(v_me, v_row.recipient_id))
     or (v_row.is_group and not private.group_send_admitted(v_row.conversation_id)) then
    raise exception 'edit_direct_message: message can no longer be edited'
      using errcode = '55000';
  end if;

  if v_row.body is distinct from v_body then
    perform enforce_create_rate_limit('edit_direct_message', v_me, 60, 3600);

    update direct_messages
       set original_body = coalesce(original_body, body),
           body = v_body,
           edited_at = now()
     where id = v_row.id
    returning * into v_row;
  end if;

  v_row.read_at := null;
  v_row.original_body := null;
  return v_row;
end;
$$;

-- ── Blocked placeholders ────────────────────────────────────────────────

create or replace function public.group_blocked_placeholders(p_conversation_id uuid, p_since timestamptz)
returns table(id uuid, created_at timestamptz)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid := auth.uid();
  v_joined_at timestamptz;
  v_hidden_before timestamptz;
begin
  if v_me is null or private.group_my_role(p_conversation_id) is null then
    raise exception 'group_blocked_placeholders: conversation not found' using errcode = 'P0002';
  end if;
  if not private.group_messages_enabled() then
    return;
  end if;

  select p.joined_at, p.hidden_before into v_joined_at, v_hidden_before
    from conversation_participants p
   where p.conversation_id = p_conversation_id
     and p.user_id = v_me;

  return query
    select m.id, m.created_at
      from direct_messages m
     where m.conversation_id = p_conversation_id
       and m.is_group
       and m.sender_id <> v_me
       and m.unsent_at is null
       and m.created_at >= v_joined_at
       and (v_hidden_before is null or m.created_at > v_hidden_before)
       and (p_since is null or m.created_at >= p_since)
       and exists (
         select 1 from user_blocks b
          where b.blocker_id = v_me
            and b.blocked_id = m.sender_id
       )
     order by m.created_at desc, m.id desc
     limit 200;
end;
$$;
revoke execute on function public.group_blocked_placeholders(uuid, timestamptz) from public, anon;
grant execute on function public.group_blocked_placeholders(uuid, timestamptz) to authenticated, service_role;

-- ── The admin reports queue ─────────────────────────────────────────────

create or replace function public.admin_report_conversation(p_message_id uuid)
returns table(kind text, title text, member_count integer)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if not private.is_admin(auth.uid()) then
    raise exception 'admin_report_conversation: not authorized' using errcode = '42501';
  end if;

  return query
    select c.kind, c.title,
           case
             when c.kind = 'group' then (
               select count(*)::integer from conversation_participants a
                where a.conversation_id = c.id and a.membership_state = 'active')
             else 2
           end
      from direct_messages m
      join conversations c on c.id = m.conversation_id
     where m.id = p_message_id;
end;
$$;
revoke execute on function public.admin_report_conversation(uuid) from public, anon;
grant execute on function public.admin_report_conversation(uuid) to authenticated, service_role;

-- ── group_invites: nothing while the flag is off ────────────────────────

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
     and private.group_messages_enabled()
   order by p.invited_at desc;
$$;
revoke execute on function public.group_invites() from public, anon;
grant execute on function public.group_invites() to authenticated, service_role;

-- ── dm_threads: no group rows while the flag is off ─────────────────────
--
-- Body as 20271216000007 with `and private.group_messages_enabled()` in
-- my_groups; the result type is unchanged, so it is replaced in place.

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

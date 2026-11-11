-- Group conversations, slice 1 (issue #1365, docs/features/group_messages.md,
-- decisions § 2461): one read rule, the send gate, and every message RPC
-- routed through them.
--
-- ── The read rule: private.can_read_message ─────────────────────────────
--
-- The single statement of who may read a message (security memo C1). The
-- SELECT policy on direct_messages calls it, so the paths that read through
-- that policy inherit it: PostgREST reads, the reactions and message-image
-- policies, the dm-images Storage policy and search_direct_messages
-- (SECURITY INVOKER). Every SECURITY DEFINER RPC that touches a message calls
-- it too, so none restates a membership rule of its own.
--
--   * Never across the caller's own delete-for-me (hidden_before).
--   * A direct message: its sender or its recipient, as before.
--   * A group message: its sender always (their own words, which they may
--     still unsend after leaving, D11), and otherwise an ACTIVE participant
--     whose window contains it (created_at >= joined_at, D3), unless the
--     caller has blocked its sender. Only the caller's own block is read, so
--     being blocked reveals nothing (group_messages.md § 3). A participant who
--     left or was removed reads nobody else's messages (D12), and a re-join
--     stamps a new joined_at, so the earlier window does not come back.
--   * With the group_messages flag off, a group message is readable only by
--     its sender: fail closed, and the sender's erasure tools keep working.
--
-- It takes no user argument: the caller is always auth.uid(), so it cannot be
-- asked about anyone else (the private.dm_send_admitted precedent).
--
-- ── The send gate ───────────────────────────────────────────────────────
--
-- A group send names its conversation and no recipient. The BEFORE INSERT
-- trigger takes a SHARED advisory lock on (conversation, sender) and then
-- re-reads the sender's membership in a fresh snapshot; leave, remove and
-- accept take the same key EXCLUSIVE. So a send racing a removal either
-- commits before it or is refused; it cannot land after it (memo § 2.1, C3).
-- The policy then admits only kind 'text' from an active member: coach shares
-- and AI-assisted replies are 1:1 only, so group content never enters a coach
-- lane (C2).
--
-- ── The flag ────────────────────────────────────────────────────────────
--
-- private.feature_flags 'group_messages', which no migration writes, so it is
-- off until an operator turns it on after the pre-deploy item in
-- deployment.md. Every RPC that creates or widens group content (create,
-- invite, accept, send, edit, react, rename, roles, remove) refuses with
-- 0A000 while it is off. Leaving, declining and the per-participant view RPCs
-- keep working, as does unsending your own message.
--
-- ── What is not here ────────────────────────────────────────────────────
--
-- Group message notifications and the group_invite notification kind are
-- slice 2, with the surfaces that open them; notify_direct_message skips a
-- group message until then. Read receipts in groups: none (D6). Auto-hide:
-- none in groups (D10); a group report goes to the site-admin queue like any
-- direct-message report, and auto_hide_target never covers direct_message.
--
-- ── Locking ─────────────────────────────────────────────────────────────
--
-- Functions (no table lock) and two ALTER POLICYs on direct_messages
-- (catalogue-only ACCESS EXCLUSIVE, released at commit).

-- ── Flag ────────────────────────────────────────────────────────────────

create or replace function private.group_messages_enabled()
returns boolean
language sql
stable
security definer
set search_path = public, private, pg_temp
as $$
  select coalesce(
    (select f.enabled from private.feature_flags f where f.name = 'group_messages'),
    false
  );
$$;
revoke execute on function private.group_messages_enabled() from public, anon, authenticated;

-- The client's read of the flag, so the surfaces can hide what the server
-- would refuse anyway.
create or replace function public.group_messages_enabled()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select private.group_messages_enabled();
$$;
revoke execute on function public.group_messages_enabled() from public, anon;
grant execute on function public.group_messages_enabled() to authenticated, service_role;

-- ── The read rule ───────────────────────────────────────────────────────

create or replace function private.can_read_message(
  p_conversation_id uuid,
  p_sender_id uuid,
  p_recipient_id uuid,
  p_is_group boolean,
  p_created_at timestamptz
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(
    (select auth.uid()) is not null
    and not exists (
      select 1 from conversation_participants h
       where h.conversation_id = p_conversation_id
         and h.user_id = (select auth.uid())
         and h.hidden_before is not null
         and p_created_at <= h.hidden_before
    )
    and case
      when not p_is_group then
        (select auth.uid()) in (p_sender_id, p_recipient_id)
      else
        (select auth.uid()) = p_sender_id
        or (
          private.group_messages_enabled()
          and exists (
            select 1 from conversation_participants a
             where a.conversation_id = p_conversation_id
               and a.user_id = (select auth.uid())
               and a.membership_state = 'active'
               and p_created_at >= a.joined_at
          )
          and not exists (
            select 1 from user_blocks b
             where b.blocker_id = (select auth.uid())
               and b.blocked_id = p_sender_id
          )
        )
    end,
    false
  );
$$;
revoke execute on function private.can_read_message(uuid, uuid, uuid, boolean, timestamptz) from public, anon;
grant execute on function private.can_read_message(uuid, uuid, uuid, boolean, timestamptz) to authenticated, service_role;

-- The first conjunct is implied by the helper; it stays so the planner can
-- still prune a scan by the caller's own sender / recipient indexes.
alter policy "participants read their own messages" on direct_messages
  to authenticated
  using (
    ((select auth.uid()) = sender_id or (select auth.uid()) = recipient_id or is_group)
    and private.can_read_message(conversation_id, sender_id, recipient_id, is_group, created_at)
  );

-- ── Membership helpers ──────────────────────────────────────────────────

-- The advisory-lock key that serialises a member's sends against their
-- removal, leave or acceptance.
create or replace function private.group_member_lock_key(p_conversation_id uuid, p_user_id uuid)
returns bigint
language sql
immutable
set search_path = public, pg_temp
as $$
  select hashtextextended('group_member:' || p_conversation_id::text || ':' || p_user_id::text, 0);
$$;
revoke execute on function private.group_member_lock_key(uuid, uuid) from public, anon, authenticated;

-- The caller's active membership of a group, or null.
create or replace function private.group_my_role(p_conversation_id uuid)
returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select p.role
    from conversation_participants p
    join conversations c on c.id = p.conversation_id and c.kind = 'group'
   where p.conversation_id = p_conversation_id
     and p.user_id = (select auth.uid())
     and p.membership_state = 'active';
$$;
revoke execute on function private.group_my_role(uuid) from public, anon, authenticated;

create or replace function private.group_send_admitted(p_conversation_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select private.group_messages_enabled()
     and private.group_my_role(p_conversation_id) is not null;
$$;
revoke execute on function private.group_send_admitted(uuid) from public, anon;
grant execute on function private.group_send_admitted(uuid) to authenticated, service_role;

create or replace function private.dm_group_image_send_admitted(p_image uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select private.dm_images_enabled()
     and exists (
       select 1
         from direct_message_images i
         join storage.objects o on o.bucket_id = 'dm-images' and o.name = i.upload_path
        where i.id = p_image
          and i.owner_id = (select auth.uid())
          and i.status = 'pending'
          and i.message_id is null
     );
$$;
revoke execute on function private.dm_group_image_send_admitted(uuid) from public, anon;
grant execute on function private.dm_group_image_send_admitted(uuid) to authenticated, service_role;

-- ── The send gate ───────────────────────────────────────────────────────

create or replace function public.direct_messages_set_conversation()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.recipient_id is not null then
    new.conversation_id := private.direct_conversation_for(new.sender_id, new.recipient_id);
    new.is_group := false;
    return new;
  end if;

  -- No recipient and no conversation names nobody to send to.
  if new.conversation_id is null then
    raise exception 'direct_messages: a message needs a recipient' using errcode = '23502';
  end if;

  -- A group send. The lock is shared with other sends and exclusive against
  -- leave / remove / accept for the same member; the check after it is a new
  -- statement, so it reads the membership as it stands once the lock is held.
  perform pg_advisory_xact_lock_shared(
    private.group_member_lock_key(new.conversation_id, new.sender_id)
  );
  if not exists (
    select 1
      from conversations c
      join conversation_participants p on p.conversation_id = c.id
     where c.id = new.conversation_id
       and c.kind = 'group'
       and p.user_id = new.sender_id
       and p.membership_state = 'active'
  ) then
    raise exception 'new row violates row-level security policy for table "direct_messages"'
      using errcode = '42501';
  end if;
  new.is_group := true;
  return new;
end;
$$;

alter policy "send when not blocked and within follow graph" on direct_messages
  with check (
    direct_messages.sender_id = (select auth.uid())
    and (
      direct_messages.route_id is null
      or private.is_route_visible_to(direct_messages.route_id, (select auth.uid()))
    )
    and direct_messages.coach_message_id is null
    and (
      (
        not direct_messages.is_group
        and not is_blocked_either_way(direct_messages.sender_id, direct_messages.recipient_id)
        and private.dm_send_admitted(direct_messages.recipient_id)
        and (
          direct_messages.kind = 'text'
          or (
            direct_messages.kind = 'ai_assisted'
            and private.is_active_coach_of((select auth.uid()), direct_messages.recipient_id)
          )
        )
        and (
          direct_messages.image_id is null
          or private.dm_image_send_admitted(direct_messages.recipient_id, direct_messages.image_id)
        )
      )
      or (
        direct_messages.is_group
        and direct_messages.kind = 'text'
        and private.group_send_admitted(direct_messages.conversation_id)
        and (
          direct_messages.image_id is null
          or private.dm_group_image_send_admitted(direct_messages.image_id)
        )
      )
    )
  );

-- A group message has no recipient, so the 1:1 request machinery has nothing
-- to move.
create or replace function private.direct_messages_request_state()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_sender_state text;
  v_recipient_state text;
  v_requested_at timestamptz;
  v_count integer;
begin
  if new.is_group then
    return null;
  end if;

  select p.request_state into v_sender_state
    from conversation_participants p
   where p.conversation_id = new.conversation_id
     and p.user_id = new.sender_id;

  select p.request_state, p.requested_at into v_recipient_state, v_requested_at
    from conversation_participants p
   where p.conversation_id = new.conversation_id
     and p.user_id = new.recipient_id;

  -- Replying to a request is accepting it, and writing to someone you
  -- declined takes the decline back.
  if v_sender_state in ('pending', 'declined') then
    update conversation_participants
       set request_state = 'accepted'
     where conversation_id = new.conversation_id
       and user_id = new.sender_id;
  end if;

  if v_recipient_state is null and not private.dm_follow_edge(new.sender_id, new.recipient_id) then
    -- A new request. The policy has already found the shared context.
    perform enforce_create_rate_limit('open_message_request', new.sender_id, 20, 86400);
    update conversation_participants
       set request_state = 'pending',
           requested_at = new.created_at
     where conversation_id = new.conversation_id
       and user_id = new.recipient_id;
    update conversation_participants
       set request_state = 'accepted'
     where conversation_id = new.conversation_id
       and user_id = new.sender_id
       and request_state is null;
  elsif v_recipient_state = 'pending' then
    select count(*) into v_count
      from direct_messages m
     where m.conversation_id = new.conversation_id
       and m.sender_id = new.sender_id
       and m.created_at >= v_requested_at;
    if v_count > 3 then
      raise exception 'direct_messages: a message request holds at most 3 messages until it is accepted'
        using errcode = '54000';
    end if;
  end if;

  return null;
end;
$$;

-- Group notifications arrive with the slice 2 surfaces that open them.
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

-- ── Message RPCs through the read rule ──────────────────────────────────

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
     or v_row.kind = 'coach_share'
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

create or replace function public.set_direct_message_reaction(p_message_id uuid, p_reaction text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid := auth.uid();
  v_msg direct_messages;
  v_partner uuid;
begin
  if v_me is null then
    raise exception 'set_direct_message_reaction: not authorized' using errcode = '42501';
  end if;

  if p_reaction is not null
     and p_reaction not in ('thumbs_up', 'heart', 'laugh', 'surprised', 'sad', 'fire') then
    raise exception 'set_direct_message_reaction: unknown reaction' using errcode = '22023';
  end if;

  select * into v_msg
    from direct_messages m
   where m.id = p_message_id
     and private.can_read_message(m.conversation_id, m.sender_id, m.recipient_id, m.is_group, m.created_at);

  if v_msg.id is null then
    raise exception 'set_direct_message_reaction: message not found' using errcode = 'P0002';
  end if;

  if v_msg.is_group then
    if v_msg.unsent_at is not null
       or not private.group_send_admitted(v_msg.conversation_id) then
      raise exception 'set_direct_message_reaction: this message cannot take a reaction'
        using errcode = '55000';
    end if;
  else
    v_partner := case when v_msg.sender_id = v_me then v_msg.recipient_id else v_msg.sender_id end;

    if v_msg.unsent_at is not null
       or v_partner is null
       or is_blocked_either_way(v_me, v_partner)
       or exists (
         select 1 from conversation_participants p
          where p.conversation_id = v_msg.conversation_id
            and p.request_state in ('pending', 'declined')
       ) then
      raise exception 'set_direct_message_reaction: this message cannot take a reaction'
        using errcode = '55000';
    end if;
  end if;

  perform enforce_create_rate_limit('dm_reaction', v_me, 120, 3600);

  if p_reaction is null then
    delete from direct_message_reactions
     where message_id = p_message_id
       and user_id = v_me;
  else
    insert into direct_message_reactions (message_id, user_id, reaction)
    values (p_message_id, v_me, p_reaction)
    on conflict (message_id, user_id)
      do update set reaction = excluded.reaction, created_at = now();
  end if;
end;
$$;

create or replace function public.hide_conversation(p_conversation_id uuid, p_through_message_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid := auth.uid();
  v_through timestamptz;
begin
  if v_me is null then
    raise exception 'hide_conversation: not authorized' using errcode = '42501';
  end if;

  -- The through-message must be one the caller can read, or one of their own
  -- already behind their hidden_before (so hiding again through it is a
  -- no-op rather than an error).
  select m.created_at into v_through
    from direct_messages m
   where m.id = p_through_message_id
     and m.conversation_id = p_conversation_id
     and (
       (not m.is_group and v_me in (m.sender_id, m.recipient_id))
       or private.can_read_message(m.conversation_id, m.sender_id, m.recipient_id, m.is_group, m.created_at)
     );

  if v_through is null then
    raise exception 'hide_conversation: conversation not found' using errcode = 'P0002';
  end if;

  -- Archiving or marking unread a conversation that is now empty for the
  -- caller means nothing, and a stale stamp would file the next message under
  -- Archived or count it twice.
  update conversation_participants
     set hidden_before = greatest(hidden_before, v_through),
         archived_at = null,
         marked_unread_at = null
   where conversation_id = p_conversation_id
     and user_id = v_me;

  if not found then
    raise exception 'hide_conversation: conversation not found' using errcode = 'P0002';
  end if;
end;
$$;

create or replace function public.search_direct_messages(p_query text, p_limit integer default 30)
returns table(id uuid, conversation_id uuid, sender_id uuid, recipient_id uuid,
              deleted_partner_key uuid, body text, created_at timestamptz, kind text)
language sql
stable
set search_path = public, pg_temp
as $$
  with q as (
    select btrim(coalesce(p_query, '')) as t
  )
  select m.id, m.conversation_id, m.sender_id, m.recipient_id,
         m.deleted_partner_key, m.body, m.created_at, m.kind
    from direct_messages m, q
   where char_length(q.t) between 2 and 100
     and m.unsent_at is null
     and m.body is not null
     and (m.sender_id = (select auth.uid()) or m.recipient_id = (select auth.uid()) or m.is_group)
     and private.can_read_message(m.conversation_id, m.sender_id, m.recipient_id, m.is_group, m.created_at)
     and m.body ilike '%' || replace(replace(replace(q.t, '\', '\\'), '%', '\%'), '_', '\_') || '%'
     and not exists (
       select 1 from conversation_participants p
        where p.conversation_id = m.conversation_id
          and p.user_id = (select auth.uid())
          and p.request_state in ('pending', 'declined')
     )
     and not exists (
       select 1 from user_blocks b
        where b.blocker_id = (select auth.uid())
          and b.blocked_id in (m.sender_id, m.recipient_id)
     )
   order by m.created_at desc, m.id desc
   limit least(greatest(coalesce(p_limit, 30), 1), 50);
$$;

CREATE OR REPLACE FUNCTION public.submit_report(p_target_kind text, p_target_id uuid, p_reason text, p_notes text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_reporter uuid := auth.uid();
  v_target_exists boolean;
  v_report_id uuid;
  v_dm direct_messages;
begin
  if v_reporter is null then
    raise exception 'submit_report: not authorized' using errcode = '42501';
  end if;

  if p_target_kind not in ('user', 'club', 'route', 'comment', 'club_post', 'run', 'route_review', 'direct_message') then
    raise exception 'submit_report: invalid target_kind %', p_target_kind
      using errcode = '22023';
  end if;

  if p_reason not in ('spam', 'harassment', 'inappropriate', 'impersonation', 'other') then
    raise exception 'submit_report: invalid reason %', p_reason
      using errcode = '22023';
  end if;

  -- Don't let a user report themselves — most likely a misclick, and
  -- the queue noise isn't worth carrying.
  if p_target_kind = 'user' and p_target_id = v_reporter then
    raise exception 'submit_report: cannot report yourself'
      using errcode = '22023';
  end if;

  -- Validate the target exists. The FROM clauses run as the function owner
  -- (postgres) so RLS doesn't block visibility.
  if p_target_kind = 'user' then
    select exists (select 1 from user_profiles where id = p_target_id) into v_target_exists;
  elsif p_target_kind = 'club' then
    select exists (select 1 from clubs where id = p_target_id) into v_target_exists;
  elsif p_target_kind = 'route' then
    select exists (select 1 from routes where id = p_target_id) into v_target_exists;
  elsif p_target_kind = 'comment' then
    select exists (select 1 from run_comments where id = p_target_id) into v_target_exists;
    -- Reporting your own comment is a misclick; reject like self-user.
    if v_target_exists and exists (
      select 1 from run_comments where id = p_target_id and author_id = v_reporter
    ) then
      raise exception 'submit_report: cannot report your own comment'
        using errcode = '22023';
    end if;
  elsif p_target_kind = 'club_post' then
    select exists (select 1 from club_posts where id = p_target_id) into v_target_exists;
    -- Reporting your own post is a misclick; reject like self-comment.
    if v_target_exists and exists (
      select 1 from club_posts where id = p_target_id and author_id = v_reporter
    ) then
      raise exception 'submit_report: cannot report your own post'
        using errcode = '22023';
    end if;
  elsif p_target_kind = 'run' then
    select exists (select 1 from runs where id = p_target_id) into v_target_exists;
    -- Reporting your own run is a misclick; reject like self-comment.
    if v_target_exists and exists (
      select 1 from runs where id = p_target_id and user_id = v_reporter
    ) then
      raise exception 'submit_report: cannot report your own run'
        using errcode = '22023';
    end if;
  elsif p_target_kind = 'route_review' then
    select exists (select 1 from route_reviews where id = p_target_id) into v_target_exists;
    -- Reporting your own review is a misclick; reject like self-comment.
    -- route_reviews' author column is `user_id` (no `author_id`).
    if v_target_exists and exists (
      select 1 from route_reviews where id = p_target_id and user_id = v_reporter
    ) then
      raise exception 'submit_report: cannot report your own review'
        using errcode = '22023';
    end if;
  elsif p_target_kind = 'direct_message' then
    -- The read rule is the gate (private.can_read_message, decisions § 2461):
    -- the reporter reads their own report back, snapshot included, so a
    -- message the caller cannot read (not theirs, before they joined a group,
    -- after they left it) answers "not found", like one that does not exist.
    select * into v_dm
      from direct_messages
     where id = p_target_id
       and private.can_read_message(conversation_id, sender_id, recipient_id, is_group, created_at);
    v_target_exists := v_dm.id is not null;
    if v_target_exists and v_dm.sender_id = v_reporter then
      raise exception 'submit_report: cannot report your own message'
        using errcode = '22023';
    end if;
    if v_target_exists and v_dm.unsent_at is not null then
      raise exception 'submit_report: message was unsent'
        using errcode = '22023';
    end if;
  end if;

  if not v_target_exists then
    raise exception 'submit_report: target % % not found', p_target_kind, p_target_id
      using errcode = '02000';
  end if;

  -- Rate-limit: 10 reports per hour per reporter.
  perform enforce_create_rate_limit('create_report', v_reporter, 10, 3600);

  begin
    insert into reports (
      reporter_id, target_kind, target_id, reason, notes,
      snapshot_body, snapshot_author_id, snapshot_sent_at, snapshot_original_body
    )
    values (
      v_reporter, p_target_kind, p_target_id, p_reason, p_notes,
      -- v_dm is only ever filled by the direct_message arm, so every other
      -- kind stores null snapshots.
      v_dm.body, v_dm.sender_id, v_dm.created_at, v_dm.original_body
    )
    returning id into v_report_id;
  exception when unique_violation then
    raise exception 'submit_report: already reported'
      using errcode = '23505',
            hint = 'You already have a pending report against this target.';
  end;

  return v_report_id;
end;
$function$

;

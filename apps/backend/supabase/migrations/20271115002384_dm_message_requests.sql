-- Direct messages: message requests from people who do not follow each other
-- (issue #1216, decisions § 2384).
--
-- ── Who may send a first message ─────────────────────────────────────────
--
-- Until now the INSERT policy admitted a send only along a follow edge (either
-- direction) and with no block either way, so a club member or an event host
-- could not message someone first. A send with no follow edge is now admitted
-- as a REQUEST when the pair shares a context, and only then:
--
--   * both are active members of the same club (club_members.status =
--     'active'), or
--   * the sender hosts an event (events.host_user_id) the recipient has a live
--     RSVP for ('going', 'maybe' or 'waitlisted'). Host to attendee only: an
--     attendee messaging a host goes through the club rule, as every event
--     belongs to a club.
--
-- A stranger with neither is refused exactly as before, and a block either way
-- still refuses every send. The decision is private.dm_send_admitted(), which
-- the policy calls with the recipient alone (the sender is always auth.uid()),
-- so it cannot be asked about anyone else's pair.
--
-- ── The request state ───────────────────────────────────────────────────
--
-- conversation_participants.request_state is the participant's own consent to
-- receive messages in the conversation without a follow edge:
--
--   null        never a request: the conversation came through the follow
--               graph, which admits it on its own.
--   'pending'   someone without a follow edge wrote to this participant and
--               they have not answered. The conversation sits in their
--               Requests list, raises no notification and shares no read
--               receipt.
--   'accepted'  this participant accepted the request, replied to it, or sent
--               it (a requester consents to replies by asking). Sends to them
--               are admitted from then on without a follow edge or a shared
--               context.
--   'declined'  this participant declined. Every message up to the decline
--               is hidden from them (hidden_before), and the other person
--               cannot send again until this participant writes to them.
--
-- The rows are owner-read, as before, so a requester never learns whether
-- their request is pending or declined: a refused send after a decline is the
-- same 42501 a block or a missing follow edge answers (decisions § 1916).
-- Accepting is what starts read receipts and notifications.
--
-- The AFTER INSERT trigger direct_messages_request_state moves the state, so
-- the policy judges the state as it stood before the send. It is named to fire
-- before trg_notify_direct_message (AFTER triggers fire in name order), so the
-- notification sees a new request as pending.
--
-- ── Limits ──────────────────────────────────────────────────────────────
--
-- A pending request holds at most 3 messages from the requester (54000 on the
-- fourth, so a client can say "wait for them to accept" without revealing
-- anything about the recipient), and opening a new request is its own
-- rate-limit bucket, open_message_request at 20 a day, on top of the send
-- buckets every message spends. Both numbers are conservative defaults for the
-- owner to revisit (decisions § 2384).
--
-- ── Blocking ────────────────────────────────────────────────────────────
--
-- A block between the pair resets an 'accepted' state on both sides to null
-- (the user_blocks trigger below), so unblocking does not quietly restore a
-- request-based conversation: like the follow edges block_user drains, the
-- consent has to be given again. decline_message_request(…, p_block => true)
-- declines and blocks in one transaction, for the Requests list's Block.
--
-- ── Retention, export and account deletion ──────────────────────────────
--
-- No new table. The two columns live on conversation_participants, which
-- already cascades with the participant's account and with its conversation,
-- and which the conversation purge sweeps (20271105000010). Both exports'
-- conversation_settings.json selects them.
--
-- ── Locking ─────────────────────────────────────────────────────────────
--
-- Both ADD COLUMNs are nullable with no default (catalogue-only). The CHECK is
-- added NOT VALID and validated by 20271115002385 in its own transaction. The
-- rest is functions, a policy expression and two triggers; CREATE TRIGGER on
-- direct_messages and user_blocks takes a brief SHARE ROW EXCLUSIVE with no
-- scan, on tables the playbook classes as small.

-- ─── the state ──────────────────────────────────────────────────────────

alter table conversation_participants
  add column request_state text,
  add column requested_at timestamptz;

alter table conversation_participants
  add constraint conversation_participants_request_state_check
    check (request_state in ('pending', 'accepted', 'declined'))
    not valid;

comment on column conversation_participants.request_state is
  'Message requests (issue #1216): null for a conversation that came through '
  'the follow graph; pending while someone without a follow edge waits for '
  'this participant to answer; accepted once they accepted, replied or sent '
  'the request; declined once they declined. Owner-read; written only by the '
  'direct_messages_request_state trigger and the request RPCs.';
comment on column conversation_participants.requested_at is
  'When the pending request was opened: the requester''s messages since then '
  'count toward the 3-message cap.';

-- ─── who may send ───────────────────────────────────────────────────────

create or replace function private.dm_follow_edge(p_a uuid, p_b uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from user_follows f
     where (f.follower_id = p_a and f.followee_id = p_b)
        or (f.follower_id = p_b and f.followee_id = p_a)
  );
$$;

revoke execute on function private.dm_follow_edge(uuid, uuid) from public, anon, authenticated;

create or replace function private.dm_shared_context(p_sender uuid, p_recipient uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
      from club_members a
      join club_members b on b.club_id = a.club_id
     where a.user_id = p_sender
       and b.user_id = p_recipient
       and a.status = 'active'
       and b.status = 'active'
  ) or exists (
    select 1
      from events e
      join event_attendees ea on ea.event_id = e.id
     where e.host_user_id = p_sender
       and ea.user_id = p_recipient
       and ea.status in ('going', 'maybe', 'waitlisted')
  );
$$;

revoke execute on function private.dm_shared_context(uuid, uuid) from public, anon, authenticated;

-- The recipient's request state in the pair's direct conversation, or null
-- when they have none.
create or replace function private.dm_recipient_request_state(p_sender uuid, p_recipient uuid)
returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select r.request_state
    from conversation_participants r
    join conversations c on c.id = r.conversation_id and c.kind = 'direct'
    join conversation_participants s on s.conversation_id = r.conversation_id and s.user_id = p_sender
   where r.user_id = p_recipient
   limit 1;
$$;

revoke execute on function private.dm_recipient_request_state(uuid, uuid) from public, anon, authenticated;

create or replace function private.dm_send_admitted(p_recipient uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid := auth.uid();
  v_state text;
begin
  if v_me is null or p_recipient is null or p_recipient = v_me then
    return false;
  end if;

  v_state := private.dm_recipient_request_state(v_me, p_recipient);
  if v_state = 'declined' then
    return false;
  end if;
  if v_state = 'accepted' then
    return true;
  end if;

  return private.dm_follow_edge(v_me, p_recipient)
      or private.dm_shared_context(v_me, p_recipient);
end;
$$;

revoke execute on function private.dm_send_admitted(uuid) from public, anon;
grant execute on function private.dm_send_admitted(uuid) to authenticated, service_role;

comment on function private.dm_send_admitted(uuid) is
  'The direct_messages INSERT policy''s audience rule for a send from '
  'auth.uid() to p_recipient (issue #1216): refused after the recipient '
  'declined; admitted once they accepted; otherwise admitted along a follow '
  'edge either way or, as a message request, when the pair shares an active '
  'club membership or the sender hosts an event the recipient RSVPed to.';

-- Re-emitted whole (bare-body rule): 20270619_001's expression with the follow
-- clause replaced by dm_send_admitted. The policy keeps its name, which the
-- grant registries cite.
alter policy "send when not blocked and within follow graph" on direct_messages
  with check (
    sender_id = (select auth.uid())
    and not is_blocked_either_way(sender_id, recipient_id)
    and private.dm_send_admitted(recipient_id)
    and (
      direct_messages.route_id is null
      or private.is_route_visible_to(direct_messages.route_id, (select auth.uid()))
    )
  );

-- ─── moving the state on a send ─────────────────────────────────────────

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

revoke execute on function private.direct_messages_request_state() from public, anon, authenticated;

create trigger direct_messages_request_state
  after insert on direct_messages
  for each row
  execute function private.direct_messages_request_state();

-- ─── notify_direct_message: nothing for a pending or declined request ──
--
-- Bare-body re-emit of 20271105000010 with the request check added.

create or replace function notify_direct_message()
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

-- ─── mark_direct_messages_read: no receipt from a pending request ───────
--
-- Body as 20271113000001, with v_share also false while the caller's own row
-- is a pending or declined request.

create or replace function mark_direct_messages_read(p_partner_id uuid, p_through_message_id uuid)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid := auth.uid();
  v_at timestamptz;
  v_id uuid;
  v_conversation uuid;
  v_share boolean;
  v_count integer;
begin
  if v_me is null then
    raise exception 'mark_direct_messages_read: not authorized' using errcode = '42501';
  end if;

  select m.created_at, m.id, m.conversation_id into v_at, v_id, v_conversation
    from direct_messages m
   where m.id = p_through_message_id
     and m.sender_id in (v_me, p_partner_id)
     and m.recipient_id in (v_me, p_partner_id);

  if v_id is null then
    raise exception 'mark_direct_messages_read: message not found' using errcode = 'P0002';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('dm_read_receipts:' || u::text, 0))
     from unnest(array[v_me, p_partner_id]) as u
    order by u;

  v_share := coalesce((select dm_read_receipts from user_settings where user_id = v_me), true)
         and coalesce((select dm_read_receipts from user_settings where user_id = p_partner_id), true)
         and not exists (
           select 1 from conversation_participants p
            where p.conversation_id = v_conversation
              and p.user_id = v_me
              and p.request_state in ('pending', 'declined')
         );

  update direct_messages m
     set read_at = now(),
         seen_at = case when v_share then now() end
   where m.sender_id = p_partner_id
     and m.recipient_id = v_me
     and m.read_at is null
     and (m.created_at < v_at or (m.created_at = v_at and m.id <= v_id))
     and not exists (
       select 1 from conversation_participants p
        where p.conversation_id = m.conversation_id
          and p.user_id = v_me
          and p.hidden_before is not null
          and m.created_at <= p.hidden_before
     );

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke execute on function mark_direct_messages_read(uuid, uuid) from public, anon;
grant execute on function mark_direct_messages_read(uuid, uuid) to authenticated, service_role;

-- ─── accept / decline ───────────────────────────────────────────────────
--
-- A conversation the caller is not in, and one with no pending request for
-- them, answer the same P0002.

create function accept_message_request(p_conversation_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid := auth.uid();
  v_state text;
begin
  if v_me is null then
    raise exception 'accept_message_request: not authorized' using errcode = '42501';
  end if;

  select p.request_state into v_state
    from conversation_participants p
   where p.conversation_id = p_conversation_id
     and p.user_id = v_me
   for update;

  -- Accepting twice converges, so a retried tap is not an error.
  if v_state = 'accepted' then
    return;
  end if;
  if v_state is distinct from 'pending' then
    raise exception 'accept_message_request: request not found' using errcode = 'P0002';
  end if;

  update conversation_participants
     set request_state = 'accepted'
   where conversation_id = p_conversation_id
     and user_id = v_me;
end;
$$;

revoke execute on function accept_message_request(uuid) from public, anon;
grant execute on function accept_message_request(uuid) to authenticated, service_role;

comment on function accept_message_request(uuid) is
  'Accept a pending message request (issue #1216): the conversation moves to '
  'the inbox, and notifications and read receipts start from now. Idempotent '
  'on an accepted one; P0002 otherwise.';

create function decline_message_request(
  p_conversation_id uuid,
  p_through_message_id uuid,
  p_block boolean default false
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid := auth.uid();
  v_state text;
  v_through timestamptz;
  v_partner uuid;
begin
  if v_me is null then
    raise exception 'decline_message_request: not authorized' using errcode = '42501';
  end if;

  select p.request_state into v_state
    from conversation_participants p
   where p.conversation_id = p_conversation_id
     and p.user_id = v_me
   for update;

  if v_state is distinct from 'pending' then
    raise exception 'decline_message_request: request not found' using errcode = 'P0002';
  end if;

  select m.created_at into v_through
    from direct_messages m
   where m.id = p_through_message_id
     and m.conversation_id = p_conversation_id
     and m.recipient_id = v_me;

  if v_through is null then
    raise exception 'decline_message_request: request not found' using errcode = 'P0002';
  end if;

  -- Hidden through the newest message the caller had on screen, as a delete
  -- is (hide_conversation); a message that arrived after it is still counted
  -- out of the inbox by dm_threads(), which lists no declined conversation.
  update conversation_participants
     set request_state = 'declined',
         hidden_before = greatest(hidden_before, v_through),
         archived_at = null,
         marked_unread_at = null
   where conversation_id = p_conversation_id
     and user_id = v_me;

  if coalesce(p_block, false) then
    select p.user_id into v_partner
      from conversation_participants p
     where p.conversation_id = p_conversation_id
       and p.user_id <> v_me
     limit 1;
    if v_partner is not null then
      perform block_user(v_partner);
    end if;
  end if;
end;
$$;

revoke execute on function decline_message_request(uuid, uuid, boolean) from public, anon;
grant execute on function decline_message_request(uuid, uuid, boolean) to authenticated, service_role;

comment on function decline_message_request(uuid, uuid, boolean) is
  'Decline a pending message request (issue #1216): its messages up to '
  'p_through_message_id leave the caller''s reads and the requester cannot '
  'send again until the caller writes to them. p_block also blocks the '
  'requester. The requester is not told. P0002 for anything but a pending '
  'request to the caller.';

-- ─── dm_threads: the request flag, and no declined conversation ────────
--
-- The return shape gains request, so the function is dropped and re-created.
-- Body as 20271113000001 apart from the new column and the declined filter.

drop function dm_threads();

create function dm_threads()
returns table (
  conversation_id uuid,
  partner_id uuid,
  deleted_partner_key uuid,
  last_body text,
  last_unsent boolean,
  last_at timestamptz,
  last_from_me boolean,
  unread bigint,
  muted boolean,
  archived boolean,
  marked_unread boolean,
  request boolean
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
      m.id
    from direct_messages m
    where (m.sender_id = (select auth.uid()) or m.recipient_id = (select auth.uid()))
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
      (sender_id = (select auth.uid())) as last_from_me
    from my_msgs
    order by conversation_id, created_at desc, id desc
  ),
  unread as (
    select conversation_id, count(*) as cnt
    from my_msgs
    where recipient_id = (select auth.uid()) and read_at is null and unsent_at is null
    group by conversation_id
  )
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
    coalesce(p.request_state = 'pending', false) as request
  from latest l
  left join unread u using (conversation_id)
  left join conversation_participants p
    on p.conversation_id = l.conversation_id
   and p.user_id = (select auth.uid())
  where p.request_state is distinct from 'declined'
  order by l.last_at desc;
$$;

revoke execute on function dm_threads() from public, anon;
grant execute on function dm_threads() to authenticated, service_role;

-- ─── a block resets request consent ─────────────────────────────────────

create or replace function private.user_blocks_reset_dm_acceptance()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  update conversation_participants p
     set request_state = null
   where p.request_state = 'accepted'
     and p.user_id in (new.blocker_id, new.blocked_id)
     and p.conversation_id in (
       select a.conversation_id
         from conversation_participants a
         join conversation_participants b on b.conversation_id = a.conversation_id
         join conversations c on c.id = a.conversation_id and c.kind = 'direct'
        where a.user_id = new.blocker_id
          and b.user_id = new.blocked_id
     );
  return null;
end;
$$;

revoke execute on function private.user_blocks_reset_dm_acceptance() from public, anon, authenticated;

create trigger user_blocks_reset_dm_acceptance
  after insert on user_blocks
  for each row
  execute function private.user_blocks_reset_dm_acceptance();

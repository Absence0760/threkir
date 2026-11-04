-- Direct messages: a conversation model with per-participant state, so each
-- side can delete a conversation for themselves, mute it and archive it
-- without touching the other person's copy (issue #1216, decisions § 2287).
--
-- ── Why a table, not a per-pair state row ────────────────────────────────
--
-- A conversation used to be implicit: the unordered pair of participants, or
-- after 20271021000003 the remaining sender plus a deleted partner's key.
-- Delete-for-me, mute and archive are per-PARTICIPANT facts about a
-- conversation, so they need a row per (conversation, participant).
-- `conversations` + `conversation_participants` is the model a group or club
-- chat needs too; a per-pair `dm_thread_state` would have to be migrated again
-- the day a conversation has three people. Only `kind = 'direct'` exists.
--
-- ── What each participant can set ────────────────────────────────────────
--
-- hidden_before  "Delete conversation" for the caller only. Every message
--                sent at or before it drops out of the caller's reads — the
--                SELECT policy below, so dm_threads(), the thread read and
--                the unread count all agree. A new message after it brings
--                the conversation back with only that message. The other
--                participant's copy is untouched, and so is a report's
--                snapshot (reports.snapshot_*).
-- muted_at       No 'message' notification while set, and the conversation's
--                unread count leaves the nav badge. The inbox still shows it.
-- archived_at    The conversation sits in the inbox's Archived list until a
--                message newer than the archive arrives (dm_threads().archived
--                compares the two), so archiving never hides a reply.
--
-- Each is written only by its RPC (hide_conversation, set_conversation_muted,
-- set_conversation_archived): SECURITY DEFINER, the caller's own row only, the
-- server's clock. A participant row is readable only by its owner, so neither
-- side learns that the other muted, archived or deleted the conversation.
--
-- ── Assignment and backfill ──────────────────────────────────────────────
--
-- direct_messages.conversation_id is set by a BEFORE INSERT trigger, never by
-- a client (no column grant). The trigger finds the pair's direct
-- conversation or creates it, under a transaction-scoped advisory lock on the
-- pair so two first messages sent at once cannot create two. It is named to
-- fire after the send throttle (triggers fire in name order).
--
-- Existing messages are backfilled here, one conversation per live pair and
-- one per (remaining sender, deleted_partner_key). direct_messages is not one
-- of migration_locks.md's high-volume tables, so the backfill runs inline;
-- the ALTERs below already hold the table for the transaction, so no message
-- can be sent between the backfill and the trigger.
--
-- ── Account deletion and retention ──────────────────────────────────────
--
-- A leaver's participant row cascades with their account; the conversation
-- stays for the remaining participant, holding only their own messages (the
-- 20271021000003 rule). private.purge_stale_direct_messages() now also drops
-- a conversation once no message references it, which covers both the 2-year
-- purge emptying a conversation and a conversation whose only messages were
-- the leaver's.
--
-- ── Locking ──────────────────────────────────────────────────────────────
--
-- The FK and the not-null CHECK on direct_messages.conversation_id are added
-- NOT VALID and validated by 20271105000011 in its own transaction, which also
-- promotes the CHECK to NOT NULL without a scan. The ADD COLUMN is nullable
-- with no default (catalogue-only). The new index and trigger take brief
-- write-blocking locks on a table the playbook classes as small.

-- ─── conversations ──────────────────────────────────────────────────────

create table conversations (
  id         uuid primary key default gen_random_uuid(),
  kind       text not null default 'direct' check (kind in ('direct')),
  created_at timestamptz not null default now()
);

comment on table conversations is
  'One conversation between participants (conversation_participants). Only '
  'kind = direct exists: a 1:1 direct-message thread, created by the first '
  'message between a pair (direct_messages_set_conversation). Issue #1216.';

create table conversation_participants (
  conversation_id uuid not null references conversations (id) on delete cascade,
  user_id         uuid not null references auth.users (id) on delete cascade,
  joined_at       timestamptz not null default now(),
  hidden_before   timestamptz,
  muted_at        timestamptz,
  archived_at     timestamptz,
  primary key (conversation_id, user_id)
);

create index conversation_participants_user
  on conversation_participants (user_id);

comment on table conversation_participants is
  'One row per participant per conversation, holding that participant''s own '
  'view of it. Owner-read only; written only by hide_conversation, '
  'set_conversation_muted and set_conversation_archived. Issue #1216.';
comment on column conversation_participants.hidden_before is
  '"Delete conversation" for this participant: messages sent at or before it '
  'are hidden from them by the direct_messages SELECT policy. A newer message '
  'brings the conversation back. The other participant is unaffected.';
comment on column conversation_participants.muted_at is
  'Set while the participant has muted the conversation: no message '
  'notification, and its unread count is left out of the nav badge.';
comment on column conversation_participants.archived_at is
  'When the participant archived the conversation. dm_threads() reports it '
  'archived only while no message is newer than this.';

alter table conversations enable row level security;
alter table conversation_participants enable row level security;

revoke all on table conversations from public, anon, authenticated;
revoke all on table conversation_participants from public, anon, authenticated;
grant select on table conversations to authenticated;
grant select on table conversation_participants to authenticated;
grant all on table conversations to service_role;
grant all on table conversation_participants to service_role;

create policy "participants read their own participant row"
  on conversation_participants for select
  to authenticated
  using (user_id = (select auth.uid()));

create policy "participants read their conversations"
  on conversations for select
  to authenticated
  using (
    exists (
      select 1 from conversation_participants p
       where p.conversation_id = conversations.id
         and p.user_id = (select auth.uid())
    )
  );

-- ─── direct_messages.conversation_id ───────────────────────────────────

alter table direct_messages
  add column conversation_id uuid;

alter table direct_messages
  add constraint direct_messages_conversation_id_fkey
    foreign key (conversation_id) references conversations (id)
    not valid;

alter table direct_messages
  add constraint direct_messages_conversation_id_not_null
    check (conversation_id is not null)
    not valid;

create index direct_messages_conversation
  on direct_messages (conversation_id, created_at desc);

comment on column direct_messages.conversation_id is
  'The conversation the message belongs to. Set by the '
  'direct_messages_set_conversation trigger on insert; a client never writes '
  'it. Issue #1216.';

-- ─── the pair's conversation ────────────────────────────────────────────

create or replace function private.direct_conversation_for(p_a uuid, p_b uuid)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_id uuid;
begin
  -- Two first messages between the same pair, sent at once, would both see no
  -- conversation and create one each. The lock is per pair and ends with the
  -- transaction.
  perform pg_advisory_xact_lock(
    hashtextextended('direct_conversation:' || least(p_a, p_b)::text || ':' || greatest(p_a, p_b)::text, 0)
  );

  select c.id into v_id
    from conversations c
    join conversation_participants pa on pa.conversation_id = c.id and pa.user_id = p_a
    join conversation_participants pb on pb.conversation_id = c.id and pb.user_id = p_b
   where c.kind = 'direct'
   limit 1;

  if v_id is null then
    insert into conversations (kind) values ('direct') returning id into v_id;
    insert into conversation_participants (conversation_id, user_id)
      values (v_id, p_a), (v_id, p_b);
  end if;

  return v_id;
end;
$$;

revoke execute on function private.direct_conversation_for(uuid, uuid) from public, anon, authenticated;

create or replace function direct_messages_set_conversation()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  -- A send always names a live recipient; a null one is refused by the INSERT
  -- policy's follow check anyway, so it never reaches a conversation.
  if new.recipient_id is null then
    raise exception 'direct_messages: a message needs a recipient' using errcode = '23502';
  end if;
  new.conversation_id := private.direct_conversation_for(new.sender_id, new.recipient_id);
  return new;
end;
$$;

revoke execute on function direct_messages_set_conversation() from public, anon, authenticated;

create trigger direct_messages_set_conversation
  before insert on direct_messages
  for each row
  execute function direct_messages_set_conversation();

-- ─── backfill ───────────────────────────────────────────────────────────
--
-- Set-based: one mapping row per conversation to create (a live pair, or a
-- remaining sender plus a deleted partner's key), then one UPDATE joining
-- every unassigned message to its row on equality keys, so the table is read
-- a fixed number of times however many pairs it holds. A live pair's key is
-- (least, greatest) of the two ids; a deleted partner's is (sender,
-- deleted_partner_key) and its conversation has the sender alone.
--
-- It is a function so the pgtap suite runs this exact body against
-- pre-trigger-shaped rows (dm_conversations_test.sql), and it refuses to
-- return while any message is left unassigned: 20271105000011 validates the
-- not-null CHECK, and a straggler must fail this migration, not strand that
-- one half-applied. Nothing calls it after this migration.

create or replace function private.backfill_direct_message_conversations()
returns integer
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_created integer;
  v_left bigint;
begin
  create temporary table dm_conversation_backfill on commit drop as
  select gen_random_uuid() as conversation_id, live, k1, k2, first_at
    from (
      select true as live,
             least(sender_id, recipient_id) as k1,
             greatest(sender_id, recipient_id) as k2,
             min(created_at) as first_at
        from direct_messages
       where recipient_id is not null
         and conversation_id is null
       group by 2, 3
      union all
      select false, sender_id, deleted_partner_key, min(created_at)
        from direct_messages
       where recipient_id is null
         and conversation_id is null
       group by 2, 3
    ) pairs;

  insert into conversations (id, kind, created_at)
  select conversation_id, 'direct', first_at from dm_conversation_backfill;
  get diagnostics v_created = row_count;

  insert into conversation_participants (conversation_id, user_id, joined_at)
  select conversation_id, k1, first_at from dm_conversation_backfill
  union all
  select conversation_id, k2, first_at from dm_conversation_backfill where live;

  update direct_messages m
     set conversation_id = b.conversation_id
    from dm_conversation_backfill b
   where m.conversation_id is null
     and b.live = (m.recipient_id is not null)
     and b.k1 = case when m.recipient_id is null then m.sender_id
                     else least(m.sender_id, m.recipient_id) end
     and b.k2 = case when m.recipient_id is null then m.deleted_partner_key
                     else greatest(m.sender_id, m.recipient_id) end;

  drop table dm_conversation_backfill;

  select count(*) into v_left from direct_messages where conversation_id is null;
  if v_left > 0 then
    raise exception 'backfill_direct_message_conversations: % message(s) left without a conversation', v_left
      using errcode = '23502';
  end if;

  return v_created;
end;
$$;

revoke execute on function private.backfill_direct_message_conversations() from public, anon, authenticated, service_role;

select private.backfill_direct_message_conversations();

-- ─── delete-for-me in the read path ────────────────────────────────────
--
-- Every client read of direct_messages goes through this policy, so a
-- conversation deleted for the caller is gone from dm_threads() (SECURITY
-- INVOKER), the thread read and the unread count alike. The subquery reads
-- conversation_participants under its own owner-only policy, which is the
-- caller's row and nobody else's.

alter policy "participants read their own messages" on direct_messages
  using (
    ((select auth.uid()) = sender_id or (select auth.uid()) = recipient_id)
    and not exists (
      select 1 from conversation_participants p
       where p.conversation_id = direct_messages.conversation_id
         and p.user_id = (select auth.uid())
         and p.hidden_before is not null
         and direct_messages.created_at <= p.hidden_before
    )
  );

-- ─── the participant RPCs ───────────────────────────────────────────────
--
-- A conversation the caller is not in and one that does not exist answer the
-- same P0002, so the RPCs cannot probe for conversation ids.

create or replace function hide_conversation(p_conversation_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid := auth.uid();
begin
  if v_me is null then
    raise exception 'hide_conversation: not authorized' using errcode = '42501';
  end if;

  -- Archiving a conversation that is now empty for the caller means nothing,
  -- and a stale archived_at would file the next message under Archived.
  update conversation_participants
     set hidden_before = now(),
         archived_at = null
   where conversation_id = p_conversation_id
     and user_id = v_me;

  if not found then
    raise exception 'hide_conversation: conversation not found' using errcode = 'P0002';
  end if;
end;
$$;

revoke execute on function hide_conversation(uuid) from public, anon;
grant execute on function hide_conversation(uuid) to authenticated, service_role;

comment on function hide_conversation(uuid) is
  'Delete a conversation for the caller only (issue #1216): stamps '
  'hidden_before = now(), so every message so far leaves the caller''s reads. '
  'The other participant keeps theirs. P0002 for a conversation the caller is '
  'not in.';

create or replace function set_conversation_muted(p_conversation_id uuid, p_muted boolean)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid := auth.uid();
begin
  if v_me is null then
    raise exception 'set_conversation_muted: not authorized' using errcode = '42501';
  end if;
  if p_muted is null then
    raise exception 'set_conversation_muted: p_muted is required' using errcode = '22004';
  end if;

  -- An already-muted conversation keeps its first muted_at.
  update conversation_participants
     set muted_at = case when p_muted then coalesce(muted_at, now()) else null end
   where conversation_id = p_conversation_id
     and user_id = v_me;

  if not found then
    raise exception 'set_conversation_muted: conversation not found' using errcode = 'P0002';
  end if;
end;
$$;

revoke execute on function set_conversation_muted(uuid, boolean) from public, anon;
grant execute on function set_conversation_muted(uuid, boolean) to authenticated, service_role;

comment on function set_conversation_muted(uuid, boolean) is
  'Mute or unmute a conversation for the caller (issue #1216). A muted '
  'conversation raises no message notification and is left out of the unread '
  'badge. P0002 for a conversation the caller is not in.';

create or replace function set_conversation_archived(p_conversation_id uuid, p_archived boolean)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid := auth.uid();
begin
  if v_me is null then
    raise exception 'set_conversation_archived: not authorized' using errcode = '42501';
  end if;
  if p_archived is null then
    raise exception 'set_conversation_archived: p_archived is required' using errcode = '22004';
  end if;

  -- Re-stamped on every archive: archived means "nothing newer than when I
  -- last archived it", so archiving again after a reply files it away again.
  update conversation_participants
     set archived_at = case when p_archived then now() else null end
   where conversation_id = p_conversation_id
     and user_id = v_me;

  if not found then
    raise exception 'set_conversation_archived: conversation not found' using errcode = 'P0002';
  end if;
end;
$$;

revoke execute on function set_conversation_archived(uuid, boolean) from public, anon;
grant execute on function set_conversation_archived(uuid, boolean) to authenticated, service_role;

comment on function set_conversation_archived(uuid, boolean) is
  'Archive or unarchive a conversation for the caller (issue #1216). It stays '
  'archived until a newer message arrives. P0002 for a conversation the '
  'caller is not in.';

-- ─── notify_direct_message: respect mute and delete-for-me ─────────────
--
-- Bare-body re-emit of 20261026_001 with two changes. A recipient who muted
-- the conversation gets no notification. And the "bell already lit" check
-- ignores unread messages the recipient deleted the conversation over: those
-- are hidden from them, so without this a hidden unread message would
-- silence every later one.

create or replace function notify_direct_message()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_hidden_before timestamptz;
  v_muted boolean;
begin
  select p.hidden_before, p.muted_at is not null
    into v_hidden_before, v_muted
    from conversation_participants p
   where p.conversation_id = new.conversation_id
     and p.user_id = new.recipient_id;

  if coalesce(v_muted, false) then
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

-- ─── dm_threads: one row per conversation, with the caller's state ─────
--
-- The return shape changes, so the function is dropped and re-created. A
-- thread is now keyed on conversation_id; partner_id and deleted_partner_key
-- stay, since every client routes a thread by them. Messages the caller
-- deleted the conversation over never reach it (the SELECT policy).

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
  archived boolean
)
language sql
stable
security invoker
set search_path = public, pg_temp
as $$
  with my_msgs as (
    select
      conversation_id,
      case when sender_id = (select auth.uid()) then recipient_id else sender_id end as partner_id,
      deleted_partner_key,
      sender_id,
      recipient_id,
      body,
      unsent_at,
      created_at,
      read_at,
      id
    from direct_messages
    where sender_id = (select auth.uid()) or recipient_id = (select auth.uid())
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
    coalesce(u.cnt, 0) as unread,
    coalesce(p.muted_at is not null, false) as muted,
    coalesce(p.archived_at is not null and p.archived_at >= l.last_at, false) as archived
  from latest l
  left join unread u using (conversation_id)
  left join conversation_participants p
    on p.conversation_id = l.conversation_id
   and p.user_id = (select auth.uid())
  order by l.last_at desc;
$$;

revoke execute on function dm_threads() from public, anon;
grant execute on function dm_threads() to authenticated, service_role;

-- ─── purge: drop a conversation once nothing references it ─────────────
--
-- Bare-body re-emit of 20261119_001 plus the empty-conversation sweep. The
-- sweep runs in its own block: a message sent into a conversation in the
-- instant it is judged empty makes the delete fail its FK, and that must not
-- roll back the message purge. The conversation is then simply kept.

create or replace function private.purge_stale_direct_messages()
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_deleted bigint;
  v_conversations bigint;
begin
  with deleted as (
    delete from direct_messages
    where created_at < now() - interval '2 years'
    returning 1
  )
  select count(*) into v_deleted from deleted;
  if v_deleted > 0 then
    raise notice 'purge_stale_direct_messages: removed % row(s)', v_deleted;
  end if;

  begin
    with emptied as (
      delete from conversations c
      where not exists (select 1 from direct_messages m where m.conversation_id = c.id)
      returning 1
    )
    select count(*) into v_conversations from emptied;
    if v_conversations > 0 then
      raise notice 'purge_stale_direct_messages: removed % empty conversation(s)', v_conversations;
    end if;
  exception when foreign_key_violation then
    raise notice 'purge_stale_direct_messages: a conversation gained a message mid-sweep; kept';
  end;
end;
$$;

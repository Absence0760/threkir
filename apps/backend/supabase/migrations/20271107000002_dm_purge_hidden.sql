-- Direct messages: erase what nobody can see any more, and bound "Delete
-- conversation" to what the deleter actually saw (PR #1289 item D, from the
-- #1280 sign-off review of 20271105000010; decisions § 2339).
--
-- ── 1. The daily purge erases messages no participant can still see ──────
--
-- Delete-for-me (hidden_before) only filtered reads, so a message both sides
-- had deleted, or one in a deleted account's thread that the remaining
-- participant had deleted, was still stored for the full 2-year window while
-- no person could ever read it again. Holding it served no purpose the app
-- can name (Art 5(1)(c) / (e)), so private.purge_stale_direct_messages() now
-- erases it on its next run.
--
-- "Can still see" is the SELECT policy's own rule, evaluated for each person
-- the message names: a sender or a non-null recipient sees it unless their
-- participant row has hidden_before at or after its created_at. A message is
-- erased only when every such person is hidden from it. A person with no
-- participant row would still see it under the policy, so it is kept for
-- them. A deleted recipient is null and no longer counts, which is what makes
-- a deleted account's thread erasable once its one remaining participant has
-- deleted it.
--
-- A report's snapshot (reports.snapshot_*) has no FK to the message and is
-- kept under the report's own retention (20271021000003). Nothing else
-- references direct_messages. The empty-conversation sweep runs after this
-- step, so a conversation the erase empties goes in the same run, with its
-- participant rows.
--
-- ── 2. hidden_before is the newest message the deleter saw ──────────────
--
-- Clients hold a delete behind an undo window and call hide_conversation when
-- it closes, so stamping now() also hid every message that arrived during the
-- window, unseen, and with (1) erased it once the other side deleted too.
-- hide_conversation now takes the id of the newest message the caller had on
-- screen and stamps that message's created_at instead; a message sent after
-- it stays visible and brings the conversation back. hidden_before never moves
-- backwards (greatest), so a stale id cannot reveal an earlier delete. The
-- message must be in the conversation and name the caller, or the call answers
-- the same P0002 as a conversation the caller is not in.
--
-- The one-argument form is dropped rather than kept: it is the now() stamp
-- this replaces, and no released client calls it (20271105000010 ships in the
-- same release as this migration).
--
-- ── Locking ──────────────────────────────────────────────────────────────
--
-- Function replacements only; no table DDL.

-- ─── hide_conversation(conversation, through message) ──────────────────

drop function hide_conversation(uuid);

create function hide_conversation(p_conversation_id uuid, p_through_message_id uuid)
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

  select m.created_at into v_through
    from direct_messages m
   where m.id = p_through_message_id
     and m.conversation_id = p_conversation_id
     and (m.sender_id = v_me or m.recipient_id = v_me);

  if v_through is null then
    raise exception 'hide_conversation: conversation not found' using errcode = 'P0002';
  end if;

  -- Archiving a conversation that is now empty for the caller means nothing,
  -- and a stale archived_at would file the next message under Archived.
  update conversation_participants
     set hidden_before = greatest(hidden_before, v_through),
         archived_at = null
   where conversation_id = p_conversation_id
     and user_id = v_me;

  if not found then
    raise exception 'hide_conversation: conversation not found' using errcode = 'P0002';
  end if;
end;
$$;

revoke execute on function hide_conversation(uuid, uuid) from public, anon;
grant execute on function hide_conversation(uuid, uuid) to authenticated, service_role;

comment on function hide_conversation(uuid, uuid) is
  'Delete a conversation for the caller only (issue #1216): hidden_before '
  'becomes the created_at of p_through_message_id, the newest message the '
  'caller saw, so a message sent after it stays visible. Never moves '
  'backwards. The other participant keeps theirs; the daily purge erases a '
  'message once no participant can see it. P0002 for a conversation the '
  'caller is not in or a message outside it.';

-- ─── purge: erase what no participant can see ──────────────────────────
--
-- Bare-body re-emit of 20271105000010 with the erase step between the 2-year
-- purge and the empty-conversation sweep. The erase is driven from the
-- participant rows that have deleted something, so it reads only those
-- conversations' messages (direct_messages_conversation index).

create or replace function private.purge_stale_direct_messages()
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_deleted bigint;
  v_hidden bigint;
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

  with erased as (
    delete from direct_messages m
     where m.id in (
       select c.id
         from conversation_participants h
         join direct_messages c
           on c.conversation_id = h.conversation_id
          and c.created_at <= h.hidden_before
          and h.user_id in (c.sender_id, c.recipient_id)
        where h.hidden_before is not null
     )
       and not exists (
         select 1
           from (values (m.sender_id), (m.recipient_id)) reader (user_id)
          where reader.user_id is not null
            and not exists (
              select 1 from conversation_participants p
               where p.conversation_id = m.conversation_id
                 and p.user_id = reader.user_id
                 and p.hidden_before is not null
                 and m.created_at <= p.hidden_before
            )
       )
    returning 1
  )
  select count(*) into v_hidden from erased;
  if v_hidden > 0 then
    raise notice 'purge_stale_direct_messages: erased % message(s) no participant can see', v_hidden;
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

revoke all on function private.purge_stale_direct_messages() from public, anon, authenticated;

comment on function private.purge_stale_direct_messages() is
  'Daily DM retention (pg_cron purge-stale-direct-messages, 03:41 UTC): '
  'purges direct_messages older than 2 years, erases messages no participant '
  'can still see (every sender / live recipient has deleted the conversation '
  'past them), then drops conversations no message references. Account '
  'deletion erasure is the sender_id ON DELETE CASCADE.';

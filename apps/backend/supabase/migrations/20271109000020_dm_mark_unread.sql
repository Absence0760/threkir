-- Direct messages: "Mark as unread" for one participant (issue #1216 P2,
-- decisions § 2347).
--
-- ── What it is ───────────────────────────────────────────────────────────
--
-- A participant can flag a conversation they have read as unread again, as a
-- reminder to come back to it. It is one more piece of per-participant state
-- on conversation_participants (20271105000010), so it is private to its
-- owner like hidden_before, muted_at and archived_at.
--
-- It never touches direct_messages.read_at. read_at is the reader's fact
-- about the other person's message, and resetting it would tell the sender
-- something the reader did not do; a separate stamp keeps the reminder the
-- reader's own.
--
-- ── How the count honours it ─────────────────────────────────────────────
--
-- dm_threads().unread is the count every client badge and inbox row reads
-- (web dm_unread.svelte.ts + the inbox list, mobile You tab + inbox), so the
-- mark is folded in there, server-side: a marked conversation counts at least
-- one. A conversation that also has unread messages counts those, not one
-- more. A new column, marked_unread, says whether the mark is set, so a
-- client opening the conversation knows to clear it. Muted and archived
-- conversations are still left out of the badge by the clients' existing
-- rule; the mark does not override that.
--
-- The mark is cleared by set_conversation_unread(…, false), which each client
-- calls when the conversation is opened, and by hide_conversation: a deleted
-- conversation that comes back with a new message comes back on that
-- message's own unread count, not on a reminder set before the delete.
--
-- ── Account deletion and export ──────────────────────────────────────────
--
-- The column lives on the participant row, which cascades with its owner's
-- account. The export (export-data/backup_spec.ts, conversation_settings.json)
-- adds it to the subject's own row.
--
-- ── Locking ──────────────────────────────────────────────────────────────
--
-- ADD COLUMN, nullable, no default: catalogue-only. The rest is function
-- replacement.

alter table conversation_participants
  add column marked_unread_at timestamptz;

comment on column conversation_participants.marked_unread_at is
  'Set while the participant has marked the conversation unread: dm_threads() '
  'counts it as at least one unread. Cleared when they open it '
  '(set_conversation_unread) or delete it (hide_conversation). Never touches '
  'direct_messages.read_at, so the other participant learns nothing.';

comment on table conversation_participants is
  'One row per participant per conversation, holding that participant''s own '
  'view of it. Owner-read only; written only by hide_conversation, '
  'set_conversation_muted, set_conversation_archived and '
  'set_conversation_unread. Issue #1216.';

-- ─── set_conversation_unread ────────────────────────────────────────────

create or replace function set_conversation_unread(p_conversation_id uuid, p_unread boolean)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid := auth.uid();
begin
  if v_me is null then
    raise exception 'set_conversation_unread: not authorized' using errcode = '42501';
  end if;
  if p_unread is null then
    raise exception 'set_conversation_unread: p_unread is required' using errcode = '22004';
  end if;

  update conversation_participants
     set marked_unread_at = case when p_unread then coalesce(marked_unread_at, now()) else null end
   where conversation_id = p_conversation_id
     and user_id = v_me;

  if not found then
    raise exception 'set_conversation_unread: conversation not found' using errcode = 'P0002';
  end if;
end;
$$;

revoke execute on function set_conversation_unread(uuid, boolean) from public, anon;
grant execute on function set_conversation_unread(uuid, boolean) to authenticated, service_role;

comment on function set_conversation_unread(uuid, boolean) is
  'Mark a conversation unread for the caller, or clear the mark (issue #1216). '
  'A marked conversation counts as at least one unread in dm_threads(). Does '
  'not touch read_at. P0002 for a conversation the caller is not in.';

-- ─── hide_conversation: a delete clears the mark ────────────────────────
--
-- Bare-body re-emit of 20271107000002 with marked_unread_at cleared beside
-- archived_at.

create or replace function hide_conversation(p_conversation_id uuid, p_through_message_id uuid)
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

-- ─── dm_threads: the mark, and the count that honours it ───────────────
--
-- The return shape gains marked_unread, so the function is dropped and
-- re-created. Body as 20271105000010 apart from the unread fold and the new
-- column.

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
  marked_unread boolean
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
    greatest(coalesce(u.cnt, 0), case when p.marked_unread_at is not null then 1 else 0 end) as unread,
    coalesce(p.muted_at is not null, false) as muted,
    coalesce(p.archived_at is not null and p.archived_at >= l.last_at, false) as archived,
    coalesce(p.marked_unread_at is not null, false) as marked_unread
  from latest l
  left join unread u using (conversation_id)
  left join conversation_participants p
    on p.conversation_id = l.conversation_id
   and p.user_id = (select auth.uid())
  order by l.last_at desc;
$$;

revoke execute on function dm_threads() from public, anon;
grant execute on function dm_threads() to authenticated, service_role;

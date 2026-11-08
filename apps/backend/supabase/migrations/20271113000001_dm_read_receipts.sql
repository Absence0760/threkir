-- Direct messages: read receipts, with a reciprocal opt-out (issue #1216,
-- decisions § 2371).
--
-- ── What it is ───────────────────────────────────────────────────────────
--
-- A sender sees "Seen" and the time under their newest message the other
-- person has read. A runner who turns read receipts off neither sends them nor
-- sees them, as in common messengers.
--
-- ── Why read_at is withheld ──────────────────────────────────────────────
--
-- direct_messages.read_at is the recipient's own fact: it drives their unread
-- count. Until now any participant could select it, so the sender could read
-- it whatever the recipient wanted. RLS works on rows, not columns, so hiding
-- it from the sender is a column grant: SELECT on direct_messages is re-granted
-- to authenticated column by column without read_at, and nothing a client can
-- call hands it back:
--
--   * dm_threads() reads it for the unread count, so it becomes SECURITY
--     DEFINER, with the SELECT policy's participant and hidden_before rules
--     written out in its own WHERE;
--   * unsend_direct_message() returned the whole row to the sender, so it now
--     returns it with read_at nulled;
--   * marking read is mark_direct_messages_read(), because the old client
--     UPDATE ... WHERE read_at IS NULL needs SELECT on read_at. The UPDATE
--     grant and the "recipient marks read" policy go.
--
-- ── What the sender sees instead ─────────────────────────────────────────
--
-- seen_at, a new column the sender may select. mark_direct_messages_read()
-- writes it beside read_at only when both participants have receipts on,
-- holding a per-user transaction advisory lock on each that the opt-out
-- trigger also takes, so a concurrent opt-out either waits for the read or is
-- waited for. An advisory lock rather than FOR SHARE on user_settings, because
-- most runners have no row to lock until they first change a setting. Turning receipts off clears seen_at on
-- every message the runner sent or received (the user_settings trigger
-- below), so an opt-out also withdraws receipts already shown, both ways.
-- Turning them back on does not restore those: only reads made while both are
-- on are shared.
--
-- ── The setting ──────────────────────────────────────────────────────────
--
-- user_settings.dm_read_receipts, a column and not a prefs bag key, because a
-- trigger and an RPC read it (settings.md § Placement rule). Default true. The
-- table is owner-read, so no one else learns the choice, and export-data's
-- user_settings.json selects every column, so the export carries it.
--
-- ── Locking ──────────────────────────────────────────────────────────────
--
-- Both ADD COLUMNs are catalogue-only (nullable, or a constant default). The
-- rest is grants, policies, functions and a trigger on user_settings.

alter table user_settings
  add column dm_read_receipts boolean not null default true;

comment on column user_settings.dm_read_receipts is
  'Direct-message read receipts (issue #1216). False: the runner''s reads are '
  'not shared and they see no one else''s. Read by mark_direct_messages_read() '
  'and user_settings_dm_read_receipts_off.';

alter table direct_messages
  add column seen_at timestamptz;

comment on column direct_messages.seen_at is
  'When the recipient read the message, as shared with the sender: written by '
  'mark_direct_messages_read() only while both participants have '
  'user_settings.dm_read_receipts on, and cleared when either turns it off. '
  'read_at is the recipient''s own fact and is not granted to clients.';

-- ─── Column grant: everything but read_at ───────────────────────────────
--
-- anon gets the same columns as authenticated, as on every column-locked
-- table (column_grant_lockdown_registry_test (4)); the SELECT policy matches
-- no row for a caller without auth.uid().

revoke select on direct_messages from anon, authenticated;
grant select (
  id, sender_id, recipient_id, body, created_at, route_id, unsent_at,
  deleted_partner_key, conversation_id, seen_at
) on direct_messages to anon, authenticated;

drop policy "recipient marks read" on direct_messages;
revoke update on direct_messages from anon, authenticated;

-- ─── mark_direct_messages_read ──────────────────────────────────────────

create function mark_direct_messages_read(p_partner_id uuid, p_through_message_id uuid)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid := auth.uid();
  v_at timestamptz;
  v_id uuid;
  v_share boolean;
  v_count integer;
begin
  if v_me is null then
    raise exception 'mark_direct_messages_read: not authorized' using errcode = '42501';
  end if;

  select m.created_at, m.id into v_at, v_id
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
         and coalesce((select dm_read_receipts from user_settings where user_id = p_partner_id), true);

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

comment on function mark_direct_messages_read(uuid, uuid) is
  'Marks the partner''s unread messages to the caller read, up to and including '
  'p_through_message_id on (created_at, id). Writes seen_at as well only when '
  'both have user_settings.dm_read_receipts on. Returns how many it marked; '
  'P0002 for a message outside the pair.';

-- ─── Opting out withdraws receipts both ways ────────────────────────────

create function private.user_settings_dm_read_receipts_off()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.dm_read_receipts is false
     and (tg_op = 'INSERT' or old.dm_read_receipts is distinct from false) then
    perform pg_advisory_xact_lock(hashtextextended('dm_read_receipts:' || new.user_id::text, 0));
    -- One statement, so two runners opting out at once cannot each lock half
    -- of the other's rows and deadlock.
    update direct_messages
       set seen_at = null
     where (sender_id = new.user_id or recipient_id = new.user_id)
       and seen_at is not null;
  end if;
  return null;
end;
$$;

revoke execute on function private.user_settings_dm_read_receipts_off() from public, anon, authenticated;

create trigger user_settings_dm_read_receipts_off
  after insert or update of dm_read_receipts on user_settings
  for each row execute function private.user_settings_dm_read_receipts_off();

-- ─── unsend_direct_message: never hand read_at to the sender ────────────
--
-- Body as 20271021000003, with read_at nulled on both returns.

create or replace function unsend_direct_message(p_message_id uuid)
returns direct_messages
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid := auth.uid();
  v_row direct_messages;
begin
  if v_me is null then
    raise exception 'unsend_direct_message: not authorized' using errcode = '42501';
  end if;

  update direct_messages
     set body = null,
         route_id = null,
         unsent_at = now()
   where id = p_message_id
     and sender_id = v_me
     and unsent_at is null
  returning * into v_row;

  if v_row.id is not null then
    v_row.read_at := null;
    return v_row;
  end if;

  -- Already unsent is not an error: a retried tap converges on the same row.
  select * into v_row
    from direct_messages
   where id = p_message_id
     and sender_id = v_me;

  if v_row.id is null then
    -- Someone else's message and no message at all answer the same, so the
    -- RPC cannot be used to probe for message ids.
    raise exception 'unsend_direct_message: message not found'
      using errcode = 'P0002';
  end if;

  v_row.read_at := null;
  return v_row;
end;
$$;

revoke execute on function unsend_direct_message(uuid) from public, anon;
grant execute on function unsend_direct_message(uuid) to authenticated, service_role;

-- ─── dm_threads: SECURITY DEFINER, so the unread count can read read_at ──
--
-- Body as 20271109000020, with the SELECT policy's rules (a participant, and
-- not at or before the caller's hidden_before) written into my_msgs.

create or replace function dm_threads()
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

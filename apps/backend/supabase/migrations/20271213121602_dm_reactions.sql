-- Direct messages: reactions (issue #1216).
--
-- A participant can put one reaction from a small fixed set on a message in
-- their conversation, change it, or take it off. Both sides see it under the
-- message.
--
-- ── The set ─────────────────────────────────────────────────────────────
--
-- Six keys, CHECKed and registered in check_constraint_unions.mjs:
-- thumbs_up, heart, laugh, surprised, sad, fire. The table stores the key,
-- never the glyph, and each client maps a key to its Unicode codepoints
-- (dm_reactions.ts / dm_reactions.dart, a parity pair). A fixed set is the
-- abuse control: a reaction carries no free text, so it needs no report path,
-- no snapshot and no moderation of its own.
--
-- ── Who may react ───────────────────────────────────────────────────────
--
-- Only set_direct_message_reaction() writes; clients hold no INSERT, UPDATE
-- or DELETE grant. It allows a reaction only when:
--
--   * the caller is the message's sender or recipient (P0002 otherwise, the
--     answer a message that does not exist gives, so ids cannot be probed);
--   * the message is live (not unsent) and not hidden from the caller by a
--     delete-for-me (hidden_before);
--   * the partner still has an account;
--   * neither side has blocked the other; and
--   * neither participant's request_state is pending or declined: a request
--     has to be accepted before anyone reacts in it.
--
-- Every refusal but "not a participant" is one 55000, so a refusal does not
-- tell the caller whether they were blocked, declined or are still waiting
-- (decisions § 1916). Each call spends the dm_reaction rate-limit bucket
-- (120 an hour), set or clear alike. A reaction raises no notification.
--
-- ── Who may read ────────────────────────────────────────────────────────
--
-- The SELECT policy admits a reaction only when the caller can read its
-- message through direct_messages' own SELECT policy (participant, not hidden
-- before) and the message is live. Unsending a message deletes its reactions
-- (trigger below), so a reaction never outlives the words it was on.
--
-- ── Retention, export, deletion ─────────────────────────────────────────
--
-- message_id cascades, so the two-year purge, the purge of messages nobody
-- can see, and the sender's account deletion take the reactions with the
-- message. user_id cascades with the reactor's account. Both Art 20 exports
-- carry the subject's own reactions (direct_message_reactions.json).
--
-- ── Locks ───────────────────────────────────────────────────────────────
--
-- A new table, a function and an AFTER UPDATE trigger on direct_messages
-- (CREATE TRIGGER takes SHARE ROW EXCLUSIVE with no scan, which readers pass).

create table direct_message_reactions (
  message_id uuid not null references direct_messages (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  reaction text not null,
  created_at timestamptz not null default now(),
  primary key (message_id, user_id),
  constraint direct_message_reactions_reaction_check
    check (reaction in ('thumbs_up', 'heart', 'laugh', 'surprised', 'sad', 'fire'))
);

create index direct_message_reactions_user_id on direct_message_reactions (user_id);

comment on table direct_message_reactions is
  'One reaction per participant per direct message, from a fixed key set '
  '(issue #1216). Written only by set_direct_message_reaction(); readable by '
  'whoever can read the message; deleted when the message is unsent.';

alter table direct_message_reactions enable row level security;

revoke all on direct_message_reactions from public, anon, authenticated;
-- Every column is readable by whoever the policy admits, so the grant is
-- table-wide (a per-column grant of every column is what
-- column_grant_lockdown_registry_test calls a table-wide grant written the
-- long way). No client holds INSERT, UPDATE or DELETE.
grant select on direct_message_reactions to anon, authenticated;
grant all on direct_message_reactions to service_role;

create policy "participants read reactions on messages they can read"
  on direct_message_reactions for select
  to authenticated
  using (
    exists (
      select 1 from direct_messages m
       where m.id = direct_message_reactions.message_id
         and m.unsent_at is null
    )
  );

create function set_direct_message_reaction(p_message_id uuid, p_reaction text)
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
     and (m.sender_id = v_me or m.recipient_id = v_me);

  if v_msg.id is null then
    raise exception 'set_direct_message_reaction: message not found' using errcode = 'P0002';
  end if;

  v_partner := case when v_msg.sender_id = v_me then v_msg.recipient_id else v_msg.sender_id end;

  if v_msg.unsent_at is not null
     or v_partner is null
     or is_blocked_either_way(v_me, v_partner)
     or exists (
       select 1 from conversation_participants p
        where p.conversation_id = v_msg.conversation_id
          and p.user_id = v_me
          and p.hidden_before is not null
          and v_msg.created_at <= p.hidden_before
     )
     or exists (
       select 1 from conversation_participants p
        where p.conversation_id = v_msg.conversation_id
          and p.request_state in ('pending', 'declined')
     ) then
    raise exception 'set_direct_message_reaction: this message cannot take a reaction'
      using errcode = '55000';
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

revoke execute on function set_direct_message_reaction(uuid, text) from public, anon;
grant execute on function set_direct_message_reaction(uuid, text) to authenticated, service_role;

comment on function set_direct_message_reaction(uuid, text) is
  'Sets (or with null clears) the caller''s reaction on a direct message '
  '(issue #1216). P0002 when the caller is not a participant; 55000 when the '
  'message is unsent or hidden from them, the partner is gone, either side '
  'blocked the other, or the conversation is an unaccepted request; 22023 '
  'for a key outside the set. Spends dm_reaction (120/hour).';

-- ─── unsend takes the reactions ─────────────────────────────────────────

create function private.direct_messages_unsent_clear_reactions()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  delete from direct_message_reactions where message_id = new.id;
  return null;
end;
$$;

revoke execute on function private.direct_messages_unsent_clear_reactions() from public, anon, authenticated;

create trigger direct_messages_unsent_clear_reactions
  after update of unsent_at on direct_messages
  for each row
  when (old.unsent_at is null and new.unsent_at is not null)
  execute function private.direct_messages_unsent_clear_reactions();

-- Group conversations, slice 1 (issue #1365, group_messages.md § 4,
-- decisions § 2458): account deletion and both purges know about groups.
--
-- ── Account deletion ────────────────────────────────────────────────────
--
-- A member's sent group messages go with their account through the existing
-- sender_id cascade (§ 2221, Art 17(1)), and their participant row cascades.
-- When that row was the group's active owner, the AFTER DELETE trigger below
-- passes ownership to the longest-standing admin, else member (§ 2). The same
-- trigger covers an owner row deleted any other way; a row deleted because its
-- whole conversation went is skipped.
--
-- ── private.purge_stale_direct_messages ─────────────────────────────────
--
--   * 2-year purge: unchanged, group or not.
--   * Erase what nobody can see, direct half: unchanged but for `not
--     is_group` (a group message's sender hiding it says nothing about the
--     other members).
--   * Erase what nobody can see, group half: a group message is erased once
--     its sender has hidden it (or their account is gone, which the cascade
--     already did) and no active participant whose window contains it can
--     still see it (each has hidden_before past it, or joined after it).
--   * A group with no active member is erased with its messages.
--   * An invite past its 14 days is retired: deleted when the invitee never
--     wrote in the group, otherwise marked left so their own messages keep
--     their participant row.
--   * Emptied conversations: a direct conversation with no message, as before,
--     and a group with no message and no active member. A new group with
--     members and no message yet is kept.
--
-- A report's snapshot outlives all of this under the reports windows (§ 2231),
-- exactly as for 1:1.
--
-- ── Locking ─────────────────────────────────────────────────────────────
--
-- CREATE OR REPLACE FUNCTION (no table lock) and one CREATE TRIGGER on
-- conversation_participants (SHARE ROW EXCLUSIVE, catalogue-only).

create or replace function private.conversation_participants_pass_ownership()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if old.role = 'owner'
     and old.membership_state = 'active'
     and exists (select 1 from conversations c where c.id = old.conversation_id and c.kind = 'group') then
    perform private.group_pass_ownership(old.conversation_id);
  end if;
  return null;
end;
$$;
revoke execute on function private.conversation_participants_pass_ownership() from public, anon, authenticated;

drop trigger if exists conversation_participants_pass_ownership on conversation_participants;
create trigger conversation_participants_pass_ownership
  after delete on conversation_participants
  for each row
  when (old.role = 'owner')
  execute function private.conversation_participants_pass_ownership();

create or replace function private.purge_stale_direct_messages()
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  c_invite_ttl constant interval := interval '14 days';
  v_deleted bigint;
  v_hidden bigint;
  v_group_hidden bigint;
  v_abandoned bigint;
  v_invites bigint;
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
          and not c.is_group
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

  with erased as (
    delete from direct_messages m
     where m.is_group
       and exists (
         select 1 from conversation_participants s
          where s.conversation_id = m.conversation_id
            and s.user_id = m.sender_id
            and s.hidden_before is not null
            and m.created_at <= s.hidden_before
       )
       and not exists (
         select 1 from conversation_participants p
          where p.conversation_id = m.conversation_id
            and p.user_id <> m.sender_id
            and p.membership_state = 'active'
            and m.created_at >= p.joined_at
            and (p.hidden_before is null or m.created_at > p.hidden_before)
       )
    returning 1
  )
  select count(*) into v_group_hidden from erased;
  if v_group_hidden > 0 then
    raise notice 'purge_stale_direct_messages: erased % group message(s) no member can see', v_group_hidden;
  end if;

  with erased as (
    delete from direct_messages m
     using conversations c
     where c.id = m.conversation_id
       and c.kind = 'group'
       and not exists (
         select 1 from conversation_participants p
          where p.conversation_id = c.id
            and p.membership_state = 'active'
       )
    returning 1
  )
  select count(*) into v_abandoned from erased;
  if v_abandoned > 0 then
    raise notice 'purge_stale_direct_messages: erased % message(s) of groups with no member left', v_abandoned;
  end if;

  with retired as (
    delete from conversation_participants p
     where p.membership_state = 'invited'
       and p.invited_at <= now() - c_invite_ttl
       and not exists (
         select 1 from direct_messages m
          where m.conversation_id = p.conversation_id
            and m.sender_id = p.user_id
       )
    returning 1
  )
  select count(*) into v_invites from retired;
  update conversation_participants p
     set membership_state = 'left',
         left_at = now()
   where p.membership_state = 'invited'
     and p.invited_at <= now() - c_invite_ttl;
  if v_invites > 0 then
    raise notice 'purge_stale_direct_messages: retired % expired invite(s)', v_invites;
  end if;

  begin
    with emptied as (
      delete from conversations c
      where not exists (select 1 from direct_messages m where m.conversation_id = c.id)
        and (
          c.kind = 'direct'
          or not exists (
            select 1 from conversation_participants p
             where p.conversation_id = c.id
               and p.membership_state = 'active'
          )
        )
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

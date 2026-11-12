-- transfer_group_ownership serialises against the owner's own leave
-- (issue #1365, decisions § 2461).
--
-- 20271216000007 locked only the target's member key. The owner's leave takes
-- the OWNER's key and then passes ownership to the longest-standing admin or
-- member, so a transfer racing it read "caller is owner" before the leave
-- committed, demoted a row that had already left and promoted the target
-- beside the successor the leave had just chosen: two active owners, and the
-- caller saw the one-owner index's raw 23505.
--
-- The transfer now takes both members' keys, the caller's and the target's,
-- in key order so two transfers (or a transfer and a removal) cannot take
-- them in opposite orders and deadlock, and reads the caller's role again
-- once they are held. A caller who left in the meantime reads the group's
-- existing P0002 and one who is no longer owner its existing 42501, the
-- refusals both clients already turn into copy.
--
-- Locking: CREATE OR REPLACE FUNCTION takes no table lock. The signature is
-- unchanged, so no client type moves.

create or replace function public.transfer_group_ownership(p_conversation_id uuid, p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid := auth.uid();
  v_role text;
  v_my_key bigint;
  v_their_key bigint;
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

  if p_user_id is null or p_user_id = v_me then
    raise exception 'transfer_group_ownership: member not found' using errcode = 'P0002';
  end if;

  -- Both keys exclusive, lower first: neither the caller nor the target can
  -- leave or be removed between the checks below and the swap.
  v_my_key := private.group_member_lock_key(p_conversation_id, v_me);
  v_their_key := private.group_member_lock_key(p_conversation_id, p_user_id);
  perform pg_advisory_xact_lock(least(v_my_key, v_their_key));
  perform pg_advisory_xact_lock(greatest(v_my_key, v_their_key));

  -- A new statement, so it reads the caller's membership as it stands once
  -- the locks are held, not as the call began.
  v_role := private.group_my_role(p_conversation_id);
  if v_role is null then
    raise exception 'transfer_group_ownership: conversation not found' using errcode = 'P0002';
  end if;
  if v_role <> 'owner' then
    raise exception 'transfer_group_ownership: only the owner transfers ownership' using errcode = '42501';
  end if;

  perform 1 from conversation_participants p
   where p.conversation_id = p_conversation_id
     and p.user_id = p_user_id
     and p.membership_state = 'active'
   for update;
  if not found then
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
     and user_id = p_user_id
     and membership_state = 'active';
end;
$$;
revoke execute on function public.transfer_group_ownership(uuid, uuid) from public, anon;
grant execute on function public.transfer_group_ownership(uuid, uuid) to authenticated, service_role;

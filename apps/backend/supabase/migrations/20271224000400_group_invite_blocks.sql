-- A block withdraws a pending group invite between the pair, and an invite
-- across a block cannot be accepted (audit of PR #1359, Low).
--
-- invite_to_group refuses to invite across a block, but a block made after
-- the invite left it standing: the invitee could still accept it and join the
-- inviter's group, and the invite kept showing in group_invites(). A block
-- leaves an existing membership alone (each side filters the other's messages
-- through private.can_read_message, decisions § 2461); an invite is not a
-- membership yet, so the block now ends it, as it ends a follow:
--
--   * user_blocks_withdraw_group_invites, AFTER INSERT on user_blocks, moves
--     every pending invite one of the pair sent the other to `left`, as a
--     decline does. When the invitee blocked, it is their refusal and holds
--     them out for the usual 14 days; when the inviter blocked, it is recorded
--     as the inviter's withdrawal (removed_by), which holds nobody out.
--   * accept_group_invite refuses an invite whose sender and invitee are
--     blocked either way, with the same P0002 as a lapsed invite. It covers an
--     invite the trigger did not see: one sent across a block an older
--     release let through, or a block row written by something other than an
--     INSERT.
--   * Invites standing across a block today are withdrawn once, below.
--
-- Locks: CREATE TRIGGER takes SHARE ROW EXCLUSIVE on user_blocks, a small
-- table, until commit. The one-off UPDATE row-locks only the invited rows
-- that cross a block.

create or replace function private.user_blocks_withdraw_group_invites()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  update conversation_participants p
     set membership_state = 'left',
         left_at = now(),
         removed_by = case when p.user_id = new.blocker_id then null else new.blocker_id end
    from conversations c
   where c.id = p.conversation_id
     and c.kind = 'group'
     and p.membership_state = 'invited'
     and (
       (p.user_id = new.blocker_id and p.invited_by = new.blocked_id)
       or (p.user_id = new.blocked_id and p.invited_by = new.blocker_id)
     );
  return null;
end;
$$;

revoke execute on function private.user_blocks_withdraw_group_invites() from public, anon, authenticated;

create trigger user_blocks_withdraw_group_invites
  after insert on user_blocks
  for each row execute function private.user_blocks_withdraw_group_invites();

create or replace function public.accept_group_invite(p_conversation_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  c_invite_ttl constant interval := interval '14 days';
  v_me uuid := auth.uid();
begin
  if v_me is null then
    raise exception 'accept_group_invite: not authorized' using errcode = '42501';
  end if;
  if not private.group_messages_enabled() then
    raise exception 'accept_group_invite: group conversations are not available' using errcode = '0A000';
  end if;

  perform pg_advisory_xact_lock(private.group_member_lock_key(p_conversation_id, v_me));

  -- joined_at is the server's clock at acceptance: the start of the readable
  -- window, which no client can backdate, and a fresh one on every re-join.
  -- An invite across a block is no invite: the block withdraws it, and one
  -- that slipped past answers as a lapsed invite does.
  update conversation_participants p
     set membership_state = 'active',
         role = 'member',
         joined_at = now(),
         last_read_at = now(),
         left_at = null,
         removed_by = null
    from conversations c
   where c.id = p.conversation_id
     and c.kind = 'group'
     and p.conversation_id = p_conversation_id
     and p.user_id = v_me
     and p.membership_state = 'invited'
     and p.invited_at > now() - c_invite_ttl
     and (p.invited_by is null or not is_blocked_either_way(v_me, p.invited_by));

  if not found then
    raise exception 'accept_group_invite: invite not found' using errcode = 'P0002';
  end if;

  -- Everyone else may have left while the invite was out; the first to accept
  -- into an ownerless group then owns it, or nobody could manage it.
  perform private.group_pass_ownership(p_conversation_id);
end;
$$;

revoke execute on function public.accept_group_invite(uuid) from public, anon;
grant execute on function public.accept_group_invite(uuid) to authenticated, service_role;

update conversation_participants p
   set membership_state = 'left',
       left_at = now(),
       removed_by = case
         when exists (select 1 from user_blocks b
                       where b.blocker_id = p.user_id and b.blocked_id = p.invited_by) then null
         else p.invited_by
       end
  from conversations c
 where c.id = p.conversation_id
   and c.kind = 'group'
   and p.membership_state = 'invited'
   and p.invited_by is not null
   and is_blocked_either_way(p.user_id, p.invited_by);

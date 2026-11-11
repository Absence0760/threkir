-- group_blocked_placeholders' p_since gains a NULL default (decisions § 2463).
--
-- Both clients call it as a GET, and a GET carries every argument in the
-- query string: web's supabase-js and Dart's postgrest both stringify a
-- null to the four letters "null", which PostgREST then casts to
-- timestamptz and refuses. That is the call on every thread that fits in
-- one page (no older messages, so no lower bound), so a member who blocked
-- someone never saw a placeholder. A GET omits a null argument instead,
-- which only resolves when the parameter has a default.
--
-- Locking: CREATE OR REPLACE FUNCTION takes no table lock. Adding a default
-- keeps the signature, so the grants below are restated only for clarity.

create or replace function public.group_blocked_placeholders(p_conversation_id uuid, p_since timestamptz default null)
returns table(id uuid, created_at timestamptz)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid := auth.uid();
  v_joined_at timestamptz;
  v_hidden_before timestamptz;
begin
  if v_me is null or private.group_my_role(p_conversation_id) is null then
    raise exception 'group_blocked_placeholders: conversation not found' using errcode = 'P0002';
  end if;
  if not private.group_messages_enabled() then
    return;
  end if;

  select p.joined_at, p.hidden_before into v_joined_at, v_hidden_before
    from conversation_participants p
   where p.conversation_id = p_conversation_id
     and p.user_id = v_me;

  return query
    select m.id, m.created_at
      from direct_messages m
     where m.conversation_id = p_conversation_id
       and m.is_group
       and m.sender_id <> v_me
       and m.unsent_at is null
       and m.created_at >= v_joined_at
       and (v_hidden_before is null or m.created_at > v_hidden_before)
       and (p_since is null or m.created_at >= p_since)
       and exists (
         select 1 from user_blocks b
          where b.blocker_id = v_me
            and b.blocked_id = m.sender_id
       )
     order by m.created_at desc, m.id desc
     limit 200;
end;
$$;
revoke execute on function public.group_blocked_placeholders(uuid, timestamptz) from public, anon;
grant execute on function public.group_blocked_placeholders(uuid, timestamptz) to authenticated, service_role;

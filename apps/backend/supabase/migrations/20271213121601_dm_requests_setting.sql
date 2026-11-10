-- Direct messages: a runner can turn message requests off (issue #1216).
--
-- Message requests (20271115002384, decisions § 2384) let an active club
-- co-member or the host of an event someone RSVPed to message them first
-- without a follow edge. § 2384 left "no per-runner switch to turn requests
-- off" as a default the owner may revisit; this is that switch.
--
-- ── The setting ─────────────────────────────────────────────────────────
--
-- user_settings.dm_requests, a column and not a prefs bag key because SQL
-- reads it (settings.md § Placement rule), on the owner-read user_settings
-- table so nobody else learns the choice. Default true (requests on), which
-- is today's behaviour. No row reads as on.
--
-- ── Enforced where the send is decided ──────────────────────────────────
--
-- private.dm_send_admitted() is the INSERT policy's audience rule. With the
-- recipient's dm_requests off, the shared-context branch (the request path)
-- no longer admits a send. Everything else is unchanged:
--
--   * a follow edge either way (and an active coaching link, 20271210001215)
--     still admits a send: turning requests off stops strangers, not people
--     the runner already has an edge with;
--   * a conversation the recipient already accepted stays open;
--   * a pending request is closed to further messages from the requester,
--     because its next send takes the shared-context branch again. The
--     recipient can still accept or decline it from their Requests list.
--
-- A refused send is the same 42501 a block, a decline or a missing follow
-- edge answers, so the sender cannot tell the switch from any of them
-- (decisions § 1916). The function stays SECURITY DEFINER and reads only the
-- recipient's row, and only to answer the caller's own send.
--
-- ── Retention, export, deletion ─────────────────────────────────────────
--
-- A column on user_settings: exported with the row (select *), deleted with
-- the account.
--
-- ── Locks ───────────────────────────────────────────────────────────────
--
-- ADD COLUMN with a constant default is catalogue-only. The rest is a
-- function body.

alter table user_settings
  add column dm_requests boolean not null default true;

comment on column user_settings.dm_requests is
  'Message requests (issue #1216): when false, someone with no follow edge '
  'cannot message this runner first through a shared club or event, and a '
  'pending request takes no further messages. Read by '
  'private.dm_send_admitted(); owner-read, so a sender never learns it.';

-- Bare-body re-emit of 20271115002384's private.dm_send_admitted with the
-- shared-context branch gated on the recipient's dm_requests.
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

  if private.dm_follow_edge(v_me, p_recipient) then
    return true;
  end if;

  return coalesce(
           (select s.dm_requests from user_settings s where s.user_id = p_recipient),
           true
         )
     and private.dm_shared_context(v_me, p_recipient);
end;
$$;

revoke execute on function private.dm_send_admitted(uuid) from public, anon;
grant execute on function private.dm_send_admitted(uuid) to authenticated, service_role;

comment on function private.dm_send_admitted(uuid) is
  'The direct_messages INSERT policy''s audience rule for a send from '
  'auth.uid() to p_recipient (issue #1216): refused after the recipient '
  'declined; admitted once they accepted; otherwise admitted along a follow '
  'edge either way or, as a message request, when the pair shares an active '
  'club membership or the sender hosts an event the recipient RSVPed to and '
  'the recipient has user_settings.dm_requests on.';

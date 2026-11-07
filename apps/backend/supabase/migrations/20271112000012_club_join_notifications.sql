-- Join-request and approval notifications on `club_members` (decisions
-- § 2358, issue #1300 BUG-009 / BUG-010). The kinds and their CHECK are
-- 20271112000010; this file is the `club_members` half on its own, so its
-- CREATE TRIGGER (SHARE ROW EXCLUSIVE on `club_members`, catalogue-only) holds
-- no lock on `notifications` or `events` while it waits.

-- ── join requests and approvals ─────────────────────────────────────────────

create or replace function private.notify_club_join_request()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform pg_advisory_xact_lock(hashtextextended(
    'club_join_request|' || new.club_id::text || '|' || new.user_id::text, 0));

  -- The people who can act on it: `is_club_admin` (owner, admin) is what the
  -- approve UPDATE and the pending-row SELECT policy both require.
  insert into public.notifications (user_id, actor_id, kind, club_id)
  select r.recipient, new.user_id, 'club_join_request', new.club_id
  from (
    select cm.user_id as recipient
    from public.club_members cm
    where cm.club_id = new.club_id
      and cm.status = 'active'
      and cm.role in ('owner', 'admin')
    union
    select c.owner_id from public.clubs c where c.id = new.club_id
  ) r
  where r.recipient is not null
    and r.recipient <> new.user_id
    and not exists (
      select 1 from public.notifications n
      where n.user_id = r.recipient
        and n.actor_id = new.user_id
        and n.kind = 'club_join_request'
        and n.club_id = new.club_id
        and n.created_at > now() - interval '24 hours'
    );
  return null;
end;
$$;

revoke execute on function private.notify_club_join_request() from public, anon, authenticated;

create trigger club_members_notify_join_request
  after insert or update of status on public.club_members
  for each row
  when (new.status = 'pending')
  execute function private.notify_club_join_request();

create or replace function private.notify_club_join_approved()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
begin
  -- Redeeming an invite token upgrades the redeemer's own pending row; they
  -- know they are in.
  if v_actor is not distinct from new.user_id then
    return null;
  end if;

  insert into public.notifications (user_id, actor_id, kind, club_id)
  values (new.user_id, v_actor, 'club_join_approved', new.club_id);
  return null;
end;
$$;

revoke execute on function private.notify_club_join_approved() from public, anon, authenticated;

create trigger club_members_notify_join_approved
  after update of status on public.club_members
  for each row
  when (old.status = 'pending' and new.status = 'active')
  execute function private.notify_club_join_approved();

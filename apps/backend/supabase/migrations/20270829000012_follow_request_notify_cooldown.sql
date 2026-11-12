-- A follow request raises at most one notification per (owner, requester)
-- pair a day.
--
-- Retracting a request deletes its unread notification
-- (private.cleanup_follow_request_notification, 20270822000001), so the only
-- dedupe `private.notify_follow_request` had, "no unread follow_request from
-- this requester", is gone the moment the request is withdrawn. Ask, retract,
-- ask again therefore raised a fresh notification every time, and since
-- decisions § 1983 put `follow_request` in the default `important` set, every
-- one of them is an email and a push to the owner. That was the residual
-- § 1983 accepted; this closes it at the source.
--
-- The cooldown needs a record that outlives the notification, because the
-- notification is exactly what the retract deletes and what the owner can
-- read or delete themselves. `private.follow_request_notices` keeps one row
-- per pair with the time a notification was last raised. A new request
-- notifies only when no row exists or the row is at least 24 hours old, and
-- claims the row in the same statement (INSERT ... ON CONFLICT DO UPDATE
-- ... WHERE), so two racing requests from one pair raise one notification.
--
-- What does not change: the request row itself is filed as before, so the
-- owner still sees every pending request in their requests list; approval,
-- decline and withdrawal behave as they did; a request whose earlier
-- notification is still unread is still not stacked. A genuinely new request
-- more than a day after the last notice notifies as before.
--
-- In `private`, so PostgREST never exposes it and no client role holds a
-- grant. Not in the Art 20 export: it is a delivery throttle, not something
-- the subject provided, and the request it throttles is exported. Both FKs
-- cascade, so deleting either account removes the row; the hourly sweep below
-- removes a row once it can no longer suppress anything.
--
-- Locks: CREATE TABLE, the indexes on the new empty table, and the function
-- replacement are catalogue-only.

create table private.follow_request_notices (
  target_id    uuid not null references auth.users(id) on delete cascade,
  requester_id uuid not null references auth.users(id) on delete cascade,
  notified_at  timestamptz not null default now(),
  primary key (target_id, requester_id)
);

create index follow_request_notices_requester_id_idx
  on private.follow_request_notices (requester_id);
create index follow_request_notices_notified_at_idx
  on private.follow_request_notices (notified_at);

comment on table private.follow_request_notices is
  'When a follow_request notification was last raised for a (target, '
  'requester) pair; notify_follow_request raises another only after 24 h. '
  'Swept hourly once older than that. decisions § 1983.';

alter table private.follow_request_notices enable row level security;
revoke all on table private.follow_request_notices
  from public, anon, authenticated, service_role;

-- Live body 20270822000001 plus the cooldown claim.
create or replace function private.notify_follow_request()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (
    select 1 from notifications
     where user_id = new.target_id
       and actor_id = new.requester_id
       and kind = 'follow_request'
       and read_at is null
  ) then
    return new;
  end if;

  insert into private.follow_request_notices as n (target_id, requester_id, notified_at)
    values (new.target_id, new.requester_id, now())
    on conflict (target_id, requester_id) do update
      set notified_at = excluded.notified_at
      where n.notified_at <= excluded.notified_at - interval '24 hours';
  if not found then
    return new;
  end if;

  insert into notifications (user_id, actor_id, kind)
    values (new.target_id, new.requester_id, 'follow_request');
  return new;
end;
$$;

revoke execute on function private.notify_follow_request() from public, anon, authenticated;

create or replace function private.cleanup_stale_follow_request_notices()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
begin
  delete from private.follow_request_notices
   where notified_at < now() - interval '24 hours';
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke all on function private.cleanup_stale_follow_request_notices() from public, anon, authenticated;

select cron.schedule(
  'cleanup-stale-follow-request-notices',
  '41 * * * *',
  $$select private.cleanup_stale_follow_request_notices()$$
);

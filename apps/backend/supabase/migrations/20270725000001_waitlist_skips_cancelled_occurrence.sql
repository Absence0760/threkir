-- promote_event_waitlist: a cancelled occurrence promotes nobody.
--
-- The trigger (20261018_001) hands a freed 'going' seat to the earliest
-- waitlisted attendee of the same (event_id, instance_start). It never asked
-- whether that occurrence had been called off, so any seat released on a
-- cancelled occurrence promoted a waitlisted member into a class that is not
-- happening. That was pre-existing for any seat release; host-cancel refunds
-- (20270723000003, decisions § 1818) made it routine: the Stripe webhook
-- deletes each refunded buyer's seat, and every delete fired a promotion.
--
-- Fix: return before promoting when an event_exceptions row exists for the
-- occurrence. Reinstating the occurrence (deleting the exception) does not
-- back-fill the freed seats; the next seat release promotes as before.
--
-- Body otherwise unchanged from 20261018_001: same signature, security
-- definer, search_path and trigger binding. `create or replace` takes no
-- table lock and keeps the existing ACL (docs/backend/migration_locks.md).

create or replace function promote_event_waitlist()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  cap integer;
  going_count integer;
  next_user uuid;
begin
  -- Only act when a 'going' slot was actually vacated.
  if old.status <> 'going' then
    return null;
  end if;
  if tg_op = 'UPDATE' and new.status = 'going' then
    return null;  -- still going, nothing freed
  end if;

  select capacity into cap from events where id = old.event_id;
  if cap is null then
    return null;  -- unlimited: there can be no waitlist to promote
  end if;

  if exists (
    select 1 from event_exceptions x
    where x.event_id = old.event_id
      and x.instance_start = old.instance_start
  ) then
    return null;  -- occurrence cancelled: nobody is promoted into it
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(old.event_id::text || '|' || old.instance_start::text, 0)
  );

  select count(*) into going_count
  from event_attendees
  where event_id = old.event_id
    and instance_start = old.instance_start
    and status = 'going';

  if going_count >= cap then
    return null;  -- still full (shouldn't happen, but be safe)
  end if;

  select user_id into next_user
  from event_attendees
  where event_id = old.event_id
    and instance_start = old.instance_start
    and status = 'waitlisted'
  order by joined_at asc, user_id asc
  limit 1;

  if next_user is not null then
    update event_attendees
    set status = 'going'
    where event_id = old.event_id
      and instance_start = old.instance_start
      and user_id = next_user;
  end if;

  return null;
end;
$$;

-- The cancel notification tells a paid registrant their money is coming back
-- (club_events.md § Refunds, decisions § 1818's follow-up).
--
-- notify_event_cancel (20261019_001) wrote a bare `event_cancel` row, so a
-- buyer whose paid class the host called off learned the class was off and had
-- to infer the refund from their bank. The fan-out renders on four rails (the
-- inbox on web + mobile, email, web push, native push), and each of them reads
-- the notifications row, so the fact belongs on the row.
--
-- `notifications.refunded` is that fact. It is a column, not a jsonb key,
-- because notifications has no payload bag: every other kind's context is a
-- typed column (event_id, event_instance_start, plan_id, ...), and every
-- renderer already reads the row by name. Default false, so every existing
-- row and every other kind reads as "no refund line", which is what they are.
--
-- WHAT `refunded` MEANS. The recipient held a `paid` / `partially_refunded`
-- order on this exact occurrence when it was called off. It does not mean
-- Stripe has already moved the money: events-cancel records the exception
-- FIRST (so no checkout can start behind the refunds) and only then issues
-- them, so at trigger time every such order is still unrefunded. The only
-- caller that can cancel an occurrence holding one is that function --
-- guard_paid_occurrence_cancel (20270723000003) refuses a client insert -- and
-- it refunds every such order in the same request, retrying from the host's
-- "Refund now" when one fails. So the copy on every rail says the payment
-- IS BEING refunded, never that it has arrived.
--
-- The row also carries `event_instance_start` now, which the original insert
-- left null. A recurring class's notification otherwise could not say which
-- occurrence was cancelled.
--
-- Unchanged: the recipient set (going / maybe / waitlisted attendees of the
-- occurrence, never the canceller), SECURITY DEFINER, search_path, and the
-- revoked EXECUTE (20261123_001). `create or replace` keeps the function's ACL;
-- the revoke is re-stated so this file alone says what the grants are.
--
-- Lock profile: ADD COLUMN with a constant default is a catalog-only change
-- (no rewrite, no scan) under a momentary ACCESS EXCLUSIVE on notifications;
-- CREATE OR REPLACE FUNCTION takes no table lock (migration_locks.md).

alter table notifications
  add column refunded boolean not null default false;

comment on column notifications.refunded is
  'event_cancel only: the recipient held a paid or partially refunded order on '
  'the cancelled occurrence, which events-cancel is refunding. False for every '
  'other kind. Renders the "your payment is being refunded" line on every rail.';

create or replace function public.notify_event_cancel()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into notifications (user_id, actor_id, kind, event_id, event_instance_start, refunded)
  select a.user_id,
         new.cancelled_by,
         'event_cancel',
         new.event_id,
         new.instance_start,
         exists (
           select 1 from event_orders o
           where o.event_id = new.event_id
             and o.instance_start = new.instance_start
             and o.buyer_user_id = a.user_id
             and o.status in ('paid', 'partially_refunded')
         )
  from event_attendees a
  where a.event_id = new.event_id
    and a.instance_start = new.instance_start
    and a.status in ('going', 'maybe', 'waitlisted')
    and a.user_id is distinct from new.cancelled_by
  on conflict do nothing;
  return null;
end;
$$;

revoke execute on function public.notify_event_cancel() from public, anon, authenticated;

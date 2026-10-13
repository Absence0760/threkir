-- A buyer whose payment completes AFTER the host called the occurrence off is
-- told their payment is being refunded (decisions § R6MONEY-1, following
-- § 1833 / § 1834).
--
-- What happened before this file. notify_event_cancel (20270725000002) fans
-- out once, when the event_exceptions row is inserted, to the occurrence's
-- going / maybe / waitlisted ATTENDEES. A buyer still on Stripe's page at that
-- moment holds a `pending` order and, unless they were a waitlister, no
-- attendee row at all. When their payment then lands, the webhook marks the
-- order `paid`, seats nothing and refunds it (§ 1833 / § 1839) -- and nothing
-- tells them. The refund's `charge.refunded` moves the order to `refunded`,
-- which announces nothing either (only `refund_failed` does, § 825). So the one
-- buyer whose money moved because of the cancel was the one buyer never told.
-- A waitlister holding an offer was told the class was off, in the plain copy,
-- because their order was still pending then -- and then paid anyway.
--
-- Two halves, so every ordering of "cancel" and "payment lands" is covered:
--
--   1. notify_event_cancel's recipients are the attendees PLUS every buyer
--      holding a paid / partially refunded order on the occurrence. A buyer
--      whose payment lands between the webhook's pre-CAS read and its post-CAS
--      re-read is `paid` and unseated when the cancel fans out: they were never
--      an attendee, so the attendee join alone missed them.
--
--   2. A new AFTER UPDATE trigger on event_orders fires on the `pending ->
--      paid` transition. If the occurrence already has an event_exceptions row,
--      the buyer gets an `event_cancel` row with `refunded = true` -- unless
--      they already hold one for this occurrence. The transition is the dedupe
--      (the webhook's CAS matches `status = 'pending'`, so a redelivery updates
--      nothing), and the existence check is the second belt: a buyer whose
--      second order completes late is still told once.
--
-- A late payer who already holds a PLAIN event_cancel row (the waitlister
-- above) gets a second row rather than having the first flipped. The first was
-- true when it was written and may already have gone out by email and push; a
-- flip would change the inbox line and reach no rail that had already sent.
-- The payment is the new fact, and a new row is what puts it on every rail.
--
-- Both triggers take the occurrence's transaction advisory lock -- the key
-- enforce_event_capacity and private.fill_event_seats already use -- so the
-- cancel and the paid transition cannot each commit unseen by the other. Each
-- statement in a plpgsql function takes a fresh snapshot under READ
-- COMMITTED, so whichever trigger waits on the lock reads the other's
-- committed row once it has it.
--
-- `events-cancel` is the only caller that can cancel an occurrence holding
-- money (guard_paid_occurrence_cancel, 20270723000003), and the webhook is the
-- only writer of `paid` (lock_event_order_status). Both run as the service
-- role, so the definer rights below open nothing a client can reach.
--
-- Lock profile (migration_locks.md): CREATE OR REPLACE FUNCTION and CREATE
-- TRIGGER take a SHARE ROW EXCLUSIVE on event_orders for the catalog change
-- only; no scan, no rewrite.

create or replace function public.notify_event_cancel()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform pg_advisory_xact_lock(
    hashtextextended(new.event_id::text || '|' || new.instance_start::text, 0)
  );

  insert into notifications (user_id, actor_id, kind, event_id, event_instance_start, refunded)
  select r.user_id,
         new.cancelled_by,
         'event_cancel',
         new.event_id,
         new.instance_start,
         exists (
           select 1 from event_orders o
           where o.event_id = new.event_id
             and o.instance_start = new.instance_start
             and o.buyer_user_id = r.user_id
             and o.status in ('paid', 'partially_refunded')
         )
  from (
    select a.user_id
    from event_attendees a
    where a.event_id = new.event_id
      and a.instance_start = new.instance_start
      and a.status in ('going', 'maybe', 'waitlisted')
    union
    select o.buyer_user_id
    from event_orders o
    where o.event_id = new.event_id
      and o.instance_start = new.instance_start
      and o.status in ('paid', 'partially_refunded')
  ) r
  where r.user_id is distinct from new.cancelled_by;
  return null;
end;
$$;

revoke execute on function public.notify_event_cancel() from public, anon, authenticated;

create or replace function public.notify_event_cancel_late_payer()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cancelled_by uuid;
begin
  perform pg_advisory_xact_lock(
    hashtextextended(new.event_id::text || '|' || new.instance_start::text, 0)
  );

  select x.cancelled_by into v_cancelled_by
  from event_exceptions x
  where x.event_id = new.event_id
    and x.instance_start = new.instance_start;
  if not found then
    return null;
  end if;

  if new.buyer_user_id is not distinct from v_cancelled_by then
    return null;
  end if;

  if exists (
    select 1 from notifications n
    where n.user_id = new.buyer_user_id
      and n.kind = 'event_cancel'
      and n.event_id = new.event_id
      and n.event_instance_start = new.instance_start
      and n.refunded
  ) then
    return null;
  end if;

  insert into notifications (user_id, actor_id, kind, event_id, event_instance_start, refunded)
  values (new.buyer_user_id, v_cancelled_by, 'event_cancel', new.event_id, new.instance_start, true);
  return null;
end;
$$;

revoke execute on function public.notify_event_cancel_late_payer() from public, anon, authenticated;

comment on function public.notify_event_cancel_late_payer() is
  'Tell a buyer whose payment completed on an already-cancelled occurrence that '
  'it is being refunded: one refunded event_cancel row per buyer per '
  'occurrence, on the pending -> paid transition. decisions § R6MONEY-1.';

create trigger notify_event_cancel_late_payer
  after update of status on event_orders
  for each row
  when (old.status = 'pending' and new.status = 'paid')
  execute function public.notify_event_cancel_late_payer();

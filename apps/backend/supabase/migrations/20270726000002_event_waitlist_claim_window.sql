-- Waitlist notify-to-pay on a PAID occurrence (club_events.md § Capacity,
-- waitlist & the payment race; rule 8, "Don't auto-charge a waitlisted
-- attendee on promotion"; decisions § 1840).
--
-- Before this migration a paid occurrence had no unpaid waitlist at all:
-- enforce_paid_order_for_priced_event demanded a paid order for a
-- `waitlisted` row as well as a `going` one, so the only people ever on a
-- priced waitlist were buyers the capacity trigger had demoted after they paid
-- (the oversold arm). And promote_event_waitlist (latest: 20270725000001)
-- moved the earliest waitlisted attendee straight to `going`, which on a priced
-- occurrence would seat someone who has not paid — the trigger above raises on
-- that, rolling back the seat release that provoked it.
--
-- The shape, end to end:
--
--   * JOIN. A `waitlisted` row with no order is now legal on a priced
--     occurrence: "tell me if a place opens". A `going` row still needs a paid
--     order, and a waitlisted row that DOES carry an order is still checked
--     against it.
--
--   * OFFER. When a seat frees on a priced occurrence, the earliest waitlisted
--     attendee is not seated. Their row gets `offer_expires_at` (the claim
--     deadline) and an `event_waitlist_slot` notification. The row stays
--     `waitlisted`; the offer is the column, not a new status (see below).
--     A waitlisted attendee who ALREADY paid (the oversold arm) goes first and
--     is seated outright — that is money we hold for a place they are owed.
--
--   * HOLD. A live offer counts against capacity everywhere a seat is
--     counted: here in enforce_event_capacity (so no other path can seat into
--     it) and in events-checkout's precheck (so nobody else can start paying
--     for it). The offer-holder's own checkout excludes their own hold.
--
--   * CLAIM. The offered attendee pays through the existing events-checkout
--     flow. The webhook's upsert turns their row `going`; the status change
--     clears the offer.
--
--   * EXPIRY. `expire-event-waitlist-offers` (pg_cron, every 5 min) removes an
--     unclaimed offer once its deadline has passed — unless the holder has a
--     live checkout reservation for the occurrence, so a payment in flight is
--     never given away under them. Removing the row fires the promotion
--     trigger, which offers the seat to the next person. A lapsed offer leaves
--     the queue: rejoining puts them at the back, so one non-responder cannot
--     be offered the same seat in a loop.
--
-- WHY A COLUMN AND NOT A STATUS. `event_attendees.status` is enumerated by
-- every client and by app builds already in the field; an `offered` value they
-- have never seen would be a row they cannot render. A held seat is still a
-- waitlisted RSVP with a deadline attached, which every existing reader
-- already shows correctly ("on the waitlist"), and only the surfaces that know
-- about offers read the column.
--
-- THE CLAIM WINDOW is 12 hours, clamped to the occurrence's sales close
-- (`private.event_waitlist_claim_window()`, the one place it is stated).
-- Twelve hours spans a night: an offer made at 22:00 is still open at 10:00,
-- so nobody loses a place to being asleep. It is short enough that a freed
-- seat can pass through two declining candidates inside a day, which matters
-- for a weekly class whose waitlist only forms in the last few days. Clamping
-- to sales close means a hold never outlives the moment nobody can pay any
-- more; an offer that would open after sales close is not made at all.
--
-- FREE OCCURRENCES are untouched: no pricing row, no offer, the earliest
-- waitlisted attendee is promoted to `going` exactly as before. A cancelled
-- occurrence still promotes and offers nothing (20270725000001).
--
-- GATE. An offer only exists on a priced occurrence, and pricing can only be
-- written for a host with a charges-enabled Connect account
-- (enforce_event_pricing_host_charges_enabled, 20261229_001); claiming goes
-- through events-checkout, which answers 503 with Stripe unset. So this rail
-- is behind the same fail-closed gate the paid rail already is.
--
-- Lock profile (docs/backend/migration_locks.md): ADD COLUMN with no default
-- is catalog-only; the partial index builds under SHARE on event_attendees
-- (writes wait for the build, which reads a table whose new column is all
-- NULL — the precedent is 20270124_001's partial index on the same table);
-- CREATE OR REPLACE FUNCTION and CREATE TRIGGER take no scan. The
-- notifications_kind_check widen is the DROP + ADD ... NOT VALID half only:
-- its VALIDATE is 20270726000022, in its own transaction, because in this
-- file it would scan the whole notifications table under the ACCESS EXCLUSIVE
-- this file's DROP still holds.

-- ─────────────── 1. the offer column ───────────────

alter table event_attendees
  add column offer_expires_at timestamptz;

comment on column event_attendees.offer_expires_at is
  'Paid occurrence only: the claim deadline of a waitlist seat offer. Set by '
  'private.fill_event_seats when a seat frees, cleared by any status change '
  '(a claim turns the row going). Not client-writable: event_attendees grants '
  'INSERT/UPDATE per column and this one is in neither list. decisions § 1840.';

create index if not exists event_attendees_open_offer_idx
  on event_attendees (offer_expires_at)
  where offer_expires_at is not null;

-- ─────────────── 2. the named constant + the hold predicate ───────────────

create or replace function private.event_waitlist_claim_window()
returns interval
language sql
immutable
as $$ select interval '12 hours' $$;

comment on function private.event_waitlist_claim_window() is
  'How long a waitlisted attendee has to pay for a seat offered to them on a '
  'paid occurrence, before sales close clamps it. Spans a night, cycles a '
  'seat twice a day. decisions § 1840.';

-- Is an offer still holding its seat? Either the deadline has not passed, or
-- the holder is mid-checkout: a live pending order on the same occurrence. The
-- second arm is what keeps a deadline that lapses during payment from handing
-- the seat to the next person while the first one's money is in flight.
create or replace function private.event_offer_held(
  p_event_id uuid,
  p_instance_start timestamptz,
  p_user_id uuid,
  p_offer_expires_at timestamptz
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select p_offer_expires_at is not null
     and (
       p_offer_expires_at > now()
       or exists (
         select 1 from event_orders o
         where o.event_id = p_event_id
           and o.instance_start = p_instance_start
           and o.buyer_user_id = p_user_id
           and o.status = 'pending'
           and o.reserved_until > now()
       )
     )
$$;

-- ─────────────── 3. a waitlist without a payment ───────────────

create or replace function enforce_paid_order_for_priced_event()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_priced boolean;
begin
  if new.status not in ('going', 'waitlisted') then
    return new;
  end if;

  -- An unpaid waitlist entry is a request to be offered a seat, not a seat
  -- (20270726000002). Only `going` needs money behind it; a waitlisted row
  -- that does name an order is still checked against it below.
  if new.status = 'waitlisted' and new.order_id is null then
    return new;
  end if;

  select exists (
    select 1 from event_pricing p
    where p.event_id = new.event_id
      and (p.instance_start = new.instance_start or p.instance_start is null)
  ) into v_priced;

  if not v_priced then
    return new;  -- free event: order_id stays null, no gate
  end if;

  if new.order_id is null then
    raise exception 'a paid order is required to register for priced event % (instance %)', new.event_id, new.instance_start
      using errcode = 'check_violation';
  end if;

  -- `instance_start` binds the order to the ONE occurrence it was bought for
  -- (20270520_001). `partially_refunded` counts as backing the seat
  -- (20270522_001).
  if not exists (
    select 1 from event_orders o
    where o.id = new.order_id
      and o.buyer_user_id = new.user_id
      and o.event_id = new.event_id
      and o.instance_start = new.instance_start
      and o.status in ('paid', 'partially_refunded')
  ) then
    raise exception 'order % is not a paid order belonging to this buyer for this event instance', new.order_id
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

-- ─────────────── 4. a held offer counts against capacity ───────────────

create or replace function enforce_event_capacity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  cap integer;
  held integer;
begin
  if new.status <> 'going' then
    return new;
  end if;

  select capacity into cap from events where id = new.event_id;
  if cap is null then
    return new;  -- unlimited
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(new.event_id::text || '|' || new.instance_start::text, 0)
  );

  -- Seats taken by someone else: their going rows, and the seats held for
  -- them by a live waitlist offer. The row being written is excluded, which
  -- is what lets an offer-holder's own claim land on the seat held for them.
  select count(*) into held
  from event_attendees a
  where a.event_id = new.event_id
    and a.instance_start = new.instance_start
    and a.user_id <> new.user_id
    and (
      a.status = 'going'
      or (a.status = 'waitlisted'
          and private.event_offer_held(a.event_id, a.instance_start, a.user_id, a.offer_expires_at))
    );

  if held >= cap then
    new.status := 'waitlisted';
  end if;

  return new;
end;
$$;

-- ─────────────── 5. filling a freed seat ───────────────

-- Fill every free seat on one occurrence from its waitlist. Free occurrence:
-- promote to going. Priced occurrence: a waitlister who already paid is
-- seated (they go first); anyone else is OFFERED the seat. Loops so a mover
-- that releases several offers at once, or a raised capacity, fills them all.
create or replace function private.fill_event_seats(
  p_event_id uuid,
  p_instance_start timestamptz
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  cap integer;
  held integer;
  v_priced boolean;
  v_close_at timestamptz;
  v_deadline timestamptz;
  v_next_user uuid;
  v_next_order uuid;
begin
  select capacity into cap from events where id = p_event_id;
  if cap is null then
    return;  -- unlimited: there can be no waitlist to promote
  end if;

  if exists (
    select 1 from event_exceptions x
    where x.event_id = p_event_id
      and x.instance_start = p_instance_start
  ) then
    return;  -- occurrence cancelled: nobody is promoted or offered (20270725000001)
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(p_event_id::text || '|' || p_instance_start::text, 0)
  );

  -- The pricing governing this occurrence: its own override row, else the
  -- series row. Sales close is the same instant events-checkout's
  -- isSalesWindowOpen grades against.
  select true,
         p_instance_start - make_interval(mins => p.sales_close_offset_minutes)
    into v_priced, v_close_at
  from event_pricing p
  where p.event_id = p_event_id
    and (p.instance_start = p_instance_start or p.instance_start is null)
  order by p.instance_start nulls last
  limit 1;
  v_priced := coalesce(v_priced, false);

  loop
    select count(*) into held
    from event_attendees a
    where a.event_id = p_event_id
      and a.instance_start = p_instance_start
      and (
        a.status = 'going'
        or (a.status = 'waitlisted'
            and private.event_offer_held(a.event_id, a.instance_start, a.user_id, a.offer_expires_at))
      );
    exit when held >= cap;

    -- A row that has ever been offered is not a candidate again: a live offer
    -- is already counted above, and a lapsed one is waiting for the mover to
    -- take it out of the queue.
    select a.user_id, a.order_id into v_next_user, v_next_order
    from event_attendees a
    where a.event_id = p_event_id
      and a.instance_start = p_instance_start
      and a.status = 'waitlisted'
      and a.offer_expires_at is null
    order by (a.order_id is null), a.joined_at asc, a.user_id asc
    limit 1;
    exit when v_next_user is null;

    if not v_priced or v_next_order is not null then
      update event_attendees
      set status = 'going'
      where event_id = p_event_id
        and instance_start = p_instance_start
        and user_id = v_next_user;
    else
      v_deadline := least(now() + private.event_waitlist_claim_window(), v_close_at);
      exit when v_deadline <= now();  -- sales closed: nobody can pay for it

      update event_attendees
      set offer_expires_at = v_deadline
      where event_id = p_event_id
        and instance_start = p_instance_start
        and user_id = v_next_user;

      insert into notifications (user_id, kind, event_id, event_instance_start)
      values (v_next_user, 'event_waitlist_slot', p_event_id, p_instance_start);
    end if;

    v_next_user := null;
    v_next_order := null;
  end loop;
end;
$$;

comment on function private.fill_event_seats(uuid, timestamptz) is
  'Fill the free seats of one occurrence from its waitlist: promote on a free '
  'occurrence, offer with a claim deadline + event_waitlist_slot notification '
  'on a priced one (a waitlister who already paid is seated first). Called by '
  'promote_event_waitlist and, through it, by the offer-expiry mover. '
  'decisions § 1840.';

create or replace function promote_event_waitlist()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- A seat comes free when a `going` row leaves going, or when a row holding
  -- a waitlist offer leaves the waitlist (declined, deleted, lapsed and
  -- removed by the mover). An offered row becoming `going` is the offer being
  -- claimed — the seat was converted, not freed.
  if old.status = 'going' then
    if tg_op = 'UPDATE' and new.status = 'going' then
      return null;  -- still going, nothing freed
    end if;
  elsif old.status = 'waitlisted' and old.offer_expires_at is not null then
    if tg_op = 'UPDATE' and new.status in ('going', 'waitlisted') then
      return null;  -- claimed, or still waiting on the same offer
    end if;
  else
    return null;
  end if;

  perform private.fill_event_seats(old.event_id, old.instance_start);
  return null;
end;
$$;

-- ─────────────── 6. a status change ends the offer ───────────────

-- Named to sort after trg_enforce_event_capacity, so it reads the status the
-- capacity trigger settled on. Any status move ends the offer: `going` is the
-- claim, anything else is the holder walking away from it. A rewrite to the
-- same status (a double-clicked "join waitlist") keeps it.
create or replace function clear_event_offer_on_status_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status is distinct from old.status then
    new.offer_expires_at := null;
  end if;
  return new;
end;
$$;

revoke execute on function clear_event_offer_on_status_change() from public, anon, authenticated;

create trigger trg_event_offer_follows_status
  before update of status on event_attendees
  for each row execute function clear_event_offer_on_status_change();

-- ─────────────── 7. the expiry mover ───────────────

-- Remove every unclaimed offer whose deadline has passed and whose holder is
-- not mid-checkout. Each delete fires promote_event_waitlist, which offers the
-- seat on. Idempotent: a second run finds nothing to remove, and the fill
-- counts seats rather than trusting a caller.
create or replace function private.expire_event_waitlist_offers()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_removed integer;
begin
  with lapsed as (
    delete from event_attendees a
    where a.status = 'waitlisted'
      and a.offer_expires_at is not null
      and a.offer_expires_at <= now()
      and not private.event_offer_held(a.event_id, a.instance_start, a.user_id, a.offer_expires_at)
    returning 1
  )
  select count(*) into v_removed from lapsed;
  return v_removed;
end;
$$;

comment on function private.expire_event_waitlist_offers() is
  'pg_cron expire-event-waitlist-offers: lapse unclaimed paid-waitlist offers '
  'and, through promote_event_waitlist, offer each seat to the next person. '
  'Skips a holder with a live checkout reservation. decisions § 1840.';

revoke execute on function private.event_waitlist_claim_window() from public, anon, authenticated;
revoke execute on function private.event_offer_held(uuid, timestamptz, uuid, timestamptz) from public, anon, authenticated;
revoke execute on function private.fill_event_seats(uuid, timestamptz) from public, anon, authenticated;
revoke execute on function private.expire_event_waitlist_offers() from public, anon, authenticated;
grant execute on function private.expire_event_waitlist_offers() to service_role;

-- ─────────────── 8. notifications.kind += event_waitlist_slot ───────────────

-- Re-emit the full union (20270701000001 is the live list). NOT VALID only;
-- the VALIDATE is 20270726000022 (see the lock note at the top).
alter table notifications drop constraint notifications_kind_check;
alter table notifications
  add constraint notifications_kind_check
  check (
    kind in (
      'kudos', 'comment', 'comment_reply', 'follow',
      'event_rsvp', 'event_cancel', 'plan_update', 'message',
      'club_post', 'run_completed', 'event_reminder', 'plan_assigned',
      'achievement', 'challenge_complete', 'content_hidden',
      'data_export_ready', 'refund_failed', 'event_waitlist_slot'
    )
  )
  not valid;

-- ─────────────── 9. schedule ───────────────

-- Every 5 minutes: a 12-hour window lapses within 5 minutes of its deadline,
-- which is noise against the window, and the run is an indexed probe of a
-- partial index that is empty almost all of the time. pg_cron's extension is
-- created by 20260602_001; `cron.schedule` is idempotent on name.
select cron.schedule(
  'expire-event-waitlist-offers',
  '*/5 * * * *',
  $$select private.expire_event_waitlist_offers()$$
);

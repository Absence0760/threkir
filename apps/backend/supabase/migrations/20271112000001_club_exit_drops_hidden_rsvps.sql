-- Leaving a club takes your upcoming RSVPs to the events you can no longer
-- see with you (decisions § 2356, issue #1300 BUG-005).
--
-- Reject, remove and leave are plain deletes on `club_members` (an admin
-- demoting a row out of `active` is the same exit), and the only trigger there
-- kept the member count. A removed member therefore stayed on the roster of
-- every members-only session they had booked, held a capped seat nobody could
-- be promoted into, and, in a private club, sat on events they could no longer
-- open.
--
--   1. `private.is_event_visible_to(event, user)` is the events SELECT
--      policy's predicate for a named user, and `is_event_visible` (the
--      event_pricing oracle, 20270524_001) now delegates to it with
--      `auth.uid()`, so the predicate has one body outside the policy itself.
--      The policy keeps its inlined, initplan-wrapped form for the hot read;
--      `club_exit_drops_hidden_rsvps_test.sql` holds it to this function over a
--      club x event x viewer matrix.
--   2. `private.drop_rsvps_on_club_exit` (AFTER DELETE, and AFTER UPDATE OF
--      status, on `club_members`, only when the old row was `active`) deletes
--      the leaver's `event_attendees` rows for the club's events whose
--      occurrence has not started yet (instance_start >= now()) and which that
--      user can no longer see. Every status goes, the waitlist included,
--      because the waitlist is `event_attendees` rows too. Each deleted
--      `going` row (or held offer) runs the existing
--      `trg_promote_event_waitlist`, so the freed seat goes to the next member
--      in line exactly as a cancelled RSVP's would.
--        * Past and in-progress occurrences are history and stay.
--        * A public event in a public club stays: the leaver can still see it
--          and could RSVP to it again as a non-member.
--        * A pending request's reject (or withdrawal) does nothing: the row
--          was never `active`, so it never granted any visibility to lose.
--        * A seat backed by money stays (a non-null `order_id`, or a `paid` /
--          `partially_refunded` order for that occurrence). Refunding is the
--          host's action and the webhook is the only order writer; deleting
--          the seat would keep the buyer's money and drop their place. The
--          seat stays on the organiser's roster, where it can be refunded.
--        * So does a row with a checkout in flight (a `pending` order whose
--          `reserved_until` is still ahead, the test `private.event_offer_held`
--          uses): the payment can still land, and the webhook would then seat
--          a buyer whose row was deleted or leave a paid order with no seat.
--      Nothing runs when the user or the club is itself being deleted: those
--      cascades remove the rows (and run promotion) on their own, and a
--      promotion inside a club delete would write into events being deleted.
--
-- Locks: CREATE OR REPLACE FUNCTION takes no table lock. CREATE TRIGGER takes
-- SHARE ROW EXCLUSIVE on `club_members` for a catalogue-only change (no scan,
-- no rewrite), blocking concurrent membership writes for an O(1) moment. No
-- column changes, so neither type generator has anything to regenerate.

-- ── 1. the visibility predicate, for a named user ──────────────────────────

create or replace function private.is_event_visible_to(p_event_id uuid, p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
      from public.events e
      join public.clubs c on c.id = e.club_id
      cross join lateral (
        select exists (
          select 1 from public.club_members m
           where m.club_id = c.id
             and m.user_id = p_user_id
             and m.status = 'active'
        ) as is_member
      ) m
     where e.id = p_event_id
       and (public.is_public_club_by_id(c.id) or c.owner_id = p_user_id or m.is_member)
       and (e.is_public = true or m.is_member)
  );
$$;

revoke execute on function private.is_event_visible_to(uuid, uuid) from public, anon, authenticated;

create or replace function is_event_visible(p_event_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, private
as $$
  select private.is_event_visible_to(p_event_id, auth.uid());
$$;

-- ── 2. the exit trigger ─────────────────────────────────────────────────────

create or replace function private.drop_rsvps_on_club_exit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (select 1 from auth.users u where u.id = old.user_id)
     or not exists (select 1 from public.clubs c where c.id = old.club_id) then
    return null;
  end if;

  delete from public.event_attendees a
   using public.events e
   where e.id = a.event_id
     and e.club_id = old.club_id
     and a.user_id = old.user_id
     and a.instance_start >= now()
     and a.order_id is null
     and not exists (
       select 1 from public.event_orders o
        where o.event_id = a.event_id
          and o.instance_start = a.instance_start
          and o.buyer_user_id = a.user_id
          and (o.status in ('paid', 'partially_refunded')
               or (o.status = 'pending' and o.reserved_until > now()))
     )
     and not private.is_event_visible_to(e.id, old.user_id);
  return null;
end;
$$;

revoke execute on function private.drop_rsvps_on_club_exit() from public, anon, authenticated;

create trigger club_members_exit_drops_rsvps
  after delete on public.club_members
  for each row
  when (old.status = 'active')
  execute function private.drop_rsvps_on_club_exit();

create trigger club_members_demote_drops_rsvps
  after update of status on public.club_members
  for each row
  when (old.status = 'active' and new.status is distinct from 'active')
  execute function private.drop_rsvps_on_club_exit();

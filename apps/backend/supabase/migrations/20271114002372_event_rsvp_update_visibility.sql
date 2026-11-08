-- An RSVP update is held to the same visibility rule as an RSVP insert, and a
-- client can no longer re-key an RSVP (decisions § 2372, issue #1300 BUG-004).
--
-- INSERT was already gated: "users RSVP to visible events" (20260629_001)
-- requires the event to be readable, and the events SELECT policy reads only
-- ACTIVE membership, so a stranger, a pending member and a removed member are
-- all refused a members-only event. UPDATE was not. "users can update their
-- own RSVP" carried only USING (`user_id = auth.uid()`), which Postgres then
-- reuses as the WITH CHECK, and `authenticated` holds the UPDATE column grant
-- on event_id, user_id and instance_start (20270408_001). Two holes followed:
--
--   * Visibility. A filtered update (every PostgREST PATCH) happened to be
--     held to the attendee SELECT policy on the new row, which joins events
--     under RLS, so a move onto a hidden event was refused by accident. An
--     update with no WHERE is not: Postgres applies SELECT policies to an
--     UPDATE only when it reads columns. A stranger's public RSVP could be
--     moved onto a members-only event, and a removed member could re-answer a
--     row the club-exit trigger (20271112000001) keeps as history.
--   * Re-keying. Moving an RSVP's event_id or instance_start through a
--     filtered PATCH onto an event or occurrence the caller CAN see skipped
--     the capacity trigger (it fires on `update of status`) and the course
--     guard, so a full session could be oversold one move at a time.
--
--   1. The UPDATE policy gains the INSERT policy's WITH CHECK: own row, and an
--      event the caller can read. USING stays own-row, so a refusal is a 42501
--      the client can show rather than a silent zero-row update.
--   2. `private.event_attendees_key_fixed` (BEFORE UPDATE OF event_id,
--      user_id, instance_start) refuses a change to any of the three when the
--      caller is a client role. The clients' upsert re-sends the same key, so
--      it passes; the server movers (`private.move_rescheduled_event_rows`,
--      `private.remap_recurrence_wallclock`) run as their owner and are not
--      affected. A client moves an RSVP by deleting it and RSVPing again,
--      which runs every insert-time check.
--
-- The organiser path ("organisers add attendees to their events") is
-- untouched: an organiser seating a walk-up on their own event is intended.
--
-- Locks: ALTER POLICY and CREATE TRIGGER each take a brief lock on
-- event_attendees for a catalogue-only change (no scan, no rewrite). No column
-- changes, so neither type generator has anything to regenerate.

alter policy "users can update their own RSVP" on public.event_attendees
  using (((select auth.uid()) = user_id))
  with check ((((select auth.uid()) = user_id) and (exists (
    select 1 from public.events where events.id = event_attendees.event_id))));

create or replace function private.event_attendees_key_fixed()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if current_user in ('authenticated', 'anon')
     and (new.event_id is distinct from old.event_id
          or new.user_id is distinct from old.user_id
          or new.instance_start is distinct from old.instance_start) then
    raise exception 'an RSVP''s event, user and occurrence are fixed: delete it and RSVP again'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

revoke execute on function private.event_attendees_key_fixed() from public, anon, authenticated;

create trigger event_attendees_key_fixed
  before update of event_id, user_id, instance_start on public.event_attendees
  for each row execute function private.event_attendees_key_fixed();

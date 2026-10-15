-- Indexes for the roster keyset orders (decisions § 1925, § 1927).
--
-- The club roster pages as
--   where club_id = $1
--   order by joined_at asc nulls last, user_id asc limit 50
-- (web fetchClubMembers), and an occurrence's attendee list as
--   where event_id = $1 and instance_start = $2
--   order by joined_at asc nulls last, user_id asc
-- (web fetchEventAttendees one page at a time; mobile
-- SocialService.fetchAttendees and ApiClient.fetchEventAttendees as a whole
-- walk), each page narrowed to the rows strictly after the previous page's
-- last row. Neither order had an index: a club's rows came through the
-- (club_id, user_id) primary key and an occurrence's through
-- event_attendees_event_instance (event_id, instance_start), and every page
-- sorted the whole club or occurrence to hand back 50 rows. A btree column
-- defaults to ASC NULLS LAST, which is exactly these orders, so each index
-- returns the rows in page order and the LIMIT ends the scan.
--
-- event_attendees_event_instance is an exact left prefix of the new attendee
-- index, so every query it served (the per-occurrence counts, the RSVP
-- lookups) is served by the new one, and it is dropped rather than kept as a
-- second index every RSVP write maintains — the 20270424_001 rule. The partial
-- event_attendees_going_instance_idx is a different predicate and stays.
--
-- Plain CREATE INDEX, not CONCURRENTLY: the apply path runs each migration in
-- a transaction, where CONCURRENTLY errors (docs/backend/migration_locks.md).
-- The build holds SHARE on its table, blocking writes but not reads, for the
-- length of one pass over it; club_members and event_attendees are bounded
-- social tables, outside the playbook's high-volume set. DROP INDEX takes a
-- brief ACCESS EXCLUSIVE on event_attendees for a catalogue change.
--
-- Deliberately not added: runs (user_id, started_at desc, id desc) and
-- user_follows (<anchor>, followed_at desc, <other> desc). Their existing
-- runs_user_started_at / user_follows_follower / user_follows_followee
-- indexes already return the leading key in order, so the planner finishes
-- the tie-break with an Incremental Sort over groups of equal started_at /
-- followed_at — one row each, in practice — rather than sorting the result.
-- There is no sort to remove, and a third index on runs, the highest-volume
-- table, would block its writers for the build and tax every insert after.

create index club_members_club_roster
  on club_members (club_id, joined_at, user_id);

create index event_attendees_instance_roster
  on event_attendees (event_id, instance_start, joined_at, user_id);

drop index event_attendees_event_instance;

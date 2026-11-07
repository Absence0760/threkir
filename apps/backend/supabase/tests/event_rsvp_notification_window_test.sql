-- RSVP notices reach the club's owner and admins, per occurrence, and a
-- re-RSVP can notify again (20271112000013, decisions § 2358, issue #1300
-- BUG-009).
--
-- Pins: an admin who did not author the event is notified, and so is the
-- owner; the notice carries the occurrence; going -> not going -> going on
-- the same occurrence inside 24 h notifies once, and again after 24 h; an
-- RSVP to a different occurrence of the same series notifies at once.

begin;

select plan(6);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa3001', 'authenticated', 'authenticated', 'owner@rsvpw.local', '', now(), now()),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa3002', 'authenticated', 'authenticated', 'admin@rsvpw.local', '', now(), now()),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa3003', 'authenticated', 'authenticated', 'author@rsvpw.local', '', now(), now()),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa3004', 'authenticated', 'authenticated', 'rsvper@rsvpw.local', '', now(), now());

insert into clubs (id, owner_id, name, slug, is_public)
values ('cccccccc-cccc-cccc-cccc-cccccccc3001',
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa3001', 'RSVP Club', 'rsvp-window-club', true);

insert into club_members (club_id, user_id, role, status) values
  ('cccccccc-cccc-cccc-cccc-cccccccc3001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa3002', 'admin', 'active'),
  ('cccccccc-cccc-cccc-cccc-cccccccc3001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa3003', 'event_organiser', 'active'),
  ('cccccccc-cccc-cccc-cccc-cccccccc3001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa3004', 'member', 'active');

insert into events (id, club_id, title, starts_at, author_id)
values ('eeeeeeee-eeee-eeee-eeee-eeeeeeee3001',
        'cccccccc-cccc-cccc-cccc-cccccccc3001', 'Weekly Hills',
        '2030-01-08 18:00+00', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa3003');

insert into event_attendees (event_id, user_id, status, instance_start)
values ('eeeeeeee-eeee-eeee-eeee-eeeeeeee3001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa3004', 'going', '2030-01-08 18:00+00');

select is(
  (select array_agg(user_id::text order by user_id) from notifications
   where kind = 'event_rsvp' and event_id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeee3001'),
  array['aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa3001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa3002',
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa3003'],
  'the author, the club owner and an admin who did not author it are each notified');

select is(
  (select count(*)::int from notifications
   where kind = 'event_rsvp' and event_instance_start = '2030-01-08 18:00+00'),
  3, 'each notice carries the occurrence it is about');

-- Not going, then going again, the same day.
delete from event_attendees
 where event_id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeee3001' and user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa3004';
insert into event_attendees (event_id, user_id, status, instance_start)
values ('eeeeeeee-eeee-eeee-eeee-eeeeeeee3001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa3004', 'going', '2030-01-08 18:00+00');
select is(
  (select count(*)::int from notifications
   where kind = 'event_rsvp' and event_id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeee3001'),
  3, 'a re-RSVP to the same occurrence within 24 h does not notify again');

-- The same member going to next week's occurrence is news.
insert into event_attendees (event_id, user_id, status, instance_start)
values ('eeeeeeee-eeee-eeee-eeee-eeeeeeee3001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa3004', 'going', '2030-01-15 18:00+00');
select is(
  (select count(*)::int from notifications
   where kind = 'event_rsvp' and event_instance_start = '2030-01-15 18:00+00'),
  3, 'an RSVP to another occurrence of the event notifies at once');

-- A day on, a re-RSVP after a cancel notifies again.
update notifications set created_at = now() - interval '25 hours'
 where kind = 'event_rsvp' and event_id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeee3001';
delete from event_attendees
 where event_id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeee3001' and user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa3004'
   and instance_start = '2030-01-08 18:00+00';
insert into event_attendees (event_id, user_id, status, instance_start)
values ('eeeeeeee-eeee-eeee-eeee-eeeeeeee3001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa3004', 'going', '2030-01-08 18:00+00');
select is(
  (select count(*)::int from notifications
   where kind = 'event_rsvp' and event_instance_start = '2030-01-08 18:00+00'),
  6, 'a re-RSVP more than 24 h after the last notice notifies again');

select is(
  (select count(*)::int from notifications
   where kind = 'event_rsvp' and user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa3004'),
  0, 'the RSVPer is never notified of their own RSVP');

select * from finish();
rollback;

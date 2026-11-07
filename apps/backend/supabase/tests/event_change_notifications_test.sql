-- Edit and delete notices to an event's attendees (20271112000013, decisions
-- § 2358, issue #1300 BUG-016).
--
-- Pins, for `events_notify_updated`: a change to the time, place or
-- description notifies each attendee of an upcoming occurrence once, never
-- the editor, never a past attendee and never an attendee of a cancelled
-- occurrence; a title-only edit notifies nobody; a second edit inside 15
-- minutes adds nothing and one after it does; a reschedule notifies the
-- attendees `events_move_rescheduled_rows` (20271111000001) moved, at their
-- new instant.
--
-- For `events_notify_deleted`: deleting the event leaves each upcoming
-- attendee an `event_cancel` that survives the delete, carries the title and
-- the club, and links no event; a club delete and an account delete that
-- cascade to the event still succeed.

begin;

select plan(16);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa2001', 'authenticated', 'authenticated', 'owner@evn.local', '', now(), now()),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa2002', 'authenticated', 'authenticated', 'going@evn.local', '', now(), now()),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa2003', 'authenticated', 'authenticated', 'maybe@evn.local', '', now(), now()),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa2004', 'authenticated', 'authenticated', 'past@evn.local', '', now(), now()),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa2005', 'authenticated', 'authenticated', 'cancelled@evn.local', '', now(), now());

insert into clubs (id, owner_id, name, slug, is_public)
values ('cccccccc-cccc-cccc-cccc-cccccccc2001',
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa2001', 'Edit Club', 'edit-club', true);

insert into club_members (club_id, user_id, role, status) values
  ('cccccccc-cccc-cccc-cccc-cccccccc2001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa2002', 'member', 'active'),
  ('cccccccc-cccc-cccc-cccc-cccccccc2001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa2003', 'member', 'active'),
  ('cccccccc-cccc-cccc-cccc-cccccccc2001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa2004', 'member', 'active'),
  ('cccccccc-cccc-cccc-cccc-cccccccc2001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa2005', 'member', 'active');

insert into events (id, club_id, title, starts_at, author_id, meet_label)
values ('eeeeeeee-eeee-eeee-eeee-eeeeeeee2001',
        'cccccccc-cccc-cccc-cccc-cccccccc2001', 'Tuesday Tempo',
        date_trunc('minute', now()) + interval '2 days',
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa2001', 'Park gates');

-- The owner RSVPs too: an editor is never told about their own edit.
insert into event_attendees (event_id, user_id, status, instance_start) values
  ('eeeeeeee-eeee-eeee-eeee-eeeeeeee2001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa2001', 'going', date_trunc('minute', now()) + interval '2 days'),
  ('eeeeeeee-eeee-eeee-eeee-eeeeeeee2001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa2002', 'going', date_trunc('minute', now()) + interval '2 days'),
  ('eeeeeeee-eeee-eeee-eeee-eeeeeeee2001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa2003', 'maybe', date_trunc('minute', now()) + interval '2 days'),
  ('eeeeeeee-eeee-eeee-eeee-eeeeeeee2001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa2004', 'going', date_trunc('minute', now()) - interval '5 days'),
  ('eeeeeeee-eeee-eeee-eeee-eeeeeeee2001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa2005', 'going', date_trunc('minute', now()) + interval '9 days');
insert into event_exceptions (event_id, instance_start, cancelled_by)
values ('eeeeeeee-eeee-eeee-eeee-eeeeeeee2001', date_trunc('minute', now()) + interval '9 days',
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa2001');
delete from notifications;

-- A title-only edit is not a change to when, where or what.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa2001"}';
update events set title = 'Tuesday Tempo Run' where id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeee2001';
reset role;
select is(
  (select count(*)::int from notifications where kind = 'event_updated'),
  0, 'a title-only edit notifies nobody');

-- The owner moves the meet point and rewrites the description in one save.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa2001"}';
update events set meet_label = 'Boathouse', description = 'Bring a headtorch'
 where id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeee2001';
reset role;

select is(
  (select meet_label from events where id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeee2001'),
  'Boathouse', 'the organiser''s edit is stored');

select is(
  (select array_agg(user_id::text order by user_id) from notifications
   where kind = 'event_updated' and event_id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeee2001'),
  array['aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa2002', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa2003'],
  'the going and maybe attendees of the upcoming occurrence are each notified once');

select is(
  (select count(*)::int from notifications
   where kind = 'event_updated' and actor_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa2001'),
  2, 'the notices name the editor as their actor');

-- A second save inside the window adds nothing.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa2001"}';
update events set meet_label = 'Boathouse steps' where id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeee2001';
reset role;
select is(
  (select count(*)::int from notifications where kind = 'event_updated'),
  2, 'a second edit within 15 minutes is folded into the first notice');

-- Past the window, a reschedule notifies again, at the moved instant.
update notifications set created_at = now() - interval '16 minutes' where kind = 'event_updated';
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa2001"}';
update events set starts_at = date_trunc('minute', now()) + interval '3 days'
 where id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeee2001';
reset role;

select is(
  (select instance_start from event_attendees
   where event_id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeee2001'
     and user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa2002'),
  date_trunc('minute', now()) + interval '3 days',
  'the reschedule moved the RSVP to the new start');

select is(
  (select count(*)::int from notifications
   where kind = 'event_updated' and created_at > now() - interval '1 minute'
     and event_instance_start = date_trunc('minute', now()) + interval '3 days'),
  2, 'the moved attendees are notified at their new instant');

select is(
  (select count(*)::int from notifications
   where kind = 'event_updated' and user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa2004'),
  0, 'an attendee of a past occurrence is not notified');

select is(
  (select count(*)::int from notifications
   where kind = 'event_updated' and user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa2005'),
  0, 'an attendee of a cancelled occurrence is not notified');

select is(
  (select count(*)::int from notifications
   where kind = 'event_updated' and user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa2001'),
  0, 'the editor is never notified of their own edit');

-- Delete.
delete from notifications;
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa2001"}';
delete from events where id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeee2001';
reset role;

select is(
  (select count(*)::int from events where id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeee2001'),
  0, 'the organiser''s delete removed the event');

select results_eq(
  $$ select user_id, actor_id, club_id, event_id, event_title, event_instance_start
       from notifications where kind = 'event_cancel' order by user_id $$,
  $$ values
       ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa2002'::uuid, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa2001'::uuid,
        'cccccccc-cccc-cccc-cccc-cccccccc2001'::uuid, null::uuid, 'Tuesday Tempo Run'::text,
        date_trunc('minute', now()) + interval '3 days'),
       ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa2003'::uuid, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa2001'::uuid,
        'cccccccc-cccc-cccc-cccc-cccccccc2001'::uuid, null::uuid, 'Tuesday Tempo Run'::text,
        date_trunc('minute', now()) + interval '3 days') $$,
  'each upcoming attendee keeps an unlinked cancel notice naming the event and its club');

-- A club delete cascades to its events after the club row is gone.
insert into events (id, club_id, title, starts_at, author_id)
values ('eeeeeeee-eeee-eeee-eeee-eeeeeeee2002',
        'cccccccc-cccc-cccc-cccc-cccccccc2001', 'Last Long Run',
        now() + interval '4 days', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa2001');
insert into event_attendees (event_id, user_id, status, instance_start)
values ('eeeeeeee-eeee-eeee-eeee-eeeeeeee2002', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa2002', 'going', now() + interval '4 days');
delete from notifications;
select lives_ok(
  $$ delete from clubs where id = 'cccccccc-cccc-cccc-cccc-cccccccc2001' $$,
  'deleting the club still succeeds with an upcoming attendee on one of its events');

select results_eq(
  $$ select user_id, club_id, event_title from notifications where kind = 'event_cancel' $$,
  $$ values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa2002'::uuid, null::uuid, 'Last Long Run'::text) $$,
  'the attendee is told, with no link to the club that no longer exists');

-- An organiser's account delete cascades to their event through author_id,
-- while they hold a place on it: the notice must not name the deleted user.
-- The paid order is the place that is still there when the events cascade
-- runs (its FK fires after it; the attendee row's fires before).
insert into clubs (id, owner_id, name, slug, is_public)
values ('cccccccc-cccc-cccc-cccc-cccccccc2002',
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa2003', 'Second Club', 'second-edit-club', true);
insert into club_members (club_id, user_id, role, status) values
  ('cccccccc-cccc-cccc-cccc-cccccccc2002', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa2004', 'event_organiser', 'active'),
  ('cccccccc-cccc-cccc-cccc-cccccccc2002', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa2002', 'member', 'active');
insert into events (id, club_id, title, starts_at, author_id)
values ('eeeeeeee-eeee-eeee-eeee-eeeeeeee2003',
        'cccccccc-cccc-cccc-cccc-cccccccc2002', 'Organiser''s Hill Reps',
        now() + interval '5 days', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa2004');
insert into event_attendees (event_id, user_id, status, instance_start) values
  ('eeeeeeee-eeee-eeee-eeee-eeeeeeee2003', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa2004', 'going', now() + interval '5 days'),
  ('eeeeeeee-eeee-eeee-eeee-eeeeeeee2003', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa2002', 'going', now() + interval '5 days');
insert into event_orders (event_id, instance_start, buyer_user_id, host_user_id, amount_cents, status)
values ('eeeeeeee-eeee-eeee-eeee-eeeeeeee2003', now() + interval '5 days',
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa2004', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa2004', 1500, 'paid');
delete from notifications;
select lives_ok(
  $$ delete from auth.users where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa2004' $$,
  'deleting an organiser''s account still succeeds when they hold a paid place on their own event');

select results_eq(
  $$ select user_id, event_title from notifications where kind = 'event_cancel' $$,
  $$ values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa2002'::uuid, 'Organiser''s Hill Reps'::text) $$,
  'the other attendee is told, and no notice names the deleted organiser');

select * from finish();
rollback;

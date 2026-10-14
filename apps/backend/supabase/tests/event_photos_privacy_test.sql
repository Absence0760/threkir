-- The attack surface of event occurrence photos (migrations 20270807000001-3,
-- decisions § 1905 / § 1906), from the side of the people who must NOT get in:
-- outsiders, anon, a steward of another club, and club members who hold no
-- steward role. The neighbouring files pin the happy paths and the moderation
-- flow itself; this one pins what each boundary refuses.
--
--   * the gallery RPC carries neither `run_id` (a private run's id) nor
--     `hidden_by` (the moderator);
--   * a private run's photo bytes reach an outsider only through the event
--     path, and only while the photo is not hidden;
--   * a members-only event's gallery, and a private club's, is empty to an
--     outsider and to anon — including the photos on PUBLIC runs, which the
--     table's run path would otherwise hand over;
--   * the steward set is the event's own club's active owner / admin /
--     event_organiser (or its named host), nobody else;
--   * nobody but the owner updates a photo, and the owner cannot re-point it
--     at another event;
--   * anon may read a gallery but may not moderate or probe stewardship;
--   * deleting an event detaches its host photos: gone from every gallery and
--     from everyone but their owner, who can still read and delete them.

begin;
select plan(38);

insert into auth.users (id, email, encrypted_password, email_confirmed_at,
                        instance_id, aud, role)
values
  ('99999999-9999-9999-9999-99991907a001', 'orga-1907@example.com', '', now(),
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('99999999-9999-9999-9999-99991907a002', 'orgb-1907@example.com', '', now(),
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('99999999-9999-9999-9999-99991907a003', 'runner-1907@example.com', '', now(),
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('99999999-9999-9999-9999-99991907a004', 'out-1907@example.com', '', now(),
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('99999999-9999-9999-9999-99991907a005', 'member-1907@example.com', '', now(),
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('99999999-9999-9999-9999-99991907a006', 'pending-1907@example.com', '', now(),
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('99999999-9999-9999-9999-99991907a007', 'rd-1907@example.com', '', now(),
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated')
on conflict (id) do nothing;

-- Club A and club B are public; club C is private. Each owner is enrolled as
-- an 'owner' member by trigger.
insert into clubs (id, owner_id, name, slug, is_public, join_policy)
values
  ('dddddddd-0000-0000-0000-00000001907a', '99999999-9999-9999-9999-99991907a001',
   'Privacy Club A 1907', 'privacy-club-a-1907', true, 'open'),
  ('dddddddd-0000-0000-0000-00000001907b', '99999999-9999-9999-9999-99991907a002',
   'Privacy Club B 1907', 'privacy-club-b-1907', true, 'open'),
  ('dddddddd-0000-0000-0000-00000001907c', '99999999-9999-9999-9999-99991907a002',
   'Privacy Club C 1907', 'privacy-club-c-1907', false, 'request');

-- In club A: an active plain member, an admin whose membership is still
-- pending (not active), and an active race_director (not in the steward set).
insert into club_members (club_id, user_id, role, status)
values
  ('dddddddd-0000-0000-0000-00000001907a', '99999999-9999-9999-9999-99991907a005', 'member', 'active'),
  ('dddddddd-0000-0000-0000-00000001907a', '99999999-9999-9999-9999-99991907a006', 'admin', 'pending'),
  ('dddddddd-0000-0000-0000-00000001907a', '99999999-9999-9999-9999-99991907a007', 'race_director', 'active');

insert into events (id, club_id, title, starts_at, author_id, is_public)
values
  ('eeeeeeee-0000-0000-0000-0000000197a1', 'dddddddd-0000-0000-0000-00000001907a',
   'Public 10K', '2026-06-20T08:00:00Z', '99999999-9999-9999-9999-99991907a001', true),
  ('eeeeeeee-0000-0000-0000-0000000197a2', 'dddddddd-0000-0000-0000-00000001907a',
   'Members-only social', '2026-06-21T08:00:00Z', '99999999-9999-9999-9999-99991907a001', false),
  ('eeeeeeee-0000-0000-0000-0000000197a3', 'dddddddd-0000-0000-0000-00000001907a',
   'Cancelled 5K', '2026-06-24T08:00:00Z', '99999999-9999-9999-9999-99991907a001', true),
  ('eeeeeeee-0000-0000-0000-0000000197b1', 'dddddddd-0000-0000-0000-00000001907b',
   'Club B Run', '2026-06-22T08:00:00Z', '99999999-9999-9999-9999-99991907a002', true),
  ('eeeeeeee-0000-0000-0000-0000000197c1', 'dddddddd-0000-0000-0000-00000001907c',
   'Private club run', '2026-06-23T08:00:00Z', '99999999-9999-9999-9999-99991907a002', true);

insert into runs (id, user_id, started_at, distance_m, duration_s, source, is_public, metadata)
values
  ('aaaaaaaa-0000-0000-0000-0000001907f1', '99999999-9999-9999-9999-99991907a003',
   '2026-06-20T08:03:00Z', 10000, 2700, 'app', false, '{"activity_type":"run"}'),
  ('aaaaaaaa-0000-0000-0000-0000001907f2', '99999999-9999-9999-9999-99991907a003',
   '2026-06-21T08:03:00Z', 5000, 1500, 'app', true, '{"activity_type":"run"}'),
  ('aaaaaaaa-0000-0000-0000-0000001907f3', '99999999-9999-9999-9999-99991907a003',
   '2026-06-21T08:05:00Z', 5000, 1500, 'app', false, '{"activity_type":"run"}'),
  ('aaaaaaaa-0000-0000-0000-0000001907f4', '99999999-9999-9999-9999-99991907a003',
   '2026-06-23T08:03:00Z', 5000, 1500, 'app', true, '{"activity_type":"run"}');

insert into run_photos (id, run_id, owner_id, storage_path, thumb_512_path, caption,
                        event_id, event_instance_start)
values
  -- the runner's PRIVATE run, at the public event
  ('11111111-0000-0000-0000-0000001907b1', 'aaaaaaaa-0000-0000-0000-0000001907f1',
   '99999999-9999-9999-9999-99991907a003', '99999999-9999-9999-9999-99991907a003/p1.jpg',
   '99999999-9999-9999-9999-99991907a003/p1_512.jpg', 'orig',
   'eeeeeeee-0000-0000-0000-0000000197a1', '2026-06-20T08:00:00Z'),
  -- a PUBLIC run and a private run at the members-only event
  ('11111111-0000-0000-0000-0000001907b2', 'aaaaaaaa-0000-0000-0000-0000001907f2',
   '99999999-9999-9999-9999-99991907a003', '99999999-9999-9999-9999-99991907a003/p2.jpg',
   null, null, 'eeeeeeee-0000-0000-0000-0000000197a2', '2026-06-21T08:00:00Z'),
  ('11111111-0000-0000-0000-0000001907b3', 'aaaaaaaa-0000-0000-0000-0000001907f3',
   '99999999-9999-9999-9999-99991907a003', '99999999-9999-9999-9999-99991907a003/p3.jpg',
   null, null, 'eeeeeeee-0000-0000-0000-0000000197a2', '2026-06-21T08:00:00Z'),
  -- a PUBLIC run at the private club's event
  ('11111111-0000-0000-0000-0000001907b4', 'aaaaaaaa-0000-0000-0000-0000001907f4',
   '99999999-9999-9999-9999-99991907a003', '99999999-9999-9999-9999-99991907a003/p4.jpg',
   null, null, 'eeeeeeee-0000-0000-0000-0000000197c1', '2026-06-23T08:00:00Z'),
  -- run-less host photos
  ('11111111-0000-0000-0000-0000001907c1', null,
   '99999999-9999-9999-9999-99991907a001', '99999999-9999-9999-9999-99991907a001/h1.jpg',
   null, null, 'eeeeeeee-0000-0000-0000-0000000197a1', '2026-06-20T08:00:00Z'),
  ('11111111-0000-0000-0000-0000001907c2', null,
   '99999999-9999-9999-9999-99991907a001', '99999999-9999-9999-9999-99991907a001/hp.jpg',
   null, null, 'eeeeeeee-0000-0000-0000-0000000197a2', '2026-06-21T08:00:00Z'),
  ('11111111-0000-0000-0000-0000001907c3', null,
   '99999999-9999-9999-9999-99991907a002', '99999999-9999-9999-9999-99991907a002/hc.jpg',
   null, null, 'eeeeeeee-0000-0000-0000-0000000197c1', '2026-06-23T08:00:00Z'),
  ('11111111-0000-0000-0000-0000001907c4', null,
   '99999999-9999-9999-9999-99991907a001', '99999999-9999-9999-9999-99991907a001/hd.jpg',
   null, null, 'eeeeeeee-0000-0000-0000-0000000197a3', '2026-06-24T08:00:00Z');

insert into storage.objects (bucket_id, name) values
  ('run-photos', '99999999-9999-9999-9999-99991907a003/p1.jpg'),
  ('run-photos', '99999999-9999-9999-9999-99991907a003/p1_512.jpg'),
  ('run-photos', '99999999-9999-9999-9999-99991907a001/hd.jpg');

-- ── the gallery's shape: no run id, no moderator ──
select ok(
  not exists (
    select 1
      from pg_proc p, unnest(p.proargnames, p.proargmodes::text[]) as a(name, mode)
     where p.oid = 'public.event_gallery_photos(uuid, timestamptz, int)'::regprocedure
       and a.mode = 't' and a.name = 'run_id'),
  'event_gallery_photos never returns run_id, so a private run''s id is not exposed');

select ok(
  not exists (
    select 1
      from pg_proc p, unnest(p.proargnames, p.proargmodes::text[]) as a(name, mode)
     where p.oid = 'public.event_gallery_photos(uuid, timestamptz, int)'::regprocedure
       and a.mode = 't' and a.name = 'hidden_by'),
  'event_gallery_photos never returns hidden_by, so the moderator is not exposed');

-- ── an outsider, before any moderation ──
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"99999999-9999-9999-9999-99991907a004","role":"authenticated"}';

select is(
  (select count(*)::int from storage.objects
    where bucket_id = 'run-photos'
      and name in ('99999999-9999-9999-9999-99991907a003/p1.jpg',
                   '99999999-9999-9999-9999-99991907a003/p1_512.jpg')),
  2, 'an outsider reads a private run''s event photo and its thumbnail through the event path');

select is(
  (select count(*)::int
     from event_gallery_photos('eeeeeeee-0000-0000-0000-0000000197a2', '2026-06-21T08:00:00Z')),
  0, 'an outsider''s gallery of a members-only event returns nothing, public-run photos included');

select is(
  (select count(*)::int
     from event_gallery_photos('eeeeeeee-0000-0000-0000-0000000197c1', '2026-06-23T08:00:00Z')),
  0, 'an outsider''s gallery of a private club''s event returns nothing, public-run photos included');

-- ── a steward of another club ──
set local "request.jwt.claims" = '{"sub":"99999999-9999-9999-9999-99991907a002","role":"authenticated"}';

select is(
  (select can_steward_event_photos('eeeeeeee-0000-0000-0000-0000000197b1')),
  true, 'club B''s owner stewards club B''s event');

select is(
  (select can_steward_event_photos('eeeeeeee-0000-0000-0000-0000000197a1')),
  false, 'club B''s owner is not a steward of club A''s event');

select throws_ok($$
  select set_event_photo_hidden('11111111-0000-0000-0000-0000001907b1', true)
$$, '42501', null, 'a steward of club B cannot hide a photo in club A''s event');

select throws_ok($$
  insert into run_photos (owner_id, storage_path, event_id, event_instance_start)
  values ('99999999-9999-9999-9999-99991907a002',
          '99999999-9999-9999-9999-99991907a002/intrude.jpg',
          'eeeeeeee-0000-0000-0000-0000000197a1', '2026-06-20T08:00:00Z')
$$, '42501', null, 'a steward of club B cannot post a run-less photo into club A''s event');

-- ── club A members who hold no steward role ──
set local "request.jwt.claims" = '{"sub":"99999999-9999-9999-9999-99991907a005","role":"authenticated"}';

select is(
  (select count(*)::int
     from event_gallery_photos('eeeeeeee-0000-0000-0000-0000000197a2', '2026-06-21T08:00:00Z')),
  3, 'a club member sees the members-only event''s gallery');

select is(
  (select can_steward_event_photos('eeeeeeee-0000-0000-0000-0000000197a1')),
  false, 'an active plain member is not a steward');

select throws_ok($$
  select set_event_photo_hidden('11111111-0000-0000-0000-0000001907b1', true)
$$, '42501', null, 'an active plain member cannot hide an event photo');

set local "request.jwt.claims" = '{"sub":"99999999-9999-9999-9999-99991907a006","role":"authenticated"}';

select is(
  (select can_steward_event_photos('eeeeeeee-0000-0000-0000-0000000197a1')),
  false, 'an admin whose membership is not active is not a steward');

select throws_ok($$
  select set_event_photo_hidden('11111111-0000-0000-0000-0000001907b1', true)
$$, '42501', null, 'an admin whose membership is not active cannot hide an event photo');

select throws_ok($$
  insert into run_photos (owner_id, storage_path, event_id, event_instance_start)
  values ('99999999-9999-9999-9999-99991907a006',
          '99999999-9999-9999-9999-99991907a006/pending.jpg',
          'eeeeeeee-0000-0000-0000-0000000197a1', '2026-06-20T08:00:00Z')
$$, '42501', null, 'an admin whose membership is not active cannot post a run-less photo');

set local "request.jwt.claims" = '{"sub":"99999999-9999-9999-9999-99991907a007","role":"authenticated"}';

select is(
  (select can_steward_event_photos('eeeeeeee-0000-0000-0000-0000000197a1')),
  false, 'a race_director is not in the photo steward set');

-- ── nobody but the owner edits a photo ──
set local "request.jwt.claims" = '{"sub":"99999999-9999-9999-9999-99991907a004","role":"authenticated"}';

with u as (
     update run_photos
        set caption = 'outsider was here'
      where id = '11111111-0000-0000-0000-0000001907b1'
     returning 1)
select is(count(*)::int, 0, 'an outsider who can see the photo updates no row of it') from u;

set local "request.jwt.claims" = '{"sub":"99999999-9999-9999-9999-99991907a001","role":"authenticated"}';

with u as (
     update run_photos
        set caption = 'steward was here',
            storage_path = '99999999-9999-9999-9999-99991907a003/swapped.jpg'
      where id = '11111111-0000-0000-0000-0000001907b1'
     returning 1)
select is(count(*)::int, 0, 'the event''s steward cannot edit the caption or storage path of an attendee''s photo') from u;

-- Nor untag it from their event; the read-back below states the tag survived.
update run_photos set event_id = null where id = '11111111-0000-0000-0000-0000001907b1';

set local "request.jwt.claims" = '{"sub":"99999999-9999-9999-9999-99991907a003","role":"authenticated"}';

select throws_ok($$
  update run_photos set event_id = 'eeeeeeee-0000-0000-0000-0000000197b1'
   where id = '11111111-0000-0000-0000-0000001907b1'
$$, '42501', null, 'the owner cannot re-point their photo at another event');

reset role;

select is(
  (select concat_ws('|', caption, storage_path, thumb_512_path, event_id::text)
     from run_photos where id = '11111111-0000-0000-0000-0000001907b1'),
  'orig|99999999-9999-9999-9999-99991907a003/p1.jpg|99999999-9999-9999-9999-99991907a003/p1_512.jpg|eeeeeeee-0000-0000-0000-0000000197a1',
  'the attendee''s photo kept its caption, paths and event through every refused edit');

-- ── logged out, before moderation ──
set local role anon;
set local "request.jwt.claims" = '{"role":"anon"}';

select is(
  (select count(*)::int from storage.objects
    where bucket_id = 'run-photos'
      and name in ('99999999-9999-9999-9999-99991907a003/p1.jpg',
                   '99999999-9999-9999-9999-99991907a003/p1_512.jpg')),
  2, 'anon reads a public event''s unhidden photo bytes');

select is(
  (select count(*)::int
     from event_gallery_photos('eeeeeeee-0000-0000-0000-0000000197a2', '2026-06-21T08:00:00Z')),
  0, 'anon''s gallery of a members-only event returns nothing');

select is(
  (select count(*)::int
     from event_gallery_photos('eeeeeeee-0000-0000-0000-0000000197c1', '2026-06-23T08:00:00Z')),
  0, 'anon''s gallery of a private club''s event returns nothing');

select throws_ok($$
  select set_event_photo_hidden('11111111-0000-0000-0000-0000001907b1', true)
$$, '42501', 'permission denied for function set_event_photo_hidden',
  'anon cannot call set_event_photo_hidden (refused at the privilege, not in the body)');

select throws_ok($$
  select can_steward_event_photos('eeeeeeee-0000-0000-0000-0000000197a1')
$$, '42501', 'permission denied for function can_steward_event_photos',
  'anon cannot call can_steward_event_photos (refused at the privilege, not in the body)');

-- ── the organiser hides the private-run photo ──
reset role;
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"99999999-9999-9999-9999-99991907a001","role":"authenticated"}';
select set_event_photo_hidden('11111111-0000-0000-0000-0000001907b1', true);

select is(
  (select count(*)::int from storage.objects
    where bucket_id = 'run-photos'
      and name in ('99999999-9999-9999-9999-99991907a003/p1.jpg',
                   '99999999-9999-9999-9999-99991907a003/p1_512.jpg')),
  2, 'the steward still reads the hidden photo''s bytes, to judge a restore');

set local "request.jwt.claims" = '{"sub":"99999999-9999-9999-9999-99991907a003","role":"authenticated"}';

select is(
  (select count(*)::int from storage.objects
    where bucket_id = 'run-photos'
      and name in ('99999999-9999-9999-9999-99991907a003/p1.jpg',
                   '99999999-9999-9999-9999-99991907a003/p1_512.jpg')),
  2, 'the owner still reads their hidden photo''s bytes');

set local "request.jwt.claims" = '{"sub":"99999999-9999-9999-9999-99991907a004","role":"authenticated"}';

select is(
  (select count(*)::int from storage.objects
    where bucket_id = 'run-photos'
      and name in ('99999999-9999-9999-9999-99991907a003/p1.jpg',
                   '99999999-9999-9999-9999-99991907a003/p1_512.jpg')),
  0, 'an outsider can no longer read a hidden private-run photo''s bytes or thumbnail');

reset role;
set local role anon;
set local "request.jwt.claims" = '{"role":"anon"}';

select is(
  (select count(*)::int from storage.objects
    where bucket_id = 'run-photos'
      and name in ('99999999-9999-9999-9999-99991907a003/p1.jpg',
                   '99999999-9999-9999-9999-99991907a003/p1_512.jpg')),
  0, 'anon can no longer read a hidden private-run photo''s bytes');

select is(
  (select array_agg(id::text order by id)
     from event_gallery_photos('eeeeeeee-0000-0000-0000-0000000197a1', '2026-06-20T08:00:00Z')),
  array['11111111-0000-0000-0000-0000001907c1'],
  'anon''s gallery of a public event holds only its unhidden photos');

-- ── deleting an event detaches its host photo ──
reset role;
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"99999999-9999-9999-9999-99991907a004","role":"authenticated"}';

select is(
  (select count(*)::int
     from event_gallery_photos('eeeeeeee-0000-0000-0000-0000000197a3', '2026-06-24T08:00:00Z')),
  1, 'before the deletion, an outsider sees the host photo in the gallery');

select is(
  (select count(*)::int from storage.objects
    where bucket_id = 'run-photos' and name = '99999999-9999-9999-9999-99991907a001/hd.jpg'),
  1, 'before the deletion, an outsider reads the host photo''s bytes');

set local "request.jwt.claims" = '{"sub":"99999999-9999-9999-9999-99991907a001","role":"authenticated"}';
delete from events where id = 'eeeeeeee-0000-0000-0000-0000000197a3';

select is(
  (select count(*)::int from run_photos
    where id = '11111111-0000-0000-0000-0000001907c4' and event_id is null),
  1, 'the owner still reads their detached host photo');

select is(
  (select count(*)::int from storage.objects
    where bucket_id = 'run-photos' and name = '99999999-9999-9999-9999-99991907a001/hd.jpg'),
  1, 'the owner still reads their detached host photo''s bytes');

set local "request.jwt.claims" = '{"sub":"99999999-9999-9999-9999-99991907a004","role":"authenticated"}';

select is(
  (select count(*)::int from run_photos where id = '11111111-0000-0000-0000-0000001907c4'),
  0, 'an outsider cannot see a detached host photo');

select is(
  (select count(*)::int from storage.objects
    where bucket_id = 'run-photos' and name = '99999999-9999-9999-9999-99991907a001/hd.jpg'),
  0, 'an outsider cannot read a detached host photo''s bytes');

with d as (
  delete from run_photos where id = '11111111-0000-0000-0000-0000001907c4' returning 1)
select is(count(*)::int, 0, 'an outsider deletes no row of a detached host photo') from d;

set local "request.jwt.claims" = '{"sub":"99999999-9999-9999-9999-99991907a001","role":"authenticated"}';

with d as (
  delete from run_photos where id = '11111111-0000-0000-0000-0000001907c4' returning 1)
select is(count(*)::int, 1, 'the owner deletes their detached host photo') from d;

select * from finish();
rollback;

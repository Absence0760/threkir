-- Join-request and approval notifications (20271112000012, decisions § 2358,
-- issue #1300 BUG-009 / BUG-010).
--
-- Pins: a pending join row notifies the club's owner and admins and nobody
-- else; a second request inside 24 h does not notify again, one after it
-- does; pending -> active by an admin notifies the member, naming the admin;
-- a member redeeming an invite over their own pending row is not told.

begin;

select plan(11);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa1001', 'authenticated', 'authenticated', 'owner@join.local', '', now(), now()),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa1002', 'authenticated', 'authenticated', 'admin@join.local', '', now(), now()),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa1003', 'authenticated', 'authenticated', 'organiser@join.local', '', now(), now()),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa1004', 'authenticated', 'authenticated', 'asker@join.local', '', now(), now()),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa1005', 'authenticated', 'authenticated', 'tokened@join.local', '', now(), now());

insert into clubs (id, owner_id, name, slug, is_public, join_policy, invite_token)
values ('cccccccc-cccc-cccc-cccc-cccccccc1001',
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa1001', 'Request Club', 'request-club', true,
        'request', 'join-notify-token');

insert into club_members (club_id, user_id, role, status) values
  ('cccccccc-cccc-cccc-cccc-cccccccc1001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa1002', 'admin', 'active'),
  ('cccccccc-cccc-cccc-cccc-cccccccc1001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa1003', 'event_organiser', 'active');

-- The asker requests to join, through the client's own insert path.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa1004"}';
insert into club_members (club_id, user_id, role, status)
values ('cccccccc-cccc-cccc-cccc-cccccccc1001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa1004', 'member', 'pending');
reset role;

select is(
  (select array_agg(user_id::text order by user_id) from notifications
   where kind = 'club_join_request' and club_id = 'cccccccc-cccc-cccc-cccc-cccccccc1001'
     and actor_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa1004'),
  array['aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa1001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa1002'],
  'a join request notifies the owner and the admin, once each');

select is(
  (select count(*)::int from notifications
   where kind = 'club_join_request' and user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa1003'),
  0, 'an event organiser, who cannot approve, is not notified');

-- Withdraw and ask again the same day.
delete from club_members
 where club_id = 'cccccccc-cccc-cccc-cccc-cccccccc1001'
   and user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa1004';
insert into club_members (club_id, user_id, role, status)
values ('cccccccc-cccc-cccc-cccc-cccccccc1001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa1004', 'member', 'pending');

select is(
  (select count(*)::int from notifications
   where kind = 'club_join_request' and user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa1001'),
  1, 'asking again within 24 h does not notify the owner a second time');

-- The earlier notice is a day old; a fresh request notifies again.
update notifications set created_at = now() - interval '25 hours'
 where kind = 'club_join_request' and club_id = 'cccccccc-cccc-cccc-cccc-cccccccc1001';
delete from club_members
 where club_id = 'cccccccc-cccc-cccc-cccc-cccccccc1001'
   and user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa1004';
insert into club_members (club_id, user_id, role, status)
values ('cccccccc-cccc-cccc-cccc-cccccccc1001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa1004', 'member', 'pending');

select is(
  (select count(*)::int from notifications
   where kind = 'club_join_request' and user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa1001'),
  2, 'a request more than 24 h after the last notice notifies again');

select is(
  (select count(*)::int from notifications where kind = 'club_join_approved'),
  0, 'nobody is told of an approval before one happens');

-- The admin approves through the client's own update path.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa1002"}';
update club_members set status = 'active'
 where club_id = 'cccccccc-cccc-cccc-cccc-cccccccc1001'
   and user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa1004';
reset role;

select is(
  (select status from club_members
   where club_id = 'cccccccc-cccc-cccc-cccc-cccccccc1001'
     and user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa1004'),
  'active', 'the admin''s approval is stored');

select results_eq(
  $$ select user_id, actor_id, club_id from notifications where kind = 'club_join_approved' $$,
  $$ values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa1004'::uuid,
             'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa1002'::uuid,
             'cccccccc-cccc-cccc-cccc-cccccccc1001'::uuid) $$,
  'the approved member is notified, by the admin, about the club');

-- A role change on an active member is not an approval.
update club_members set role = 'event_organiser'
 where club_id = 'cccccccc-cccc-cccc-cccc-cccccccc1001'
   and user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa1004';
select is(
  (select count(*)::int from notifications where kind = 'club_join_approved'),
  1, 'a later update to an active member raises no second approval');

-- A pending member who redeems an invite token lets themselves in.
insert into club_members (club_id, user_id, role, status)
values ('cccccccc-cccc-cccc-cccc-cccccccc1001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa1005', 'member', 'pending');
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa1005"}';
select lives_ok(
  $$ select join_club_by_token('join-notify-token') $$,
  'a pending member can redeem the invite token');
reset role;

select is(
  (select status from club_members
   where club_id = 'cccccccc-cccc-cccc-cccc-cccccccc1001'
     and user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa1005'),
  'active', 'the token redemption made the member active');

select is(
  (select count(*)::int from notifications
   where kind = 'club_join_approved' and user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa1005'),
  0, 'letting yourself in with a token is not reported back to you as an approval');

select * from finish();
rollback;

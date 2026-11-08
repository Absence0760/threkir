-- Pins migration 20271115002384 — message requests (issue #1216, decisions
-- § 2384): who may send a first message without a follow edge, the request
-- state each send moves, the 3-message cap, no notification or read receipt
-- before acceptance, accept / decline / decline-and-block, and the block
-- reset.

begin;
select plan(37);

insert into auth.users (id, email, encrypted_password, email_confirmed_at,
                        instance_id, aud, role)
select ('aaaa2384-0000-0000-0000-0000000000' || s)::uuid, 'req-' || s || '@example.com', '', now(),
       '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'
  from unnest(array['a1', 'b2', 'c3', 'd4', 'e5', 'f6', 'a7', 'b8', 'c9']) as s
on conflict (id) do nothing;

-- A owns the club and hosts its event. B, F, G (a7) and H (b8) are active
-- members, E is still pending. D RSVPed to A's event without joining the club.
-- C has no tie to A at all. I (c9) is followed by A.
insert into clubs (id, owner_id, name, slug, is_public)
values ('cccc2384-0000-0000-0000-000000000001', 'aaaa2384-0000-0000-0000-0000000000a1',
        'Requests Club', 'requests-club-2384', true);

insert into club_members (club_id, user_id, role, status) values
  ('cccc2384-0000-0000-0000-000000000001', 'aaaa2384-0000-0000-0000-0000000000a1', 'owner', 'active'),
  ('cccc2384-0000-0000-0000-000000000001', 'aaaa2384-0000-0000-0000-0000000000b2', 'member', 'active'),
  ('cccc2384-0000-0000-0000-000000000001', 'aaaa2384-0000-0000-0000-0000000000e5', 'member', 'pending'),
  ('cccc2384-0000-0000-0000-000000000001', 'aaaa2384-0000-0000-0000-0000000000f6', 'member', 'active'),
  ('cccc2384-0000-0000-0000-000000000001', 'aaaa2384-0000-0000-0000-0000000000a7', 'member', 'active'),
  ('cccc2384-0000-0000-0000-000000000001', 'aaaa2384-0000-0000-0000-0000000000b8', 'member', 'active')
on conflict (club_id, user_id) do update set status = excluded.status;

insert into events (id, club_id, title, starts_at, author_id)
values ('eeee2384-0000-0000-0000-000000000001', 'cccc2384-0000-0000-0000-000000000001',
        'Requests Run', '2099-03-07 09:00+00', 'aaaa2384-0000-0000-0000-0000000000a1');

insert into event_attendees (event_id, user_id, instance_start, status)
values ('eeee2384-0000-0000-0000-000000000001', 'aaaa2384-0000-0000-0000-0000000000d4',
        '2099-03-07 09:00+00', 'going');

insert into user_follows (follower_id, followee_id)
values ('aaaa2384-0000-0000-0000-0000000000a1', 'aaaa2384-0000-0000-0000-0000000000c9');

insert into user_blocks (blocker_id, blocked_id)
values ('aaaa2384-0000-0000-0000-0000000000f6', 'aaaa2384-0000-0000-0000-0000000000a1');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"aaaa2384-0000-0000-0000-0000000000a1","role":"authenticated"}';

-- ── who may send a first message ──

select throws_ok(
  $$insert into direct_messages (sender_id, recipient_id, body)
    values ('aaaa2384-0000-0000-0000-0000000000a1', 'aaaa2384-0000-0000-0000-0000000000c3', 'cold')$$,
  '42501', null,
  'a stranger with no follow edge and no shared club or event is refused');

select throws_ok(
  $$insert into direct_messages (sender_id, recipient_id, body)
    values ('aaaa2384-0000-0000-0000-0000000000a1', 'aaaa2384-0000-0000-0000-0000000000e5', 'pending member')$$,
  '42501', null,
  'a pending club membership is not a shared context, so the send is refused');

select throws_ok(
  $$insert into direct_messages (sender_id, recipient_id, body)
    values ('aaaa2384-0000-0000-0000-0000000000a1', 'aaaa2384-0000-0000-0000-0000000000f6', 'blocked member')$$,
  '42501', null,
  'a block refuses a request even between club members');

select lives_ok(
  $$insert into direct_messages (id, sender_id, recipient_id, body)
    values ('11112384-0000-0000-0000-000000000001',
            'aaaa2384-0000-0000-0000-0000000000a1', 'aaaa2384-0000-0000-0000-0000000000b2', 'club hello')$$,
  'a club member can message another active member first, as a request');

select lives_ok(
  $$insert into direct_messages (id, sender_id, recipient_id, body)
    values ('11112384-0000-0000-0000-000000000002',
            'aaaa2384-0000-0000-0000-0000000000a1', 'aaaa2384-0000-0000-0000-0000000000d4', 'see you saturday')$$,
  'an event host can message someone who RSVPed, as a request');

select lives_ok(
  $$insert into direct_messages (id, sender_id, recipient_id, body)
    values ('11112384-0000-0000-0000-000000000003',
            'aaaa2384-0000-0000-0000-0000000000a1', 'aaaa2384-0000-0000-0000-0000000000c9', 'followed hello')$$,
  'a follow edge still admits a send');

set local "request.jwt.claims" = '{"sub":"aaaa2384-0000-0000-0000-0000000000d4","role":"authenticated"}';
select throws_ok(
  $$insert into direct_messages (sender_id, recipient_id, body)
    values ('aaaa2384-0000-0000-0000-0000000000d4', 'aaaa2384-0000-0000-0000-0000000000c3', 'attendee to stranger')$$,
  '42501', null,
  'an attendee with no club tie is refused to a stranger');

-- ── the state each send left ──

set local role postgres;

select is(
  (select p.request_state from conversation_participants p
     join direct_messages m on m.conversation_id = p.conversation_id
    where m.id = '11112384-0000-0000-0000-000000000001'
      and p.user_id = 'aaaa2384-0000-0000-0000-0000000000b2'),
  'pending',
  'the recipient of a club request holds it as pending');

select is(
  (select p.request_state from conversation_participants p
     join direct_messages m on m.conversation_id = p.conversation_id
    where m.id = '11112384-0000-0000-0000-000000000001'
      and p.user_id = 'aaaa2384-0000-0000-0000-0000000000a1'),
  'accepted',
  'the requester consents to replies by asking');

select is(
  (select p.request_state from conversation_participants p
     join direct_messages m on m.conversation_id = p.conversation_id
    where m.id = '11112384-0000-0000-0000-000000000002'
      and p.user_id = 'aaaa2384-0000-0000-0000-0000000000d4'),
  'pending',
  'the recipient of an event-host request holds it as pending');

select is(
  (select p.request_state is null from conversation_participants p
     join direct_messages m on m.conversation_id = p.conversation_id
    where m.id = '11112384-0000-0000-0000-000000000003'
      and p.user_id = 'aaaa2384-0000-0000-0000-0000000000c9'),
  true,
  'a follow-graph conversation is never a request');

select is(
  (select count(*)::int from notifications
    where kind = 'message'
      and user_id = 'aaaa2384-0000-0000-0000-0000000000c9'
      and actor_id = 'aaaa2384-0000-0000-0000-0000000000a1'),
  1,
  'a follow-graph message notifies its recipient');

select is(
  (select count(*)::int from notifications
    where kind = 'message'
      and user_id = 'aaaa2384-0000-0000-0000-0000000000b2'
      and actor_id = 'aaaa2384-0000-0000-0000-0000000000a1'),
  0,
  'a pending request raises no notification');

select ok(
  (select count from rate_limits
    where user_id = 'aaaa2384-0000-0000-0000-0000000000a1'
      and bucket = 'open_message_request'
    order by window_start desc limit 1) >= 2,
  'opening a request spends the open_message_request bucket');

-- ── the inbox flag ──

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"aaaa2384-0000-0000-0000-0000000000b2","role":"authenticated"}';

select is(
  (select request from dm_threads() where partner_id = 'aaaa2384-0000-0000-0000-0000000000a1'),
  true,
  'dm_threads() flags the conversation as a request for its recipient');

set local "request.jwt.claims" = '{"sub":"aaaa2384-0000-0000-0000-0000000000a1","role":"authenticated"}';

select is(
  (select request from dm_threads() where partner_id = 'aaaa2384-0000-0000-0000-0000000000b2'),
  false,
  'the requester sees an ordinary conversation');

-- ── the 3-message cap ──

select lives_ok(
  $$insert into direct_messages (id, sender_id, recipient_id, body)
    values ('11112384-0000-0000-0000-000000000004',
            'aaaa2384-0000-0000-0000-0000000000a1', 'aaaa2384-0000-0000-0000-0000000000b2', 'second')$$,
  'a pending request takes a second message');

select lives_ok(
  $$insert into direct_messages (id, sender_id, recipient_id, body)
    values ('11112384-0000-0000-0000-000000000005',
            'aaaa2384-0000-0000-0000-0000000000a1', 'aaaa2384-0000-0000-0000-0000000000b2', 'third')$$,
  'a pending request takes a third message');

select throws_ok(
  $$insert into direct_messages (sender_id, recipient_id, body)
    values ('aaaa2384-0000-0000-0000-0000000000a1', 'aaaa2384-0000-0000-0000-0000000000b2', 'fourth')$$,
  '54000', null,
  'a fourth message into a pending request is refused');

-- ── no read receipt before acceptance ──

set local "request.jwt.claims" = '{"sub":"aaaa2384-0000-0000-0000-0000000000b2","role":"authenticated"}';

select is(
  mark_direct_messages_read('aaaa2384-0000-0000-0000-0000000000a1', '11112384-0000-0000-0000-000000000005'),
  3,
  'the recipient can read a pending request');

set local role postgres;

select is(
  (select count(*)::int from direct_messages
    where sender_id = 'aaaa2384-0000-0000-0000-0000000000a1'
      and recipient_id = 'aaaa2384-0000-0000-0000-0000000000b2'
      and read_at is not null and seen_at is null),
  3,
  'reading a pending request shares no receipt with the requester');

-- ── accept ──

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"aaaa2384-0000-0000-0000-0000000000c3","role":"authenticated"}';

select throws_ok(
  $$select accept_message_request((select conversation_id from conversation_participants
                                   where user_id = 'aaaa2384-0000-0000-0000-0000000000c3' limit 1))$$,
  'P0002', null,
  'accepting a request the caller does not hold is refused');

set local "request.jwt.claims" = '{"sub":"aaaa2384-0000-0000-0000-0000000000a1","role":"authenticated"}';

select throws_ok(
  format($$select decline_message_request(%L, '11112384-0000-0000-0000-000000000001')$$,
    (select conversation_id from direct_messages where id = '11112384-0000-0000-0000-000000000001')),
  'P0002', null,
  'the requester cannot decline their own request');

set local "request.jwt.claims" = '{"sub":"aaaa2384-0000-0000-0000-0000000000b2","role":"authenticated"}';

select lives_ok(
  format($$select accept_message_request(%L)$$,
    (select conversation_id from direct_messages where id = '11112384-0000-0000-0000-000000000001')),
  'the recipient accepts the request');

select is(
  (select request_state from conversation_participants
    where user_id = 'aaaa2384-0000-0000-0000-0000000000b2'
      and conversation_id = (select conversation_id from direct_messages
                              where id = '11112384-0000-0000-0000-000000000001')),
  'accepted',
  'the recipient''s row reads accepted');

set local "request.jwt.claims" = '{"sub":"aaaa2384-0000-0000-0000-0000000000a1","role":"authenticated"}';

select lives_ok(
  $$insert into direct_messages (id, sender_id, recipient_id, body)
    values ('11112384-0000-0000-0000-000000000006',
            'aaaa2384-0000-0000-0000-0000000000a1', 'aaaa2384-0000-0000-0000-0000000000b2', 'thanks')$$,
  'an accepted request lifts the cap');

set local role postgres;

select is(
  (select count(*)::int from notifications
    where kind = 'message'
      and user_id = 'aaaa2384-0000-0000-0000-0000000000b2'
      and actor_id = 'aaaa2384-0000-0000-0000-0000000000a1'),
  1,
  'a message after acceptance notifies the recipient');

-- ── decline ──

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"aaaa2384-0000-0000-0000-0000000000a1","role":"authenticated"}';

insert into direct_messages (id, sender_id, recipient_id, body)
values ('11112384-0000-0000-0000-000000000007',
        'aaaa2384-0000-0000-0000-0000000000a1', 'aaaa2384-0000-0000-0000-0000000000a7', 'to g');

set local "request.jwt.claims" = '{"sub":"aaaa2384-0000-0000-0000-0000000000a7","role":"authenticated"}';

select is(
  (select count(*)::int from dm_threads() where partner_id = 'aaaa2384-0000-0000-0000-0000000000a1'),
  1,
  'the request is listed for its recipient before the decline');

select lives_ok(
  format($$select decline_message_request(%L, '11112384-0000-0000-0000-000000000007')$$,
    (select conversation_id from direct_messages where id = '11112384-0000-0000-0000-000000000007')),
  'the recipient declines the request');

select is(
  (select count(*)::int from dm_threads() where partner_id = 'aaaa2384-0000-0000-0000-0000000000a1'),
  0,
  'a declined request is not listed for the decliner');

set local "request.jwt.claims" = '{"sub":"aaaa2384-0000-0000-0000-0000000000a1","role":"authenticated"}';

select throws_ok(
  $$insert into direct_messages (sender_id, recipient_id, body)
    values ('aaaa2384-0000-0000-0000-0000000000a1', 'aaaa2384-0000-0000-0000-0000000000a7', 'again')$$,
  '42501', null,
  'the requester cannot send again after a decline');

set local "request.jwt.claims" = '{"sub":"aaaa2384-0000-0000-0000-0000000000a7","role":"authenticated"}';

select lives_ok(
  $$insert into direct_messages (sender_id, recipient_id, body)
    values ('aaaa2384-0000-0000-0000-0000000000a7', 'aaaa2384-0000-0000-0000-0000000000a1', 'changed my mind')$$,
  'the decliner can still write, which takes the decline back');

set local role postgres;

select is(
  (select request_state from conversation_participants
    where user_id = 'aaaa2384-0000-0000-0000-0000000000a7'
      and conversation_id = (select conversation_id from direct_messages
                              where id = '11112384-0000-0000-0000-000000000007')),
  'accepted',
  'writing to the requester accepts the conversation');

-- ── decline and block ──

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"aaaa2384-0000-0000-0000-0000000000a1","role":"authenticated"}';

insert into direct_messages (id, sender_id, recipient_id, body)
values ('11112384-0000-0000-0000-000000000008',
        'aaaa2384-0000-0000-0000-0000000000a1', 'aaaa2384-0000-0000-0000-0000000000b8', 'to h');

set local "request.jwt.claims" = '{"sub":"aaaa2384-0000-0000-0000-0000000000b8","role":"authenticated"}';

select lives_ok(
  format($$select decline_message_request(%L, '11112384-0000-0000-0000-000000000008', true)$$,
    (select conversation_id from direct_messages where id = '11112384-0000-0000-0000-000000000008')),
  'the recipient declines and blocks in one call');

select is(
  (select count(*)::int from user_blocks
    where blocker_id = 'aaaa2384-0000-0000-0000-0000000000b8'
      and blocked_id = 'aaaa2384-0000-0000-0000-0000000000a1'),
  1,
  'decline-and-block files the block');

set local "request.jwt.claims" = '{"sub":"aaaa2384-0000-0000-0000-0000000000a1","role":"authenticated"}';

select throws_ok(
  $$insert into direct_messages (sender_id, recipient_id, body)
    values ('aaaa2384-0000-0000-0000-0000000000a1', 'aaaa2384-0000-0000-0000-0000000000b8', 'after block')$$,
  '42501', null,
  'a blocked requester cannot send');

-- ── a block resets accepted consent ──

set local "request.jwt.claims" = '{"sub":"aaaa2384-0000-0000-0000-0000000000b2","role":"authenticated"}';
select block_user('aaaa2384-0000-0000-0000-0000000000a1');

set local role postgres;

select is(
  (select count(*)::int from conversation_participants
    where conversation_id = (select conversation_id from direct_messages
                              where id = '11112384-0000-0000-0000-000000000001')
      and request_state is null),
  2,
  'a block resets accepted consent on both sides');

select * from finish();
rollback;

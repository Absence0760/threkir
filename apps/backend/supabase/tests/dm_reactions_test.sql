-- Pins migration 20271213121602 — reactions on direct messages (issue
-- #1216): only participants react, only through the RPC, only on a live
-- message they can see, never across a block or inside an unaccepted
-- request, from the fixed set; reads follow the message's own visibility;
-- unsend and account deletion take the reactions.

begin;
select plan(24);

insert into auth.users (id, email, encrypted_password, email_confirmed_at,
                        instance_id, aud, role)
select ('aaaa1216-4ea0-0000-0000-0000000000' || s)::uuid, 'react-' || s || '@example.com', '', now(),
       '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'
  from unnest(array['a1', 'b2', 'c3', 'd4', 'e5']) as s
on conflict (id) do nothing;

-- A follows B and E. D shares a club with A and has sent A a request.
insert into user_follows (follower_id, followee_id) values
  ('aaaa1216-4ea0-0000-0000-0000000000a1', 'aaaa1216-4ea0-0000-0000-0000000000b2'),
  ('aaaa1216-4ea0-0000-0000-0000000000a1', 'aaaa1216-4ea0-0000-0000-0000000000e5');

insert into clubs (id, owner_id, name, slug, is_public)
values ('cccc1216-4ea0-0000-0000-000000000001', 'aaaa1216-4ea0-0000-0000-0000000000a1',
        'Reactions Club', 'reactions-club-1216', true);
insert into club_members (club_id, user_id, role, status) values
  ('cccc1216-4ea0-0000-0000-000000000001', 'aaaa1216-4ea0-0000-0000-0000000000a1', 'owner', 'active'),
  ('cccc1216-4ea0-0000-0000-000000000001', 'aaaa1216-4ea0-0000-0000-0000000000d4', 'member', 'active')
on conflict (club_id, user_id) do update set status = excluded.status;

insert into direct_messages (id, sender_id, recipient_id, body, created_at) values
  ('2222a216-4ea0-0000-0000-000000000001', 'aaaa1216-4ea0-0000-0000-0000000000a1', 'aaaa1216-4ea0-0000-0000-0000000000b2', 'hi', now() - interval '5 minutes'),
  ('2222a216-4ea0-0000-0000-000000000004', 'aaaa1216-4ea0-0000-0000-0000000000a1', 'aaaa1216-4ea0-0000-0000-0000000000e5', 'to e', now() - interval '5 minutes'),
  ('2222a216-4ea0-0000-0000-000000000005', 'aaaa1216-4ea0-0000-0000-0000000000a1', 'aaaa1216-4ea0-0000-0000-0000000000b2', 'oops', now() - interval '3 minutes'),
  ('2222a216-4ea0-0000-0000-000000000002', 'aaaa1216-4ea0-0000-0000-0000000000b2', 'aaaa1216-4ea0-0000-0000-0000000000a1', 'yo', now() - interval '4 minutes');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"aaaa1216-4ea0-0000-0000-0000000000d4","role":"authenticated"}';
insert into direct_messages (id, sender_id, recipient_id, body) values
  ('2222a216-4ea0-0000-0000-000000000003', 'aaaa1216-4ea0-0000-0000-0000000000d4', 'aaaa1216-4ea0-0000-0000-0000000000a1', 'request');

-- ── participants react through the RPC ──

set local "request.jwt.claims" = '{"sub":"aaaa1216-4ea0-0000-0000-0000000000a1","role":"authenticated"}';
select lives_ok(
  $$select set_direct_message_reaction('2222a216-4ea0-0000-0000-000000000002', 'heart')$$,
  'the recipient can react to a message');
select lives_ok(
  $$select set_direct_message_reaction('2222a216-4ea0-0000-0000-000000000002', 'fire')$$,
  'reacting again replaces the reaction');
select is(
  (select array_agg(reaction) from direct_message_reactions
    where message_id = '2222a216-4ea0-0000-0000-000000000002'),
  array['fire'],
  'one reaction per participant per message');
select throws_ok(
  $$select set_direct_message_reaction('2222a216-4ea0-0000-0000-000000000002', 'poop')$$,
  '22023', null,
  'a key outside the set is refused');
select throws_ok(
  $$insert into direct_message_reactions (message_id, user_id, reaction)
    values ('2222a216-4ea0-0000-0000-000000000001', 'aaaa1216-4ea0-0000-0000-0000000000a1', 'heart')$$,
  '42501', null,
  'a client cannot insert a reaction directly');
select throws_ok(
  $$delete from direct_message_reactions returning 1$$,
  '42501', null,
  'a client cannot delete reactions directly');

set local "request.jwt.claims" = '{"sub":"aaaa1216-4ea0-0000-0000-0000000000b2","role":"authenticated"}';
select lives_ok(
  $$select set_direct_message_reaction('2222a216-4ea0-0000-0000-000000000002', 'thumbs_up')$$,
  'the sender can react to their own message');
select is(
  (select count(*)::int from direct_message_reactions
    where message_id = '2222a216-4ea0-0000-0000-000000000002'),
  2,
  'the other participant reads both reactions');

-- ── someone outside the conversation ──

set local "request.jwt.claims" = '{"sub":"aaaa1216-4ea0-0000-0000-0000000000c3","role":"authenticated"}';
select throws_ok(
  $$select set_direct_message_reaction('2222a216-4ea0-0000-0000-000000000002', 'heart')$$,
  'P0002', null,
  'a non-participant is told the message does not exist');
select is(
  (select count(*)::int from direct_message_reactions),
  0,
  'a non-participant reads no reactions');

-- ── an unaccepted request ──

set local "request.jwt.claims" = '{"sub":"aaaa1216-4ea0-0000-0000-0000000000a1","role":"authenticated"}';
select throws_ok(
  $$select set_direct_message_reaction('2222a216-4ea0-0000-0000-000000000003', 'heart')$$,
  '55000', null,
  'the recipient of a pending request cannot react before accepting');
set local "request.jwt.claims" = '{"sub":"aaaa1216-4ea0-0000-0000-0000000000d4","role":"authenticated"}';
select throws_ok(
  $$select set_direct_message_reaction('2222a216-4ea0-0000-0000-000000000003', 'heart')$$,
  '55000', null,
  'the requester cannot react inside their own pending request either');

-- ── a block, either way, with the same answer ──

set local "request.jwt.claims" = '{"sub":"aaaa1216-4ea0-0000-0000-0000000000e5","role":"authenticated"}';
insert into user_blocks (blocker_id, blocked_id)
values ('aaaa1216-4ea0-0000-0000-0000000000e5', 'aaaa1216-4ea0-0000-0000-0000000000a1');
select throws_ok(
  $$select set_direct_message_reaction('2222a216-4ea0-0000-0000-000000000004', 'heart')$$,
  '55000', null,
  'the blocker cannot react');
set local "request.jwt.claims" = '{"sub":"aaaa1216-4ea0-0000-0000-0000000000a1","role":"authenticated"}';
select throws_ok(
  $$select set_direct_message_reaction('2222a216-4ea0-0000-0000-000000000004', 'heart')$$,
  '55000', null,
  'the blocked person gets the same refusal as a closed request, so the block is not revealed');

-- ── unsend takes the reactions ──

set local "request.jwt.claims" = '{"sub":"aaaa1216-4ea0-0000-0000-0000000000b2","role":"authenticated"}';
select lives_ok(
  $$select set_direct_message_reaction('2222a216-4ea0-0000-0000-000000000005', 'laugh')$$,
  'a reaction on a message about to be unsent');
set local "request.jwt.claims" = '{"sub":"aaaa1216-4ea0-0000-0000-0000000000a1","role":"authenticated"}';
select lives_ok(
  $$select unsend_direct_message('2222a216-4ea0-0000-0000-000000000005')$$,
  'the sender unsends it');
reset role;
select ok(
  (select unsent_at is not null from direct_messages where id = '2222a216-4ea0-0000-0000-000000000005'),
  'the message is stamped unsent');
select is(
  (select count(*)::int from direct_message_reactions
    where message_id = '2222a216-4ea0-0000-0000-000000000005'),
  0,
  'unsending deleted the reactions on it');
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"aaaa1216-4ea0-0000-0000-0000000000b2","role":"authenticated"}';
select throws_ok(
  $$select set_direct_message_reaction('2222a216-4ea0-0000-0000-000000000005', 'laugh')$$,
  '55000', null,
  'an unsent message takes no reaction');

-- ── delete-for-me hides the reactions and refuses new ones ──

set local "request.jwt.claims" = '{"sub":"aaaa1216-4ea0-0000-0000-0000000000a1","role":"authenticated"}';
select hide_conversation(
  (select conversation_id from direct_messages where id = '2222a216-4ea0-0000-0000-000000000002'),
  '2222a216-4ea0-0000-0000-000000000002');
select is(
  (select count(*)::int from direct_message_reactions
    where message_id = '2222a216-4ea0-0000-0000-000000000002'),
  0,
  'reactions on a message the viewer deleted for themselves are hidden from them');
-- Since 20271216000006 the lookup is the read rule, and a message behind the
-- viewer's own hidden_before is one they cannot read, so it is not found.
select throws_ok(
  $$select set_direct_message_reaction('2222a216-4ea0-0000-0000-000000000002', 'sad')$$,
  'P0002', null,
  'a message deleted for the viewer takes no reaction from them');
set local "request.jwt.claims" = '{"sub":"aaaa1216-4ea0-0000-0000-0000000000b2","role":"authenticated"}';
select is(
  (select count(*)::int from direct_message_reactions
    where message_id = '2222a216-4ea0-0000-0000-000000000002'),
  2,
  'the other participant still reads them');

-- ── the reactor's account deletion takes their reactions ──

reset role;
delete from auth.users where id = 'aaaa1216-4ea0-0000-0000-0000000000b2';
select is(
  (select count(*)::int from direct_message_reactions
    where user_id = 'aaaa1216-4ea0-0000-0000-0000000000b2'),
  0,
  'deleting the account deletes its reactions');
select is(
  (select count(*)::int from direct_message_reactions),
  0,
  'and the messages it sent take every reaction on them');

select * from finish();
rollback;

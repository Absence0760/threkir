-- Pins 20271109000020 (issue #1216 P2): "Mark as unread" is the caller's own
-- participant state. dm_threads() counts a marked conversation as at least one
-- unread, without adding to a real unread count; the other participant's view
-- and read_at are untouched; a client cannot write the stamp directly; the
-- RPC refuses anon, a non-participant and a null flag; clearing it and
-- deleting the conversation both drop the mark.

begin;
select plan(18);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('d0000000-0000-0000-0000-00000000000a', 'authenticated', 'authenticated', 'a@unread.local', '', now(), now()),
  ('d0000000-0000-0000-0000-00000000000b', 'authenticated', 'authenticated', 'b@unread.local', '', now(), now()),
  ('d0000000-0000-0000-0000-00000000000c', 'authenticated', 'authenticated', 'c@unread.local', '', now(), now());

insert into user_follows (follower_id, followee_id) values
  ('d0000000-0000-0000-0000-00000000000a', 'd0000000-0000-0000-0000-00000000000b');

-- A <-> B, every message already read.
insert into direct_messages (id, sender_id, recipient_id, body, created_at, read_at) values
  ('d0000000-0000-0000-0000-0000000000a1', 'd0000000-0000-0000-0000-00000000000a', 'd0000000-0000-0000-0000-00000000000b', 'hello', now() - interval '2 hours', now()),
  ('d0000000-0000-0000-0000-0000000000b1', 'd0000000-0000-0000-0000-00000000000b', 'd0000000-0000-0000-0000-00000000000a', 'hi',    now() - interval '1 hour', now());

create temporary table conv as
  select conversation_id as id from direct_messages where id = 'd0000000-0000-0000-0000-0000000000a1';
grant select on conv to authenticated;

-- ── Refusals ────────────────────────────────────────────────────────────

set local role anon;
select throws_ok(
  $$select set_conversation_unread('d0000000-0000-0000-0000-0000000000ff', true)$$,
  '42501', null,
  'anon cannot call set_conversation_unread');
reset role;

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"d0000000-0000-0000-0000-00000000000c","role":"authenticated"}';
select throws_ok(
  $$select set_conversation_unread((select id from conv), true)$$,
  'P0002', null,
  'a non-participant cannot mark it unread');

set local "request.jwt.claims" = '{"sub":"d0000000-0000-0000-0000-00000000000a","role":"authenticated"}';
select throws_ok(
  $$select set_conversation_unread((select id from conv), null)$$,
  '22004', null,
  'set_conversation_unread refuses a null flag');
select throws_ok(
  $$update conversation_participants set marked_unread_at = now() where conversation_id = (select id from conv)$$,
  '42501', null,
  'a client cannot write the mark directly');

-- ── Marking ─────────────────────────────────────────────────────────────

select is(
  (select unread::int from dm_threads() where conversation_id = (select id from conv)),
  0,
  'a read conversation starts with nothing unread');
select lives_ok(
  $$select set_conversation_unread((select id from conv), true)$$,
  'a participant can mark the conversation unread');
select is(
  (select marked_unread from dm_threads() where conversation_id = (select id from conv)),
  true,
  'dm_threads reports it marked unread');
select is(
  (select unread::int from dm_threads() where conversation_id = (select id from conv)),
  1,
  'a marked conversation with no unread message counts one');

set local "request.jwt.claims" = '{"sub":"d0000000-0000-0000-0000-00000000000b","role":"authenticated"}';
select is(
  (select row(marked_unread, unread)::text from dm_threads() where conversation_id = (select id from conv)),
  '(f,0)',
  'the other participant''s view is untouched');
reset role;

select is(
  (select count(*)::int from direct_messages
    where conversation_id = (select id from conv) and read_at is not null),
  2,
  'marking unread leaves every read_at as it was');

-- Two unread messages from B: the mark does not add a third.
insert into direct_messages (id, sender_id, recipient_id, body, created_at) values
  ('d0000000-0000-0000-0000-0000000000b2', 'd0000000-0000-0000-0000-00000000000b', 'd0000000-0000-0000-0000-00000000000a', 'one', now() + interval '1 minute'),
  ('d0000000-0000-0000-0000-0000000000b3', 'd0000000-0000-0000-0000-00000000000b', 'd0000000-0000-0000-0000-00000000000a', 'two', now() + interval '2 minutes');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"d0000000-0000-0000-0000-00000000000a","role":"authenticated"}';
select is(
  (select unread::int from dm_threads() where conversation_id = (select id from conv)),
  2,
  'a marked conversation with unread messages counts those, not one more');

-- ── Clearing ────────────────────────────────────────────────────────────

select lives_ok(
  $$select set_conversation_unread((select id from conv), false)$$,
  'a participant can clear the mark');
select is(
  (select marked_unread from dm_threads() where conversation_id = (select id from conv)),
  false,
  'dm_threads reports the mark cleared');
reset role;

update direct_messages set read_at = now()
 where id in ('d0000000-0000-0000-0000-0000000000b2', 'd0000000-0000-0000-0000-0000000000b3');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"d0000000-0000-0000-0000-00000000000a","role":"authenticated"}';
select is(
  (select unread::int from dm_threads() where conversation_id = (select id from conv)),
  0,
  'once cleared and read, nothing is counted');

-- ── Delete for me drops the mark ────────────────────────────────────────

select lives_ok(
  $$select set_conversation_unread((select id from conv), true)$$,
  'a participant can mark it unread again');
select is(
  (select marked_unread from dm_threads() where conversation_id = (select id from conv)),
  true,
  'dm_threads reports it marked unread again');
select lives_ok(
  $$select hide_conversation((select id from conv), 'd0000000-0000-0000-0000-0000000000b3')$$,
  'a participant can delete the marked conversation');
reset role;

select is(
  (select marked_unread_at from conversation_participants
    where conversation_id = (select id from conv) and user_id = 'd0000000-0000-0000-0000-00000000000a'),
  null,
  'deleting the conversation clears the mark');

select * from finish();
rollback;

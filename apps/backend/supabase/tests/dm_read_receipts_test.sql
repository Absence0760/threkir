-- Pins 20271113000001 (issue #1216): read receipts and their reciprocal
-- opt-out are enforced by the server. No client can select read_at, the
-- recipient's own fact; the sender sees seen_at only when both participants
-- have receipts on; turning them off withdraws receipts already shown, both
-- ways; marking read is the RPC, which keeps the bound on what was shown;
-- dm_threads() still counts unread and still honours hidden_before; unsend no
-- longer hands read_at back.

begin;
select plan(29);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('e1000000-0000-0000-0000-00000000000a', 'authenticated', 'authenticated', 'a@receipts.local', '', now(), now()),
  ('e1000000-0000-0000-0000-00000000000b', 'authenticated', 'authenticated', 'b@receipts.local', '', now(), now()),
  ('e1000000-0000-0000-0000-00000000000c', 'authenticated', 'authenticated', 'c@receipts.local', '', now(), now());

insert into user_follows (follower_id, followee_id) values
  ('e1000000-0000-0000-0000-00000000000a', 'e1000000-0000-0000-0000-00000000000b'),
  ('e1000000-0000-0000-0000-00000000000a', 'e1000000-0000-0000-0000-00000000000c');

-- A -> B twice, then A -> C once. Nobody has a user_settings row yet, so
-- everyone is on the default (receipts on).
insert into direct_messages (id, sender_id, recipient_id, body, created_at) values
  ('e1000000-0000-0000-0000-0000000000a1', 'e1000000-0000-0000-0000-00000000000a', 'e1000000-0000-0000-0000-00000000000b', 'one', now() - interval '3 minutes'),
  ('e1000000-0000-0000-0000-0000000000a2', 'e1000000-0000-0000-0000-00000000000a', 'e1000000-0000-0000-0000-00000000000b', 'two', now() - interval '2 minutes'),
  ('e1000000-0000-0000-0000-0000000000c1', 'e1000000-0000-0000-0000-00000000000a', 'e1000000-0000-0000-0000-00000000000c', 'hey', now() - interval '1 minute');

-- ── Grants ──────────────────────────────────────────────────────────────

select ok(
  not has_column_privilege('authenticated', 'public.direct_messages', 'read_at', 'SELECT'),
  'authenticated cannot select direct_messages.read_at');
select ok(
  has_column_privilege('authenticated', 'public.direct_messages', 'seen_at', 'SELECT'),
  'authenticated can select direct_messages.seen_at');
select ok(
  not has_column_privilege('anon', 'public.direct_messages', 'read_at', 'SELECT'),
  'anon cannot select direct_messages.read_at either');
select ok(
  not has_table_privilege('authenticated', 'public.direct_messages', 'UPDATE')
    and not has_column_privilege('authenticated', 'public.direct_messages', 'read_at', 'UPDATE')
    and not has_column_privilege('authenticated', 'public.direct_messages', 'seen_at', 'UPDATE'),
  'a client cannot write read_at or seen_at directly');

set local role anon;
select throws_ok(
  $$select mark_direct_messages_read('e1000000-0000-0000-0000-00000000000a', 'e1000000-0000-0000-0000-0000000000a1')$$,
  '42501', null,
  'anon cannot call mark_direct_messages_read');
reset role;

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"e1000000-0000-0000-0000-00000000000a","role":"authenticated"}';
select throws_ok(
  $$select read_at from direct_messages where id = 'e1000000-0000-0000-0000-0000000000a1'$$,
  '42501', null,
  'the sender cannot select read_at');

-- ── Opted in: B reads the first message ─────────────────────────────────

set local "request.jwt.claims" = '{"sub":"e1000000-0000-0000-0000-00000000000c","role":"authenticated"}';
select throws_ok(
  $$select mark_direct_messages_read('e1000000-0000-0000-0000-00000000000a', 'e1000000-0000-0000-0000-0000000000a1')$$,
  'P0002', null,
  'a third person cannot mark someone else''s pair read');

set local "request.jwt.claims" = '{"sub":"e1000000-0000-0000-0000-00000000000b","role":"authenticated"}';
select is(
  (select unread::int from dm_threads() where partner_id = 'e1000000-0000-0000-0000-00000000000a'),
  2,
  'dm_threads still counts the recipient''s unread messages');
select is(
  mark_direct_messages_read('e1000000-0000-0000-0000-00000000000a', 'e1000000-0000-0000-0000-0000000000a1'),
  1,
  'marking read stops at the message the reader was shown');
select is(
  (select unread::int from dm_threads() where partner_id = 'e1000000-0000-0000-0000-00000000000a'),
  1,
  'the later message stays unread');

set local "request.jwt.claims" = '{"sub":"e1000000-0000-0000-0000-00000000000a","role":"authenticated"}';
select isnt(
  (select seen_at from direct_messages where id = 'e1000000-0000-0000-0000-0000000000a1'),
  null,
  'both opted in: the sender sees seen_at');
select is(
  (select seen_at from direct_messages where id = 'e1000000-0000-0000-0000-0000000000a2'),
  null,
  'an unread message has no seen_at');
select is(
  (select read_at from unsend_direct_message('e1000000-0000-0000-0000-0000000000a1')),
  null,
  'unsend_direct_message does not hand read_at to the sender');
reset role;

-- ── The recipient opts out: B ───────────────────────────────────────────

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"e1000000-0000-0000-0000-00000000000b","role":"authenticated"}';
insert into user_settings (user_id, dm_read_receipts)
values ('e1000000-0000-0000-0000-00000000000b', false);

set local "request.jwt.claims" = '{"sub":"e1000000-0000-0000-0000-00000000000a","role":"authenticated"}';
select is(
  (select seen_at from direct_messages where id = 'e1000000-0000-0000-0000-0000000000a1'),
  null,
  'opting out withdraws a receipt the sender had already seen');

set local "request.jwt.claims" = '{"sub":"e1000000-0000-0000-0000-00000000000b","role":"authenticated"}';
select is(
  mark_direct_messages_read('e1000000-0000-0000-0000-00000000000a', 'e1000000-0000-0000-0000-0000000000a2'),
  1,
  'an opted-out recipient can still mark read');
select is(
  (select unread::int from dm_threads() where partner_id = 'e1000000-0000-0000-0000-00000000000a'),
  0,
  'and their own unread count clears');
select is(
  (select seen_at from direct_messages where id = 'e1000000-0000-0000-0000-0000000000a2'),
  null,
  'the opted-out recipient''s read writes no seen_at');

set local "request.jwt.claims" = '{"sub":"e1000000-0000-0000-0000-00000000000a","role":"authenticated"}';
-- Both A -> B messages, read back as unseen: a count of seen rows would read
-- zero for a sender who could not see the messages at all.
select is(
  (select array_agg(seen_at is null order by created_at)::text from direct_messages
    where sender_id = 'e1000000-0000-0000-0000-00000000000a'
      and recipient_id = 'e1000000-0000-0000-0000-00000000000b'),
  '{t,t}',
  'the sender sees no receipt from an opted-out recipient');
reset role;

select is(
  (select count(*)::int from direct_messages
    where recipient_id = 'e1000000-0000-0000-0000-00000000000b' and read_at is not null),
  2,
  'read_at is still stored for the recipient''s own unread count');

-- ── The sender opts out: A, while C has receipts on ─────────────────────

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"e1000000-0000-0000-0000-00000000000c","role":"authenticated"}';
select is(
  mark_direct_messages_read('e1000000-0000-0000-0000-00000000000a', 'e1000000-0000-0000-0000-0000000000c1'),
  1,
  'C reads A''s message');

set local "request.jwt.claims" = '{"sub":"e1000000-0000-0000-0000-00000000000a","role":"authenticated"}';
select isnt(
  (select seen_at from direct_messages where id = 'e1000000-0000-0000-0000-0000000000c1'),
  null,
  'A sees C''s receipt while both are opted in');

insert into user_settings (user_id, dm_read_receipts)
values ('e1000000-0000-0000-0000-00000000000a', false);
select is(
  (select seen_at from direct_messages where id = 'e1000000-0000-0000-0000-0000000000c1'),
  null,
  'opting out hides receipts on the runner''s own messages too');
reset role;

insert into direct_messages (id, sender_id, recipient_id, body, created_at) values
  ('e1000000-0000-0000-0000-0000000000c2', 'e1000000-0000-0000-0000-00000000000a', 'e1000000-0000-0000-0000-00000000000c', 'again', now());

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"e1000000-0000-0000-0000-00000000000c","role":"authenticated"}';
select is(
  mark_direct_messages_read('e1000000-0000-0000-0000-00000000000a', 'e1000000-0000-0000-0000-0000000000c2'),
  1,
  'C reads the next one');
select is(
  (select seen_at from direct_messages where id = 'e1000000-0000-0000-0000-0000000000c2'),
  null,
  'a sender who opted out gets no new receipt');

-- ── Back on: only reads made while both are on are shared ───────────────

set local "request.jwt.claims" = '{"sub":"e1000000-0000-0000-0000-00000000000a","role":"authenticated"}';
update user_settings set dm_read_receipts = true
 where user_id = 'e1000000-0000-0000-0000-00000000000a';
select is(
  (select count(*)::int from direct_messages
    where recipient_id = 'e1000000-0000-0000-0000-00000000000c' and seen_at is not null),
  0,
  'turning receipts back on does not restore earlier ones');

-- ── dm_threads still honours delete-for-me ──────────────────────────────

reset role;
insert into direct_messages (id, sender_id, recipient_id, body, created_at) values
  ('e1000000-0000-0000-0000-0000000000c3', 'e1000000-0000-0000-0000-00000000000c', 'e1000000-0000-0000-0000-00000000000a', 'old', now() - interval '10 minutes');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"e1000000-0000-0000-0000-00000000000a","role":"authenticated"}';
select is(
  (select unread::int from dm_threads() where partner_id = 'e1000000-0000-0000-0000-00000000000c'),
  1,
  'an unread message older than the delete point still counts before the delete');
select lives_ok(
  $$select hide_conversation(
      (select conversation_id from direct_messages where id = 'e1000000-0000-0000-0000-0000000000c2'),
      'e1000000-0000-0000-0000-0000000000c2')$$,
  'A deletes the conversation with C');
select is(
  (select count(*)::int from dm_threads()
    where partner_id = 'e1000000-0000-0000-0000-00000000000c'),
  0,
  'dm_threads leaves out messages at or before hidden_before, unread or not');

reset role;
select is(
  (select hidden_before from conversation_participants
    where conversation_id = (select conversation_id from direct_messages where id = 'e1000000-0000-0000-0000-0000000000c2')
      and user_id = 'e1000000-0000-0000-0000-00000000000a'),
  (select created_at from direct_messages where id = 'e1000000-0000-0000-0000-0000000000c2'),
  'the delete records hidden_before at the message A deleted through');

select * from finish();
rollback;

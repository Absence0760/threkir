-- Pins 20271105000001 (issue #1216): conversations + per-participant state.
-- A message is assigned its pair's conversation by the server; "delete
-- conversation" hides it for the caller only and a newer message brings it
-- back; mute silences the notification; archive holds until a newer message;
-- participant state is private to its owner and written only by the RPCs; an
-- account deletion keeps the remaining participant's conversation; and the
-- purge drops a conversation once nothing references it.
--
-- now() is the transaction's start for every statement here, so the RPCs'
-- stamps are all "now" and each message that must land AFTER a stamp is
-- seeded as superuser with an explicit later created_at.

begin;
select plan(30);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('dc000000-0000-0000-0000-00000000000a', 'authenticated', 'authenticated', 'a@conv.local', '', now(), now()),
  ('dc000000-0000-0000-0000-00000000000b', 'authenticated', 'authenticated', 'b@conv.local', '', now(), now()),
  ('dc000000-0000-0000-0000-00000000000c', 'authenticated', 'authenticated', 'c@conv.local', '', now(), now());

insert into user_follows (follower_id, followee_id) values
  ('dc000000-0000-0000-0000-00000000000a', 'dc000000-0000-0000-0000-00000000000b');

-- A <-> B, both directions, in the past.
insert into direct_messages (id, sender_id, recipient_id, body, created_at, read_at) values
  ('dc000000-0000-0000-0000-0000000000a1', 'dc000000-0000-0000-0000-00000000000a', 'dc000000-0000-0000-0000-00000000000b', 'hello', now() - interval '3 hours', now()),
  ('dc000000-0000-0000-0000-0000000000b1', 'dc000000-0000-0000-0000-00000000000b', 'dc000000-0000-0000-0000-00000000000a', 'hi',    now() - interval '2 hours', null),
  ('dc000000-0000-0000-0000-0000000000a2', 'dc000000-0000-0000-0000-00000000000a', 'dc000000-0000-0000-0000-00000000000b', 'how',   now() - interval '1 hour', null);

-- ── Assignment ──────────────────────────────────────────────────────────

select is(
  (select count(distinct conversation_id)::int from direct_messages
    where id in ('dc000000-0000-0000-0000-0000000000a1', 'dc000000-0000-0000-0000-0000000000b1',
                 'dc000000-0000-0000-0000-0000000000a2')),
  1,
  'both directions of a pair share one conversation');
select is(
  (select array_agg(user_id order by user_id)::text from conversation_participants
    where conversation_id = (select conversation_id from direct_messages where id = 'dc000000-0000-0000-0000-0000000000a1')),
  '{dc000000-0000-0000-0000-00000000000a,dc000000-0000-0000-0000-00000000000b}',
  'the conversation has exactly the pair as participants');

create temporary table conv as
  select conversation_id as id from direct_messages where id = 'dc000000-0000-0000-0000-0000000000a1';
grant select on conv to authenticated;

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"dc000000-0000-0000-0000-00000000000a","role":"authenticated"}';

select throws_ok(
  $$insert into direct_messages (sender_id, recipient_id, body, conversation_id)
    values ('dc000000-0000-0000-0000-00000000000a', 'dc000000-0000-0000-0000-00000000000b', 'x', (select id from conv))$$,
  '42501', null,
  'a client cannot choose a message''s conversation');
select lives_ok(
  $$insert into direct_messages (id, sender_id, recipient_id, body)
    values ('dc000000-0000-0000-0000-0000000000a3', 'dc000000-0000-0000-0000-00000000000a', 'dc000000-0000-0000-0000-00000000000b', 'client send')$$,
  'an ordinary client send still works');
select is(
  (select conversation_id from direct_messages where id = 'dc000000-0000-0000-0000-0000000000a3'),
  (select id from conv),
  'a client send lands in the pair''s existing conversation');

-- ── Participant state is private and RPC-only ──────────────────────────

select is(
  (select count(*)::int from conversation_participants where conversation_id = (select id from conv)),
  1,
  'a participant reads only their own participant row');
select is(
  (select user_id from conversation_participants where conversation_id = (select id from conv)),
  'dc000000-0000-0000-0000-00000000000a'::uuid,
  'the row a participant reads is their own');
select throws_ok(
  $$update conversation_participants set muted_at = now() where conversation_id = (select id from conv)$$,
  '42501', null,
  'a client cannot write participant state directly');

set local "request.jwt.claims" = '{"sub":"dc000000-0000-0000-0000-00000000000c","role":"authenticated"}';
select throws_ok(
  $$select hide_conversation((select id from conv))$$,
  'P0002', null,
  'a non-participant cannot delete the conversation');
select throws_ok(
  $$select set_conversation_muted((select id from conv), true)$$,
  'P0002', null,
  'a non-participant cannot mute it');
select throws_ok(
  $$select set_conversation_archived((select id from conv), true)$$,
  'P0002', null,
  'a non-participant cannot archive it');
select is(
  (select count(*)::int from conversations where id = (select id from conv)),
  0,
  'a non-participant cannot read the conversation');

-- ── Delete for me ───────────────────────────────────────────────────────

set local "request.jwt.claims" = '{"sub":"dc000000-0000-0000-0000-00000000000a","role":"authenticated"}';
select isnt_empty(
  $$select 1 from dm_threads() where conversation_id = (select id from conv)$$,
  'before deleting, the conversation is in A''s inbox');
select lives_ok(
  $$select hide_conversation((select id from conv))$$,
  'a participant can delete the conversation for themselves');
select is(
  (select count(*)::int from direct_messages where conversation_id = (select id from conv)),
  0,
  'every message so far is gone from the deleter''s reads');
select is_empty(
  $$select 1 from dm_threads() where conversation_id = (select id from conv)$$,
  'and the conversation is gone from their inbox');

set local "request.jwt.claims" = '{"sub":"dc000000-0000-0000-0000-00000000000b","role":"authenticated"}';
select is(
  (select count(*)::int from direct_messages where conversation_id = (select id from conv)),
  4,
  'the other participant still has every message');

reset role;
insert into direct_messages (id, sender_id, recipient_id, body, created_at) values
  ('dc000000-0000-0000-0000-0000000000b2', 'dc000000-0000-0000-0000-00000000000b', 'dc000000-0000-0000-0000-00000000000a', 'are you there', now() + interval '1 minute');
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"dc000000-0000-0000-0000-00000000000a","role":"authenticated"}';

select is(
  (select last_body || ':' || unread from dm_threads() where conversation_id = (select id from conv)),
  'are you there:1',
  'a newer message brings the conversation back with only that message');
select is(
  (select count(*)::int from notifications
    where user_id = 'dc000000-0000-0000-0000-00000000000a' and kind = 'message'),
  2,
  'an unread message hidden by the delete does not silence the next notification');

-- ── Mute ────────────────────────────────────────────────────────────────

select lives_ok(
  $$select set_conversation_muted((select id from conv), true)$$,
  'a participant can mute the conversation');
select is(
  (select muted from dm_threads() where conversation_id = (select id from conv)),
  true,
  'dm_threads reports it muted');

reset role;
update direct_messages set read_at = now() where recipient_id = 'dc000000-0000-0000-0000-00000000000a';
insert into direct_messages (sender_id, recipient_id, body, created_at) values
  ('dc000000-0000-0000-0000-00000000000b', 'dc000000-0000-0000-0000-00000000000a', 'muted ping', now() + interval '2 minutes');
select is(
  (select count(*)::int from notifications
    where user_id = 'dc000000-0000-0000-0000-00000000000a' and kind = 'message'),
  2,
  'a message into a muted conversation raises no notification');
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"dc000000-0000-0000-0000-00000000000a","role":"authenticated"}';

select lives_ok(
  $$select set_conversation_muted((select id from conv), false)$$,
  'a participant can unmute it');
select is(
  (select muted from dm_threads() where conversation_id = (select id from conv)),
  false,
  'dm_threads reports it unmuted');

-- ── Archive ─────────────────────────────────────────────────────────────
--
-- The archive stamp is now(), which is older than the seeded "muted ping", so
-- the conversation reads as not archived until the last message is older than
-- the stamp. Move the messages back to make the archive the newest event.

reset role;
update direct_messages set created_at = created_at - interval '1 day'
 where conversation_id = (select id from conv);
update conversation_participants set hidden_before = hidden_before - interval '1 day'
 where conversation_id = (select id from conv);
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"dc000000-0000-0000-0000-00000000000a","role":"authenticated"}';

select lives_ok(
  $$select set_conversation_archived((select id from conv), true)$$,
  'a participant can archive the conversation');
select is(
  (select archived from dm_threads() where conversation_id = (select id from conv)),
  true,
  'dm_threads reports it archived');

reset role;
insert into direct_messages (sender_id, recipient_id, body, created_at) values
  ('dc000000-0000-0000-0000-00000000000b', 'dc000000-0000-0000-0000-00000000000a', 'new reply', now() + interval '3 minutes');
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"dc000000-0000-0000-0000-00000000000a","role":"authenticated"}';

select is(
  (select archived from dm_threads() where conversation_id = (select id from conv)),
  false,
  'a message newer than the archive brings the conversation back to the inbox');

-- ── Account deletion and purge ──────────────────────────────────────────

reset role;
delete from auth.users where id = 'dc000000-0000-0000-0000-00000000000b';

select is(
  (select array_agg(user_id)::text from conversation_participants where conversation_id = (select id from conv)),
  '{dc000000-0000-0000-0000-00000000000a}',
  'the leaver''s participant row goes with their account and the remaining one stays');

-- A conversation whose only messages age out of the 2-year window.
insert into user_follows (follower_id, followee_id) values
  ('dc000000-0000-0000-0000-00000000000a', 'dc000000-0000-0000-0000-00000000000c');
insert into direct_messages (id, sender_id, recipient_id, body, created_at) values
  ('dc000000-0000-0000-0000-0000000000c1', 'dc000000-0000-0000-0000-00000000000a', 'dc000000-0000-0000-0000-00000000000c', 'old', now() - interval '3 years');
create temporary table old_conv as
  select conversation_id as id from direct_messages where id = 'dc000000-0000-0000-0000-0000000000c1';

select private.purge_stale_direct_messages();

select is(
  (select count(*)::int from conversations where id = (select id from old_conv)),
  0,
  'the purge drops a conversation once its last message is purged');
select is(
  (select count(*)::int from conversations where id = (select id from conv)),
  1,
  'the purge keeps a conversation that still has messages');

select * from finish();
rollback;

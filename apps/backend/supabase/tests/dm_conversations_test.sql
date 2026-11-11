-- Pins 20271105000010 (issue #1216): conversations + per-participant state.
-- A message is assigned its pair's conversation by the server; "delete
-- conversation" hides it for the caller only and a newer message brings it
-- back; mute silences the notification; archive holds until a newer message;
-- participant state is private to its owner and written only by the RPCs; an
-- account deletion keeps the remaining participant's conversation; the
-- purge drops a conversation once nothing references it; anon reaches none
-- of the RPCs; and the migration's backfill assigns every pre-trigger
-- message, live pair or deleted partner, refuses to leave one behind, and is
-- callable by no client role, service_role included.
--
-- now() is the transaction's start for every statement here, so the RPCs'
-- stamps are all "now" and each message that must land AFTER a stamp is
-- seeded as superuser with an explicit later created_at.

begin;
select plan(43);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('dc000000-0000-0000-0000-00000000000a', 'authenticated', 'authenticated', 'a@conv.local', '', now(), now()),
  ('dc000000-0000-0000-0000-00000000000b', 'authenticated', 'authenticated', 'b@conv.local', '', now(), now()),
  ('dc000000-0000-0000-0000-00000000000c', 'authenticated', 'authenticated', 'c@conv.local', '', now(), now()),
  ('dc000000-0000-0000-0000-00000000000d', 'authenticated', 'authenticated', 'd@conv.local', '', now(), now()),
  ('dc000000-0000-0000-0000-00000000000e', 'authenticated', 'authenticated', 'e@conv.local', '', now(), now());

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

-- ── anon, and a user with no conversation ───────────────────────────────

set local role anon;
select throws_ok(
  $$select hide_conversation('dc000000-0000-0000-0000-0000000000ff', 'dc000000-0000-0000-0000-0000000000ff')$$,
  '42501', null,
  'anon cannot call hide_conversation');
select throws_ok(
  $$select set_conversation_muted('dc000000-0000-0000-0000-0000000000ff', true)$$,
  '42501', null,
  'anon cannot call set_conversation_muted');
select throws_ok(
  $$select set_conversation_archived('dc000000-0000-0000-0000-0000000000ff', true)$$,
  '42501', null,
  'anon cannot call set_conversation_archived');
select throws_ok(
  $$select * from dm_threads()$$,
  '42501', null,
  'anon cannot call dm_threads');
reset role;

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"dc000000-0000-0000-0000-00000000000c","role":"authenticated"}';
select is_empty(
  $$select 1 from dm_threads()$$,
  'dm_threads is empty for a user in no conversation');
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
  $$select hide_conversation((select id from conv), 'dc000000-0000-0000-0000-0000000000a3')$$,
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
  $$select hide_conversation((select id from conv), 'dc000000-0000-0000-0000-0000000000a3')$$,
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
select is(
  (select row(hidden_before, muted_at, archived_at)::text from conversation_participants
    where conversation_id = (select id from conv) and user_id = 'dc000000-0000-0000-0000-00000000000b'),
  '(,,)',
  'A''s delete, mute and archive left B''s participant row untouched');

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
-- A deleted every message A sent before B left, so nobody can see what is
-- left and 20271107000002's erase empties the conversation too
-- (dm_purge_hidden_test.sql pins the keep side).
select is(
  (select count(*)::int from conversations where id = (select id from conv)),
  0,
  'the purge erases a deleted account''s thread its remaining participant had deleted');

-- ── The backfill ────────────────────────────────────────────────────────
--
-- Rows as they stood before 20271105000010: no conversation_id, assigned by no
-- trigger. Column and triggers are relaxed inside this transaction only.

alter table direct_messages alter column conversation_id drop not null;
alter table direct_messages disable trigger user;

insert into direct_messages (id, sender_id, recipient_id, deleted_partner_key, body, created_at) values
  ('dc000000-0000-0000-0000-0000000000d1', 'dc000000-0000-0000-0000-00000000000d', 'dc000000-0000-0000-0000-00000000000e', null,
   'd to e', now() - interval '5 days'),
  ('dc000000-0000-0000-0000-0000000000e1', 'dc000000-0000-0000-0000-00000000000e', 'dc000000-0000-0000-0000-00000000000d', null,
   'e to d', now() - interval '4 days'),
  ('dc000000-0000-0000-0000-0000000000d2', 'dc000000-0000-0000-0000-00000000000d', null, 'dc000000-0000-0000-0000-00000000aa01',
   'to a leaver', now() - interval '6 days'),
  ('dc000000-0000-0000-0000-0000000000d3', 'dc000000-0000-0000-0000-00000000000d', null, 'dc000000-0000-0000-0000-00000000aa01',
   'to the same leaver', now() - interval '3 days'),
  ('dc000000-0000-0000-0000-0000000000d4', 'dc000000-0000-0000-0000-00000000000d', null, 'dc000000-0000-0000-0000-00000000aa02',
   'to another leaver', now() - interval '2 days');

select is(
  private.backfill_direct_message_conversations(),
  3,
  'the backfill creates one conversation per live pair and per (sender, deleted partner)');
select is(
  (select count(*)::int from direct_messages where conversation_id is null),
  0,
  'the backfill leaves no message without a conversation');
select is(
  (select array_agg(distinct p.user_id order by p.user_id)::text
     from direct_messages m
     join conversation_participants p on p.conversation_id = m.conversation_id
    where m.id in ('dc000000-0000-0000-0000-0000000000d1', 'dc000000-0000-0000-0000-0000000000e1')),
  '{dc000000-0000-0000-0000-00000000000d,dc000000-0000-0000-0000-00000000000e}',
  'both directions of a backfilled pair share one conversation holding the pair');
select is(
  (select count(distinct m.conversation_id)::int || ':' ||
          (select string_agg(distinct p.user_id::text, ',')
             from conversation_participants p
            where p.conversation_id in (select conversation_id from direct_messages
                                         where id in ('dc000000-0000-0000-0000-0000000000d2',
                                                      'dc000000-0000-0000-0000-0000000000d4')))
     from direct_messages m
    where m.id in ('dc000000-0000-0000-0000-0000000000d2', 'dc000000-0000-0000-0000-0000000000d3',
                   'dc000000-0000-0000-0000-0000000000d4')),
  '2:dc000000-0000-0000-0000-00000000000d',
  'a deleted partner''s messages get one conversation per key, holding the sender alone');
select is(
  (select c.created_at from conversations c
     join direct_messages m on m.conversation_id = c.id
    where m.id = 'dc000000-0000-0000-0000-0000000000e1'),
  (select created_at from direct_messages where id = 'dc000000-0000-0000-0000-0000000000d1'),
  'a backfilled conversation starts at its first message');

-- A row neither branch can key (no recipient and no deleted-partner key) must
-- fail the migration, not reach 20271105000011's validation.
alter table direct_messages drop constraint direct_messages_audience_check;
insert into direct_messages (id, sender_id, recipient_id, deleted_partner_key, body) values
  ('dc000000-0000-0000-0000-0000000000d5', 'dc000000-0000-0000-0000-00000000000d', null, null, 'unkeyed');
select throws_ok(
  $$select private.backfill_direct_message_conversations()$$,
  '23502', null,
  'the backfill refuses to finish while a message is left without a conversation');

select ok(
  not exists (
    select 1 from unnest(array['anon', 'authenticated', 'service_role']) r
     where has_function_privilege(r, 'private.backfill_direct_message_conversations()', 'execute')
  ),
  'the conversation backfill is callable by no client role, service_role included');

select * from finish();
rollback;

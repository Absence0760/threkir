-- Pins 20271107000002 (PR #1289 item D, decisions § 2339): "Delete
-- conversation" stamps the newest message the deleter saw, not now(), and
-- never moves backwards; the daily purge erases a message once every person
-- it names has deleted the conversation past it, including a deleted
-- account's thread once its remaining participant deletes it; and a
-- conversation whose only messages were the leaver's is dropped with its
-- remaining participant row.
--
-- now() is the transaction's start for every statement here, so every
-- message is seeded as superuser with an explicit created_at.

begin;
select plan(22);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('df000000-0000-0000-0000-00000000000a', 'authenticated', 'authenticated', 'a@purgehidden.local', '', now(), now()),
  ('df000000-0000-0000-0000-00000000000b', 'authenticated', 'authenticated', 'b@purgehidden.local', '', now(), now()),
  ('df000000-0000-0000-0000-00000000000c', 'authenticated', 'authenticated', 'c@purgehidden.local', '', now(), now()),
  ('df000000-0000-0000-0000-00000000000d', 'authenticated', 'authenticated', 'd@purgehidden.local', '', now(), now()),
  ('df000000-0000-0000-0000-00000000000e', 'authenticated', 'authenticated', 'e@purgehidden.local', '', now(), now());

insert into user_follows (follower_id, followee_id) values
  ('df000000-0000-0000-0000-00000000000a', 'df000000-0000-0000-0000-00000000000b'),
  ('df000000-0000-0000-0000-00000000000c', 'df000000-0000-0000-0000-00000000000d'),
  ('df000000-0000-0000-0000-00000000000e', 'df000000-0000-0000-0000-00000000000c');

-- A <-> B. a1 and b1 are what A has on screen; b2 arrives during A's undo
-- window, after the newest message A saw.
insert into direct_messages (id, sender_id, recipient_id, body, created_at) values
  ('df000000-0000-0000-0000-0000000000a1', 'df000000-0000-0000-0000-00000000000a', 'df000000-0000-0000-0000-00000000000b', 'one',   now() - interval '3 hours'),
  ('df000000-0000-0000-0000-0000000000b1', 'df000000-0000-0000-0000-00000000000b', 'df000000-0000-0000-0000-00000000000a', 'two',   now() - interval '2 hours'),
  ('df000000-0000-0000-0000-0000000000b2', 'df000000-0000-0000-0000-00000000000b', 'df000000-0000-0000-0000-00000000000a', 'three', now() - interval '1 hour');

-- C <-> D: D will delete their account after both have written.
insert into direct_messages (id, sender_id, recipient_id, body, created_at) values
  ('df000000-0000-0000-0000-0000000000c1', 'df000000-0000-0000-0000-00000000000c', 'df000000-0000-0000-0000-00000000000d', 'to d',   now() - interval '3 hours'),
  ('df000000-0000-0000-0000-0000000000d1', 'df000000-0000-0000-0000-00000000000d', 'df000000-0000-0000-0000-00000000000c', 'from d', now() - interval '2 hours');

-- E -> C only: E will leave, and every message in the conversation is E's.
insert into direct_messages (id, sender_id, recipient_id, body, created_at) values
  ('df000000-0000-0000-0000-0000000000e1', 'df000000-0000-0000-0000-00000000000e', 'df000000-0000-0000-0000-00000000000c', 'only mine', now() - interval '1 hour');

create temporary table ab as
  select conversation_id as id from direct_messages where id = 'df000000-0000-0000-0000-0000000000a1';
create temporary table cd as
  select conversation_id as id from direct_messages where id = 'df000000-0000-0000-0000-0000000000c1';
create temporary table ec as
  select conversation_id as id from direct_messages where id = 'df000000-0000-0000-0000-0000000000e1';
grant select on ab, cd, ec to authenticated;

-- ── hidden_before is the newest message the deleter saw ─────────────────

select ok(
  not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'hide_conversation' and p.pronargs = 1
  ),
  'the now()-stamping one-argument hide_conversation is gone');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"df000000-0000-0000-0000-00000000000a","role":"authenticated"}';

select throws_ok(
  $$select hide_conversation((select id from ab), 'df000000-0000-0000-0000-0000000000c1')$$,
  'P0002', null,
  'a message from another conversation is refused as not found');
select lives_ok(
  $$select hide_conversation((select id from ab), 'df000000-0000-0000-0000-0000000000b1')$$,
  'A deletes the conversation through the newest message on their screen');
select is(
  (select array_agg(id order by created_at)::text from direct_messages where conversation_id = (select id from ab)),
  '{df000000-0000-0000-0000-0000000000b2}',
  'a message sent after the newest one A saw stays in A''s reads');
select is(
  (select last_body from dm_threads() where conversation_id = (select id from ab)),
  'three',
  'and keeps the conversation in A''s inbox');

reset role;
select is(
  (select hidden_before from conversation_participants
    where conversation_id = (select id from ab) and user_id = 'df000000-0000-0000-0000-00000000000a'),
  (select created_at from direct_messages where id = 'df000000-0000-0000-0000-0000000000b1'),
  'hidden_before is the seen message''s created_at, not now()');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"df000000-0000-0000-0000-00000000000a","role":"authenticated"}';
select lives_ok(
  $$select hide_conversation((select id from ab), 'df000000-0000-0000-0000-0000000000a1')$$,
  'a delete through an older message is accepted');
reset role;
select is(
  (select hidden_before from conversation_participants
    where conversation_id = (select id from ab) and user_id = 'df000000-0000-0000-0000-00000000000a'),
  (select created_at from direct_messages where id = 'df000000-0000-0000-0000-0000000000b1'),
  'but hidden_before never moves backwards');

-- ── The purge erases only what no participant can see ──────────────────

select private.purge_stale_direct_messages();
select is(
  (select count(*)::int from direct_messages where conversation_id = (select id from ab)),
  3,
  'one side''s delete erases nothing: B can still see every message');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"df000000-0000-0000-0000-00000000000b","role":"authenticated"}';
select lives_ok(
  $$select hide_conversation((select id from ab), 'df000000-0000-0000-0000-0000000000a1')$$,
  'B deletes the conversation through an earlier message');
reset role;

select private.purge_stale_direct_messages();
select is(
  (select array_agg(id order by created_at)::text from direct_messages where conversation_id = (select id from ab)),
  '{df000000-0000-0000-0000-0000000000b1,df000000-0000-0000-0000-0000000000b2}',
  'the purge erases the message both sides deleted and keeps the ones B can still see');
select is(
  (select count(*)::int from conversations where id = (select id from ab)),
  1,
  'a conversation with messages left is kept');

-- ── A deleted account's thread ──────────────────────────────────────────

delete from auth.users where id = 'df000000-0000-0000-0000-00000000000d';

select is(
  (select array_agg(id)::text from direct_messages where conversation_id = (select id from cd)),
  '{df000000-0000-0000-0000-0000000000c1}',
  'the leaver''s message goes with their account and the remaining sender''s stays');

select private.purge_stale_direct_messages();
select is(
  (select count(*)::int from direct_messages where id = 'df000000-0000-0000-0000-0000000000c1'),
  1,
  'the purge keeps a deleted account''s thread its remaining participant can still see');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"df000000-0000-0000-0000-00000000000c","role":"authenticated"}';
select isnt_empty(
  $$select 1 from dm_threads() where conversation_id = (select id from cd)$$,
  'the deleted account''s thread is in C''s inbox');
select lives_ok(
  $$select hide_conversation((select id from cd), 'df000000-0000-0000-0000-0000000000c1')$$,
  'C deletes the deleted account''s thread');
reset role;

select private.purge_stale_direct_messages();
select is(
  (select count(*)::int from direct_messages where id = 'df000000-0000-0000-0000-0000000000c1'),
  0,
  'the purge erases a deleted account''s thread once its remaining participant deletes it');
select is(
  (select count(*)::int from conversations where id = (select id from cd)),
  0,
  'and drops the conversation it emptied');
select is(
  (select count(*)::int from conversation_participants where conversation_id = (select id from cd)),
  0,
  'with the remaining participant''s row');

-- ── A conversation whose only messages were the leaver's ───────────────

delete from auth.users where id = 'df000000-0000-0000-0000-00000000000e';

select is(
  (select count(*)::int from direct_messages where conversation_id = (select id from ec)),
  0,
  'the leaver''s messages go with their account, leaving the conversation empty');

select private.purge_stale_direct_messages();
select is(
  (select count(*)::int from conversations where id = (select id from ec)),
  0,
  'the purge drops a conversation whose only messages were the leaver''s');
select is(
  (select count(*)::int from conversation_participants where conversation_id = (select id from ec)),
  0,
  'and the remaining participant''s row with it');

select * from finish();
rollback;

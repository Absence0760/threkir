-- Pins 20271021000003 (issue #1216): sender-only soft unsend with no client
-- hard-delete path, the recipient no longer able to rewrite a message,
-- recipient_id ON DELETE SET NULL keeping the remaining user's sent messages
-- under a per-partner key, dm_threads() over deleted partners + unsent
-- messages, and the direct_message report snapshot that survives an unsend and
-- the sender's account deletion.

begin;
select plan(32);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('d5000000-0000-0000-0000-00000000000a', 'authenticated', 'authenticated', 'a@unsend.local', '', now(), now()),
  ('d5000000-0000-0000-0000-00000000000b', 'authenticated', 'authenticated', 'b@unsend.local', '', now(), now()),
  ('d5000000-0000-0000-0000-00000000000c', 'authenticated', 'authenticated', 'c@unsend.local', '', now(), now()),
  ('d5000000-0000-0000-0000-00000000000d', 'authenticated', 'authenticated', 'd@unsend.local', '', now(), now());

-- A and B follow each other, so both may send.
insert into user_follows (follower_id, followee_id) values
  ('d5000000-0000-0000-0000-00000000000a', 'd5000000-0000-0000-0000-00000000000b'),
  ('d5000000-0000-0000-0000-00000000000b', 'd5000000-0000-0000-0000-00000000000a');

-- Seeded as superuser. m1/m2: A -> B. m3: B -> A. m4/m5: A -> C, A -> D (the
-- two partners who will delete their accounts).
insert into direct_messages (id, sender_id, recipient_id, body, created_at) values
  ('d5000000-0000-0000-0000-0000000000a1', 'd5000000-0000-0000-0000-00000000000a', 'd5000000-0000-0000-0000-00000000000b', 'first',  '2026-10-01T10:00:00Z'),
  ('d5000000-0000-0000-0000-0000000000a2', 'd5000000-0000-0000-0000-00000000000a', 'd5000000-0000-0000-0000-00000000000b', 'second', '2026-10-01T10:01:00Z'),
  ('d5000000-0000-0000-0000-0000000000b3', 'd5000000-0000-0000-0000-00000000000b', 'd5000000-0000-0000-0000-00000000000a', 'nasty',  '2026-10-01T10:02:00Z'),
  ('d5000000-0000-0000-0000-0000000000a4', 'd5000000-0000-0000-0000-00000000000a', 'd5000000-0000-0000-0000-00000000000c', 'to c',   '2026-10-02T10:00:00Z'),
  ('d5000000-0000-0000-0000-0000000000a5', 'd5000000-0000-0000-0000-00000000000a', 'd5000000-0000-0000-0000-00000000000d', 'to d',   '2026-10-03T10:00:00Z');

set local role authenticated;

-- ── No client hard delete, from either side ──────────────────────────────
set local "request.jwt.claims" = '{"sub":"d5000000-0000-0000-0000-00000000000b","role":"authenticated"}';
select throws_ok(
  $$delete from direct_messages where id = 'd5000000-0000-0000-0000-0000000000a1'$$,
  '42501', null,
  'the recipient cannot hard-delete the sender''s message');
select throws_ok(
  $$delete from direct_messages where id = 'd5000000-0000-0000-0000-0000000000b3'$$,
  '42501', null,
  'the sender cannot hard-delete their own message either — unsend is the only path');

-- ── The recipient cannot rewrite or unsend the sender's message ─────────
select throws_ok(
  $$update direct_messages set body = 'forged' where id = 'd5000000-0000-0000-0000-0000000000a1'$$,
  '42501', null,
  'the recipient cannot rewrite the sender''s body');
select throws_ok(
  $$update direct_messages set unsent_at = now(), body = null where id = 'd5000000-0000-0000-0000-0000000000a1'$$,
  '42501', null,
  'the recipient cannot stamp unsent_at on the sender''s message');
select lives_ok(
  $$update direct_messages set read_at = now() where id = 'd5000000-0000-0000-0000-0000000000a1'$$,
  'the recipient can still mark a message read');
select throws_ok(
  $$select unsend_direct_message('d5000000-0000-0000-0000-0000000000a2')$$,
  'P0002', null,
  'the recipient cannot unsend the sender''s message');

-- ── A send cannot pre-set the columns the server owns ────────────────────
select throws_ok(
  $$insert into direct_messages (sender_id, recipient_id, body, read_at)
    values ('d5000000-0000-0000-0000-00000000000b', 'd5000000-0000-0000-0000-00000000000a', 'pre-read', now())$$,
  '42501', null,
  'a send cannot arrive already read');
select throws_ok(
  $$insert into direct_messages (sender_id, recipient_id, body, created_at)
    values ('d5000000-0000-0000-0000-00000000000b', 'd5000000-0000-0000-0000-00000000000a', 'backdated', '2020-01-01')$$,
  '42501', null,
  'a send cannot be backdated');
select lives_ok(
  $$insert into direct_messages (sender_id, recipient_id, body)
    values ('d5000000-0000-0000-0000-00000000000b', 'd5000000-0000-0000-0000-00000000000a', 'ordinary send')$$,
  'an ordinary send still works through the column-scoped grant');

-- ── Reporting: only the recipient, and the report keeps a snapshot ───────
set local "request.jwt.claims" = '{"sub":"d5000000-0000-0000-0000-00000000000a","role":"authenticated"}';
select throws_ok(
  $$select submit_report('direct_message', 'd5000000-0000-0000-0000-0000000000a1', 'harassment', null)$$,
  '22023', 'submit_report: cannot report your own message',
  'a sender cannot report their own message');

set local "request.jwt.claims" = '{"sub":"d5000000-0000-0000-0000-00000000000c","role":"authenticated"}';
select throws_ok(
  $$select submit_report('direct_message', 'd5000000-0000-0000-0000-0000000000b3', 'harassment', null)$$,
  '02000', null,
  'a non-participant cannot report (and so cannot snapshot) someone else''s message');

set local "request.jwt.claims" = '{"sub":"d5000000-0000-0000-0000-00000000000a","role":"authenticated"}';
select lives_ok(
  $$select submit_report('direct_message', 'd5000000-0000-0000-0000-0000000000b3', 'harassment', 'threatening')$$,
  'the recipient can report the message');
select is(
  (select snapshot_body from reports
    where target_kind = 'direct_message' and target_id = 'd5000000-0000-0000-0000-0000000000b3'),
  'nasty',
  'the report snapshots the body');
select is(
  (select snapshot_author_id from reports
    where target_kind = 'direct_message' and target_id = 'd5000000-0000-0000-0000-0000000000b3'),
  'd5000000-0000-0000-0000-00000000000b'::uuid,
  'the report snapshots the sender');
select is(
  (select snapshot_sent_at from reports
    where target_kind = 'direct_message' and target_id = 'd5000000-0000-0000-0000-0000000000b3'),
  '2026-10-01T10:02:00Z'::timestamptz,
  'the report snapshots when it was sent');
select throws_ok(
  $$select submit_report('direct_message', 'd5000000-0000-0000-0000-0000000000b3', 'spam', null)$$,
  '23505', null,
  'a second pending report on the same message is refused');

-- ── Sender-only unsend ───────────────────────────────────────────────────
set local "request.jwt.claims" = '{"sub":"d5000000-0000-0000-0000-00000000000b","role":"authenticated"}';
select is(
  (select unsent_at is not null and body is null and route_id is null
     from unsend_direct_message('d5000000-0000-0000-0000-0000000000b3')),
  true,
  'the sender unsends: body + attachment cleared, unsent_at stamped');
select lives_ok(
  $$select unsend_direct_message('d5000000-0000-0000-0000-0000000000b3')$$,
  'unsending twice is idempotent');
select throws_ok(
  $$select unsend_direct_message('d5000000-0000-0000-0000-0000000000ff')$$,
  'P0002', null,
  'unsending a message that does not exist answers not-found');

set local "request.jwt.claims" = '{"sub":"d5000000-0000-0000-0000-00000000000a","role":"authenticated"}';
select is(
  (select count(*)::int from direct_messages
    where id = 'd5000000-0000-0000-0000-0000000000b3' and body is null and unsent_at is not null),
  1,
  'the recipient still sees the row, as unsent (the placeholder''s source)');
select is(
  (select snapshot_body from reports
    where target_kind = 'direct_message' and target_id = 'd5000000-0000-0000-0000-0000000000b3'),
  'nasty',
  'the unsend did not touch the report snapshot');

-- A fresh unread message, then unsent: it must not count as unread.
set local role postgres;
insert into direct_messages (id, sender_id, recipient_id, body, created_at) values
  ('d5000000-0000-0000-0000-0000000000b6', 'd5000000-0000-0000-0000-00000000000b', 'd5000000-0000-0000-0000-00000000000a', 'oops', now() + interval '1 minute');
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"d5000000-0000-0000-0000-00000000000b","role":"authenticated"}';
select lives_ok(
  $$select unsend_direct_message('d5000000-0000-0000-0000-0000000000b6')$$,
  'the sender unsends a message the recipient has not read');

set local "request.jwt.claims" = '{"sub":"d5000000-0000-0000-0000-00000000000a","role":"authenticated"}';
select throws_ok(
  $$select submit_report('direct_message', 'd5000000-0000-0000-0000-0000000000b6', 'spam', null)$$,
  '22023', 'submit_report: message was unsent',
  'an unsent message has nothing left to report');
select is(
  (select last_unsent from dm_threads() where partner_id = 'd5000000-0000-0000-0000-00000000000b'),
  true,
  'dm_threads flags an unsent latest message');
select is(
  (select last_body from dm_threads() where partner_id = 'd5000000-0000-0000-0000-00000000000b'),
  null,
  'an unsent latest message carries no preview body');
select is(
  (select unread from dm_threads() where partner_id = 'd5000000-0000-0000-0000-00000000000b'),
  1::bigint,
  'an unsent message is not unread (only the ordinary send is)');

-- ── Account deletion keeps the remaining user's sent messages ────────────
set local role postgres;
delete from auth.users where id in (
  'd5000000-0000-0000-0000-00000000000b',
  'd5000000-0000-0000-0000-00000000000c',
  'd5000000-0000-0000-0000-00000000000d');

select is(
  (select count(*)::int from direct_messages where sender_id = 'd5000000-0000-0000-0000-00000000000a'),
  4,
  'every message the remaining user sent survives their partners'' deletion');
select is(
  (select count(*)::int from direct_messages where id in (
     'd5000000-0000-0000-0000-0000000000b3', 'd5000000-0000-0000-0000-0000000000b6')),
  0,
  'the leaver''s own sent messages are erased');
select is(
  (select count(distinct deleted_partner_key)::int from direct_messages
    where sender_id = 'd5000000-0000-0000-0000-00000000000a' and recipient_id is null),
  3,
  'each deleted partner gets its own conversation key');
select is(
  (select snapshot_body from reports
    where target_kind = 'direct_message' and target_id = 'd5000000-0000-0000-0000-0000000000b3'),
  'nasty',
  'the report snapshot outlives the sender''s account deletion');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"d5000000-0000-0000-0000-00000000000a","role":"authenticated"}';
select is(
  (select count(*)::int from dm_threads() where partner_id is null and deleted_partner_key is not null),
  3,
  'dm_threads lists each deleted partner as its own thread');
select is(
  (select last_body from dm_threads()
    where deleted_partner_key = (select deleted_partner_key from direct_messages
                                  where id = 'd5000000-0000-0000-0000-0000000000a2')),
  'second',
  'a deleted partner''s thread previews the remaining user''s latest message');

select * from finish();
rollback;

-- Pins 20271114000210 (issue #1216, decisions § 2373): the sender may edit a
-- live message within 15 minutes, nobody else may, and no client can write
-- the body directly. The first edit keeps the text as sent in original_body,
-- which no client can read, a report snapshots it, and unsend erases it.

begin;
select plan(32);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('e2000000-0000-0000-0000-00000000000a', 'authenticated', 'authenticated', 'a@dmedit.local', '', now(), now()),
  ('e2000000-0000-0000-0000-00000000000b', 'authenticated', 'authenticated', 'b@dmedit.local', '', now(), now()),
  ('e2000000-0000-0000-0000-00000000000c', 'authenticated', 'authenticated', 'c@dmedit.local', '', now(), now()),
  ('e2000000-0000-0000-0000-00000000000d', 'authenticated', 'authenticated', 'admin@dmedit.local', '', now(), now());

insert into app_admins (user_id) values ('e2000000-0000-0000-0000-00000000000d');

insert into user_follows (follower_id, followee_id) values
  ('e2000000-0000-0000-0000-00000000000a', 'e2000000-0000-0000-0000-00000000000b'),
  ('e2000000-0000-0000-0000-00000000000a', 'e2000000-0000-0000-0000-00000000000c');

-- Seeded as superuser. A -> B: a1 fresh, a2 fresh (to be unsent), a3 sent 20
-- minutes ago (past the window), a4 fresh (to be edited then reported).
-- A -> C: c1 fresh (C will block A).
insert into direct_messages (id, sender_id, recipient_id, body, created_at) values
  ('e2000000-0000-0000-0000-0000000000a1', 'e2000000-0000-0000-0000-00000000000a', 'e2000000-0000-0000-0000-00000000000b', 'see you at 7',   now() - interval '1 minute'),
  ('e2000000-0000-0000-0000-0000000000a2', 'e2000000-0000-0000-0000-00000000000a', 'e2000000-0000-0000-0000-00000000000b', 'to be unsent',   now() - interval '1 minute'),
  ('e2000000-0000-0000-0000-0000000000a3', 'e2000000-0000-0000-0000-00000000000a', 'e2000000-0000-0000-0000-00000000000b', 'old news',       now() - interval '20 minutes'),
  ('e2000000-0000-0000-0000-0000000000a4', 'e2000000-0000-0000-0000-00000000000a', 'e2000000-0000-0000-0000-00000000000b', 'something nasty', now() - interval '1 minute'),
  ('e2000000-0000-0000-0000-0000000000c1', 'e2000000-0000-0000-0000-00000000000a', 'e2000000-0000-0000-0000-00000000000c', 'hi c',           now() - interval '1 minute');

-- ── Grants ──────────────────────────────────────────────────────────────

select ok(
  has_column_privilege('authenticated', 'public.direct_messages', 'edited_at', 'SELECT'),
  'authenticated can select direct_messages.edited_at');
select ok(
  not has_column_privilege('authenticated', 'public.direct_messages', 'original_body', 'SELECT'),
  'authenticated cannot select direct_messages.original_body');
select ok(
  not has_column_privilege('authenticated', 'public.direct_messages', 'body', 'UPDATE'),
  'a client cannot update body directly; the RPC is the only edit path');
select throws_ok(
  $$select edit_direct_message('e2000000-0000-0000-0000-0000000000a1', 'x')$$,
  '42501', null,
  'edit_direct_message refuses a caller with no session');

set local role authenticated;

-- ── The sender, inside the window ───────────────────────────────────────
set local "request.jwt.claims" = '{"sub":"e2000000-0000-0000-0000-00000000000a","role":"authenticated"}';

select is(
  (select body from edit_direct_message('e2000000-0000-0000-0000-0000000000a1', '  see you at 7:30  ')),
  'see you at 7:30',
  'the sender edits a fresh message and gets the trimmed text back');
select is(
  (select body from direct_messages where id = 'e2000000-0000-0000-0000-0000000000a1'),
  'see you at 7:30',
  'the edit is stored');
select ok(
  (select edited_at is not null from direct_messages where id = 'e2000000-0000-0000-0000-0000000000a1'),
  'the edit stamps edited_at');
select ok(
  (select original_body is null and read_at is null
     from edit_direct_message('e2000000-0000-0000-0000-0000000000a1', 'see you at 7:45')),
  'the returned row carries neither original_body nor read_at');
select throws_ok(
  $$select original_body from direct_messages where id = 'e2000000-0000-0000-0000-0000000000a1'$$,
  '42501', null,
  'the sender cannot select original_body');

-- ── Refusals ────────────────────────────────────────────────────────────

select throws_ok(
  $$select edit_direct_message('e2000000-0000-0000-0000-0000000000a3', 'fresh news')$$,
  '55000', 'edit_direct_message: message can no longer be edited',
  'the sender cannot edit a message past the 15-minute window');
select is(
  (select body from direct_messages where id = 'e2000000-0000-0000-0000-0000000000a3'),
  'old news',
  'the message past the window is visible to the sender and unchanged');

select lives_ok(
  $$select unsend_direct_message('e2000000-0000-0000-0000-0000000000a2')$$,
  'the sender unsends a2');
select throws_ok(
  $$select edit_direct_message('e2000000-0000-0000-0000-0000000000a2', 'back again')$$,
  '55000', 'edit_direct_message: message can no longer be edited',
  'an unsent message cannot be edited');
select ok(
  (select body is null and unsent_at is not null from direct_messages where id = 'e2000000-0000-0000-0000-0000000000a2'),
  'the unsent message stays unsent with no body');

select throws_ok(
  $$select edit_direct_message('e2000000-0000-0000-0000-0000000000a1', '   ')$$,
  '22023', null,
  'a blank body is refused');
select throws_ok(
  $$select edit_direct_message('e2000000-0000-0000-0000-0000000000a1', repeat('x', 4001))$$,
  '22023', null,
  'a body over 4000 characters is refused');

-- The recipient, B.
set local "request.jwt.claims" = '{"sub":"e2000000-0000-0000-0000-00000000000b","role":"authenticated"}';
select is(
  (select body from direct_messages where id = 'e2000000-0000-0000-0000-0000000000a1'),
  'see you at 7:45',
  'the recipient sees the edited text');
select ok(
  (select edited_at is not null from direct_messages where id = 'e2000000-0000-0000-0000-0000000000a1'),
  'the recipient sees the edited mark');
select throws_ok(
  $$select edit_direct_message('e2000000-0000-0000-0000-0000000000a1', 'forged')$$,
  'P0002', 'edit_direct_message: message not found',
  'the recipient cannot edit the sender''s message');

-- A third party, C, who can see none of A -> B.
set local "request.jwt.claims" = '{"sub":"e2000000-0000-0000-0000-00000000000c","role":"authenticated"}';
select throws_ok(
  $$select edit_direct_message('e2000000-0000-0000-0000-0000000000a1', 'forged')$$,
  'P0002', 'edit_direct_message: message not found',
  'a third party cannot edit the message');

-- C blocks A: A can no longer edit what A sent C.
select lives_ok(
  $$select block_user('e2000000-0000-0000-0000-00000000000a')$$,
  'C blocks A');
select isnt_empty(
  $$select 1 from user_blocks
     where blocker_id = 'e2000000-0000-0000-0000-00000000000c'
       and blocked_id = 'e2000000-0000-0000-0000-00000000000a'$$,
  'C reads back the block');
set local "request.jwt.claims" = '{"sub":"e2000000-0000-0000-0000-00000000000a","role":"authenticated"}';
select throws_ok(
  $$select edit_direct_message('e2000000-0000-0000-0000-0000000000c1', 'changed after the block')$$,
  '55000', 'edit_direct_message: message can no longer be edited',
  'a sender cannot edit a message once either side has blocked the other');
select is(
  (select body from direct_messages where id = 'e2000000-0000-0000-0000-0000000000c1'),
  'hi c',
  'the blocked message is visible to the sender and unchanged');

-- ── The text as sent survives the edits and reaches a report ────────────

select lives_ok(
  $$select edit_direct_message('e2000000-0000-0000-0000-0000000000a4', 'something nice')$$,
  'the sender edits a4 once');
select lives_ok(
  $$select edit_direct_message('e2000000-0000-0000-0000-0000000000a4', 'something kind')$$,
  'and again');

set local "request.jwt.claims" = '{"sub":"e2000000-0000-0000-0000-00000000000b","role":"authenticated"}';
select lives_ok(
  $$select submit_report('direct_message', 'e2000000-0000-0000-0000-0000000000a4', 'harassment', null)$$,
  'the recipient reports the edited message');
select is(
  (select snapshot_body || ' / ' || snapshot_original_body from reports
    where target_kind = 'direct_message' and target_id = 'e2000000-0000-0000-0000-0000000000a4'),
  'something kind / something nasty',
  'the report snapshots the latest text and the text as first sent');

set local "request.jwt.claims" = '{"sub":"e2000000-0000-0000-0000-00000000000d","role":"authenticated"}';
select is(
  (select snapshot_original_body from fetch_reports_for_target('direct_message', 'e2000000-0000-0000-0000-0000000000a4')),
  'something nasty',
  'the moderator sees the text as first sent');

-- ── Unsend erases the text as sent; the report keeps its snapshot ───────

set local "request.jwt.claims" = '{"sub":"e2000000-0000-0000-0000-00000000000a","role":"authenticated"}';
select lives_ok(
  $$select unsend_direct_message('e2000000-0000-0000-0000-0000000000a4')$$,
  'the sender unsends the edited message');

reset role;
select ok(
  (select body is null and original_body is null from direct_messages where id = 'e2000000-0000-0000-0000-0000000000a4'),
  'unsend nulls original_body as well as body');
select is(
  (select snapshot_original_body from reports
    where target_kind = 'direct_message' and target_id = 'e2000000-0000-0000-0000-0000000000a4'),
  'something nasty',
  'the report keeps the text as first sent after the unsend');

select * from finish();
rollback;

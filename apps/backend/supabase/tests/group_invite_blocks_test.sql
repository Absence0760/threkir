-- Pins 20271224000400 (audit of PR #1359, Low): a block withdraws the pending
-- group invites between the pair, and an invite across a block cannot be
-- accepted.
--
--   1-3.  The invitee blocks the inviter: the invite is withdrawn as their own
--         refusal, it no longer lists, and accepting it is refused.
--   4-5.  The inviter blocks the invitee: the invite is withdrawn as the
--         inviter's, and accepting it is refused.
--   6.    An invite still standing across a block (the trigger off, as for a
--         row an older release let through) cannot be accepted.
--   7-8.  An invite between people who did not block each other still accepts.

begin;
select plan(8);

insert into private.feature_flags (name, enabled) values ('group_messages', true)
on conflict (name) do update set enabled = true;

insert into auth.users (id, email, encrypted_password, email_confirmed_at, instance_id, aud, role)
select ('b2400000-0000-0000-0000-0000000000' || s)::uuid, 'gib-' || s || '@example.com', '', now(),
       '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'
  from unnest(array['a0', 'a1', 'a2', 'a3', 'a4']) as s;

-- a0 invites; it follows the four invitees, so it may message each 1:1.
insert into user_follows (follower_id, followee_id)
select 'b2400000-0000-0000-0000-0000000000a0', ('b2400000-0000-0000-0000-0000000000' || s)::uuid
  from unnest(array['a1', 'a2', 'a3', 'a4']) as s;

create temporary table g (id uuid);
grant all on g to authenticated;

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"b2400000-0000-0000-0000-0000000000a0","role":"authenticated"}';
insert into g select create_group_conversation('Track Tuesday',
  array['b2400000-0000-0000-0000-0000000000a1', 'b2400000-0000-0000-0000-0000000000a2',
        'b2400000-0000-0000-0000-0000000000a3', 'b2400000-0000-0000-0000-0000000000a4']::uuid[]);

-- ── 1-3: the invitee blocks the inviter ──────────────────────────────────────
set local "request.jwt.claims" = '{"sub":"b2400000-0000-0000-0000-0000000000a1","role":"authenticated"}';
select block_user('b2400000-0000-0000-0000-0000000000a0');

reset role;
select is(
  (select membership_state || '|' || coalesce(removed_by::text, '-') from conversation_participants
    where conversation_id = (select id from g) and user_id = 'b2400000-0000-0000-0000-0000000000a1'),
  'left|-',
  'blocking the inviter withdraws the invite as the invitee''s own refusal');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"b2400000-0000-0000-0000-0000000000a1","role":"authenticated"}';
select is_empty(
  $$ select 1 from group_invites() where conversation_id = (select id from g) $$,
  'the withdrawn invite no longer lists for the invitee');
select throws_ok(
  $$ select accept_group_invite((select id from g)) $$,
  'P0002', 'accept_group_invite: invite not found',
  'the invitee cannot accept an invite from someone they blocked');

-- ── 4-5: the inviter blocks the invitee ──────────────────────────────────────
set local "request.jwt.claims" = '{"sub":"b2400000-0000-0000-0000-0000000000a0","role":"authenticated"}';
select block_user('b2400000-0000-0000-0000-0000000000a2');

reset role;
select is(
  (select membership_state || '|' || coalesce(removed_by::text, '-') from conversation_participants
    where conversation_id = (select id from g) and user_id = 'b2400000-0000-0000-0000-0000000000a2'),
  'left|b2400000-0000-0000-0000-0000000000a0',
  'blocking the invitee withdraws the invite as the inviter''s');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"b2400000-0000-0000-0000-0000000000a2","role":"authenticated"}';
select throws_ok(
  $$ select accept_group_invite((select id from g)) $$,
  'P0002', 'accept_group_invite: invite not found',
  'the blocked invitee cannot accept');

-- ── 6: an invite standing across a block ─────────────────────────────────────
reset role;
alter table user_blocks disable trigger user_blocks_withdraw_group_invites;
insert into user_blocks (blocker_id, blocked_id)
values ('b2400000-0000-0000-0000-0000000000a3', 'b2400000-0000-0000-0000-0000000000a0');
alter table user_blocks enable trigger user_blocks_withdraw_group_invites;

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"b2400000-0000-0000-0000-0000000000a3","role":"authenticated"}';
select throws_ok(
  $$ select accept_group_invite((select id from g)) $$,
  'P0002', 'accept_group_invite: invite not found',
  'an invite left standing across a block cannot be accepted');

-- ── 7: no block, no change ───────────────────────────────────────────────────
set local "request.jwt.claims" = '{"sub":"b2400000-0000-0000-0000-0000000000a4","role":"authenticated"}';
select lives_ok(
  $$ select accept_group_invite((select id from g)) $$,
  'an invite between people who did not block each other still accepts');

reset role;
select is(
  (select membership_state from conversation_participants
    where conversation_id = (select id from g) and user_id = 'b2400000-0000-0000-0000-0000000000a4'),
  'active',
  'the unblocked invitee is now a member');

select * from finish();
rollback;

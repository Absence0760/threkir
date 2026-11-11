-- Pins migrations 20271217000001-6 (issue #1365 slice 2, decisions § 2463):
-- the group message and group_invite notifications (mute, block, invitee,
-- leaver, burst, flag), the rename system line (written by rename_group only,
-- never editable or forgeable, read inside the window), the blocked-sender
-- placeholders (the blocker's alone, no body, nothing to anyone else), the
-- admin reports queue's conversation lookup, the flag gate on dm_threads() and
-- group_invites(), and the notification cascade with the conversation.

begin;
select plan(38);

insert into private.feature_flags (name, enabled) values ('group_messages', true)
on conflict (name) do update set enabled = true;

-- c1 owner, c2..c7 people c1 follows; c8 an app admin.
insert into auth.users (id, email, encrypted_password, email_confirmed_at, instance_id, aud, role)
select ('b1365200-0000-0000-0000-0000000000' || s)::uuid, 'gm2-' || s || '@example.com', '', now(),
       '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'
  from unnest(array['c1', 'c2', 'c3', 'c4', 'c5', 'c6', 'c7', 'c8']) as s
on conflict (id) do nothing;

insert into user_follows (follower_id, followee_id)
select 'b1365200-0000-0000-0000-0000000000c1'::uuid, u.id
  from auth.users u
 where u.id::text like 'b1365200-0000-0000-0000-%'
   and u.id <> 'b1365200-0000-0000-0000-0000000000c1'
on conflict do nothing;
insert into app_admins (user_id) values ('b1365200-0000-0000-0000-0000000000c8') on conflict do nothing;

-- now() is the transaction's start throughout, so every stamp below is equal
-- unless backdated; the window tests backdate what came first.
create temporary table g (k text primary key, id uuid);
grant all on g to authenticated, anon;

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"b1365200-0000-0000-0000-0000000000c1","role":"authenticated"}';

insert into g values ('main', create_group_conversation('Tuesday tempo',
  array['b1365200-0000-0000-0000-0000000000c2', 'b1365200-0000-0000-0000-0000000000c3',
        'b1365200-0000-0000-0000-0000000000c4', 'b1365200-0000-0000-0000-0000000000c5',
        'b1365200-0000-0000-0000-0000000000c6']::uuid[]));

-- ── group_invite notifications ──

reset role;
select is(
  (select count(*)::integer from notifications
    where kind = 'group_invite' and conversation_id = (select id from g where k = 'main')
      and actor_id = 'b1365200-0000-0000-0000-0000000000c1'),
  5,
  'creating a group raises one group_invite notice per invitee, naming the inviter and the group');
select is(
  (select count(*)::integer from notifications
    where kind = 'group_invite' and user_id = 'b1365200-0000-0000-0000-0000000000c1'),
  0,
  'the inviter is not notified of their own invites');

-- c2, c3, c4, c5 accept; c6 stays invited. c3 mutes. c4 blocks c2.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"b1365200-0000-0000-0000-0000000000c2","role":"authenticated"}';
select accept_group_invite((select id from g where k = 'main'));
set local "request.jwt.claims" = '{"sub":"b1365200-0000-0000-0000-0000000000c3","role":"authenticated"}';
select accept_group_invite((select id from g where k = 'main'));
select set_conversation_muted((select id from g where k = 'main'), true);
set local "request.jwt.claims" = '{"sub":"b1365200-0000-0000-0000-0000000000c4","role":"authenticated"}';
select accept_group_invite((select id from g where k = 'main'));
set local "request.jwt.claims" = '{"sub":"b1365200-0000-0000-0000-0000000000c5","role":"authenticated"}';
select accept_group_invite((select id from g where k = 'main'));
select leave_conversation((select id from g where k = 'main'));

reset role;
update conversation_participants set joined_at = now() - interval '1 hour'
 where conversation_id = (select id from g where k = 'main') and membership_state = 'active';
insert into user_blocks (blocker_id, blocked_id)
values ('b1365200-0000-0000-0000-0000000000c4', 'b1365200-0000-0000-0000-0000000000c2');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"b1365200-0000-0000-0000-0000000000c1","role":"authenticated"}';
select lives_ok(
  $$select invite_to_group((select id from g where k = 'main'), array['b1365200-0000-0000-0000-0000000000c7']::uuid[])$$,
  'the owner invites one more');
reset role;
select is(
  (select count(*)::integer from notifications
    where kind = 'group_invite' and user_id = 'b1365200-0000-0000-0000-0000000000c7'
      and conversation_id = (select id from g where k = 'main')),
  1,
  'invite_to_group notifies the invitee once');

-- ── group message notifications ──

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"b1365200-0000-0000-0000-0000000000c2","role":"authenticated"}';
insert into direct_messages (sender_id, conversation_id, body)
values ('b1365200-0000-0000-0000-0000000000c2', (select id from g where k = 'main'), 'first from c2');

reset role;
insert into g select 'c2_first', id from direct_messages where body = 'first from c2';
update direct_messages set created_at = now() - interval '2 minutes' where body = 'first from c2';
select is(
  (select string_agg(user_id::text, ',' order by user_id) from notifications
    where kind = 'message' and conversation_id = (select id from g where k = 'main')),
  'b1365200-0000-0000-0000-0000000000c1',
  'a group message notifies only the active, unmuted members who do not block its sender (c4 blocked c2 and is not told of a message they cannot read)');
select ok(
  (select actor_id = 'b1365200-0000-0000-0000-0000000000c2' from notifications
    where kind = 'message' and conversation_id = (select id from g where k = 'main')),
  'the notice names the sender as its actor');
select is(
  (select count(*)::integer from notifications
    where kind = 'message' and user_id = 'b1365200-0000-0000-0000-0000000000c3'),
  0, 'a member who muted the group is not notified');
select is(
  (select count(*)::integer from notifications
    where kind = 'message' and user_id in ('b1365200-0000-0000-0000-0000000000c6',
                                           'b1365200-0000-0000-0000-0000000000c7')),
  0, 'an invitee is not notified');
select is(
  (select count(*)::integer from notifications
    where kind = 'message' and user_id = 'b1365200-0000-0000-0000-0000000000c5'),
  0, 'a member who left is not notified');
select is(
  (select count(*)::integer from notifications
    where kind = 'message' and user_id = 'b1365200-0000-0000-0000-0000000000c2'),
  0, 'the sender is not notified of their own message');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"b1365200-0000-0000-0000-0000000000c2","role":"authenticated"}';
insert into direct_messages (sender_id, conversation_id, body)
values ('b1365200-0000-0000-0000-0000000000c2', (select id from g where k = 'main'), 'second from c2');
reset role;
select is(
  (select count(*)::integer from notifications
    where kind = 'message' and user_id = 'b1365200-0000-0000-0000-0000000000c1'
      and conversation_id = (select id from g where k = 'main')),
  1, 'a second message while the first notice is unread raises no second notice');

update notifications set read_at = now()
 where kind = 'message' and user_id = 'b1365200-0000-0000-0000-0000000000c1';
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"b1365200-0000-0000-0000-0000000000c4","role":"authenticated"}';
insert into direct_messages (sender_id, conversation_id, body)
values ('b1365200-0000-0000-0000-0000000000c4', (select id from g where k = 'main'), 'from c4');
reset role;
insert into g select 'c2_second', id from direct_messages where body = 'second from c2';
insert into g select 'c4_msg', id from direct_messages where body = 'from c4';
select is(
  (select string_agg(user_id::text, ',' order by user_id) from notifications
    where kind = 'message' and read_at is null and conversation_id = (select id from g where k = 'main')),
  'b1365200-0000-0000-0000-0000000000c1,b1365200-0000-0000-0000-0000000000c2',
  'once the notice is read the next message notifies again, and a blocked member is still told of the blocker''s message');

update private.feature_flags set enabled = false where name = 'group_messages';
update notifications set read_at = now() where conversation_id = (select id from g where k = 'main');
insert into direct_messages (sender_id, conversation_id, body)
values ('b1365200-0000-0000-0000-0000000000c1', (select id from g where k = 'main'), 'flag off');
select is(
  (select count(*)::integer from notifications
    where kind = 'message' and read_at is null and conversation_id = (select id from g where k = 'main')),
  0, 'no group message notice while the flag is off');

-- ── the flag gate on the inbox and the invites ──

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"b1365200-0000-0000-0000-0000000000c1","role":"authenticated"}';
select is(
  (select count(*)::integer from dm_threads() where kind = 'group'),
  0, 'dm_threads lists no group while the flag is off');
set local "request.jwt.claims" = '{"sub":"b1365200-0000-0000-0000-0000000000c6","role":"authenticated"}';
select is(
  (select count(*)::integer from group_invites()),
  0, 'group_invites lists nothing while the flag is off');
reset role;
update private.feature_flags set enabled = true where name = 'group_messages';
set local role authenticated;
select is(
  (select title from group_invites()),
  'Tuesday tempo', 'with the flag on the invitee sees the invite');
set local "request.jwt.claims" = '{"sub":"b1365200-0000-0000-0000-0000000000c1","role":"authenticated"}';
select is(
  (select title || '|' || member_count from dm_threads() where kind = 'group'),
  'Tuesday tempo|4', 'with the flag on the group is in the inbox');

-- ── the rename system line ──

set local "request.jwt.claims" = '{"sub":"b1365200-0000-0000-0000-0000000000c2","role":"authenticated"}';
select throws_ok(
  $$select rename_group((select id from g where k = 'main'), 'Mine now')$$,
  '42501', null, 'a member who is not an admin cannot rename');
select throws_ok(
  $$insert into direct_messages (sender_id, conversation_id, body, kind)
    values ('b1365200-0000-0000-0000-0000000000c2', (select id from g where k = 'main'), 'c2 renamed the group', 'group_renamed')$$,
  '42501', null, 'a client cannot write a rename line of its own');

set local "request.jwt.claims" = '{"sub":"b1365200-0000-0000-0000-0000000000c1","role":"authenticated"}';
select lives_ok(
  $$select rename_group((select id from g where k = 'main'), '  Thursday tempo  ')$$,
  'the owner renames');
select lives_ok(
  $$select rename_group((select id from g where k = 'main'), 'Thursday tempo')$$,
  'renaming to the same title is a no-op');

reset role;
select is(
  (select count(*)::integer || '|' || min(body) || '|' || bool_and(is_group)::text || '|' || min(sender_id::text)
     from direct_messages
    where conversation_id = (select id from g where k = 'main') and kind = 'group_renamed'),
  '1|Thursday tempo|true|b1365200-0000-0000-0000-0000000000c1',
  'one rename line, as the renamer, carrying the trimmed new title');
select is(
  (select count(*)::integer from notifications
    where kind = 'message' and read_at is null and conversation_id = (select id from g where k = 'main')),
  0, 'a rename line notifies nobody');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"b1365200-0000-0000-0000-0000000000c2","role":"authenticated"}';
select is(
  (select body from direct_messages
    where conversation_id = (select id from g where k = 'main') and kind = 'group_renamed'),
  'Thursday tempo', 'a member reads the rename line');
set local "request.jwt.claims" = '{"sub":"b1365200-0000-0000-0000-0000000000c1","role":"authenticated"}';
select throws_ok(
  $$select edit_direct_message(
      (select id from direct_messages where conversation_id = (select id from g where k = 'main') and kind = 'group_renamed'),
      'c1 handed the group to nobody')$$,
  '55000', null, 'the rename line cannot be edited into other words');

-- A late joiner does not read the rename from before they joined.
reset role;
update direct_messages set created_at = now() - interval '1 minute'
 where conversation_id = (select id from g where k = 'main') and kind = 'group_renamed';
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"b1365200-0000-0000-0000-0000000000c7","role":"authenticated"}';
select accept_group_invite((select id from g where k = 'main'));
select is(
  (select count(*)::integer from direct_messages
    where conversation_id = (select id from g where k = 'main') and kind = 'group_renamed'),
  0, 'a member who joined after the rename does not read its line');
select is(
  (select title from dm_threads() where kind = 'group'),
  'Thursday tempo', 'but the inbox carries the current title');

-- ── blocked placeholders ──

-- c4 blocked c2, who sent two messages; c4 joined before both.
set local "request.jwt.claims" = '{"sub":"b1365200-0000-0000-0000-0000000000c4","role":"authenticated"}';
select is(
  (select count(*)::integer from direct_messages
    where conversation_id = (select id from g where k = 'main')
      and sender_id = 'b1365200-0000-0000-0000-0000000000c2'),
  0, 'the blocker does not read the blocked member''s messages');
select is(
  (select count(*)::integer from group_blocked_placeholders((select id from g where k = 'main'), null)),
  2, 'the blocker gets one placeholder per message they do not read');
select ok(
  (select array_agg(p.id order by p.id) = (select array_agg(id order by id) from g where k in ('c2_first', 'c2_second'))
     from group_blocked_placeholders((select id from g where k = 'main'), null) p),
  'each placeholder stands in for a blocked member''s message');
select is(
  pg_get_function_result('public.group_blocked_placeholders(uuid, timestamptz)'::regprocedure),
  'TABLE(id uuid, created_at timestamp with time zone)',
  'a placeholder carries an id and a time, never a body or a sender');
select is(
  (select count(*)::integer from group_blocked_placeholders(
     (select id from g where k = 'main'),
     now() - interval '1 minute')),
  1, 'p_since bounds the placeholders to the page on screen');

set local "request.jwt.claims" = '{"sub":"b1365200-0000-0000-0000-0000000000c1","role":"authenticated"}';
select is(
  (select count(*)::integer from group_blocked_placeholders((select id from g where k = 'main'), null)),
  0, 'a member who blocked nobody gets no placeholder');
set local "request.jwt.claims" = '{"sub":"b1365200-0000-0000-0000-0000000000c2","role":"authenticated"}';
select is(
  (select count(*)::integer from group_blocked_placeholders((select id from g where k = 'main'), null)),
  0, 'the blocked member is told nothing');
set local "request.jwt.claims" = '{"sub":"b1365200-0000-0000-0000-0000000000c5","role":"authenticated"}';
select throws_ok(
  $$select * from group_blocked_placeholders((select id from g where k = 'main'), null)$$,
  'P0002', null, 'someone who left gets the uniform not-found');

-- ── the admin reports queue ──

select throws_ok(
  $$select * from admin_report_conversation((select id from g where k = 'c4_msg'))$$,
  '42501', null, 'only a site admin looks up a reported message''s conversation');
set local "request.jwt.claims" = '{"sub":"b1365200-0000-0000-0000-0000000000c8","role":"authenticated"}';
select is(
  (select kind || '|' || title || '|' || member_count from admin_report_conversation(
     (select id from g where k = 'c4_msg'))),
  'group|Thursday tempo|5', 'a site admin sees the group a reported message went to');

-- ── the cascade ──

-- The purge erases a group's messages and then the group.
reset role;
delete from direct_messages where conversation_id = (select id from g where k = 'main');
delete from conversations where id = (select id from g where k = 'main');
select is(
  (select count(*)::integer from notifications
    where user_id::text like 'b1365200-0000-0000-0000-%' and kind in ('message', 'group_invite')),
  0, 'a group''s notices go with it');

select * from finish();
rollback;

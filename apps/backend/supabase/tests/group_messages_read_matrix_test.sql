-- Pins migrations 20271216000006 / 07 (issue #1365, decisions § 2461, security
-- memo C1/C2): every way to read or touch a group message, for every kind of
-- person — an active member, an invitee, a removed member, a leaver, a member
-- who joined after the message, a blocked and a blocking member, a
-- non-member, anon, and a coach — goes through private.can_read_message.
--
-- Fixtures are written as postgres with explicit timestamps (now() is one
-- instant inside a transaction, so a window needs explicit times). The send
-- trigger still runs on every fixture message, so each was sent while its
-- sender was active.

begin;
select plan(96);

insert into private.feature_flags (name, enabled) values ('group_messages', true)
on conflict (name) do update set enabled = true;
insert into private.feature_flags (name, enabled) values ('dm_images', true)
on conflict (name) do update set enabled = true;

-- o1 owner, a2 admin, m3 member (blocks b7), b7 member, c9 member and m3's
-- coach, j8 joined a day ago, r5 removed, l6 left, i4 invited, n0 outsider.
insert into auth.users (id, email, encrypted_password, email_confirmed_at, instance_id, aud, role)
select ('a1365000-0000-0000-0000-0000000000' || s)::uuid, 'gm-' || s || '@example.com', '', now(),
       '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'
  from unnest(array['a1', 'a2', 'a3', 'a4', 'a5', 'a6', 'a7', 'a8', 'a9', 'a0']) as s
on conflict (id) do nothing;

insert into conversations (id, kind, title, created_by) values
  ('c1365000-0000-0000-0000-000000000001', 'group', 'Tuesday tempo', 'a1365000-0000-0000-0000-0000000000a1');

insert into conversation_participants (conversation_id, user_id, membership_state, role, joined_at, invited_at, invited_by)
select 'c1365000-0000-0000-0000-000000000001', ('a1365000-0000-0000-0000-0000000000' || s)::uuid,
       'active', r, now() - j, null, null
  from (values ('a1', 'owner', interval '10 days'), ('a2', 'admin', interval '10 days'),
               ('a3', 'member', interval '10 days'), ('a7', 'member', interval '10 days'),
               ('a9', 'member', interval '10 days'), ('a8', 'member', interval '1 day'),
               ('a5', 'member', interval '10 days'), ('a6', 'member', interval '10 days'))
       as t (s, r, j);
insert into conversation_participants (conversation_id, user_id, membership_state, invited_at, invited_by)
values ('c1365000-0000-0000-0000-000000000001', 'a1365000-0000-0000-0000-0000000000a4',
        'invited', now() - interval '1 day', 'a1365000-0000-0000-0000-0000000000a1');

insert into direct_messages (id, sender_id, conversation_id, body, created_at) values
  ('d1365000-0000-0000-0000-000000000001', 'a1365000-0000-0000-0000-0000000000a1', 'c1365000-0000-0000-0000-000000000001', 'hello group tempo', now() - interval '5 days'),
  ('d1365000-0000-0000-0000-000000000002', 'a1365000-0000-0000-0000-0000000000a7', 'c1365000-0000-0000-0000-000000000001', 'blocked words tempo', now() - interval '4 days'),
  ('d1365000-0000-0000-0000-000000000003', 'a1365000-0000-0000-0000-0000000000a5', 'c1365000-0000-0000-0000-000000000001', 'removed said tempo', now() - interval '3 days'),
  ('d1365000-0000-0000-0000-000000000004', 'a1365000-0000-0000-0000-0000000000a6', 'c1365000-0000-0000-0000-000000000001', 'leaver said tempo', now() - interval '3 days'),
  ('d1365000-0000-0000-0000-000000000006', 'a1365000-0000-0000-0000-0000000000a6', 'c1365000-0000-0000-0000-000000000001', 'leaver recent tempo', now() - interval '1 minute'),
  ('d1365000-0000-0000-0000-000000000005', 'a1365000-0000-0000-0000-0000000000a3', 'c1365000-0000-0000-0000-000000000001', 'after join tempo', now() - interval '30 minutes');

update conversation_participants
   set membership_state = 'left', left_at = now() - interval '2 days',
       removed_by = case when user_id = 'a1365000-0000-0000-0000-0000000000a5'
                         then 'a1365000-0000-0000-0000-0000000000a1'::uuid end
 where conversation_id = 'c1365000-0000-0000-0000-000000000001'
   and user_id in ('a1365000-0000-0000-0000-0000000000a5', 'a1365000-0000-0000-0000-0000000000a6');

insert into user_blocks (blocker_id, blocked_id)
values ('a1365000-0000-0000-0000-0000000000a3', 'a1365000-0000-0000-0000-0000000000a7');
insert into coach_athletes (coach_id, athlete_id, status, invite_token)
values ('a1365000-0000-0000-0000-0000000000a9', 'a1365000-0000-0000-0000-0000000000a3', 'active', 'gm-1365-coach');

insert into direct_message_reactions (message_id, user_id, reaction)
values ('d1365000-0000-0000-0000-000000000001', 'a1365000-0000-0000-0000-0000000000a2', 'heart');
insert into direct_message_images (id, owner_id, message_id, status, upload_path, storage_path, width, height)
values ('e1365000-0000-0000-0000-000000000001', 'a1365000-0000-0000-0000-0000000000a1',
        'd1365000-0000-0000-0000-000000000001', 'ready',
        'a1365000-0000-0000-0000-0000000000a1/e1365000-0000-0000-0000-000000000001/upload',
        'a1365000-0000-0000-0000-0000000000a1/e1365000-0000-0000-0000-000000000001.jpg', 10, 10);
insert into storage.objects (bucket_id, name)
values ('dm-images', 'a1365000-0000-0000-0000-0000000000a1/e1365000-0000-0000-0000-000000000001.jpg');

select ok(
  (select bool_and(is_group and recipient_id is null) from direct_messages
    where conversation_id = 'c1365000-0000-0000-0000-000000000001'),
  'the send trigger marks every message in a group conversation is_group with no recipient');

set local role authenticated;

-- ── an active member (who blocks b7) ──

set local "request.jwt.claims" = '{"sub":"a1365000-0000-0000-0000-0000000000a3","role":"authenticated"}';
select results_eq(
  $$select id from direct_messages where conversation_id = 'c1365000-0000-0000-0000-000000000001' order by created_at, id$$,
  $$values ('d1365000-0000-0000-0000-000000000001'::uuid), ('d1365000-0000-0000-0000-000000000003'::uuid),
           ('d1365000-0000-0000-0000-000000000004'::uuid), ('d1365000-0000-0000-0000-000000000005'::uuid),
           ('d1365000-0000-0000-0000-000000000006'::uuid)$$,
  'a member reads the group from their join, a leaver''s and a removed member''s messages included');
select is_empty(
  $$select 1 from direct_messages where id = 'd1365000-0000-0000-0000-000000000002'$$,
  'the blocker never sees the message of the member they blocked');
select results_eq(
  $$select id from search_direct_messages('tempo') where conversation_id = 'c1365000-0000-0000-0000-000000000001'$$,
  $$values ('d1365000-0000-0000-0000-000000000006'::uuid), ('d1365000-0000-0000-0000-000000000005'::uuid),
           ('d1365000-0000-0000-0000-000000000004'::uuid), ('d1365000-0000-0000-0000-000000000003'::uuid),
           ('d1365000-0000-0000-0000-000000000001'::uuid)$$,
  'search finds the member''s readable group messages and leaves the blocked member''s out');
select is(
  (select kind || '|' || title || '|' || last_body || '|' || member_count || '|' || membership_state || '|' || coalesce(partner_id::text, 'none')
     from dm_threads() where conversation_id = 'c1365000-0000-0000-0000-000000000001'),
  'group|Tuesday tempo|leaver recent tempo|6|active|none',
  'the inbox lists the group with its title, last readable message and active-member count');
select is(
  (select count(*)::int from direct_message_reactions where message_id = 'd1365000-0000-0000-0000-000000000001'),
  1, 'a member reads the reactions on a message they can read');
select is(
  (select count(*)::int from direct_message_images where id = 'e1365000-0000-0000-0000-000000000001'),
  1, 'a member reads the photo row of a message they can read');
select is(
  (select count(*)::int from storage.objects
    where bucket_id = 'dm-images' and name = 'a1365000-0000-0000-0000-0000000000a1/e1365000-0000-0000-0000-000000000001.jpg'),
  1, 'a member reads the photo object of a message they can read');
select lives_ok(
  $$select set_direct_message_reaction('d1365000-0000-0000-0000-000000000001', 'fire')$$,
  'a member reacts to a group message');
select throws_ok(
  $$select set_direct_message_reaction('d1365000-0000-0000-0000-000000000002', 'fire')$$,
  'P0002', null,
  'the blocker cannot react to the blocked member''s message: it is not found');
select lives_ok(
  $$select submit_report('direct_message', 'd1365000-0000-0000-0000-000000000001', 'spam', null)$$,
  'a member reports a group message they can read');
select lives_ok(
  $$insert into direct_messages (id, sender_id, conversation_id, body)
    values ('d1365000-0000-0000-0000-000000000010', 'a1365000-0000-0000-0000-0000000000a3', 'c1365000-0000-0000-0000-000000000001', 'new from m3')$$,
  'an active member sends to the group by naming the conversation');
select is(
  (select conversation_id from direct_messages where id = 'd1365000-0000-0000-0000-000000000010'),
  'c1365000-0000-0000-0000-000000000001'::uuid, 'the member''s send lands in the group it named');
select lives_ok(
  $$select edit_direct_message('d1365000-0000-0000-0000-000000000010', 'new from m3, edited')$$,
  'an active member edits their own group message inside the window');
select lives_ok(
  $$select mark_conversation_read('c1365000-0000-0000-0000-000000000001', 'd1365000-0000-0000-0000-000000000005')$$,
  'a member marks the group read through a message they can read');
select is(
  (select last_read_at from conversation_participants
    where conversation_id = 'c1365000-0000-0000-0000-000000000001' and user_id = 'a1365000-0000-0000-0000-0000000000a3'),
  now() - interval '30 minutes', 'the read position moves to the message marked');
select is(
  (select array_agg(membership_state order by membership_state)
     from group_members('c1365000-0000-0000-0000-000000000001')),
  array['active', 'active', 'active', 'active', 'active', 'active'],
  'a member''s roster lists the six active members and not the pending invite');
select throws_ok(
  $$insert into direct_messages (sender_id, conversation_id, body, kind)
    values ('a1365000-0000-0000-0000-0000000000a3', 'c1365000-0000-0000-0000-000000000001', 'x', 'ai_assisted')$$,
  '42501', null,
  'an AI-assisted reply cannot be sent into a group');
select throws_ok(
  $$insert into direct_messages (sender_id, conversation_id, body, is_group)
    values ('a1365000-0000-0000-0000-0000000000a3', 'c1365000-0000-0000-0000-000000000001', 'x', true)$$,
  '42501', null,
  'a client cannot write is_group itself');
select lives_ok(
  $$insert into direct_messages (id, sender_id, recipient_id, conversation_id, body)
    values ('d1365000-0000-0000-0000-000000000011', 'a1365000-0000-0000-0000-0000000000a3',
            'a1365000-0000-0000-0000-0000000000a9', 'c1365000-0000-0000-0000-000000000001', 'to my coach')$$,
  'a message naming a recipient is a 1:1 send whatever conversation it names');

reset role;
select is(
  (select (conversation_id <> 'c1365000-0000-0000-0000-000000000001' and not is_group)::text
     from direct_messages where id = 'd1365000-0000-0000-0000-000000000011'),
  'true',
  'the 1:1 send lands in the pair''s own conversation, not the group it named');
set local role authenticated;

-- ── the blocked member ──

set local "request.jwt.claims" = '{"sub":"a1365000-0000-0000-0000-0000000000a7","role":"authenticated"}';
select is(
  (select count(*)::int from direct_messages
    where id in ('d1365000-0000-0000-0000-000000000005', 'd1365000-0000-0000-0000-000000000010')),
  2, 'the blocked member still reads the blocker''s messages: nobody is told about the block');
select lives_ok(
  $$select set_direct_message_reaction('d1365000-0000-0000-0000-000000000005', 'heart')$$,
  'the blocked member can still react to the blocker''s message');
select lives_ok(
  $$insert into direct_messages (sender_id, conversation_id, body)
    values ('a1365000-0000-0000-0000-0000000000a7', 'c1365000-0000-0000-0000-000000000001', 'still here')$$,
  'a block does not stop the blocked member posting to a group they share');
select is(
  (select count(*)::int from direct_messages
    where conversation_id = 'c1365000-0000-0000-0000-000000000001' and body = 'still here'),
  1, 'the blocked member''s post lands in the group');

set local "request.jwt.claims" = '{"sub":"a1365000-0000-0000-0000-0000000000a3","role":"authenticated"}';
select is_empty(
  $$select 1 from direct_message_reactions
     where message_id = 'd1365000-0000-0000-0000-000000000005'
       and user_id = 'a1365000-0000-0000-0000-0000000000a7'$$,
  'the blocker never sees a reaction from the member they blocked');
reset role;
select is(
  (select count(*)::int from direct_message_reactions
    where message_id = 'd1365000-0000-0000-0000-000000000005' and user_id = 'a1365000-0000-0000-0000-0000000000a7'),
  1, 'the blocked member''s reaction is stored, so nothing tells them about the block');
set local role authenticated;

-- ── a member who joined after a message ──

set local "request.jwt.claims" = '{"sub":"a1365000-0000-0000-0000-0000000000a8","role":"authenticated"}';
select is_empty(
  $$select 1 from direct_messages
     where id in ('d1365000-0000-0000-0000-000000000001', 'd1365000-0000-0000-0000-000000000002',
                  'd1365000-0000-0000-0000-000000000003', 'd1365000-0000-0000-0000-000000000004')$$,
  'a member cannot read group messages from before they joined');
select is(
  (select count(*)::int from direct_messages where id = 'd1365000-0000-0000-0000-000000000005'),
  1, 'a member reads a group message sent after they joined');
select is_empty(
  $$select 1 from search_direct_messages('hello group')$$,
  'search never sees a group message from before the member joined');
select is_empty(
  $$select 1 from direct_message_reactions where message_id = 'd1365000-0000-0000-0000-000000000001'$$,
  'a late joiner never sees reactions on a message from before they joined');
select is_empty(
  $$select 1 from direct_message_images where id = 'e1365000-0000-0000-0000-000000000001'$$,
  'a late joiner cannot see the photo row of a message from before they joined');
select throws_ok(
  $$select set_direct_message_reaction('d1365000-0000-0000-0000-000000000001', 'fire')$$,
  'P0002', null, 'a late joiner cannot react to a message from before they joined');
select throws_ok(
  $$select submit_report('direct_message', 'd1365000-0000-0000-0000-000000000001', 'spam', null)$$,
  '02000', null, 'a late joiner cannot report a message from before they joined');
select throws_ok(
  $$select mark_conversation_read('c1365000-0000-0000-0000-000000000001', 'd1365000-0000-0000-0000-000000000001')$$,
  'P0002', null, 'a late joiner cannot mark read through a message from before they joined');
select is(
  (select unread from dm_threads() where conversation_id = 'c1365000-0000-0000-0000-000000000001'),
  4::bigint,
  'a late joiner''s unread count holds only the messages after they joined');

-- ── the removed member ──

set local "request.jwt.claims" = '{"sub":"a1365000-0000-0000-0000-0000000000a5","role":"authenticated"}';
select is_empty(
  $$select 1 from direct_messages
     where conversation_id = 'c1365000-0000-0000-0000-000000000001'
       and sender_id <> 'a1365000-0000-0000-0000-0000000000a5'$$,
  'a removed member reads nothing of the others'' messages, even inside their old window');
select is(
  (select count(*)::int from direct_messages where id = 'd1365000-0000-0000-0000-000000000003'),
  1, 'a removed member still reads their own message');
select is_empty(
  $$select 1 from search_direct_messages('tempo') where sender_id <> 'a1365000-0000-0000-0000-0000000000a5'$$,
  'search never sees the others'' group messages for a removed member');
select is(
  (select coalesce(last_body, '') || '|' || membership_state || '|' || coalesce(member_count::text, 'hidden')
     from dm_threads() where conversation_id = 'c1365000-0000-0000-0000-000000000001'),
  'removed said tempo|left|hidden',
  'a removed member''s inbox row carries only their own message and no member count');
select is_empty(
  $$select 1 from direct_message_reactions where message_id = 'd1365000-0000-0000-0000-000000000001'$$,
  'a removed member never sees reactions on the others'' messages');
select is_empty(
  $$select 1 from direct_message_images where id = 'e1365000-0000-0000-0000-000000000001'$$,
  'a removed member cannot see the photo row of the others'' messages');
select is_empty(
  $$select 1 from storage.objects
     where bucket_id = 'dm-images' and name = 'a1365000-0000-0000-0000-0000000000a1/e1365000-0000-0000-0000-000000000001.jpg'$$,
  'a removed member cannot read the photo object of the others'' messages');
select throws_ok(
  $$select set_direct_message_reaction('d1365000-0000-0000-0000-000000000001', 'fire')$$,
  'P0002', null, 'a removed member cannot react');
select throws_ok(
  $$select submit_report('direct_message', 'd1365000-0000-0000-0000-000000000001', 'spam', null)$$,
  '02000', null, 'a removed member cannot report a message they can no longer read');
select throws_ok(
  $$insert into direct_messages (sender_id, conversation_id, body)
    values ('a1365000-0000-0000-0000-0000000000a5', 'c1365000-0000-0000-0000-000000000001', 'let me back')$$,
  '42501', null, 'a removed member cannot send');
select throws_ok(
  $$select mark_conversation_read('c1365000-0000-0000-0000-000000000001', 'd1365000-0000-0000-0000-000000000003')$$,
  'P0002', null, 'a removed member cannot mark the group read');
select throws_ok(
  $$select group_members('c1365000-0000-0000-0000-000000000001')$$,
  'P0002', null, 'a removed member cannot list the roster');
select is_empty(
  $$select 1 from conversations where id = 'c1365000-0000-0000-0000-000000000001'$$,
  'a removed member cannot see the group''s conversation row or its title');
select throws_ok(
  $$select hide_conversation('c1365000-0000-0000-0000-000000000001', 'd1365000-0000-0000-0000-000000000001')$$,
  'P0002', null, 'a removed member cannot hide through a message they can no longer read');
select lives_ok(
  $$select unsend_direct_message('d1365000-0000-0000-0000-000000000003')$$,
  'a removed member can still unsend their own message');

-- ── the leaver (D11) ──

set local "request.jwt.claims" = '{"sub":"a1365000-0000-0000-0000-0000000000a6","role":"authenticated"}';
select is_empty(
  $$select 1 from direct_messages
     where conversation_id = 'c1365000-0000-0000-0000-000000000001'
       and sender_id <> 'a1365000-0000-0000-0000-0000000000a6'$$,
  'a leaver reads nothing of the others'' messages');
select throws_ok(
  $$select edit_direct_message('d1365000-0000-0000-0000-000000000006', 'changed my mind')$$,
  '55000', null, 'a leaver cannot edit their group message');
select lives_ok(
  $$select unsend_direct_message('d1365000-0000-0000-0000-000000000006')$$,
  'a leaver can still unsend their own group message');
select is(
  (select unsent_at is not null from direct_messages where id = 'd1365000-0000-0000-0000-000000000006'),
  true, 'the leaver''s unsend took effect');
select lives_ok(
  $$select hide_conversation('c1365000-0000-0000-0000-000000000001', 'd1365000-0000-0000-0000-000000000004')$$,
  'a leaver may delete the group for themselves through their own message');
select is(
  (select hidden_before from conversation_participants
    where conversation_id = 'c1365000-0000-0000-0000-000000000001' and user_id = 'a1365000-0000-0000-0000-0000000000a6'),
  now() - interval '3 days', 'the leaver''s delete-for-me is stored');

-- ── the invitee ──

set local "request.jwt.claims" = '{"sub":"a1365000-0000-0000-0000-0000000000a4","role":"authenticated"}';
select is_empty(
  $$select 1 from direct_messages where conversation_id = 'c1365000-0000-0000-0000-000000000001'$$,
  'an invitee reads nothing of the group''s messages before accepting');
select is_empty(
  $$select 1 from search_direct_messages('tempo')$$,
  'search never sees group messages for an invitee');
select is(
  (select count(*)::int from dm_threads() where conversation_id = 'c1365000-0000-0000-0000-000000000001'),
  0, 'an invitee never sees the group in their inbox before they accept');
select is(
  (select title || '|' || invited_by::text || '|' || member_count from group_invites()
    where conversation_id = 'c1365000-0000-0000-0000-000000000001'),
  'Tuesday tempo|a1365000-0000-0000-0000-0000000000a1|6',
  'an invitee sees the title, who invited them and the member count');
select throws_ok(
  $$select group_members('c1365000-0000-0000-0000-000000000001')$$,
  'P0002', null, 'an invitee cannot list the member names before accepting');
select is(
  (select title from conversations where id = 'c1365000-0000-0000-0000-000000000001'),
  'Tuesday tempo', 'an invitee with a live invite reads the group''s title');
select throws_ok(
  $$insert into direct_messages (sender_id, conversation_id, body)
    values ('a1365000-0000-0000-0000-0000000000a4', 'c1365000-0000-0000-0000-000000000001', 'hi all')$$,
  '42501', null, 'an invitee cannot send before accepting');
select throws_ok(
  $$select set_direct_message_reaction('d1365000-0000-0000-0000-000000000005', 'fire')$$,
  'P0002', null, 'an invitee cannot react');
select throws_ok(
  $$select submit_report('direct_message', 'd1365000-0000-0000-0000-000000000005', 'spam', null)$$,
  '02000', null, 'an invitee cannot report a message they cannot read');

-- ── a non-member ──

set local "request.jwt.claims" = '{"sub":"a1365000-0000-0000-0000-0000000000a0","role":"authenticated"}';
select is_empty(
  $$select 1 from direct_messages where conversation_id = 'c1365000-0000-0000-0000-000000000001'$$,
  'a non-member reads nothing of the group''s messages');
select is_empty(
  $$select 1 from conversations where id = 'c1365000-0000-0000-0000-000000000001'$$,
  'a non-member cannot see the group''s conversation row');
select is(
  (select count(*)::int from group_invites() where conversation_id = 'c1365000-0000-0000-0000-000000000001'),
  0, 'a runner who was not invited never sees the invite');
select throws_ok(
  $$insert into direct_messages (sender_id, conversation_id, body)
    values ('a1365000-0000-0000-0000-0000000000a0', 'c1365000-0000-0000-0000-000000000001', 'gatecrash')$$,
  '42501', null, 'a non-member cannot send');
select throws_ok(
  $$select set_direct_message_reaction('d1365000-0000-0000-0000-000000000005', 'fire')$$,
  'P0002', null, 'a non-member cannot react');
select throws_ok(
  $$select submit_report('direct_message', 'd1365000-0000-0000-0000-000000000005', 'spam', null)$$,
  '02000', null, 'a non-member cannot report');
select throws_ok(
  $$select group_members('c1365000-0000-0000-0000-000000000001')$$,
  'P0002', null, 'a non-member gets the same not-found as for a group that does not exist');
select throws_ok(
  $$select group_members('c1365000-0000-0000-0000-0000000000ff')$$,
  'P0002', null, 'a group that does not exist answers not-found');

-- ── a coach who shares the group with their athlete (C2) ──

set local "request.jwt.claims" = '{"sub":"a1365000-0000-0000-0000-0000000000a9","role":"authenticated"}';
select is(
  (select count(*)::int from direct_messages
    where conversation_id = 'c1365000-0000-0000-0000-000000000001'
      and sender_id = 'a1365000-0000-0000-0000-0000000000a3'),
  2, 'as a group member the coach reads their athlete''s group messages');
-- The coach-assist thread lane (apps/web/src/lib/coach/assist/context.ts)
-- reads the pair's thread as sender in pair and recipient in pair.
select is(
  (select count(*)::int from direct_messages
    where sender_id in ('a1365000-0000-0000-0000-0000000000a9', 'a1365000-0000-0000-0000-0000000000a3')
      and recipient_id in ('a1365000-0000-0000-0000-0000000000a9', 'a1365000-0000-0000-0000-0000000000a3')
      and is_group),
  0, 'the coach-assist thread lane''s pair filter takes no group message');
select is(
  (select count(*)::int from direct_messages
    where sender_id in ('a1365000-0000-0000-0000-0000000000a9', 'a1365000-0000-0000-0000-0000000000a3')
      and recipient_id in ('a1365000-0000-0000-0000-0000000000a9', 'a1365000-0000-0000-0000-0000000000a3')),
  1, 'the lane still takes the pair''s own 1:1 message');
select throws_ok(
  $$insert into direct_messages (sender_id, conversation_id, body, kind)
    values ('a1365000-0000-0000-0000-0000000000a9', 'c1365000-0000-0000-0000-000000000001', 'assisted', 'ai_assisted')$$,
  '42501', null, 'a coach cannot send an AI-assisted reply into a group');
select throws_ok(
  $$insert into direct_messages (sender_id, conversation_id, body, kind)
    values ('a1365000-0000-0000-0000-0000000000a9', 'c1365000-0000-0000-0000-000000000001', 'shared', 'coach_share')$$,
  '42501', null, 'a coach share cannot land in a group');

-- ── reports in a group: the site-admin queue, no auto-hide (D10) ──

set local "request.jwt.claims" = '{"sub":"a1365000-0000-0000-0000-0000000000a1","role":"authenticated"}';
select throws_ok(
  $$select submit_report('direct_message', 'd1365000-0000-0000-0000-000000000001', 'spam', null)$$,
  '22023', null, 'the sender cannot report their own group message');
select lives_ok(
  $$select submit_report('direct_message', 'd1365000-0000-0000-0000-000000000005', 'harassment', null)$$,
  'the owner reports a member''s message');
set local "request.jwt.claims" = '{"sub":"a1365000-0000-0000-0000-0000000000a2","role":"authenticated"}';
select lives_ok(
  $$select submit_report('direct_message', 'd1365000-0000-0000-0000-000000000005', 'harassment', null)$$,
  'a second member reports it');
set local "request.jwt.claims" = '{"sub":"a1365000-0000-0000-0000-0000000000a8","role":"authenticated"}';
select lives_ok(
  $$select submit_report('direct_message', 'd1365000-0000-0000-0000-000000000005', 'harassment', null)$$,
  'a third member reports it');
set local "request.jwt.claims" = '{"sub":"a1365000-0000-0000-0000-0000000000a9","role":"authenticated"}';
select is(
  (select body from direct_messages where id = 'd1365000-0000-0000-0000-000000000005'),
  'after join tempo',
  'three reports do not hide a group message: it waits for a site admin');
reset role;
select is(
  (select count(*)::int || '|' || bool_and(snapshot_body = 'after join tempo')::text from reports
    where target_kind = 'direct_message' and target_id = 'd1365000-0000-0000-0000-000000000005'),
  '3|true', 'each group report is queued with the server''s snapshot of the message');
set local role authenticated;

-- ── anon ──

set local role anon;
select is_empty(
  $$select 1 from direct_messages where conversation_id = 'c1365000-0000-0000-0000-000000000001'$$,
  'anon reads nothing of the group''s messages');
select throws_ok(
  $$select group_members('c1365000-0000-0000-0000-000000000001')$$,
  '42501', null, 'anon cannot call the group RPCs');
reset role;

-- ── flag off: fail closed ──

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"a1365000-0000-0000-0000-0000000000a3","role":"authenticated"}';
select is(group_messages_enabled(), true, 'with the flag on a member reads it as on');
select isnt_empty(
  $$select 1 from group_blocked_placeholders('c1365000-0000-0000-0000-000000000001')$$,
  'with the flag on the blocker gets a placeholder for the blocked member''s message');
reset role;

update private.feature_flags set enabled = false where name = 'group_messages';
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"a1365000-0000-0000-0000-0000000000a3","role":"authenticated"}';
select is(group_messages_enabled(), false, 'with the flag off a member reads it as off');
select throws_ok(
  $$select edit_direct_message('d1365000-0000-0000-0000-000000000010', 'edited with the flag off')$$,
  '55000', 'edit_direct_message: message can no longer be edited',
  'with the flag off a member cannot edit their own group message inside the window');
select throws_ok(
  $$select set_direct_message_reaction('d1365000-0000-0000-0000-000000000010', 'fire')$$,
  '55000', 'set_direct_message_reaction: this message cannot take a reaction',
  'with the flag off a member cannot react to a group message');
select is_empty(
  $$select 1 from group_blocked_placeholders('c1365000-0000-0000-0000-000000000001')$$,
  'with the flag off group_blocked_placeholders returns nothing');
select is_empty(
  $$select 1 from direct_messages
     where conversation_id = 'c1365000-0000-0000-0000-000000000001'
       and sender_id <> 'a1365000-0000-0000-0000-0000000000a3'$$,
  'with the flag off a member reads nothing of anyone else''s group messages');
select is(
  (select count(*)::int from direct_messages where id = 'd1365000-0000-0000-0000-000000000005'),
  1, 'with the flag off a member still reads their own message');
select throws_ok(
  $$insert into direct_messages (sender_id, conversation_id, body)
    values ('a1365000-0000-0000-0000-0000000000a3', 'c1365000-0000-0000-0000-000000000001', 'flag off')$$,
  '42501', null, 'with the flag off a member cannot send to a group');

select * from finish();
rollback;

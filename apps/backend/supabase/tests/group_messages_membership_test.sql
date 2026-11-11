-- Pins migration 20271216000007 (issue #1365, decisions § 2461, owner
-- decisions D1, D2, D3, D12; security memo C3, C5): creating a group, inviting
-- (always an invite the invitee accepts, only people the inviter could
-- message 1:1, never across a block, 32 seats including live invites, 14-day
-- expiry), accepting with a server-stamped window, declining, leaving,
-- removing by rank, roles, ownership, renaming, a re-join that does not bring
-- the earlier window back, the uniform not-found, and the default-off flag.

begin;
select plan(69);

insert into private.feature_flags (name, enabled) values ('group_messages', true)
on conflict (name) do update set enabled = true;

-- b1 owner, b2..b6 people b1 and b2 follow, b7 a stranger, b8 who blocked b1,
-- and 40 more for the cap.
insert into auth.users (id, email, encrypted_password, email_confirmed_at, instance_id, aud, role)
select ('b1365000-0000-0000-0000-0000000000' || s)::uuid, 'gmm-' || s || '@example.com', '', now(),
       '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'
  from unnest(array['b1', 'b2', 'b3', 'b4', 'b5', 'b6', 'b7', 'b8']) as s
on conflict (id) do nothing;
insert into auth.users (id, email, encrypted_password, email_confirmed_at, instance_id, aud, role)
select ('b1365000-0000-0000-0000-000000000' || (100 + g)::text)::uuid, 'gmm-cap-' || g || '@example.com', '', now(),
       '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'
  from generate_series(1, 40) as g
on conflict (id) do nothing;

insert into user_follows (follower_id, followee_id)
select f.id, u.id
  from auth.users u
 cross join (values ('b1365000-0000-0000-0000-0000000000b1'::uuid), ('b1365000-0000-0000-0000-0000000000b2'::uuid)) f (id)
 where u.id::text like 'b1365000-0000-0000-0000-%'
   and u.id <> f.id
   and u.id <> 'b1365000-0000-0000-0000-0000000000b7'
on conflict do nothing;
insert into user_blocks (blocker_id, blocked_id)
values ('b1365000-0000-0000-0000-0000000000b8', 'b1365000-0000-0000-0000-0000000000b1');

create temporary table g (k text primary key, id uuid);
grant all on g to authenticated, anon;

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"b1365000-0000-0000-0000-0000000000b1","role":"authenticated"}';

-- ── create ──

select throws_ok(
  $$select create_group_conversation('   ', array['b1365000-0000-0000-0000-0000000000b2', 'b1365000-0000-0000-0000-0000000000b3']::uuid[])$$,
  '22023', null, 'a group needs a title');
select throws_ok(
  $$select create_group_conversation(repeat('x', 61), array['b1365000-0000-0000-0000-0000000000b2', 'b1365000-0000-0000-0000-0000000000b3']::uuid[])$$,
  '22023', null, 'a title is at most 60 characters');
select throws_ok(
  $$select create_group_conversation('Two of us', array['b1365000-0000-0000-0000-0000000000b2', 'b1365000-0000-0000-0000-0000000000b1']::uuid[])$$,
  '22023', null, 'a group needs at least two other people');
select throws_ok(
  $$select create_group_conversation('Strangers', array['b1365000-0000-0000-0000-0000000000b2', 'b1365000-0000-0000-0000-0000000000b7']::uuid[])$$,
  '42501', null, 'nobody can be invited whom the inviter could not message 1:1 (D1)');
select throws_ok(
  $$select create_group_conversation('Blocked', array['b1365000-0000-0000-0000-0000000000b2', 'b1365000-0000-0000-0000-0000000000b8']::uuid[])$$,
  '42501', null, 'an invite across a block is the same refusal');
select throws_ok(
  $$select create_group_conversation('Ghost', array['b1365000-0000-0000-0000-0000000000b2', 'b1365000-0000-0000-0000-0000000000ff']::uuid[])$$,
  '42501', null, 'an account that does not exist is the same refusal');

insert into g values ('main', create_group_conversation('  Saturday long run  ',
  array['b1365000-0000-0000-0000-0000000000b2', 'b1365000-0000-0000-0000-0000000000b3',
        'b1365000-0000-0000-0000-0000000000b4', 'b1365000-0000-0000-0000-0000000000b5']::uuid[]));

reset role;
select is(
  (select kind || '|' || title || '|' || created_by::text from conversations where id = (select id from g where k = 'main')),
  'group|Saturday long run|b1365000-0000-0000-0000-0000000000b1',
  'the group is created with a trimmed title and its creator');
select is(
  (select string_agg(user_id::text || ':' || membership_state || ':' || coalesce(role, '-'), ',' order by user_id)
     from conversation_participants where conversation_id = (select id from g where k = 'main')),
  'b1365000-0000-0000-0000-0000000000b1:active:owner,b1365000-0000-0000-0000-0000000000b2:invited:-,b1365000-0000-0000-0000-0000000000b3:invited:-,b1365000-0000-0000-0000-0000000000b4:invited:-,b1365000-0000-0000-0000-0000000000b5:invited:-',
  'the creator is the owner and everyone else is invited, never added');
select ok(
  (select bool_and(invited_by = 'b1365000-0000-0000-0000-0000000000b1' and invited_at = now())
     from conversation_participants
    where conversation_id = (select id from g where k = 'main') and membership_state = 'invited'),
  'each invite records who sent it and when');
set local role authenticated;

-- ── accept, decline ──

set local "request.jwt.claims" = '{"sub":"b1365000-0000-0000-0000-0000000000b2","role":"authenticated"}';
select throws_ok(
  $$update conversation_participants set joined_at = now() - interval '1 year'
     where user_id = 'b1365000-0000-0000-0000-0000000000b2'$$,
  '42501', null, 'a participant cannot backdate their own window');
select lives_ok(
  $$select accept_group_invite((select id from g where k = 'main'))$$,
  'an invitee accepts');
select is(
  (select membership_state || '|' || role || '|' || (joined_at = now())::text
     from conversation_participants
    where conversation_id = (select id from g where k = 'main') and user_id = 'b1365000-0000-0000-0000-0000000000b2'),
  'active|member|true',
  'accepting makes a member whose window starts at the server''s clock');
select throws_ok(
  $$select accept_group_invite((select id from g where k = 'main'))$$,
  'P0002', null, 'there is no invite left to accept twice');

set local "request.jwt.claims" = '{"sub":"b1365000-0000-0000-0000-0000000000b3","role":"authenticated"}';
select lives_ok($$select accept_group_invite((select id from g where k = 'main'))$$, 'a second invitee accepts');
set local "request.jwt.claims" = '{"sub":"b1365000-0000-0000-0000-0000000000b4","role":"authenticated"}';
select lives_ok($$select decline_group_invite((select id from g where k = 'main'))$$, 'an invitee declines');
select throws_ok(
  $$select accept_group_invite((select id from g where k = 'main'))$$,
  'P0002', null, 'a declined invite cannot be accepted');

-- ── expiry ──

reset role;
update conversation_participants set invited_at = now() - interval '15 days'
 where conversation_id = (select id from g where k = 'main') and user_id = 'b1365000-0000-0000-0000-0000000000b5';
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"b1365000-0000-0000-0000-0000000000b5","role":"authenticated"}';
select is(
  (select count(*)::int from group_invites() where conversation_id = (select id from g where k = 'main')),
  0, 'an invite older than 14 days drops out of the invite list');
select throws_ok(
  $$select accept_group_invite((select id from g where k = 'main'))$$,
  'P0002', null, 'an invite older than 14 days cannot be accepted');

-- ── roles ──

set local "request.jwt.claims" = '{"sub":"b1365000-0000-0000-0000-0000000000b2","role":"authenticated"}';
select throws_ok(
  $$select invite_to_group((select id from g where k = 'main'), array['b1365000-0000-0000-0000-0000000000b6']::uuid[])$$,
  '42501', null, 'a member cannot invite');
select throws_ok(
  $$select set_group_member_role((select id from g where k = 'main'), 'b1365000-0000-0000-0000-0000000000b3', 'admin')$$,
  '42501', null, 'a member cannot change roles');
select throws_ok(
  $$select rename_group((select id from g where k = 'main'), 'Mine now')$$,
  '42501', null, 'a member cannot rename the group');
select throws_ok(
  $$select remove_group_member((select id from g where k = 'main'), 'b1365000-0000-0000-0000-0000000000b3')$$,
  '42501', null, 'a member cannot remove anyone');

set local "request.jwt.claims" = '{"sub":"b1365000-0000-0000-0000-0000000000b1","role":"authenticated"}';
select throws_ok(
  $$select set_group_member_role((select id from g where k = 'main'), 'b1365000-0000-0000-0000-0000000000b2', 'owner')$$,
  '22023', null, 'a role is admin or member; ownership moves by transfer');
select lives_ok(
  $$select set_group_member_role((select id from g where k = 'main'), 'b1365000-0000-0000-0000-0000000000b2', 'admin')$$,
  'the owner makes a member an admin');

set local "request.jwt.claims" = '{"sub":"b1365000-0000-0000-0000-0000000000b2","role":"authenticated"}';
select is(
  invite_to_group((select id from g where k = 'main'),
                  array['b1365000-0000-0000-0000-0000000000b6', 'b1365000-0000-0000-0000-0000000000b3']::uuid[]),
  1, 'an admin invites; an existing member is not invited again');
select lives_ok(
  $$select rename_group((select id from g where k = 'main'), 'Sunday long run')$$,
  'an admin renames the group');
select is(
  (select title from conversations where id = (select id from g where k = 'main')),
  'Sunday long run', 'the new title is stored');
select throws_ok(
  $$select rename_group((select id from g where k = 'main'), '')$$,
  '22023', null, 'a rename needs a title');
select throws_ok(
  $$select remove_group_member((select id from g where k = 'main'), 'b1365000-0000-0000-0000-0000000000b1')$$,
  '42501', null, 'nobody removes the owner');
select lives_ok(
  $$select remove_group_member((select id from g where k = 'main'), 'b1365000-0000-0000-0000-0000000000b6')$$,
  'an admin cancels a pending invite');
select lives_ok(
  $$select remove_group_member((select id from g where k = 'main'), 'b1365000-0000-0000-0000-0000000000b3')$$,
  'an admin removes a member');

reset role;
select is(
  (select membership_state || '|' || removed_by::text || '|' || (left_at is not null)::text
     from conversation_participants
    where conversation_id = (select id from g where k = 'main') and user_id = 'b1365000-0000-0000-0000-0000000000b3'),
  'left|b1365000-0000-0000-0000-0000000000b2|true',
  'a removal is a left row naming who removed them');
set local role authenticated;

set local "request.jwt.claims" = '{"sub":"b1365000-0000-0000-0000-0000000000b3","role":"authenticated"}';
select throws_ok(
  $$select leave_conversation((select id from g where k = 'main'))$$,
  'P0002', null, 'a removed member has no membership left to leave');

-- ── a second admin, then the owner transfers and leaves ──

set local "request.jwt.claims" = '{"sub":"b1365000-0000-0000-0000-0000000000b1","role":"authenticated"}';
select is(
  invite_to_group((select id from g where k = 'main'), array['b1365000-0000-0000-0000-0000000000b3']::uuid[]),
  1, 'the owner re-invites the removed member');
set local "request.jwt.claims" = '{"sub":"b1365000-0000-0000-0000-0000000000b3","role":"authenticated"}';
select lives_ok($$select accept_group_invite((select id from g where k = 'main'))$$, 'the removed member re-joins');
set local "request.jwt.claims" = '{"sub":"b1365000-0000-0000-0000-0000000000b1","role":"authenticated"}';
select lives_ok(
  $$select set_group_member_role((select id from g where k = 'main'), 'b1365000-0000-0000-0000-0000000000b3', 'admin')$$,
  'the owner makes a second admin');
set local "request.jwt.claims" = '{"sub":"b1365000-0000-0000-0000-0000000000b2","role":"authenticated"}';
select throws_ok(
  $$select remove_group_member((select id from g where k = 'main'), 'b1365000-0000-0000-0000-0000000000b3')$$,
  '42501', null, 'an admin cannot remove another admin');
select throws_ok(
  $$select transfer_group_ownership((select id from g where k = 'main'), 'b1365000-0000-0000-0000-0000000000b2')$$,
  '42501', null, 'only the owner transfers ownership');

set local "request.jwt.claims" = '{"sub":"b1365000-0000-0000-0000-0000000000b1","role":"authenticated"}';
select lives_ok(
  $$select transfer_group_ownership((select id from g where k = 'main'), 'b1365000-0000-0000-0000-0000000000b3')$$,
  'the owner transfers ownership to an admin');
reset role;
select is(
  (select string_agg(user_id::text || ':' || role, ',' order by user_id)
     from conversation_participants
    where conversation_id = (select id from g where k = 'main') and membership_state = 'active'),
  'b1365000-0000-0000-0000-0000000000b1:admin,b1365000-0000-0000-0000-0000000000b2:admin,b1365000-0000-0000-0000-0000000000b3:owner',
  'a transfer makes the old owner an admin and the new one the only owner');
-- b2 has been an admin since before b3 re-joined, so b2 is the longest-standing.
update conversation_participants set joined_at = now() - interval '1 hour'
 where conversation_id = (select id from g where k = 'main') and user_id = 'b1365000-0000-0000-0000-0000000000b2';
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"b1365000-0000-0000-0000-0000000000b3","role":"authenticated"}';
select lives_ok($$select leave_conversation((select id from g where k = 'main'))$$, 'the owner leaves');
reset role;
select is(
  (select user_id::text from conversation_participants
    where conversation_id = (select id from g where k = 'main') and role = 'owner' and membership_state = 'active'),
  'b1365000-0000-0000-0000-0000000000b2',
  'ownership passes to the longest-standing admin');
set local role authenticated;

-- ── re-joining does not bring the earlier window back (D3, D12) ──

reset role;
update conversation_participants set joined_at = now() - interval '3 hours'
 where conversation_id = (select id from g where k = 'main') and user_id = 'b1365000-0000-0000-0000-0000000000b1';
insert into direct_messages (id, sender_id, conversation_id, body, created_at) values
  ('d1365000-0000-0000-0000-0000000000b1', 'b1365000-0000-0000-0000-0000000000b2', (select id from g where k = 'main'), 'before b1 left', now() - interval '2 hours'),
  ('d1365000-0000-0000-0000-0000000000b2', 'b1365000-0000-0000-0000-0000000000b1', (select id from g where k = 'main'), 'b1 own words', now() - interval '2 hours');
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"b1365000-0000-0000-0000-0000000000b1","role":"authenticated"}';
select is(
  (select count(*)::int from direct_messages where id = 'd1365000-0000-0000-0000-0000000000b1'),
  1, 'a member reads a message inside their window');
select lives_ok($$select leave_conversation((select id from g where k = 'main'))$$, 'the member leaves');
select is(
  (select membership_state from conversation_participants
    where conversation_id = (select id from g where k = 'main') and user_id = 'b1365000-0000-0000-0000-0000000000b1'),
  'left', 'leaving leaves a left row');
set local "request.jwt.claims" = '{"sub":"b1365000-0000-0000-0000-0000000000b2","role":"authenticated"}';
select throws_ok(
  $$select invite_to_group((select id from g where k = 'main'), array['b1365000-0000-0000-0000-0000000000b1']::uuid[])$$,
  '42501', null, 'someone who just left cannot be invited straight back');
select throws_ok(
  $$select invite_to_group((select id from g where k = 'main'), array['b1365000-0000-0000-0000-0000000000b4']::uuid[])$$,
  '42501', null, 'someone who declined cannot be invited again within 14 days');
reset role;
update conversation_participants set left_at = now() - interval '15 days'
 where conversation_id = (select id from g where k = 'main') and user_id = 'b1365000-0000-0000-0000-0000000000b1';
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"b1365000-0000-0000-0000-0000000000b2","role":"authenticated"}';
select is(
  invite_to_group((select id from g where k = 'main'), array['b1365000-0000-0000-0000-0000000000b1']::uuid[]),
  1, 'after 14 days the leaver can be invited back');
set local "request.jwt.claims" = '{"sub":"b1365000-0000-0000-0000-0000000000b1","role":"authenticated"}';
select lives_ok($$select accept_group_invite((select id from g where k = 'main'))$$, 'the leaver re-joins');
select is(
  (select membership_state || '|' || (joined_at = now())::text from conversation_participants
    where conversation_id = (select id from g where k = 'main') and user_id = 'b1365000-0000-0000-0000-0000000000b1'),
  'active|true', 'the re-join opens a new window at the server''s clock');
select is_empty(
  $$select 1 from direct_messages where id = 'd1365000-0000-0000-0000-0000000000b1'$$,
  'after re-joining the earlier window is hidden: the message from before they left stays unreadable');
select is(
  (select count(*)::int from direct_messages where id = 'd1365000-0000-0000-0000-0000000000b2'),
  1, 'their own message from the earlier window is still theirs');

-- ── the cap: 32 including live invites (D2) ──

set local "request.jwt.claims" = '{"sub":"b1365000-0000-0000-0000-0000000000b1","role":"authenticated"}';
insert into g values ('cap', create_group_conversation('Big group',
  array['b1365000-0000-0000-0000-000000000101', 'b1365000-0000-0000-0000-000000000102']::uuid[]));
select throws_ok(
  $$select invite_to_group((select id from g where k = 'cap'),
      (select array_agg(('b1365000-0000-0000-0000-000000000' || (100 + n)::text)::uuid) from generate_series(3, 32) n))$$,
  '54000', null, 'a group holds at most 32 people, pending invites included');
select is(
  invite_to_group((select id from g where k = 'cap'),
      (select array_agg(('b1365000-0000-0000-0000-000000000' || (100 + n)::text)::uuid) from generate_series(3, 31) n)),
  29, 'the 32nd seat can be filled');
reset role;
update conversation_participants set invited_at = now() - interval '15 days'
 where conversation_id = (select id from g where k = 'cap') and user_id = 'b1365000-0000-0000-0000-000000000131';
set local role authenticated;
select is(
  invite_to_group((select id from g where k = 'cap'), array['b1365000-0000-0000-0000-000000000132']::uuid[]),
  1, 'an expired invite frees its seat');

-- ── one not-found for a group the caller is not in and one that does not exist (C5) ──

set local "request.jwt.claims" = '{"sub":"b1365000-0000-0000-0000-0000000000b7","role":"authenticated"}';
select throws_ok(
  $$select invite_to_group((select id from g where k = 'cap'), array['b1365000-0000-0000-0000-0000000000b2']::uuid[])$$,
  'P0002', null, 'inviting into a group you are not in is not-found');
select throws_ok(
  $$select rename_group((select id from g where k = 'cap'), 'x')$$,
  'P0002', null, 'renaming a group you are not in is not-found');
select throws_ok(
  $$select leave_conversation((select id from g where k = 'cap'))$$,
  'P0002', null, 'leaving a group you are not in is not-found');
select throws_ok(
  $$select leave_conversation('c1365000-0000-0000-0000-0000000000ee')$$,
  'P0002', null, 'leaving a group that does not exist is the same not-found');

-- ── an invitee accepting into a group everyone else left becomes its owner ──

set local "request.jwt.claims" = '{"sub":"b1365000-0000-0000-0000-0000000000b1","role":"authenticated"}';
insert into g values ('orphan', create_group_conversation('Orphan',
  array['b1365000-0000-0000-0000-000000000135', 'b1365000-0000-0000-0000-000000000136']::uuid[]));
select lives_ok($$select leave_conversation((select id from g where k = 'orphan'))$$,
  'the owner leaves a group that has only invitees');
set local "request.jwt.claims" = '{"sub":"b1365000-0000-0000-0000-000000000135","role":"authenticated"}';
select lives_ok($$select accept_group_invite((select id from g where k = 'orphan'))$$,
  'an invitee accepts into the ownerless group');
select is(
  (select role from conversation_participants
    where conversation_id = (select id from g where k = 'orphan') and user_id = 'b1365000-0000-0000-0000-000000000135'),
  'owner', 'the first to accept into an ownerless group owns it');

-- ── flag off ──

reset role;
update private.feature_flags set enabled = false where name = 'group_messages';
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"b1365000-0000-0000-0000-0000000000b1","role":"authenticated"}';
select throws_ok(
  $$select create_group_conversation('Off', array['b1365000-0000-0000-0000-0000000000b2', 'b1365000-0000-0000-0000-0000000000b3']::uuid[])$$,
  '0A000', null, 'with the flag off no group can be created');
select throws_ok(
  $$select invite_to_group((select id from g where k = 'cap'), array['b1365000-0000-0000-0000-000000000140']::uuid[])$$,
  '0A000', null, 'with the flag off nobody can be invited');
set local "request.jwt.claims" = '{"sub":"b1365000-0000-0000-0000-000000000103","role":"authenticated"}';
select throws_ok(
  $$select accept_group_invite((select id from g where k = 'cap'))$$,
  '0A000', null, 'with the flag off an invite cannot be accepted');
select lives_ok(
  $$select decline_group_invite((select id from g where k = 'cap'))$$,
  'with the flag off an invite can still be declined');
select is(
  (select membership_state from conversation_participants
    where conversation_id = (select id from g where k = 'cap') and user_id = 'b1365000-0000-0000-0000-000000000103'),
  'left', 'the declined invite is a left row');
set local "request.jwt.claims" = '{"sub":"b1365000-0000-0000-0000-0000000000b1","role":"authenticated"}';
select lives_ok(
  $$select leave_conversation((select id from g where k = 'main'))$$,
  'with the flag off a member can still leave');
select is(
  (select membership_state from conversation_participants
    where conversation_id = (select id from g where k = 'main') and user_id = 'b1365000-0000-0000-0000-0000000000b1'),
  'left', 'the flag-off leave took effect');

select * from finish();
rollback;

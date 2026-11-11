-- Pins migration 20271216000008 (issue #1365, group_messages.md § 4,
-- decisions § 2461): the 2-year purge and the erase-what-nobody-can-see purge
-- on group messages, a group with no active member, expired invites, the
-- empty-conversation sweep, and account deletion of a member and of the
-- owner (ownership passes on).

begin;
select plan(16);

insert into private.feature_flags (name, enabled) values ('group_messages', true)
on conflict (name) do update set enabled = true;

insert into auth.users (id, email, encrypted_password, email_confirmed_at, instance_id, aud, role)
select ('e1365000-0000-0000-0000-0000000000' || s)::uuid, 'gmp-' || s || '@example.com', '', now(),
       '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'
  from unnest(array['e1', 'e2', 'e3', 'e4', 'e5', 'e6', 'e7', 'e8', 'e9']) as s
on conflict (id) do nothing;

-- G1: e1 owner, e2 admin, e3 member (all since 10 days), e4 joined a day ago;
-- e5 an expired invite who never wrote; e6 an expired re-invite who had.
-- G2: everyone has left. G3: a new group with no message yet.
insert into conversations (id, kind, title, created_by) values
  ('a1365e00-0000-0000-0000-000000000001', 'group', 'Purge one', 'e1365000-0000-0000-0000-0000000000e1'),
  ('a1365e00-0000-0000-0000-000000000002', 'group', 'Abandoned', 'e1365000-0000-0000-0000-0000000000e1'),
  ('a1365e00-0000-0000-0000-000000000003', 'group', 'New', 'e1365000-0000-0000-0000-0000000000e1'),
  ('a1365e00-0000-0000-0000-000000000004', 'group', 'Owned', 'e1365000-0000-0000-0000-0000000000e7');
insert into conversation_participants (conversation_id, user_id, membership_state, role, joined_at) values
  ('a1365e00-0000-0000-0000-000000000001', 'e1365000-0000-0000-0000-0000000000e1', 'active', 'owner', now() - interval '10 days'),
  ('a1365e00-0000-0000-0000-000000000001', 'e1365000-0000-0000-0000-0000000000e2', 'active', 'admin', now() - interval '10 days'),
  ('a1365e00-0000-0000-0000-000000000001', 'e1365000-0000-0000-0000-0000000000e3', 'active', 'member', now() - interval '10 days'),
  ('a1365e00-0000-0000-0000-000000000001', 'e1365000-0000-0000-0000-0000000000e4', 'active', 'member', now() - interval '1 day'),
  ('a1365e00-0000-0000-0000-000000000001', 'e1365000-0000-0000-0000-0000000000e6', 'active', 'member', now() - interval '10 days'),
  ('a1365e00-0000-0000-0000-000000000002', 'e1365000-0000-0000-0000-0000000000e1', 'active', 'owner', now() - interval '10 days'),
  ('a1365e00-0000-0000-0000-000000000003', 'e1365000-0000-0000-0000-0000000000e1', 'active', 'owner', now()),
  ('a1365e00-0000-0000-0000-000000000004', 'e1365000-0000-0000-0000-0000000000e7', 'active', 'owner', now() - interval '10 days'),
  ('a1365e00-0000-0000-0000-000000000004', 'e1365000-0000-0000-0000-0000000000e8', 'active', 'member', now() - interval '9 days'),
  ('a1365e00-0000-0000-0000-000000000004', 'e1365000-0000-0000-0000-0000000000e9', 'active', 'admin', now() - interval '5 days');
insert into conversation_participants (conversation_id, user_id, membership_state, invited_at, invited_by) values
  ('a1365e00-0000-0000-0000-000000000001', 'e1365000-0000-0000-0000-0000000000e5', 'invited', now() - interval '15 days', 'e1365000-0000-0000-0000-0000000000e1');

insert into direct_messages (id, sender_id, conversation_id, body, created_at) values
  -- sender and every member whose window holds it have hidden it
  ('d1365e00-0000-0000-0000-000000000001', 'e1365000-0000-0000-0000-0000000000e3', 'a1365e00-0000-0000-0000-000000000001', 'erase me', now() - interval '5 days'),
  -- sender hid it, the owner still sees it
  ('d1365e00-0000-0000-0000-000000000002', 'e1365000-0000-0000-0000-0000000000e3', 'a1365e00-0000-0000-0000-000000000001', 'owner sees me', now() - interval '3 days'),
  -- everyone else hid it, the sender did not
  ('d1365e00-0000-0000-0000-000000000003', 'e1365000-0000-0000-0000-0000000000e1', 'a1365e00-0000-0000-0000-000000000001', 'sender sees me', now() - interval '5 days'),
  ('d1365e00-0000-0000-0000-000000000004', 'e1365000-0000-0000-0000-0000000000e2', 'a1365e00-0000-0000-0000-000000000001', 'three years old', now() - interval '3 years'),
  ('d1365e00-0000-0000-0000-000000000006', 'e1365000-0000-0000-0000-0000000000e6', 'a1365e00-0000-0000-0000-000000000001', 'e6 wrote once', now() - interval '6 days'),
  ('d1365e00-0000-0000-0000-000000000005', 'e1365000-0000-0000-0000-0000000000e1', 'a1365e00-0000-0000-0000-000000000002', 'nobody left', now() - interval '5 days'),
  ('d1365e00-0000-0000-0000-000000000007', 'e1365000-0000-0000-0000-0000000000e7', 'a1365e00-0000-0000-0000-000000000004', 'owner words', now() - interval '2 days'),
  ('d1365e00-0000-0000-0000-000000000008', 'e1365000-0000-0000-0000-0000000000e8', 'a1365e00-0000-0000-0000-000000000004', 'member words', now() - interval '2 days');

-- e6 leaves and is re-invited, and that invite lapses.
update conversation_participants
   set membership_state = 'invited', invited_at = now() - interval '15 days',
       invited_by = 'e1365000-0000-0000-0000-0000000000e1', role = null
 where conversation_id = 'a1365e00-0000-0000-0000-000000000001' and user_id = 'e1365000-0000-0000-0000-0000000000e6';
update conversation_participants set membership_state = 'left', left_at = now() - interval '1 day'
 where conversation_id = 'a1365e00-0000-0000-0000-000000000002';

-- Delete-for-me stamps: e1 (the owner) through 4 days ago, e2 through 3 days
-- ago, e3 through yesterday; e4 joined yesterday and hid nothing.
update conversation_participants p
   set hidden_before = now() - h.ago
  from (values ('e1365000-0000-0000-0000-0000000000e1'::uuid, interval '4 days'),
               ('e1365000-0000-0000-0000-0000000000e2'::uuid, interval '3 days'),
               ('e1365000-0000-0000-0000-0000000000e3'::uuid, interval '1 day')) h (user_id, ago)
 where p.conversation_id = 'a1365e00-0000-0000-0000-000000000001'
   and p.user_id = h.user_id;
-- 'sender sees me' sits between e1's and e2's stamps: hidden from e2 and e3,
-- still in view for e1, its sender.
update direct_messages set created_at = now() - interval '3 days 12 hours'
 where id = 'd1365e00-0000-0000-0000-000000000003';

select private.purge_stale_direct_messages();

select is(
  (select count(*)::int from direct_messages where id = 'd1365e00-0000-0000-0000-000000000001'),
  0, 'a group message its sender hid and no member in whose window it sits can see is erased');
select is(
  (select count(*)::int from direct_messages where id = 'd1365e00-0000-0000-0000-000000000002'),
  1, 'a group message its sender hid survives while one active member can still see it');
select is(
  (select count(*)::int from direct_messages where id = 'd1365e00-0000-0000-0000-000000000003'),
  1, 'a group message survives while its sender has not hidden it, whatever the others did');
select is(
  (select count(*)::int from direct_messages where id = 'd1365e00-0000-0000-0000-000000000004'),
  0, 'the 2-year purge takes a group message like any other');
select is(
  (select count(*)::int from direct_messages where conversation_id = 'a1365e00-0000-0000-0000-000000000002'),
  0, 'a group with no active member loses its messages');
select is(
  (select count(*)::int from conversations where id = 'a1365e00-0000-0000-0000-000000000002'),
  0, 'and the abandoned group itself goes');
select is(
  (select count(*)::int from conversations where id = 'a1365e00-0000-0000-0000-000000000003'),
  1, 'a new group with members and no message yet survives the empty-conversation sweep');
select is(
  (select count(*)::int from conversation_participants
    where conversation_id = 'a1365e00-0000-0000-0000-000000000001' and user_id = 'e1365000-0000-0000-0000-0000000000e5'),
  0, 'an expired invite from someone who never wrote is retired');
select is(
  (select membership_state || '|' || (left_at is not null)::text from conversation_participants
    where conversation_id = 'a1365e00-0000-0000-0000-000000000001' and user_id = 'e1365000-0000-0000-0000-0000000000e6'),
  'left|true', 'an expired re-invite of someone who wrote there becomes a left row, keeping their own messages theirs');
select is(
  (select count(*)::int from direct_messages where id = 'd1365e00-0000-0000-0000-000000000006'),
  1, 'their message stays in the group');

-- ── account deletion ──

delete from auth.users where id = 'e1365000-0000-0000-0000-0000000000e7';
select is(
  (select count(*)::int from direct_messages where id = 'd1365e00-0000-0000-0000-000000000007'),
  0, 'a deleted owner''s group messages go with their account (Art 17)');
select is(
  (select user_id::text from conversation_participants
    where conversation_id = 'a1365e00-0000-0000-0000-000000000004' and role = 'owner' and membership_state = 'active'),
  'e1365000-0000-0000-0000-0000000000e9',
  'a deleted owner''s group passes to the longest-standing admin, ahead of an older member');
select is(
  (select count(*)::int from direct_messages where id = 'd1365e00-0000-0000-0000-000000000008'),
  1, 'the other members'' messages stay');
select is(
  (select created_by from conversations where id = 'a1365e00-0000-0000-0000-000000000004'),
  null::uuid, 'the group''s created_by is cleared with the creator''s account');

delete from auth.users where id in ('e1365000-0000-0000-0000-0000000000e8', 'e1365000-0000-0000-0000-0000000000e9');
select is(
  (select count(*)::int from conversation_participants where conversation_id = 'a1365e00-0000-0000-0000-000000000004'),
  0, 'every member''s participant row cascades with their account');
select private.purge_stale_direct_messages();
select is(
  (select count(*)::int from conversations where id = 'a1365e00-0000-0000-0000-000000000004'),
  0, 'a group whose last member deleted their account is purged on the next run');

select * from finish();
rollback;

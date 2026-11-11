-- Pins the send-versus-remove serialisation of migration 20271216000006
-- (issue #1365, decisions § 2461, security memo § 2.1 and C3).
--
-- A group send takes a SHARED transaction advisory lock on (conversation,
-- sender) before it reads the sender's membership; remove, leave and accept
-- take the same key EXCLUSIVE before they change it. Shared and exclusive
-- advisory locks on one key conflict, so in production a send waits for a
-- removal in flight and then re-reads membership in a fresh snapshot (it is a
-- new statement once the lock is held), and a removal waits for a send in
-- flight to commit. One pgTAP session cannot run two transactions, so this
-- file pins the two halves it can observe: each side takes the lock in the
-- mode the argument needs, on the key the other side uses, and the send
-- reads the membership as it stands rather than as the statement began.

begin;
select plan(10);

insert into private.feature_flags (name, enabled) values ('group_messages', true)
on conflict (name) do update set enabled = true;

insert into auth.users (id, email, encrypted_password, email_confirmed_at, instance_id, aud, role)
select ('c1365000-0000-0000-0000-0000000000' || s)::uuid, 'gmr-' || s || '@example.com', '', now(),
       '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'
  from unnest(array['c1', 'c2', 'c3']) as s
on conflict (id) do nothing;
insert into user_follows (follower_id, followee_id)
values ('c1365000-0000-0000-0000-0000000000c1', 'c1365000-0000-0000-0000-0000000000c3');

insert into conversations (id, kind, title, created_by) values
  ('f1365000-0000-0000-0000-000000000001', 'group', 'Race', 'c1365000-0000-0000-0000-0000000000c1');
insert into conversation_participants (conversation_id, user_id, membership_state, role, joined_at) values
  ('f1365000-0000-0000-0000-000000000001', 'c1365000-0000-0000-0000-0000000000c1', 'active', 'owner', now() - interval '1 day'),
  ('f1365000-0000-0000-0000-000000000001', 'c1365000-0000-0000-0000-0000000000c2', 'active', 'member', now() - interval '1 day');

-- The advisory lock this session holds on a member's key, as pg_locks names
-- a bigint key: its high and low 32 bits, objsubid 1.
create temporary table lock_key as
select u.id as user_id, private.group_member_lock_key('f1365000-0000-0000-0000-000000000001', u.id) as k
  from (values ('c1365000-0000-0000-0000-0000000000c2'::uuid), ('c1365000-0000-0000-0000-0000000000c3'::uuid)) u (id);
create or replace function pg_temp.held_mode(p_user uuid) returns text language sql as $$
  select string_agg(l.mode, ',' order by l.mode)
    from pg_locks l, lock_key k
   where k.user_id = p_user
     and l.locktype = 'advisory'
     and l.pid = pg_backend_pid()
     and l.objsubid = 1
     and l.classid::bigint = (k.k >> 32) & 4294967295
     and l.objid::bigint = k.k & 4294967295;
$$;
grant select on lock_key to authenticated;

select is(pg_temp.held_mode('c1365000-0000-0000-0000-0000000000c2'), null,
          'no lock is held on the member''s key before anything happens');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"c1365000-0000-0000-0000-0000000000c2","role":"authenticated"}';
select lives_ok(
  $$insert into direct_messages (sender_id, conversation_id, body)
    values ('c1365000-0000-0000-0000-0000000000c2', 'f1365000-0000-0000-0000-000000000001', 'before the removal')$$,
  'an active member sends');
reset role;
select is(pg_temp.held_mode('c1365000-0000-0000-0000-0000000000c2'), 'ShareLock',
          'the send holds the member''s key SHARED until it commits');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"c1365000-0000-0000-0000-0000000000c1","role":"authenticated"}';
select lives_ok(
  $$select remove_group_member('f1365000-0000-0000-0000-000000000001', 'c1365000-0000-0000-0000-0000000000c2')$$,
  'the owner removes the member');
reset role;
select is(
  (select membership_state || '|' || removed_by::text from conversation_participants
    where conversation_id = 'f1365000-0000-0000-0000-000000000001' and user_id = 'c1365000-0000-0000-0000-0000000000c2'),
  'left|c1365000-0000-0000-0000-0000000000c1', 'the removal is stored');
select is(pg_temp.held_mode('c1365000-0000-0000-0000-0000000000c2'), 'ExclusiveLock,ShareLock',
          'the removal takes the same key EXCLUSIVE, which conflicts with any other session''s send');

-- The removal is visible to the next statement. In READ COMMITTED a send
-- that waited on the lock is in the same position once the removal commits.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"c1365000-0000-0000-0000-0000000000c2","role":"authenticated"}';
select throws_ok(
  $$insert into direct_messages (sender_id, conversation_id, body)
    values ('c1365000-0000-0000-0000-0000000000c2', 'f1365000-0000-0000-0000-000000000001', 'after the removal')$$,
  '42501', null,
  'a send after the removal is refused: it cannot land after it');
reset role;
select is(
  (select string_agg(body, ',') from direct_messages where conversation_id = 'f1365000-0000-0000-0000-000000000001'),
  'before the removal',
  'only the message that won the race is in the group');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"c1365000-0000-0000-0000-0000000000c1","role":"authenticated"}';
select is(
  invite_to_group('f1365000-0000-0000-0000-000000000001', array['c1365000-0000-0000-0000-0000000000c3']::uuid[]),
  1, 'the owner invites a third runner');
set local "request.jwt.claims" = '{"sub":"c1365000-0000-0000-0000-0000000000c3","role":"authenticated"}';
select accept_group_invite('f1365000-0000-0000-0000-000000000001');
reset role;
select is(pg_temp.held_mode('c1365000-0000-0000-0000-0000000000c3'), 'ExclusiveLock',
          'accepting takes the new member''s key EXCLUSIVE, so a window opens against no send in flight');

select * from finish();
rollback;

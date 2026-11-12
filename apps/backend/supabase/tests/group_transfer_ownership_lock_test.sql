-- Pins transfer_group_ownership's serialisation against the owner's own leave
-- (migration 20271223001359, decisions § 2461).
--
-- The owner's leave takes the owner's member key and passes ownership on; a
-- transfer that held only the target's key could read "caller is owner"
-- before that leave committed and then promote a second active owner, which
-- surfaced as the one-owner index's raw 23505. One pgTAP session cannot run
-- two transactions, so this file pins what it can observe: the transfer holds
-- BOTH members' keys exclusive (the caller's is the one a leave takes), and
-- the refusals a caller who lost the race meets are the group's existing
-- P0002 / 42501, never 23505.

begin;
select plan(8);

insert into private.feature_flags (name, enabled) values ('group_messages', true)
on conflict (name) do update set enabled = true;

insert into auth.users (id, email, encrypted_password, email_confirmed_at, instance_id, aud, role)
select ('c1359000-0000-0000-0000-0000000000' || s)::uuid, 'gto-' || s || '@example.com', '', now(),
       '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'
  from unnest(array['c1', 'c2', 'c3']) as s
on conflict (id) do nothing;

insert into conversations (id, kind, title, created_by) values
  ('f1359000-0000-0000-0000-000000000001', 'group', 'Hand-over', 'c1359000-0000-0000-0000-0000000000c1');
insert into conversation_participants (conversation_id, user_id, membership_state, role, joined_at) values
  ('f1359000-0000-0000-0000-000000000001', 'c1359000-0000-0000-0000-0000000000c1', 'active', 'owner', now() - interval '3 days'),
  ('f1359000-0000-0000-0000-000000000001', 'c1359000-0000-0000-0000-0000000000c2', 'active', 'admin', now() - interval '2 days'),
  ('f1359000-0000-0000-0000-000000000001', 'c1359000-0000-0000-0000-0000000000c3', 'active', 'member', now() - interval '1 day');

-- The advisory lock this session holds on a member's key, as pg_locks names
-- a bigint key: its high and low 32 bits, objsubid 1.
create temporary table lock_key as
select u.id as user_id, private.group_member_lock_key('f1359000-0000-0000-0000-000000000001', u.id) as k
  from (values ('c1359000-0000-0000-0000-0000000000c1'::uuid),
               ('c1359000-0000-0000-0000-0000000000c3'::uuid)) u (id);
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

select is(pg_temp.held_mode('c1359000-0000-0000-0000-0000000000c1'), null,
          'no lock is held on the owner''s key before the transfer');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"c1359000-0000-0000-0000-0000000000c1","role":"authenticated"}';
select lives_ok(
  $$select transfer_group_ownership('f1359000-0000-0000-0000-000000000001', 'c1359000-0000-0000-0000-0000000000c3')$$,
  'the owner hands the group to a member');
reset role;

select is(pg_temp.held_mode('c1359000-0000-0000-0000-0000000000c1'), 'ExclusiveLock',
          'the transfer holds the CALLER''s key exclusive, the key the owner''s leave takes');
select is(pg_temp.held_mode('c1359000-0000-0000-0000-0000000000c3'), 'ExclusiveLock',
          'and the target''s key, so the target cannot leave mid-transfer');
select is(
  (select string_agg(user_id::text || ':' || role, ',' order by user_id)
     from conversation_participants
    where conversation_id = 'f1359000-0000-0000-0000-000000000001'
      and membership_state = 'active'),
  'c1359000-0000-0000-0000-0000000000c1:admin,c1359000-0000-0000-0000-0000000000c2:admin,c1359000-0000-0000-0000-0000000000c3:owner',
  'one active owner after the swap');

-- The loser of the race, replayed in order: the former owner tries again
-- once someone else holds the group.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"c1359000-0000-0000-0000-0000000000c1","role":"authenticated"}';
select throws_ok(
  $$select transfer_group_ownership('f1359000-0000-0000-0000-000000000001', 'c1359000-0000-0000-0000-0000000000c2')$$,
  '42501', 'transfer_group_ownership: only the owner transfers ownership',
  'a caller who is no longer owner meets the group''s 42501, not 23505');

-- The new owner leaves (the leave's pass hands the group to the longest-
-- standing admin), then tries to transfer: it reads as gone, P0002.
set local "request.jwt.claims" = '{"sub":"c1359000-0000-0000-0000-0000000000c3","role":"authenticated"}';
select leave_conversation('f1359000-0000-0000-0000-000000000001');
select throws_ok(
  $$select transfer_group_ownership('f1359000-0000-0000-0000-000000000001', 'c1359000-0000-0000-0000-0000000000c2')$$,
  'P0002', 'transfer_group_ownership: conversation not found',
  'an owner who left meets the group''s P0002, not 23505');
reset role;

select is(
  (select count(*)::int from conversation_participants
    where conversation_id = 'f1359000-0000-0000-0000-000000000001'
      and membership_state = 'active' and role = 'owner'),
  1, 'the group still has exactly one active owner');

select * from finish();
rollback;

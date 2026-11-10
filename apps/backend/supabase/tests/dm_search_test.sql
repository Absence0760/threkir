-- Pins migration 20271212000003 — searching direct messages (issue #1216):
-- the function runs under the caller's own RLS, so nobody finds a message in
-- a conversation they are not in; unsent, deleted-for-me, Requests and
-- blocked-by-me conversations are left out; the query is a literal.

begin;
select plan(14);

insert into auth.users (id, email, encrypted_password, email_confirmed_at,
                        instance_id, aud, role)
select ('aaaa1216-5ea4-0000-0000-0000000000' || s)::uuid, 'search-' || s || '@example.com', '', now(),
       '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'
  from unnest(array['a1', 'b2', 'c3', 'd4', 'e5', 'f6']) as s
on conflict (id) do nothing;

-- A and B follow each other; C and D follow each other; A follows E; F shares
-- a club with A and has sent A a request.
insert into user_follows (follower_id, followee_id) values
  ('aaaa1216-5ea4-0000-0000-0000000000a1', 'aaaa1216-5ea4-0000-0000-0000000000b2'),
  ('aaaa1216-5ea4-0000-0000-0000000000c3', 'aaaa1216-5ea4-0000-0000-0000000000d4'),
  ('aaaa1216-5ea4-0000-0000-0000000000a1', 'aaaa1216-5ea4-0000-0000-0000000000e5');

insert into clubs (id, owner_id, name, slug, is_public)
values ('cccc1216-5ea4-0000-0000-000000000001', 'aaaa1216-5ea4-0000-0000-0000000000a1',
        'Search Club', 'search-club-1216', true);
insert into club_members (club_id, user_id, role, status) values
  ('cccc1216-5ea4-0000-0000-000000000001', 'aaaa1216-5ea4-0000-0000-0000000000a1', 'owner', 'active'),
  ('cccc1216-5ea4-0000-0000-000000000001', 'aaaa1216-5ea4-0000-0000-0000000000f6', 'member', 'active')
on conflict (club_id, user_id) do update set status = excluded.status;

insert into direct_messages (id, sender_id, recipient_id, body, created_at) values
  ('3333a216-5ea4-0000-0000-000000000001', 'aaaa1216-5ea4-0000-0000-0000000000a1', 'aaaa1216-5ea4-0000-0000-0000000000b2', 'Tempo run tomorrow?', now() - interval '10 minutes'),
  ('3333a216-5ea4-0000-0000-000000000002', 'aaaa1216-5ea4-0000-0000-0000000000b2', 'aaaa1216-5ea4-0000-0000-0000000000a1', 'yes, tempo at 7', now() - interval '9 minutes'),
  ('3333a216-5ea4-0000-0000-000000000003', 'aaaa1216-5ea4-0000-0000-0000000000a1', 'aaaa1216-5ea4-0000-0000-0000000000b2', 'secret tempo plan', now() - interval '8 minutes'),
  ('3333a216-5ea4-0000-0000-000000000004', 'aaaa1216-5ea4-0000-0000-0000000000c3', 'aaaa1216-5ea4-0000-0000-0000000000d4', 'their tempo too', now() - interval '7 minutes'),
  ('3333a216-5ea4-0000-0000-000000000005', 'aaaa1216-5ea4-0000-0000-0000000000a1', 'aaaa1216-5ea4-0000-0000-0000000000e5', 'tempo with e', now() - interval '6 minutes'),
  ('3333a216-5ea4-0000-0000-000000000006', 'aaaa1216-5ea4-0000-0000-0000000000a1', 'aaaa1216-5ea4-0000-0000-0000000000b2', '100% tempo_pace', now() - interval '5 minutes');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"aaaa1216-5ea4-0000-0000-0000000000f6","role":"authenticated"}';
insert into direct_messages (id, sender_id, recipient_id, body)
values ('3333a216-5ea4-0000-0000-000000000007', 'aaaa1216-5ea4-0000-0000-0000000000f6', 'aaaa1216-5ea4-0000-0000-0000000000a1', 'tempo request');

select is(
  (select count(*)::int from search_direct_messages('tempo')),
  1,
  'the requester finds their own request message');

-- ── the caller's own conversations, and nothing else ──

set local "request.jwt.claims" = '{"sub":"aaaa1216-5ea4-0000-0000-0000000000c3","role":"authenticated"}';
select is(
  (select array_agg(id::text order by id) from search_direct_messages('tempo')),
  array['3333a216-5ea4-0000-0000-000000000004'],
  'user C finds only their own message, none of A and B''s');
select is(
  (select count(*)::int from search_direct_messages('secret')),
  0,
  'user C cannot find a word that appears only in A and B''s conversation');

set local "request.jwt.claims" = '{"sub":"aaaa1216-5ea4-0000-0000-0000000000a1","role":"authenticated"}';
select is(
  (select array_agg(id::text order by created_at desc) from search_direct_messages('TEMPO')),
  array['3333a216-5ea4-0000-0000-000000000006', '3333a216-5ea4-0000-0000-000000000005',
        '3333a216-5ea4-0000-0000-000000000003', '3333a216-5ea4-0000-0000-000000000002',
        '3333a216-5ea4-0000-0000-000000000001'],
  'A finds their own matches, case-insensitively, newest first, and not the pending request');

-- ── the query is a literal ──

select is(
  (select count(*)::int from search_direct_messages('%%')),
  0,
  'a percent sign is matched literally, not as a wildcard');
select is(
  (select array_agg(id::text) from search_direct_messages('0% t')),
  array['3333a216-5ea4-0000-0000-000000000006'],
  'a literal percent sign matches where it appears');
select is(
  (select count(*)::int from search_direct_messages('o_p')),
  1,
  'an underscore is matched literally');
select is(
  (select count(*)::int from search_direct_messages('t')),
  0,
  'a one-character query matches nothing');

-- ── unsent, deleted for me, blocked ──

select unsend_direct_message('3333a216-5ea4-0000-0000-000000000003');
select is(
  (select count(*)::int from search_direct_messages('secret')),
  0,
  'an unsent message is not found');

insert into user_blocks (blocker_id, blocked_id)
values ('aaaa1216-5ea4-0000-0000-0000000000a1', 'aaaa1216-5ea4-0000-0000-0000000000e5');
select is(
  (select count(*)::int from search_direct_messages('with e')),
  0,
  'a conversation with someone the caller blocked is not searched');
set local "request.jwt.claims" = '{"sub":"aaaa1216-5ea4-0000-0000-0000000000e5","role":"authenticated"}';
select is(
  (select count(*)::int from search_direct_messages('with e')),
  1,
  'being blocked changes nothing for the blocked person, so it reveals nothing');

set local "request.jwt.claims" = '{"sub":"aaaa1216-5ea4-0000-0000-0000000000a1","role":"authenticated"}';
select hide_conversation(
  (select conversation_id from direct_messages where id = '3333a216-5ea4-0000-0000-000000000002'),
  '3333a216-5ea4-0000-0000-000000000002');
select is(
  (select array_agg(id::text) from search_direct_messages('tempo')),
  array['3333a216-5ea4-0000-0000-000000000006'],
  'messages deleted for the caller are not found; a later one is');

-- ── the function's shape ──

reset role;
select is(
  (select prosecdef from pg_proc where oid = 'public.search_direct_messages(text, integer)'::regprocedure),
  false,
  'search runs as SECURITY INVOKER, under the caller''s RLS');
select ok(
  not has_function_privilege('anon', 'public.search_direct_messages(text, integer)', 'execute'),
  'anon cannot call it');

select * from finish();
rollback;

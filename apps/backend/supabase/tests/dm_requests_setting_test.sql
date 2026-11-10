-- Pins migration 20271213121601 — a runner can turn message requests off
-- (issue #1216): the switch is enforced by the INSERT policy, a follow edge
-- and an accepted conversation still admit sends, a pending request takes no
-- more messages, the refusal is the one 42501, and nobody else can read the
-- setting.

begin;
select plan(12);

insert into auth.users (id, email, encrypted_password, email_confirmed_at,
                        instance_id, aud, role)
select ('aaaa1216-5e70-0000-0000-0000000000' || s)::uuid, 'reqoff-' || s || '@example.com', '', now(),
       '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'
  from unnest(array['a1', 'b2', 'c3', 'd4']) as s
on conflict (id) do nothing;

-- A owns the club; B, C and D are active members. A follows D.
insert into clubs (id, owner_id, name, slug, is_public)
values ('cccc1216-5e70-0000-0000-000000000001', 'aaaa1216-5e70-0000-0000-0000000000a1',
        'Requests Off Club', 'requests-off-club-1216', true);

insert into club_members (club_id, user_id, role, status)
select 'cccc1216-5e70-0000-0000-000000000001', u, r, 'active'
  from (values ('aaaa1216-5e70-0000-0000-0000000000a1'::uuid, 'owner'),
               ('aaaa1216-5e70-0000-0000-0000000000b2'::uuid, 'member'),
               ('aaaa1216-5e70-0000-0000-0000000000c3'::uuid, 'member'),
               ('aaaa1216-5e70-0000-0000-0000000000d4'::uuid, 'member')) as v(u, r)
on conflict (club_id, user_id) do update set status = excluded.status;

insert into user_follows (follower_id, followee_id)
values ('aaaa1216-5e70-0000-0000-0000000000a1', 'aaaa1216-5e70-0000-0000-0000000000d4');

set local role authenticated;

-- B and D turn requests off themselves; the column is theirs to write.
set local "request.jwt.claims" = '{"sub":"aaaa1216-5e70-0000-0000-0000000000b2","role":"authenticated"}';
select lives_ok(
  $$insert into user_settings (user_id, dm_requests)
    values ('aaaa1216-5e70-0000-0000-0000000000b2', false)
    on conflict (user_id) do update set dm_requests = excluded.dm_requests$$,
  'a runner can turn their own message requests off');

set local "request.jwt.claims" = '{"sub":"aaaa1216-5e70-0000-0000-0000000000d4","role":"authenticated"}';
insert into user_settings (user_id, dm_requests)
values ('aaaa1216-5e70-0000-0000-0000000000d4', false)
on conflict (user_id) do update set dm_requests = excluded.dm_requests;

set local "request.jwt.claims" = '{"sub":"aaaa1216-5e70-0000-0000-0000000000a1","role":"authenticated"}';

select throws_ok(
  $$insert into direct_messages (sender_id, recipient_id, body)
    values ('aaaa1216-5e70-0000-0000-0000000000a1', 'aaaa1216-5e70-0000-0000-0000000000b2', 'club hello')$$,
  '42501', null,
  'with requests off, a club co-member cannot message first');

select is(
  (select count(*)::int from user_settings where user_id = 'aaaa1216-5e70-0000-0000-0000000000b2'),
  0,
  'the sender cannot read the recipient''s setting');

select lives_ok(
  $$insert into direct_messages (sender_id, recipient_id, body)
    values ('aaaa1216-5e70-0000-0000-0000000000a1', 'aaaa1216-5e70-0000-0000-0000000000d4', 'followed hello')$$,
  'a follow edge still admits a send to someone with requests off');

select lives_ok(
  $$insert into direct_messages (id, sender_id, recipient_id, body)
    values ('1111a216-5e70-0000-0000-000000000001',
            'aaaa1216-5e70-0000-0000-0000000000a1', 'aaaa1216-5e70-0000-0000-0000000000c3', 'request one')$$,
  'with requests on, a club co-member can message first');

-- C turns requests off while A's request is still pending.
set local "request.jwt.claims" = '{"sub":"aaaa1216-5e70-0000-0000-0000000000c3","role":"authenticated"}';
insert into user_settings (user_id, dm_requests)
values ('aaaa1216-5e70-0000-0000-0000000000c3', false)
on conflict (user_id) do update set dm_requests = excluded.dm_requests;

set local "request.jwt.claims" = '{"sub":"aaaa1216-5e70-0000-0000-0000000000a1","role":"authenticated"}';
select throws_ok(
  $$insert into direct_messages (sender_id, recipient_id, body)
    values ('aaaa1216-5e70-0000-0000-0000000000a1', 'aaaa1216-5e70-0000-0000-0000000000c3', 'request two')$$,
  '42501', null,
  'a pending request takes no more messages once the recipient turns requests off');

-- C can still answer the request already in their list.
set local "request.jwt.claims" = '{"sub":"aaaa1216-5e70-0000-0000-0000000000c3","role":"authenticated"}';
select is(
  (select bool_or(request) from dm_threads()),
  true,
  'the pending request stays in the recipient''s Requests list');
select lives_ok(
  $$select accept_message_request(
      (select conversation_id from direct_messages where id = '1111a216-5e70-0000-0000-000000000001'))$$,
  'the recipient can still accept it');

set local "request.jwt.claims" = '{"sub":"aaaa1216-5e70-0000-0000-0000000000a1","role":"authenticated"}';
select lives_ok(
  $$insert into direct_messages (sender_id, recipient_id, body)
    values ('aaaa1216-5e70-0000-0000-0000000000a1', 'aaaa1216-5e70-0000-0000-0000000000c3', 'after accept')$$,
  'an accepted conversation stays open with requests off');

-- B turns requests back on.
set local "request.jwt.claims" = '{"sub":"aaaa1216-5e70-0000-0000-0000000000b2","role":"authenticated"}';
update user_settings set dm_requests = true where user_id = 'aaaa1216-5e70-0000-0000-0000000000b2';

set local "request.jwt.claims" = '{"sub":"aaaa1216-5e70-0000-0000-0000000000a1","role":"authenticated"}';
select lives_ok(
  $$insert into direct_messages (sender_id, recipient_id, body)
    values ('aaaa1216-5e70-0000-0000-0000000000a1', 'aaaa1216-5e70-0000-0000-0000000000b2', 'club hello again')$$,
  'turning requests back on admits the request');

update user_settings set dm_requests = true
 where user_id = 'aaaa1216-5e70-0000-0000-0000000000c3';
select is(
  (select count(*)::int from user_settings where user_id = 'aaaa1216-5e70-0000-0000-0000000000c3'),
  0,
  'the other runner''s row is not visible to update');

reset role;
select is(
  (select dm_requests from user_settings where user_id = 'aaaa1216-5e70-0000-0000-0000000000c3'),
  false,
  'the other runner''s setting is unchanged');

select * from finish();
rollback;

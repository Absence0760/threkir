-- Challenge invite links (migration 20271103000001, decisions § 2261).
--
-- Pins: the token is unreadable by any client role; only the creator (or a
-- club admin) can mint or rotate it; the preview is anon-readable and keeps the
-- creator's private-profile id and name null; joining needs a session, is
-- idempotent, makes the private challenge visible to the joiner, keeps the
-- leaderboard name rule, returns NULL for an unknown or rotated token, is
-- rate-limited, and every path closes with the challenge_invite_links gate.
-- The definer join refuses, as it would an unknown token and still counting
-- the attempt, a block either way with the creator, an ended challenge and a
-- shadow-hidden creator; the preview withholds the last and a blocked caller
-- too.

begin;

select plan(34);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000c1000001', 'authenticated', 'authenticated', 'creator@ci.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000c1000002', 'authenticated', 'authenticated', 'joiner@ci.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000c1000003', 'authenticated', 'authenticated', 'stranger@ci.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000c1000004', 'authenticated', 'authenticated', 'blocked@ci.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000c1000005', 'authenticated', 'authenticated', 'hidden@ci.local', '', now(), now());

insert into user_profiles (id, display_name)
values
  ('00000000-0000-0000-0000-0000c1000001', 'Creator Cass'),
  ('00000000-0000-0000-0000-0000c1000002', 'Joiner Jo'),
  ('00000000-0000-0000-0000-0000c1000003', 'Stranger Sam'),
  ('00000000-0000-0000-0000-0000c1000004', 'Blocked Bo'),
  ('00000000-0000-0000-0000-0000c1000005', 'Hidden Hal')
on conflict (id) do update set display_name = excluded.display_name;

update user_profiles set shadow_hidden = true
 where id = '00000000-0000-0000-0000-0000c1000005';

insert into user_blocks (blocker_id, blocked_id)
values ('00000000-0000-0000-0000-0000c1000001', '00000000-0000-0000-0000-0000c1000004');

update user_profiles set profile_private = true
 where id = '00000000-0000-0000-0000-0000c1000001';

insert into private.feature_flags (name, enabled) values ('challenge_invite_links', true)
  on conflict (name) do update set enabled = true;

insert into challenges (id, creator_id, title, metric, scope, goal_value, starts_at, ends_at, is_public)
values
  ('eeeeeeee-eeee-eeee-eeee-eeeec1000001', '00000000-0000-0000-0000-0000c1000001',
   'Run 50 km with me', 'distance', 'individual', 50000,
   now() - interval '1 day', now() + interval '29 days', false),
  ('eeeeeeee-eeee-eeee-eeee-eeeec1000002', '00000000-0000-0000-0000-0000c1000001',
   'Club battle', 'distance', 'club_vs_club', null,
   now() - interval '1 day', now() + interval '29 days', true),
  ('eeeeeeee-eeee-eeee-eeee-eeeec1000003', '00000000-0000-0000-0000-0000c1000001',
   'Last month''s 50 km', 'distance', 'individual', 50000,
   now() - interval '31 days', now() - interval '1 day', false),
  ('eeeeeeee-eeee-eeee-eeee-eeeec1000004', '00000000-0000-0000-0000-0000c1000005',
   'Hidden creator''s run', 'distance', 'individual', 50000,
   now() - interval '1 day', now() + interval '29 days', false);

insert into private.challenge_invite_tokens (challenge_id, token)
values
  ('eeeeeeee-eeee-eeee-eeee-eeeec1000003', 'tok-ended'),
  ('eeeeeeee-eeee-eeee-eeee-eeeec1000004', 'tok-hidden');

insert into challenge_participants (challenge_id, user_id)
values ('eeeeeeee-eeee-eeee-eeee-eeeec1000001', '00000000-0000-0000-0000-0000c1000001');

-- ── The token never reaches a client role ──
set local role anon;
select throws_ok(
  $$ select token from private.challenge_invite_tokens $$,
  '42501', null, 'anon cannot read the invite token table');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000c1000001","role":"authenticated"}';
select throws_ok(
  $$ select token from private.challenge_invite_tokens $$,
  '42501', null, 'even the creator cannot read the invite token table directly');

-- ── Minting ──
select isnt(
  get_challenge_invite_token('eeeeeeee-eeee-eeee-eeee-eeeec1000001'), null,
  'the creator mints a token');
reset role;
create temporary table tok as
  select t.token from private.challenge_invite_tokens t
   where t.challenge_id = 'eeeeeeee-eeee-eeee-eeee-eeeec1000001';
grant select on tok to anon, authenticated;
set local role authenticated;

select is(
  get_challenge_invite_token('eeeeeeee-eeee-eeee-eeee-eeeec1000001'),
  (select token from tok),
  'a second call returns the same token');
select is(
  (select creator_id from challenge_invite_preview((select token from tok))),
  '00000000-0000-0000-0000-0000c1000001'::uuid,
  'the creator previewing their own link gets their id back');
select is(
  get_challenge_invite_token('eeeeeeee-eeee-eeee-eeee-eeeec1000002'), null,
  'a club_vs_club challenge gets no link');

set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000c1000003","role":"authenticated"}';
select is(
  get_challenge_invite_token('eeeeeeee-eeee-eeee-eeee-eeeec1000001'), null,
  'a stranger cannot mint or read the token');
select is(
  rotate_challenge_invite_token('eeeeeeee-eeee-eeee-eeee-eeeec1000001'), null,
  'a stranger cannot rotate the token');

-- ── Preview ──
set local role anon;
set local "request.jwt.claims" = '{"role":"anon"}';
select is(
  (select title from challenge_invite_preview((select token from tok))),
  'Run 50 km with me', 'anon previews the challenge the token names');
select is(
  (select creator_name from challenge_invite_preview((select token from tok))),
  null, 'a private creator''s name stays null in the preview');
select is(
  (select creator_id from challenge_invite_preview((select token from tok))),
  null, 'a private creator''s id stays null in the preview with the name');
select is(
  (select count(*)::int from challenge_invite_preview('not-a-token')),
  0, 'an unknown token previews nothing');
select throws_ok(
  $$ select join_challenge_by_token((select token from tok)) $$,
  '42501', null, 'anon cannot join');

-- ── Joining ──
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000c1000002","role":"authenticated"}';
select is(
  (select count(*)::int from challenges where id = 'eeeeeeee-eeee-eeee-eeee-eeeec1000001'),
  0, 'before joining, the private challenge is invisible to the joiner');
select is(
  join_challenge_by_token((select token from tok)),
  'eeeeeeee-eeee-eeee-eeee-eeeec1000001'::uuid, 'the joiner joins by token');
select is(
  join_challenge_by_token((select token from tok)),
  'eeeeeeee-eeee-eeee-eeee-eeeec1000001'::uuid, 'joining again is a no-op, not an error');
select is(
  (select count(*)::int from challenges where id = 'eeeeeeee-eeee-eeee-eeee-eeeec1000001'),
  1, 'after joining, the challenge is visible');
select is(
  (select joined from challenge_invite_preview((select token from tok))),
  true, 'the preview reports the caller as joined');
select is(
  (select display_name from challenge_leaderboard('eeeeeeee-eeee-eeee-eeee-eeeec1000001')
    where user_id = '00000000-0000-0000-0000-0000c1000001'),
  null, 'the leaderboard keeps a private creator''s name null for a joiner');
select is(
  join_challenge_by_token('not-a-token'), null, 'an unknown token returns NULL');
select is(
  join_challenge_by_token('tok-ended'), null,
  'an ended challenge joins nothing, like an unknown token');
select is(
  join_challenge_by_token('tok-hidden'), null,
  'a shadow-hidden creator''s challenge joins nothing');

-- ── Blocks, either way, refuse the definer join ──
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000c1000004","role":"authenticated"}';
select is(
  (select count(*)::int from challenge_invite_preview((select token from tok))),
  0, 'a caller the creator blocked gets nothing from the preview');
select is(
  join_challenge_by_token((select token from tok)), null,
  'a caller the creator blocked joins nothing, like an unknown token');
do $$
begin
  for i in 1..29 loop
    perform join_challenge_by_token('blocked-guess-' || i);
  end loop;
end $$;
select throws_ok(
  $$ select join_challenge_by_token('blocked-guess-30') $$,
  'P0001', null, 'a refused join still counts toward the rate limit');
reset role;
select is(
  (select count(*)::int from challenge_participants
    where user_id = '00000000-0000-0000-0000-0000c1000004'),
  0, 'the blocked caller never became a participant');

-- ── A shadow-hidden creator's link shows nothing to anyone else ──
set local role anon;
set local "request.jwt.claims" = '{"role":"anon"}';
select is(
  (select count(*)::int from challenge_invite_preview('tok-hidden')),
  0, 'a shadow-hidden creator''s challenge previews nothing');
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000c1000005","role":"authenticated"}';
select is(
  (select title from challenge_invite_preview('tok-hidden')),
  'Hidden creator''s run', 'the shadow-hidden creator still previews their own link');

-- ── Rotation ──
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000c1000001","role":"authenticated"}';
select isnt(
  rotate_challenge_invite_token('eeeeeeee-eeee-eeee-eeee-eeeec1000001'),
  (select token from tok), 'the creator rotates the token');
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000c1000003","role":"authenticated"}';
select is(
  join_challenge_by_token((select token from tok)), null,
  'the rotated-out token joins nothing');

-- ── Rate limit: 30 attempts an hour, misses included ──
do $$
begin
  for i in 1..29 loop
    perform join_challenge_by_token('guess-' || i);
  end loop;
end $$;
select throws_ok(
  $$ select join_challenge_by_token('guess-31') $$,
  'P0001', null, 'the 31st attempt in an hour is refused');

-- ── The gate closes every path ──
reset role;
update private.feature_flags set enabled = false where name = 'challenge_invite_links';
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000c1000001","role":"authenticated"}';
select is(
  get_challenge_invite_token('eeeeeeee-eeee-eeee-eeee-eeeec1000001'), null,
  'gate closed: no token for the creator');
select is(
  challenge_invite_links_enabled(), false, 'gate closed: the reader reports false');
select throws_ok(
  $$ select join_challenge_by_token('anything') $$,
  'P0001', 'challenge_invite_links_disabled', 'gate closed: joining raises');

select * from finish();
rollback;

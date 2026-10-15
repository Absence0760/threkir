-- clubs.strava_club_id and its one writer, set_club_strava_link (migration
-- 20270819001953, decisions § 1959).
--
-- The column is a claim on a Strava club, so the two things worth measuring
-- are that a client cannot make the claim directly (the freeze trigger
-- discards the value, read back as a privileged session) and that the RPC the
-- strava-clubs Edge Function calls makes it only for an active owner/admin of
-- the Threkir club, once per Strava club.

begin;
select plan(17);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('5c5c5c5c-0000-0000-0000-0000000000a1', 'authenticated', 'authenticated', 'owner@stravalink.local', '', now(), now()),
  ('5c5c5c5c-0000-0000-0000-0000000000a2', 'authenticated', 'authenticated', 'member@stravalink.local', '', now(), now()),
  ('5c5c5c5c-0000-0000-0000-0000000000a3', 'authenticated', 'authenticated', 'other@stravalink.local', '', now(), now());

select tests.confirm_consent();

-- ── a client insert cannot arrive pre-linked ────────────────────────────────
set local role authenticated;
set local "request.jwt.claims" =
  '{"sub":"5c5c5c5c-0000-0000-0000-0000000000a1","role":"authenticated"}';
insert into clubs (id, owner_id, name, slug, is_public, strava_club_id)
values ('5c5c5c5c-0000-0000-0000-0000000000c1', '5c5c5c5c-0000-0000-0000-0000000000a1',
        'Strava Link Club', 'strava-link-club', true, 4242);
reset role;

select is(
  (select strava_club_id from clubs where id = '5c5c5c5c-0000-0000-0000-0000000000c1'),
  null::bigint,
  'a club created by a client with strava_club_id set is not linked');

insert into club_members (club_id, user_id, role, status)
values ('5c5c5c5c-0000-0000-0000-0000000000c1', '5c5c5c5c-0000-0000-0000-0000000000a2', 'member', 'active');

insert into clubs (id, owner_id, name, slug, is_public)
values ('5c5c5c5c-0000-0000-0000-0000000000c2', '5c5c5c5c-0000-0000-0000-0000000000a3',
        'Other Club', 'other-strava-link-club', true);

-- ── the RPC is server-only ──────────────────────────────────────────────────
set local role authenticated;
set local "request.jwt.claims" =
  '{"sub":"5c5c5c5c-0000-0000-0000-0000000000a1","role":"authenticated"}';
select throws_ok(
  $$ select set_club_strava_link('5c5c5c5c-0000-0000-0000-0000000000a1',
       '5c5c5c5c-0000-0000-0000-0000000000c1', 4242) $$,
  '42501',
  null,
  'a signed-in client cannot call set_club_strava_link, even for its own club');
reset role;

-- ── the RPC links for an owner, and the value lands ─────────────────────────
set local role service_role;
select is(
  set_club_strava_link('5c5c5c5c-0000-0000-0000-0000000000a1',
    '5c5c5c5c-0000-0000-0000-0000000000c1', 4242),
  'ok',
  'the owner of the Threkir club can link it');
reset role;
select is(
  (select strava_club_id from clubs where id = '5c5c5c5c-0000-0000-0000-0000000000c1'),
  4242::bigint,
  'the linked Strava club id is stored');

-- search_clubs returns `setof clubs` through an explicit column list, so a new
-- clubs column breaks every call unless the list grows with it.
set local role anon;
select is(
  (select strava_club_id from search_clubs('Strava Link Club')
    where id = '5c5c5c5c-0000-0000-0000-0000000000c1'),
  4242::bigint,
  'search_clubs still answers after the column landed, and carries the link');
reset role;

-- ── a client update cannot move or clear the link ───────────────────────────
set local role authenticated;
set local "request.jwt.claims" =
  '{"sub":"5c5c5c5c-0000-0000-0000-0000000000a1","role":"authenticated"}';
update clubs set strava_club_id = 777, description = 'edited'
 where id = '5c5c5c5c-0000-0000-0000-0000000000c1';
reset role;
select is(
  (select strava_club_id from clubs where id = '5c5c5c5c-0000-0000-0000-0000000000c1'),
  4242::bigint,
  'an owner cannot re-point the link with a direct update');
select is(
  (select description from clubs where id = '5c5c5c5c-0000-0000-0000-0000000000c1'),
  'edited',
  'the rest of that update still applied — the link is discarded, not the write');

-- ── who may link ─────────────────────────────────────────────────────────────
set local role service_role;
select is(
  set_club_strava_link('5c5c5c5c-0000-0000-0000-0000000000a2',
    '5c5c5c5c-0000-0000-0000-0000000000c1', 99),
  'not_club_admin',
  'an ordinary member cannot link the club');
reset role;
select is(
  (select strava_club_id from clubs where id = '5c5c5c5c-0000-0000-0000-0000000000c1'),
  4242::bigint,
  'and the refused link left the stored one alone');

set local role service_role;
select is(
  set_club_strava_link('5c5c5c5c-0000-0000-0000-0000000000a3',
    '5c5c5c5c-0000-0000-0000-0000000000c1', 99),
  'not_club_admin',
  'an admin of a different club cannot link this one');
select is(
  set_club_strava_link('5c5c5c5c-0000-0000-0000-0000000000a3',
    '5c5c5c5c-0000-0000-0000-0000000000c2', 4242),
  'already_linked',
  'a Strava club already linked to one Threkir club cannot be claimed by another');
select is(
  set_club_strava_link('5c5c5c5c-0000-0000-0000-0000000000a3',
    '5c5c5c5c-0000-0000-0000-0000000000c2', -5),
  'invalid_strava_club',
  'a non-positive Strava club id is refused');
select is(
  set_club_strava_link('5c5c5c5c-0000-0000-0000-0000000000a1',
    '5c5c5c5c-0000-0000-0000-0000000000c1', null),
  'invalid_strava_club',
  'a missing Strava club id is refused rather than read as an unlink');
reset role;

-- ── unlinking is a client RPC, for the club's admins only ───────────────────
set local role authenticated;
set local "request.jwt.claims" =
  '{"sub":"5c5c5c5c-0000-0000-0000-0000000000a2","role":"authenticated"}';
select is(
  unlink_club_strava('5c5c5c5c-0000-0000-0000-0000000000c1'),
  false,
  'an ordinary member cannot unlink the club');
reset role;
select is(
  (select strava_club_id from clubs where id = '5c5c5c5c-0000-0000-0000-0000000000c1'),
  4242::bigint,
  'and the refused unlink left the link in place');

set local role authenticated;
set local "request.jwt.claims" =
  '{"sub":"5c5c5c5c-0000-0000-0000-0000000000a1","role":"authenticated"}';
select is(
  unlink_club_strava('5c5c5c5c-0000-0000-0000-0000000000c1'),
  true,
  'the owner can unlink');
reset role;
select is(
  (select strava_club_id from clubs where id = '5c5c5c5c-0000-0000-0000-0000000000c1'),
  null::bigint,
  'unlinking clears the stored id');

select * from finish();
rollback;

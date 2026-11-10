-- The release sync's author resolution (migration 20271127100001, issue
-- #1349, decisions § 2429): private.resolve_club_publisher names the club's
-- active owner, else its earliest-joined active admin (then the lowest user
-- id), and that account is one load_park_catalogue accepts. It refuses an
-- unknown slug, a slug whose club is not the committed id, a club that is not
-- verified, public and visible, and one with no active owner or admin. No
-- client role can call it.

begin;

select plan(14);

-- ── Fixture ──
-- O owns the club. A1 and A2 are admins, A1 joined first; A3 joined at the
-- same instant as A2 with a higher id. M is a plain member.
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000000c3a01', 'authenticated', 'authenticated', 'rcp-owner@rcp.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000c3a02', 'authenticated', 'authenticated', 'rcp-admin1@rcp.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000c3a03', 'authenticated', 'authenticated', 'rcp-admin2@rcp.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000c3a04', 'authenticated', 'authenticated', 'rcp-admin3@rcp.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000c3a05', 'authenticated', 'authenticated', 'rcp-member@rcp.local', '', now(), now());

select tests.confirm_consent();

insert into clubs (id, owner_id, name, slug, is_public)
values ('00000000-0000-0000-0000-0000000c3b01', '00000000-0000-0000-0000-0000000c3a01',
        'RCP Official', 'rcp-official', true);

insert into club_members (club_id, user_id, role, status, joined_at, activity_waiver_ack_at)
values
  ('00000000-0000-0000-0000-0000000c3b01', '00000000-0000-0000-0000-0000000c3a02', 'admin', 'active',
   '2026-01-01T00:00:00Z', now()),
  ('00000000-0000-0000-0000-0000000c3b01', '00000000-0000-0000-0000-0000000c3a04', 'admin', 'active',
   '2026-02-01T00:00:00Z', now()),
  ('00000000-0000-0000-0000-0000000c3b01', '00000000-0000-0000-0000-0000000c3a03', 'admin', 'active',
   '2026-02-01T00:00:00Z', now()),
  ('00000000-0000-0000-0000-0000000c3b01', '00000000-0000-0000-0000-0000000c3a05', 'member', 'active',
   '2025-01-01T00:00:00Z', now());

update clubs set is_verified = true where id = '00000000-0000-0000-0000-0000000c3b01';

create temp table picks (n int primary key, author uuid);
grant select, insert on picks to service_role;

create function pg_temp.pick(p_n int) returns void language sql as $$
  insert into picks
  values (p_n, private.resolve_club_publisher('rcp-official', '00000000-0000-0000-0000-0000000c3b01'));
$$;

-- ── Owner first ──
set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';
select pg_temp.pick(1);
reset role;
set local "request.jwt.claims" = '{}';

select is((select author from picks where n = 1), '00000000-0000-0000-0000-0000000c3a01'::uuid,
  'the active owner is picked over every admin, even one who joined earlier');
select ok(
  private.is_official_publisher('00000000-0000-0000-0000-0000000c3b01', (select author from picks where n = 1)),
  'the picked account is one load_park_catalogue accepts');

-- ── No active owner: the earliest admin ──
update club_members set status = 'pending'
 where club_id = '00000000-0000-0000-0000-0000000c3b01' and role = 'owner';

set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';
select pg_temp.pick(2);
reset role;
set local "request.jwt.claims" = '{}';

select is((select author from picks where n = 2), '00000000-0000-0000-0000-0000000c3a02'::uuid,
  'with no active owner, the earliest-joined active admin is picked, never the earlier-joined member');

-- ── A tie on joined_at: the lowest user id ──
update club_members set status = 'rejected'
 where club_id = '00000000-0000-0000-0000-0000000c3b01' and user_id = '00000000-0000-0000-0000-0000000c3a02';

set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';
select pg_temp.pick(3);
reset role;
set local "request.jwt.claims" = '{}';

select is((select author from picks where n = 3), '00000000-0000-0000-0000-0000000c3a03'::uuid,
  'admins who joined at the same instant are ordered by user id');
select ok(
  private.is_official_publisher('00000000-0000-0000-0000-0000000c3b01', (select author from picks where n = 3)),
  'the fallback admin is also accepted by load_park_catalogue');

-- ── Refusals ──
set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';
select throws_ok(
  $$ select private.resolve_club_publisher('rcp-nobody', '00000000-0000-0000-0000-0000000c3b01') $$,
  'P0002', 'resolve_club_publisher: no club has the slug rcp-nobody',
  'an unknown slug is refused');
select throws_ok(
  $$ select private.resolve_club_publisher('rcp-official', '00000000-0000-0000-0000-0000000c3b09') $$,
  '22023',
  'resolve_club_publisher: the club rcp-official is 00000000-0000-0000-0000-0000000c3b01, not the committed 00000000-0000-0000-0000-0000000c3b09',
  'a slug whose club is not the committed id is refused');
reset role;
set local "request.jwt.claims" = '{}';

update club_members set status = 'pending'
 where club_id = '00000000-0000-0000-0000-0000000c3b01' and role = 'admin';
select is(
  (select count(*) from club_members where club_id = '00000000-0000-0000-0000-0000000c3b01' and status = 'active'),
  1::bigint,
  'the club still has an active member (a positive control: the refusal below is about the role, not an empty club)');

set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';
select throws_ok(
  $$ select private.resolve_club_publisher('rcp-official', '00000000-0000-0000-0000-0000000c3b01') $$,
  '42501', 'resolve_club_publisher: the club rcp-official has no active owner or admin',
  'a club with only members is refused');
reset role;
set local "request.jwt.claims" = '{}';

update club_members set status = 'active'
 where club_id = '00000000-0000-0000-0000-0000000c3b01' and role = 'owner';
update clubs set is_verified = false where id = '00000000-0000-0000-0000-0000000c3b01';

set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';
select throws_ok(
  $$ select private.resolve_club_publisher('rcp-official', '00000000-0000-0000-0000-0000000c3b01') $$,
  '42501', 'resolve_club_publisher: the club rcp-official is not verified, public and visible',
  'an unverified club is refused, even with an active owner');
reset role;
set local "request.jwt.claims" = '{}';

update clubs set is_verified = true, is_public = false where id = '00000000-0000-0000-0000-0000000c3b01';

set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';
select throws_ok(
  $$ select private.resolve_club_publisher('rcp-official', '00000000-0000-0000-0000-0000000c3b01') $$,
  '42501', 'resolve_club_publisher: the club rcp-official is not verified, public and visible',
  'a private club is refused');
reset role;
set local "request.jwt.claims" = '{}';

update clubs set is_public = true where id = '00000000-0000-0000-0000-0000000c3b01';

set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';
select is(
  private.resolve_club_publisher('rcp-official', '00000000-0000-0000-0000-0000000c3b01'),
  '00000000-0000-0000-0000-0000000c3a01'::uuid,
  'a verified public club with its owner back resolves again');
reset role;
set local "request.jwt.claims" = '{}';

set local role anon;
select throws_ok(
  $$ select private.resolve_club_publisher('rcp-official', '00000000-0000-0000-0000-0000000c3b01') $$,
  '42501', 'permission denied for function resolve_club_publisher',
  'anon cannot call it');
reset role;

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000c3a01","role":"authenticated"}';
select throws_ok(
  $$ select private.resolve_club_publisher('rcp-official', '00000000-0000-0000-0000-0000000c3b01') $$,
  '42501', 'permission denied for function resolve_club_publisher',
  'a signed-in account, even the owner, cannot call it');
reset role;
set local "request.jwt.claims" = '{}';

select * from finish();
rollback;

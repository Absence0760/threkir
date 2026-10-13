-- Pins migration 20270801000001: a club's activity-risk acknowledgement is
-- enforced in the database on every join path (§ R7CLUBS-1).
--
--   * join_club_by_token refuses a waiver club with `activity_waiver_required`
--     until the caller passes the acknowledgement, plants no row when it
--     refuses, and server-stamps the acknowledgement when it admits.
--   * An earlier acknowledgement on the membership row carries a later
--     token join without asking again.
--   * A club without the waiver still joins by token with the token alone.
--   * The two self-join INSERT policies refuse a waiver club's row with a
--     null acknowledgement and admit one that carries it.
--   * EXECUTE stays revoked from anon on the new signature.

begin;
select plan(13);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000007a0001', 'authenticated', 'authenticated', 'owner@r7waiver.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000007a0002', 'authenticated', 'authenticated', 'joiner@r7waiver.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000007a0003', 'authenticated', 'authenticated', 'self@r7waiver.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000007a0004', 'authenticated', 'authenticated', 'back@r7waiver.local', '', now(), now());

set local role service_role;

insert into clubs (id, owner_id, name, slug, is_public, join_policy, invite_token, requires_activity_waiver)
values
  ('7a7a7a7a-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000007a0001',
   'Waiver Invite Club', 'r7-waiver-invite', false, 'invite', 'r7-waiver-token', true),
  ('7a7a7a7a-0000-0000-0000-000000000002', '00000000-0000-0000-0000-0000007a0001',
   'Plain Invite Club', 'r7-plain-invite', false, 'invite', 'r7-plain-token', false),
  ('7a7a7a7a-0000-0000-0000-000000000003', '00000000-0000-0000-0000-0000007a0001',
   'Waiver Open Club', 'r7-waiver-open', true, 'open', null, true),
  ('7a7a7a7a-0000-0000-0000-000000000004', '00000000-0000-0000-0000-0000007a0001',
   'Waiver Request Club', 'r7-waiver-request', true, 'request', null, true);

-- A member who acknowledged once, was later rejected, and is re-invited.
insert into club_members (club_id, user_id, role, status, activity_waiver_ack_at)
values ('7a7a7a7a-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000007a0004',
        'member', 'rejected', now() - interval '30 days');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000007a0002","role":"authenticated"}';

select throws_ok(
  $$ select join_club_by_token('r7-waiver-token') $$,
  'P0001',
  'activity_waiver_required',
  'a token join to a waiver club without the acknowledgement is refused'
);

select throws_ok(
  $$ select join_club_by_token('r7-waiver-token', false) $$,
  'P0001',
  'activity_waiver_required',
  'an explicit false acknowledgement is refused too'
);

reset role;
select is_empty(
  $$ select 1 from club_members
     where club_id = '7a7a7a7a-0000-0000-0000-000000000001'
       and user_id = '00000000-0000-0000-0000-0000007a0002' $$,
  'a refused token join plants no membership row'
);

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000007a0002","role":"authenticated"}';

select is(
  join_club_by_token('r7-waiver-token', true),
  '7a7a7a7a-0000-0000-0000-000000000001'::uuid,
  'a token join with the acknowledgement returns the club id'
);

reset role;
select results_eq(
  $$ select status, activity_waiver_ack_at is not null from club_members
     where club_id = '7a7a7a7a-0000-0000-0000-000000000001'
       and user_id = '00000000-0000-0000-0000-0000007a0002' $$,
  $$ values ('active'::text, true) $$,
  'the acknowledged token join is active and records the acknowledgement'
);

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000007a0004","role":"authenticated"}';

select is(
  join_club_by_token('r7-waiver-token'),
  '7a7a7a7a-0000-0000-0000-000000000001'::uuid,
  'an earlier acknowledgement carries a later token join without asking again'
);

reset role;
select results_eq(
  $$ select status, activity_waiver_ack_at < now() - interval '29 days' from club_members
     where club_id = '7a7a7a7a-0000-0000-0000-000000000001'
       and user_id = '00000000-0000-0000-0000-0000007a0004' $$,
  $$ values ('active'::text, true) $$,
  'the re-join keeps the original acknowledgement timestamp'
);

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000007a0002","role":"authenticated"}';

select is(
  join_club_by_token('r7-plain-token'),
  '7a7a7a7a-0000-0000-0000-000000000002'::uuid,
  'a club without the waiver still joins by token alone'
);

set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000007a0003","role":"authenticated"}';

select throws_ok(
  $$ insert into club_members (club_id, user_id, role, status)
     values ('7a7a7a7a-0000-0000-0000-000000000003',
             '00000000-0000-0000-0000-0000007a0003', 'member', 'active') $$,
  '42501',
  null,
  'a self-join to an open waiver club without the acknowledgement is refused'
);

select lives_ok(
  $$ insert into club_members (club_id, user_id, role, status, activity_waiver_ack_at)
     values ('7a7a7a7a-0000-0000-0000-000000000003',
             '00000000-0000-0000-0000-0000007a0003', 'member', 'active', now()) $$,
  'a self-join to an open waiver club with the acknowledgement is admitted'
);

select throws_ok(
  $$ insert into club_members (club_id, user_id, role, status)
     values ('7a7a7a7a-0000-0000-0000-000000000004',
             '00000000-0000-0000-0000-0000007a0003', 'member', 'pending') $$,
  '42501',
  null,
  'a join request to a waiver club without the acknowledgement is refused'
);

reset role;

select ok(
  not has_function_privilege('anon', 'public.join_club_by_token(text, boolean)', 'EXECUTE'),
  'anon has no EXECUTE on join_club_by_token(text, boolean)'
);

select ok(
  has_function_privilege('authenticated', 'public.join_club_by_token(text, boolean)', 'EXECUTE'),
  'authenticated keeps EXECUTE on join_club_by_token(text, boolean)'
);

select * from finish();
rollback;

-- Private profiles and follower approval (20270822000001, decisions § 1967).
--
-- Principals:
--   P  private profile owner
--   A  follower P approved before the switch (an existing user_follows row)
--   S  stranger who asks to follow P
--   Q  stranger who asks and then withdraws
--   B  stranger who asks and is then blocked by P
--   U  public profile owner, the control every read is checked against
--   anon (a null viewer)
--
-- Every refusal below is asserted beside a row the same read must return (U's
-- run, A's edge), so an empty fixture cannot pass for a refusal.

begin;

select plan(30);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('b1a50000-0000-0000-0000-00000000000a', 'authenticated', 'authenticated', 'p@private.local', '', now(), now()),
  ('b1a50000-0000-0000-0000-00000000000b', 'authenticated', 'authenticated', 'a@private.local', '', now(), now()),
  ('b1a50000-0000-0000-0000-00000000000c', 'authenticated', 'authenticated', 's@private.local', '', now(), now()),
  ('b1a50000-0000-0000-0000-00000000000d', 'authenticated', 'authenticated', 'q@private.local', '', now(), now()),
  ('b1a50000-0000-0000-0000-00000000000e', 'authenticated', 'authenticated', 'b@private.local', '', now(), now()),
  ('b1a50000-0000-0000-0000-00000000000f', 'authenticated', 'authenticated', 'u@private.local', '', now(), now());

select tests.confirm_consent();

update user_profiles set display_name = 'Private Pat'
 where id = 'b1a50000-0000-0000-0000-00000000000a';

insert into user_follows (follower_id, followee_id) values
  ('b1a50000-0000-0000-0000-00000000000b', 'b1a50000-0000-0000-0000-00000000000a');

insert into runs (id, user_id, started_at, distance_m, duration_s, source, is_public, metadata)
values
  ('b1a5aaaa-0000-0000-0000-000000000001', 'b1a50000-0000-0000-0000-00000000000a',
   now() - interval '3 days', 5000, 1500, 'app', true, '{"activity_type":"run"}'),
  ('b1a5aaaa-0000-0000-0000-000000000002', 'b1a50000-0000-0000-0000-00000000000f',
   now() - interval '3 days', 5000, 1500, 'app', true, '{"activity_type":"run"}'),
  -- P's live-broadcast stub: in progress, not concluded.
  ('b1a5aaaa-0000-0000-0000-000000000003', 'b1a50000-0000-0000-0000-00000000000a',
   now() - interval '10 minutes', 0, 0, 'app', true, '{"in_progress":true}');

insert into gym_workouts (id, user_id, title, started_at, is_public)
values
  ('b1a5cccc-0000-0000-0000-000000000001', 'b1a50000-0000-0000-0000-00000000000a', 'Private lift', now() - interval '2 days', true),
  ('b1a5cccc-0000-0000-0000-000000000002', 'b1a50000-0000-0000-0000-00000000000f', 'Public lift', now() - interval '2 days', true);

-- (1)
select is(
  (select profile_private from user_profiles where id = 'b1a50000-0000-0000-0000-00000000000f'),
  false,
  'a profile is public unless its owner makes it private');

update user_profiles set profile_private = true
 where id = 'b1a50000-0000-0000-0000-00000000000a';

-- ── S asks to follow P ──
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"b1a50000-0000-0000-0000-00000000000c","role":"authenticated"}';

-- (2)
select is(
  (select public.request_follow('b1a50000-0000-0000-0000-00000000000a')),
  'requested',
  'following a private profile files a request');

-- (3)
select is(
  (select public.request_follow('b1a50000-0000-0000-0000-00000000000f')),
  'following',
  'following a public profile follows at once');

-- (4)
select throws_ok(
  $$insert into user_follows (follower_id, followee_id)
      values ('b1a50000-0000-0000-0000-00000000000c', 'b1a50000-0000-0000-0000-00000000000a')$$,
  '42501', null,
  'a direct follow of a private profile is refused by the rail');

-- (5)
select throws_ok(
  $$insert into follow_requests (requester_id, target_id)
      values ('b1a50000-0000-0000-0000-00000000000c', 'b1a50000-0000-0000-0000-00000000000f')$$,
  '42501', null,
  'a request to a public profile is refused, so a public profile is never left pending');

-- (6)
select is(
  (select count(*)::int from public_runs
    where user_id in ('b1a50000-0000-0000-0000-00000000000a', 'b1a50000-0000-0000-0000-00000000000f')
      and id <> 'b1a5aaaa-0000-0000-0000-000000000003'),
  1,
  'a stranger reads the public owner''s run and not the private owner''s');

-- (7)
select is(
  (select count(*)::int from public_runs where id = 'b1a5aaaa-0000-0000-0000-000000000003'),
  1,
  'a private owner''s live broadcast stays readable on its link');

-- (8)
select results_eq(
  $$select r.id::text, private.is_run_visible_to(r.id, 'b1a50000-0000-0000-0000-00000000000c')
      from (values ('b1a5aaaa-0000-0000-0000-000000000001'::uuid),
                   ('b1a5aaaa-0000-0000-0000-000000000002'::uuid),
                   ('b1a5aaaa-0000-0000-0000-000000000003'::uuid)) r(id)
     order by 1$$,
  $$values ('b1a5aaaa-0000-0000-0000-000000000001', false),
           ('b1a5aaaa-0000-0000-0000-000000000002', true),
           ('b1a5aaaa-0000-0000-0000-000000000003', true)$$,
  'kudos, comments and live pings follow: the private run is closed to a stranger, the public and live ones are open');

-- (9)
select results_eq(
  $$select r.id::text, private.is_run_photo_visible_to(r.id, 'b1a50000-0000-0000-0000-00000000000c')
      from (values ('b1a5aaaa-0000-0000-0000-000000000001'::uuid),
                   ('b1a5aaaa-0000-0000-0000-000000000002'::uuid)) r(id)
     order by 1$$,
  $$values ('b1a5aaaa-0000-0000-0000-000000000001', false),
           ('b1a5aaaa-0000-0000-0000-000000000002', true)$$,
  'photos of a private owner''s public run are closed to a stranger');

-- (10)
select is(
  (select count(*)::int from public_gym_workouts
    where user_id in ('b1a50000-0000-0000-0000-00000000000a', 'b1a50000-0000-0000-0000-00000000000f')),
  1,
  'a stranger reads the public owner''s lift and not the private owner''s');

-- (11) A's approved edge into P sits beside S's own edge into U.
select is(
  (select count(*)::int from user_follows
    where followee_id in ('b1a50000-0000-0000-0000-00000000000a', 'b1a50000-0000-0000-0000-00000000000f')),
  1,
  'a stranger reads the public profile''s follower list and not the private one''s');

-- (12)
select results_eq(
  $$select profile_private, follower_count, viewer_follows, viewer_requested, content_visible
      from public.profile_follow_summary('b1a50000-0000-0000-0000-00000000000a')$$,
  $$values (true, 1::bigint, false, true, false)$$,
  'the summary gives a stranger the counts and their own pending state, and says the content is closed');

-- (13)
select is(
  (select count(*)::int from public_profile_by_id('b1a50000-0000-0000-0000-00000000000f'))
    + (select count(*)::int from public_profile_by_id('b1a50000-0000-0000-0000-00000000000a')),
  1,
  'the share-page projection serves the public profile and not the private one');

-- (14)
select throws_ok(
  $$select public.approve_follow_request('b1a50000-0000-0000-0000-00000000000c')$$,
  'P0002', null,
  'only the profile owner can approve a request made to them');

-- ── anon ──
reset role;
set local role anon;
set local "request.jwt.claims" = '{"role":"anon"}';

-- (15)
select is(
  (select count(*)::int from public_runs
    where user_id in ('b1a50000-0000-0000-0000-00000000000a', 'b1a50000-0000-0000-0000-00000000000f')
      and id <> 'b1a5aaaa-0000-0000-0000-000000000003'),
  1,
  'a signed-out reader (share page, sitemap) gets the public run and not the private owner''s');

-- (16)
select is(
  (select count(*)::int from public_profile_by_id('b1a50000-0000-0000-0000-00000000000f'))
    + (select count(*)::int from public_profile_by_id('b1a50000-0000-0000-0000-00000000000a')),
  1,
  'the /share/profile lookup is not-found for a private profile when signed out');

-- ── A, the approved follower ──
reset role;
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"b1a50000-0000-0000-0000-00000000000b","role":"authenticated"}';

-- (17)
select is(
  (select count(*)::int from public_runs where user_id = 'b1a50000-0000-0000-0000-00000000000a'),
  2,
  'an approved follower reads the private owner''s public runs');

-- (18)
select is(
  (select count(*)::int from public_profile_by_id('b1a50000-0000-0000-0000-00000000000a')),
  1,
  'an approved follower resolves the private profile');

-- ── P, the owner ──
reset role;
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"b1a50000-0000-0000-0000-00000000000a","role":"authenticated"}';

-- (19)
select is(
  (select count(*)::int from notifications
    where user_id = 'b1a50000-0000-0000-0000-00000000000a'
      and actor_id = 'b1a50000-0000-0000-0000-00000000000c'
      and kind = 'follow_request'),
  1,
  'the owner is notified of the request');

-- (20)
select is(
  (select count(*)::int from follow_requests where target_id = 'b1a50000-0000-0000-0000-00000000000a'),
  1,
  'the owner reads their pending request');

-- (21)
select lives_ok(
  $$select public.approve_follow_request('b1a50000-0000-0000-0000-00000000000c')$$,
  'the owner approves the request');

reset role;

-- (22)
select results_eq(
  $$select
      (select count(*)::int from user_follows
        where follower_id = 'b1a50000-0000-0000-0000-00000000000c'
          and followee_id = 'b1a50000-0000-0000-0000-00000000000a'),
      (select count(*)::int from follow_requests
        where requester_id = 'b1a50000-0000-0000-0000-00000000000c'),
      (select count(*)::int from notifications
        where user_id = 'b1a50000-0000-0000-0000-00000000000a'
          and actor_id = 'b1a50000-0000-0000-0000-00000000000c')$$,
  $$values (1, 0, 0)$$,
  'approval moves the request into user_follows, and neither the request nor a "started following you" line is left in the owner''s inbox');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"b1a50000-0000-0000-0000-00000000000c","role":"authenticated"}';

-- (23)
select is(
  (select count(*)::int from public_runs where user_id = 'b1a50000-0000-0000-0000-00000000000a'),
  2,
  'once approved, the follower reads the private owner''s runs');

-- ── Q withdraws ──
set local "request.jwt.claims" = '{"sub":"b1a50000-0000-0000-0000-00000000000d","role":"authenticated"}';
select public.request_follow('b1a50000-0000-0000-0000-00000000000a');
delete from follow_requests where requester_id = 'b1a50000-0000-0000-0000-00000000000d';
reset role;

-- (24)
select results_eq(
  $$select
      (select count(*)::int from follow_requests where requester_id = 'b1a50000-0000-0000-0000-00000000000d'),
      (select count(*)::int from notifications
        where actor_id = 'b1a50000-0000-0000-0000-00000000000d' and kind = 'follow_request')$$,
  $$values (0, 0)$$,
  'withdrawing a request retracts its unread notification');

-- ── B is blocked while pending ──
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"b1a50000-0000-0000-0000-00000000000e","role":"authenticated"}';
select public.request_follow('b1a50000-0000-0000-0000-00000000000a');
reset role;

-- (25)
select is(
  (select count(*)::int from follow_requests where requester_id = 'b1a50000-0000-0000-0000-00000000000e'),
  1,
  'the request is pending before the block');

insert into user_blocks (blocker_id, blocked_id)
values ('b1a50000-0000-0000-0000-00000000000a', 'b1a50000-0000-0000-0000-00000000000e');

-- (26)
select is(
  (select count(*)::int from follow_requests where requester_id = 'b1a50000-0000-0000-0000-00000000000e'),
  0,
  'a block clears a pending request');

-- ── Q asks again; P goes public ──
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"b1a50000-0000-0000-0000-00000000000d","role":"authenticated"}';
select public.request_follow('b1a50000-0000-0000-0000-00000000000a');
set local "request.jwt.claims" = '{"sub":"b1a50000-0000-0000-0000-00000000000a","role":"authenticated"}';

-- (27)
select lives_ok(
  $$update user_profiles set profile_private = false
     where id = 'b1a50000-0000-0000-0000-00000000000a'$$,
  'the owner makes the profile public again');

reset role;

-- (28)
select results_eq(
  $$select
      (select count(*)::int from user_follows
        where follower_id = 'b1a50000-0000-0000-0000-00000000000d'
          and followee_id = 'b1a50000-0000-0000-0000-00000000000a'),
      (select count(*)::int from follow_requests where target_id = 'b1a50000-0000-0000-0000-00000000000a')$$,
  $$values (1, 0)$$,
  'going public approves every pending request');

-- (29)
select is(
  (select count(*)::int from user_follows
    where follower_id = 'b1a50000-0000-0000-0000-00000000000e'
      and followee_id = 'b1a50000-0000-0000-0000-00000000000a'),
  0,
  'the blocked requester is not swept in when the profile goes public');

-- (30)
select is(
  has_column_privilege('anon', 'public.user_profiles', 'profile_private', 'SELECT')
    and has_column_privilege('authenticated', 'public.user_profiles', 'profile_private', 'SELECT'),
  true,
  'the flag is cross-user readable, so a viewer can render Request instead of Follow');

select * from finish();
rollback;

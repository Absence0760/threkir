-- Private profiles, the owner's side of the flow (20270822000001, decisions
-- § 1967): the owner switches the profile private under their own role, reads
-- the requests made to them, declines one and approves another; the approved
-- follower then gets the header, the follower list and the run count a
-- stranger is denied in private_profiles_test.sql.
--
-- Principals:
--   P  the owner, who goes private
--   B  followed P while the profile was still public
--   A  asks, and is approved
--   D  asks, is declined, and asks again
begin;

select plan(7);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('f0110000-0000-0000-0000-00000000000a', 'authenticated', 'authenticated', 'p@ownerflow.local', '', now(), now()),
  ('f0110000-0000-0000-0000-00000000000b', 'authenticated', 'authenticated', 'a@ownerflow.local', '', now(), now()),
  ('f0110000-0000-0000-0000-00000000000c', 'authenticated', 'authenticated', 'b@ownerflow.local', '', now(), now()),
  ('f0110000-0000-0000-0000-00000000000d', 'authenticated', 'authenticated', 'd@ownerflow.local', '', now(), now());

select tests.confirm_consent();

insert into user_follows (follower_id, followee_id) values
  ('f0110000-0000-0000-0000-00000000000c', 'f0110000-0000-0000-0000-00000000000a');

insert into runs (id, user_id, started_at, distance_m, duration_s, source, is_public, metadata)
values
  ('f011aaaa-0000-0000-0000-000000000001', 'f0110000-0000-0000-0000-00000000000a',
   now() - interval '2 days', 6000, 1800, 'app', true, '{"activity_type":"run"}');

-- ── P switches the profile private ──
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"f0110000-0000-0000-0000-00000000000a","role":"authenticated"}';
update user_profiles set profile_private = true
 where id = 'f0110000-0000-0000-0000-00000000000a';
reset role;

-- (1)
select is(
  (select profile_private from user_profiles where id = 'f0110000-0000-0000-0000-00000000000a'),
  true,
  'the owner turns their own profile private');

-- ── A and D ask ──
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"f0110000-0000-0000-0000-00000000000b","role":"authenticated"}';
select public.request_follow('f0110000-0000-0000-0000-00000000000a');
set local "request.jwt.claims" = '{"sub":"f0110000-0000-0000-0000-00000000000d","role":"authenticated"}';
select public.request_follow('f0110000-0000-0000-0000-00000000000a');

-- ── P reads, declines D, approves A ──
set local "request.jwt.claims" = '{"sub":"f0110000-0000-0000-0000-00000000000a","role":"authenticated"}';

-- (2)
select results_eq(
  $$select requester_id::text from follow_requests
     where target_id = 'f0110000-0000-0000-0000-00000000000a'
     order by 1$$,
  $$values ('f0110000-0000-0000-0000-00000000000b'), ('f0110000-0000-0000-0000-00000000000d')$$,
  'the owner reads both requests made to them');

delete from follow_requests
 where requester_id = 'f0110000-0000-0000-0000-00000000000d'
   and target_id = 'f0110000-0000-0000-0000-00000000000a';
select public.approve_follow_request('f0110000-0000-0000-0000-00000000000b');
reset role;

-- (3)
select results_eq(
  $$select
      (select count(*)::int from follow_requests
        where requester_id = 'f0110000-0000-0000-0000-00000000000d'),
      (select count(*)::int from user_follows
        where follower_id = 'f0110000-0000-0000-0000-00000000000d'),
      (select count(*)::int from notifications
        where actor_id = 'f0110000-0000-0000-0000-00000000000d' and kind = 'follow_request'),
      (select count(*)::int from user_follows
        where follower_id = 'f0110000-0000-0000-0000-00000000000b'
          and followee_id = 'f0110000-0000-0000-0000-00000000000a')$$,
  $$values (0, 0, 0, 1)$$,
  'a decline drops the request and its notification without a follow, while the approved asker follows');

-- ── A, now approved ──
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"f0110000-0000-0000-0000-00000000000b","role":"authenticated"}';

-- (4)
select results_eq(
  $$select profile_private, follower_count, following_count, viewer_follows, viewer_requested, content_visible
      from public.profile_follow_summary('f0110000-0000-0000-0000-00000000000a')$$,
  $$values (true, 2::bigint, 0::bigint, true, false, true)$$,
  'the summary tells an approved follower they follow and the content is open');

-- (5)
select results_eq(
  $$select follower_id::text from user_follows
     where followee_id = 'f0110000-0000-0000-0000-00000000000a'
     order by 1$$,
  $$values ('f0110000-0000-0000-0000-00000000000b'), ('f0110000-0000-0000-0000-00000000000c')$$,
  'an approved follower reads the private profile''s whole follower list, not only their own edge');

-- (6)
select results_eq(
  $$select public_run_count from public_run_counts(array['f0110000-0000-0000-0000-00000000000a'::uuid])$$,
  $$values (1::bigint)$$,
  'an approved follower gets the private owner''s public run count');

-- ── D asks again ──
set local "request.jwt.claims" = '{"sub":"f0110000-0000-0000-0000-00000000000d","role":"authenticated"}';

-- (7)
select is(
  (select public.request_follow('f0110000-0000-0000-0000-00000000000a')),
  'requested',
  'a declined asker can ask again');

select * from finish();
rollback;

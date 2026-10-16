-- Pins migration 20270829000012: one follow_request notification per
-- (owner, requester) pair per 24 hours, however often the requester
-- withdraws and asks again (the email loop decisions § 1983 left open).
--
-- Principals:
--   P   private profile owner
--   R1  asks, withdraws, asks again; later asks again after the window
--   R2  a second requester, whose own first ask must notify regardless of R1
--
-- Every "no new notification" below sits beside the request row the same
-- ask filed, so a request that silently failed cannot pass for a cooldown.

begin;

select plan(14);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('f0c00000-0000-0000-0000-00000000000a', 'authenticated', 'authenticated', 'p@cooldown.local', '', now(), now()),
  ('f0c00000-0000-0000-0000-0000000000b1', 'authenticated', 'authenticated', 'r1@cooldown.local', '', now(), now()),
  ('f0c00000-0000-0000-0000-0000000000b2', 'authenticated', 'authenticated', 'r2@cooldown.local', '', now(), now());

select tests.confirm_consent();

update user_profiles set profile_private = true
 where id = 'f0c00000-0000-0000-0000-00000000000a';

-- ── R1 asks ──
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"f0c00000-0000-0000-0000-0000000000b1","role":"authenticated"}';
select public.request_follow('f0c00000-0000-0000-0000-00000000000a');
reset role;

-- (1)
select is(
  (select count(*)::int from notifications
    where user_id = 'f0c00000-0000-0000-0000-00000000000a'
      and actor_id = 'f0c00000-0000-0000-0000-0000000000b1'
      and kind = 'follow_request'),
  1,
  'a first request notifies the owner');

-- ── R1 withdraws and asks again, inside the window ──
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"f0c00000-0000-0000-0000-0000000000b1","role":"authenticated"}';
delete from follow_requests
 where requester_id = 'f0c00000-0000-0000-0000-0000000000b1'
   and target_id = 'f0c00000-0000-0000-0000-00000000000a';
reset role;

-- (2) Withdrawal still retracts the unread notification, as before.
select is(
  (select count(*)::int from notifications
    where actor_id = 'f0c00000-0000-0000-0000-0000000000b1' and kind = 'follow_request'),
  0,
  'withdrawing a request still retracts its unread notification');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"f0c00000-0000-0000-0000-0000000000b1","role":"authenticated"}';

-- (3)
select is(
  (select public.request_follow('f0c00000-0000-0000-0000-00000000000a')),
  'requested',
  'the re-request is filed');
reset role;

-- (4) The request is pending for the owner to act on...
select is(
  (select count(*)::int from follow_requests
    where requester_id = 'f0c00000-0000-0000-0000-0000000000b1'
      and target_id = 'f0c00000-0000-0000-0000-00000000000a'),
  1,
  'the re-request sits in the owner''s pending requests');

-- (5) ...but raises no second notification, so no second email or push.
select is(
  (select count(*)::int from notifications
    where actor_id = 'f0c00000-0000-0000-0000-0000000000b1' and kind = 'follow_request'),
  0,
  'ask, withdraw, ask again within 24 h raises no new notification');

-- ── R2, a different requester ──
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"f0c00000-0000-0000-0000-0000000000b2","role":"authenticated"}';
select public.request_follow('f0c00000-0000-0000-0000-00000000000a');
reset role;

-- (6)
select is(
  (select count(*)::int from notifications
    where user_id = 'f0c00000-0000-0000-0000-00000000000a'
      and actor_id = 'f0c00000-0000-0000-0000-0000000000b2'
      and kind = 'follow_request'),
  1,
  'a second requester''s first request notifies, whatever the first requester did');

-- (7) A READ notification also starts the window: the owner reads R2's,
-- R2 withdraws (the read row survives, as before) and asks again.
update notifications set read_at = now()
 where actor_id = 'f0c00000-0000-0000-0000-0000000000b2' and kind = 'follow_request';
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"f0c00000-0000-0000-0000-0000000000b2","role":"authenticated"}';
delete from follow_requests where requester_id = 'f0c00000-0000-0000-0000-0000000000b2';
select public.request_follow('f0c00000-0000-0000-0000-00000000000a');
reset role;
select results_eq(
  $$ select count(*)::int, count(*) filter (where read_at is null)::int
       from notifications
      where actor_id = 'f0c00000-0000-0000-0000-0000000000b2' and kind = 'follow_request' $$,
  $$ values (1, 0) $$,
  'a re-request after the owner read the first raises nothing new');

-- ── After the window ──
-- Simulate 25 hours passing for R1's pair.
update private.follow_request_notices
   set notified_at = now() - interval '25 hours'
 where target_id = 'f0c00000-0000-0000-0000-00000000000a'
   and requester_id = 'f0c00000-0000-0000-0000-0000000000b1';
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"f0c00000-0000-0000-0000-0000000000b1","role":"authenticated"}';
delete from follow_requests where requester_id = 'f0c00000-0000-0000-0000-0000000000b1';
select public.request_follow('f0c00000-0000-0000-0000-00000000000a');
reset role;

-- (8)
select is(
  (select count(*)::int from notifications
    where actor_id = 'f0c00000-0000-0000-0000-0000000000b1' and kind = 'follow_request'
      and read_at is null),
  1,
  'a request more than 24 h after the last notice notifies again');

-- (9) The claim moved the window forward.
select is(
  (select notified_at from private.follow_request_notices
    where target_id = 'f0c00000-0000-0000-0000-00000000000a'
      and requester_id = 'f0c00000-0000-0000-0000-0000000000b1'),
  now(),
  'notifying restarts the pair''s window');

-- ── Approval is unchanged ──
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"f0c00000-0000-0000-0000-00000000000a","role":"authenticated"}';
select public.approve_follow_request('f0c00000-0000-0000-0000-0000000000b1');
reset role;

-- (10)
select results_eq(
  $$ select
       (select count(*)::int from user_follows
         where follower_id = 'f0c00000-0000-0000-0000-0000000000b1'
           and followee_id = 'f0c00000-0000-0000-0000-00000000000a'),
       (select count(*)::int from follow_requests
         where requester_id = 'f0c00000-0000-0000-0000-0000000000b1'),
       (select count(*)::int from notifications
         where actor_id = 'f0c00000-0000-0000-0000-0000000000b1') $$,
  $$ values (1, 0, 0) $$,
  'approval still moves the request into user_follows and retracts the unread notice');

-- ── The table is the server's ──
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"f0c00000-0000-0000-0000-0000000000b2","role":"authenticated"}';

-- (11)
select throws_ok(
  $$ select count(*) from private.follow_request_notices $$,
  '42501', null,
  'a signed-in user cannot read the cooldown rows');
reset role;

-- ── Retention ──
update private.follow_request_notices
   set notified_at = now() - interval '25 hours'
 where requester_id = 'f0c00000-0000-0000-0000-0000000000b2';

-- (12)
select ok(
  private.cleanup_stale_follow_request_notices() >= 1,
  'the sweep deletes the row past the window');

-- (13)
select results_eq(
  $$ select requester_id::text from private.follow_request_notices
      where target_id = 'f0c00000-0000-0000-0000-00000000000a' $$,
  $$ values ('f0c00000-0000-0000-0000-0000000000b1') $$,
  'the sweep keeps a row still inside its window');

-- (14)
select is(
  (select count(*)::int from cron.job where jobname = 'cleanup-stale-follow-request-notices'),
  1,
  'the sweep is scheduled');

select * from finish();
rollback;

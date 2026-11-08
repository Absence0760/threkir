-- Pins 20271119002396: race_course_review_queue() lists the races with
-- pending course suggestions the caller may review (issue #1297, decisions
-- § 2396).
--
-- A claimed race reaches its organiser club's owners/admins only; an
-- unclaimed race reaches the owners/admins of every verified club. A plain
-- member, the owner of an unverified club and anon see nothing. Only
-- suggestions on a public route count, a reviewed suggestion leaves the
-- queue, a claim moves the race to the claiming club alone, and a club that
-- loses its verification loses the queue.

begin;
select plan(13);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('a1d00000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'rcq-org@rcq.local', '', now(), now()),
  ('a1d00000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'rcq-member@rcq.local', '', now(), now()),
  ('a1d00000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'rcq-other@rcq.local', '', now(), now()),
  ('a1d00000-0000-0000-0000-000000000004', 'authenticated', 'authenticated', 'rcq-runner@rcq.local', '', now(), now())
on conflict (id) do nothing;

select tests.confirm_consent();

-- V: verified (owner org). W: verified (owner other). U: never verified
-- (owner runner).
insert into clubs (id, owner_id, name, slug, is_public)
values
  ('a1d11111-0000-0000-0000-000000000001', 'a1d00000-0000-0000-0000-000000000001', 'RCQ Marathon', 'rcq-marathon', true),
  ('a1d11111-0000-0000-0000-000000000002', 'a1d00000-0000-0000-0000-000000000003', 'RCQ Other Org', 'rcq-other', true),
  ('a1d11111-0000-0000-0000-000000000003', 'a1d00000-0000-0000-0000-000000000004', 'RCQ Fan Club', 'rcq-fan', true);

set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';
update clubs set is_verified = true
 where id in ('a1d11111-0000-0000-0000-000000000001', 'a1d11111-0000-0000-0000-000000000002');
reset role;
set local "request.jwt.claims" = '';

insert into club_members (club_id, user_id, role, status)
values ('a1d11111-0000-0000-0000-000000000001', 'a1d00000-0000-0000-0000-000000000002', 'member', 'active')
on conflict do nothing;

insert into routes (id, user_id, name, waypoints, distance_m, elevation_m, surface, is_public)
values
  ('a1d22222-0000-0000-0000-000000000001', 'a1d00000-0000-0000-0000-000000000004',
   'RCQ runner trace', '[]'::jsonb, 42300, 160, 'road', true),
  ('a1d22222-0000-0000-0000-000000000002', 'a1d00000-0000-0000-0000-000000000004',
   'RCQ runner private trace', '[]'::jsonb, 42300, 160, 'road', false),
  ('a1d22222-0000-0000-0000-000000000003', 'a1d00000-0000-0000-0000-000000000002',
   'RCQ member trace', '[]'::jsonb, 21100, 80, 'road', true);

-- L1 claimed by V, L2 unclaimed, L3 claimed by W, L4 unclaimed with no
-- suggestion, L5 unclaimed with a suggestion on a private route only.
set local role service_role;
insert into race_listings (id, provider, provider_race_id, name, race_date, distance_m, organiser_club_id)
values
  ('a1d33333-0000-0000-0000-000000000001', 'runsignup', 'rcq-1', 'RCQ City Marathon', '2036-11-14', 42195,
   'a1d11111-0000-0000-0000-000000000001'),
  ('a1d33333-0000-0000-0000-000000000002', 'runsignup', 'rcq-2', 'RCQ Unclaimed Half', '2036-11-21', 21097, null),
  ('a1d33333-0000-0000-0000-000000000003', 'runsignup', 'rcq-3', 'RCQ Other Marathon', '2036-11-28', 42195,
   'a1d11111-0000-0000-0000-000000000002'),
  ('a1d33333-0000-0000-0000-000000000004', 'runsignup', 'rcq-4', 'RCQ Quiet 10K', '2036-12-05', 10000, null),
  ('a1d33333-0000-0000-0000-000000000005', 'runsignup', 'rcq-5', 'RCQ Private 5K', '2036-12-12', 5000, null);
reset role;

insert into race_course_suggestions (id, listing_id, route_id, user_id)
values
  ('a1d44444-0000-0000-0000-000000000001', 'a1d33333-0000-0000-0000-000000000001',
   'a1d22222-0000-0000-0000-000000000001', 'a1d00000-0000-0000-0000-000000000004'),
  ('a1d44444-0000-0000-0000-000000000002', 'a1d33333-0000-0000-0000-000000000002',
   'a1d22222-0000-0000-0000-000000000001', 'a1d00000-0000-0000-0000-000000000004'),
  ('a1d44444-0000-0000-0000-000000000003', 'a1d33333-0000-0000-0000-000000000002',
   'a1d22222-0000-0000-0000-000000000003', 'a1d00000-0000-0000-0000-000000000002'),
  ('a1d44444-0000-0000-0000-000000000004', 'a1d33333-0000-0000-0000-000000000003',
   'a1d22222-0000-0000-0000-000000000001', 'a1d00000-0000-0000-0000-000000000004'),
  ('a1d44444-0000-0000-0000-000000000005', 'a1d33333-0000-0000-0000-000000000005',
   'a1d22222-0000-0000-0000-000000000002', 'a1d00000-0000-0000-0000-000000000004');

-- ── who sees the queue ──────────────────────────────────────────────────────

set local role anon;
select throws_ok(
  $$ select * from race_course_review_queue() $$,
  '42501', null,
  'anon cannot read the review queue'
);
reset role;

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"a1d00000-0000-0000-0000-000000000004","role":"authenticated"}';
select is_empty(
  $$ select * from race_course_review_queue() where listing_id::text like 'a1d33333-%' $$,
  'the owner of an unverified club sees no review queue'
);
reset role;

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"a1d00000-0000-0000-0000-000000000002","role":"authenticated"}';
select is_empty(
  $$ select * from race_course_review_queue() where listing_id::text like 'a1d33333-%' $$,
  'a plain member of a verified club sees no review queue'
);
reset role;

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"a1d00000-0000-0000-0000-000000000001","role":"authenticated"}';
select results_eq(
  $$ select listing_id, organiser_club_id, pending_count from race_course_review_queue()
      where listing_id::text like 'a1d33333-%' $$,
  $$ values ('a1d33333-0000-0000-0000-000000000001'::uuid, 'a1d11111-0000-0000-0000-000000000001'::uuid, 1),
            ('a1d33333-0000-0000-0000-000000000002'::uuid, null::uuid, 2) $$,
  'a verified club''s owner sees its own race and the unclaimed race, not another club''s or one with only a private route suggested'
);
select results_eq(
  $$ select name, race_date from race_course_review_queue()
      where listing_id = 'a1d33333-0000-0000-0000-000000000002' $$,
  $$ values ('RCQ Unclaimed Half'::text, '2036-11-21'::date) $$,
  'each queued race carries its name and date'
);
reset role;

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"a1d00000-0000-0000-0000-000000000003","role":"authenticated"}';
select results_eq(
  $$ select listing_id from race_course_review_queue() where listing_id::text like 'a1d33333-%' $$,
  $$ values ('a1d33333-0000-0000-0000-000000000002'::uuid), ('a1d33333-0000-0000-0000-000000000003'::uuid) $$,
  'another verified club''s owner sees the unclaimed race and its own'
);
reset role;

-- ── claiming moves the race to the claiming club alone ──────────────────────

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"a1d00000-0000-0000-0000-000000000001","role":"authenticated"}';
select lives_ok(
  $$ select claim_race_listing('a1d33333-0000-0000-0000-000000000002', 'a1d11111-0000-0000-0000-000000000001') $$,
  'the owner claims the unclaimed race from the queue'
);
reset role;
select is(
  (select organiser_club_id from race_listings where id = 'a1d33333-0000-0000-0000-000000000002'),
  'a1d11111-0000-0000-0000-000000000001'::uuid,
  'the claim from the queue records the organiser club'
);

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"a1d00000-0000-0000-0000-000000000003","role":"authenticated"}';
select results_eq(
  $$ select listing_id from race_course_review_queue() where listing_id::text like 'a1d33333-%' $$,
  $$ values ('a1d33333-0000-0000-0000-000000000003'::uuid) $$,
  'once claimed, the race leaves every other club''s queue'
);
reset role;

-- ── a reviewed suggestion leaves the queue ──────────────────────────────────

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"a1d00000-0000-0000-0000-000000000001","role":"authenticated"}';
select lives_ok(
  $$ select review_race_course_suggestion('a1d44444-0000-0000-0000-000000000001', false, null, null) $$,
  'the organiser rejects the only suggestion on its race'
);
select results_eq(
  $$ select listing_id, organiser_club_id, pending_count from race_course_review_queue()
      where listing_id::text like 'a1d33333-%' $$,
  $$ values ('a1d33333-0000-0000-0000-000000000002'::uuid, 'a1d11111-0000-0000-0000-000000000001'::uuid, 2) $$,
  'a race with no pending suggestion left drops out of the queue'
);
reset role;
select is(
  (select status from race_course_suggestions where id = 'a1d44444-0000-0000-0000-000000000001'),
  'rejected',
  'the rejection marks the suggestion rejected'
);

-- ── losing verification loses the queue ─────────────────────────────────────

set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';
update clubs set is_verified = false where id = 'a1d11111-0000-0000-0000-000000000001';
reset role;

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"a1d00000-0000-0000-0000-000000000001","role":"authenticated"}';
select is_empty(
  $$ select * from race_course_review_queue() where listing_id::text like 'a1d33333-%' $$,
  'a club that is no longer verified has no review queue'
);
reset role;

select * from finish();
rollback;

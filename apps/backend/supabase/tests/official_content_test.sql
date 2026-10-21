-- Pins 20271021000030: "official" content is derived from the verified club,
-- never stored per row (issue #1190, decisions § 2227).
--
-- Official = the row's club is verified, public and not hidden, and the row's
-- author is an ACTIVE owner or admin of it. A plain member's club content is
-- not official, nor is an unverified or private club's; revoking the badge or
-- demoting the publisher clears it at once; a client can neither write the
-- flag (there is no column) nor verify its own club. Anon reads it on public
-- rows and never sees a private row through it.

begin;
select plan(20);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('0f1c0000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'oc-owner@oc.local', '', now(), now()),
  ('0f1c0000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'oc-admin@oc.local', '', now(), now()),
  ('0f1c0000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'oc-member@oc.local', '', now(), now()),
  ('0f1c0000-0000-0000-0000-000000000004', 'authenticated', 'authenticated', 'oc-outsider@oc.local', '', now(), now())
on conflict (id) do nothing;

update user_profiles set age_confirmed_at = now()
where id in ('0f1c0000-0000-0000-0000-000000000002', '0f1c0000-0000-0000-0000-000000000004');

-- V: verified + public. U: public, never verified. P: verified but private.
-- The owner is enrolled by enroll_club_owner; is_verified is service-role only.
insert into clubs (id, owner_id, name, slug, is_public)
values
  ('0f1c1111-0000-0000-0000-000000000001', '0f1c0000-0000-0000-0000-000000000001', 'Official Marathon', 'oc-official', true),
  ('0f1c1111-0000-0000-0000-000000000002', '0f1c0000-0000-0000-0000-000000000004', 'Fan Club', 'oc-fan', true),
  ('0f1c1111-0000-0000-0000-000000000003', '0f1c0000-0000-0000-0000-000000000001', 'Private Org', 'oc-private', false);

set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';
update clubs set is_verified = true
where id in ('0f1c1111-0000-0000-0000-000000000001', '0f1c1111-0000-0000-0000-000000000003');
reset role;

insert into club_members (club_id, user_id, role, status)
values
  ('0f1c1111-0000-0000-0000-000000000001', '0f1c0000-0000-0000-0000-000000000002', 'admin', 'active'),
  ('0f1c1111-0000-0000-0000-000000000001', '0f1c0000-0000-0000-0000-000000000003', 'member', 'active'),
  ('0f1c1111-0000-0000-0000-000000000003', '0f1c0000-0000-0000-0000-000000000002', 'admin', 'active');

insert into routes (id, user_id, club_id, name, waypoints, distance_m, surface, is_public)
values
  ('0f1c2222-0000-0000-0000-000000000001', '0f1c0000-0000-0000-0000-000000000002', '0f1c1111-0000-0000-0000-000000000001',
   'Official course', '[]'::jsonb, 42195, 'road', true),
  ('0f1c2222-0000-0000-0000-000000000002', '0f1c0000-0000-0000-0000-000000000003', '0f1c1111-0000-0000-0000-000000000001',
   'Member loop', '[]'::jsonb, 5000, 'road', true),
  ('0f1c2222-0000-0000-0000-000000000003', '0f1c0000-0000-0000-0000-000000000004', '0f1c1111-0000-0000-0000-000000000002',
   'Fan copy', '[]'::jsonb, 42195, 'road', true),
  ('0f1c2222-0000-0000-0000-000000000004', '0f1c0000-0000-0000-0000-000000000002', '0f1c1111-0000-0000-0000-000000000003',
   'Private org course', '[]'::jsonb, 10000, 'road', true),
  ('0f1c2222-0000-0000-0000-000000000005', '0f1c0000-0000-0000-0000-000000000002', null,
   'Admin personal loop', '[]'::jsonb, 8000, 'road', true);

insert into training_plans (id, user_id, club_id, name, goal_event, goal_distance_m, start_date, end_date,
                            status, is_template, is_public_template)
values
  ('0f1c3333-0000-0000-0000-000000000001', '0f1c0000-0000-0000-0000-000000000002', '0f1c1111-0000-0000-0000-000000000001',
   'Official marathon plan', 'distance_full', 42195, '2036-01-01', '2036-04-01', 'completed', true, true);

insert into gym_routines (id, author_id, club_id, title)
values
  ('0f1c4444-0000-0000-0000-000000000001', '0f1c0000-0000-0000-0000-000000000002', '0f1c1111-0000-0000-0000-000000000001',
   'Official strength block');

insert into challenges (id, creator_id, club_id, title, metric, scope, starts_at, ends_at, is_public, participant_count)
values
  ('0f1c5555-0000-0000-0000-000000000001', '0f1c0000-0000-0000-0000-000000000002', '0f1c1111-0000-0000-0000-000000000001',
   'Official 100 km', 'distance', 'individual', now() - interval '1 day', now() + interval '30 days', true, 1);

insert into session_plans (id, author_id, club_id, title, is_public)
values
  ('0f1c6666-0000-0000-0000-000000000001', '0f1c0000-0000-0000-0000-000000000002', '0f1c1111-0000-0000-0000-000000000001',
   'Official mobility flow', true),
  ('0f1c6666-0000-0000-0000-000000000002', '0f1c0000-0000-0000-0000-000000000002', '0f1c1111-0000-0000-0000-000000000001',
   'Members-only flow', false);

-- ── the derivation ─────────────────────────────────────────────────────────

-- 1. Verified club + active admin author → official.
select ok(
  (select r.is_official from routes r where r.id = '0f1c2222-0000-0000-0000-000000000001'),
  'a verified club''s admin publishes an official route'
);

-- 2. A plain member's club route is not.
select is(
  (select r.is_official from routes r where r.id = '0f1c2222-0000-0000-0000-000000000002'),
  false,
  'a member who is not an owner/admin does not publish official content'
);

-- 3. An unverified club's owner is not.
select is(
  (select r.is_official from routes r where r.id = '0f1c2222-0000-0000-0000-000000000003'),
  false,
  'an unverified club''s content is not official'
);

-- 4. A private club lends no badge, even verified: a public route never
--    reveals its private-club association (public_routes masks club_id).
select is(
  (select r.is_official from routes r where r.id = '0f1c2222-0000-0000-0000-000000000004'),
  false,
  'a private verified club''s content is not official'
);

-- 5. The admin's own content with no club is not.
select is(
  (select r.is_official from routes r where r.id = '0f1c2222-0000-0000-0000-000000000005'),
  false,
  'content outside a club is not official, whoever wrote it'
);

-- 6-9. The same derivation on every content table.
select ok(
  (select p.is_official from training_plans p where p.id = '0f1c3333-0000-0000-0000-000000000001'),
  'training_plans.is_official derives from the verified club'
);
select ok(
  (select g.is_official from gym_routines g where g.id = '0f1c4444-0000-0000-0000-000000000001'),
  'gym_routines.is_official derives from the verified club'
);
select ok(
  (select c.is_official from challenges c where c.id = '0f1c5555-0000-0000-0000-000000000001'),
  'challenges.is_official derives from the verified club'
);
select ok(
  (select s.is_official from session_plans s where s.id = '0f1c6666-0000-0000-0000-000000000001'),
  'session_plans.is_official derives from the verified club'
);

-- ── no forgery ─────────────────────────────────────────────────────────────
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"0f1c0000-0000-0000-0000-000000000004","role":"authenticated"}';

-- 10. There is no column to write.
select throws_ok(
  $$ insert into routes (user_id, name, waypoints, distance_m, surface, is_public, is_official)
     values ('0f1c0000-0000-0000-0000-000000000004', 'Forged', '[]'::jsonb, 1000, 'road', true, true) $$,
  '42703',
  null,
  'is_official is derived: a client cannot write it'
);

-- 11. A non-admin cannot file content under the verified club.
select throws_ok(
  $$ insert into routes (user_id, club_id, name, waypoints, distance_m, surface, is_public)
     values ('0f1c0000-0000-0000-0000-000000000004', '0f1c1111-0000-0000-0000-000000000001',
             'Squatter', '[]'::jsonb, 1000, 'road', true) $$,
  '42501',
  null,
  'an outsider cannot publish under a verified club'
);

-- 12. The fan club's owner cannot verify their own club.
update clubs set is_verified = true where id = '0f1c1111-0000-0000-0000-000000000002';
reset role;
select is(
  (select is_verified from clubs where id = '0f1c1111-0000-0000-0000-000000000002'),
  false,
  'a club owner cannot verify their own club'
);

-- ── who can read it ────────────────────────────────────────────────────────
set local role anon;
set local "request.jwt.claims" = '';

-- 13. Anon reads the flag on a public route through public_routes.
select ok(
  (select is_official from public_routes where id = '0f1c2222-0000-0000-0000-000000000001'),
  'anon reads is_official on a public route'
);

-- 14. Anon reads the computed field on a public session plan.
select ok(
  (select s.is_official from session_plans s where s.id = '0f1c6666-0000-0000-0000-000000000001'),
  'anon reads is_official on a public session plan'
);

-- 15. ...and the flag never surfaces a private row: RLS still decides.
select is(
  (select count(*)::int from session_plans s where s.id = '0f1c6666-0000-0000-0000-000000000002'),
  0,
  'an official club''s members-only session plan stays hidden from anon'
);

-- 16. The challenge browse carries the flag for a logged-out visitor.
select ok(
  (select b.is_official from browse_public_challenges(null, 100, 0) b
   where b.id = '0f1c5555-0000-0000-0000-000000000001'),
  'browse_public_challenges returns is_official'
);
reset role;

-- ── revocation is immediate ────────────────────────────────────────────────

-- 17. Demoting the publisher clears their content.
update club_members set role = 'member'
where club_id = '0f1c1111-0000-0000-0000-000000000001'
  and user_id = '0f1c0000-0000-0000-0000-000000000002';
select is(
  (select r.is_official from routes r where r.id = '0f1c2222-0000-0000-0000-000000000001'),
  false,
  'a demoted admin''s content stops reading as official'
);
update club_members set role = 'admin'
where club_id = '0f1c1111-0000-0000-0000-000000000001'
  and user_id = '0f1c0000-0000-0000-0000-000000000002';

-- 18. The owner's own content is official too.
update routes set user_id = '0f1c0000-0000-0000-0000-000000000001'
where id = '0f1c2222-0000-0000-0000-000000000002';
select ok(
  (select r.is_official from routes r where r.id = '0f1c2222-0000-0000-0000-000000000002'),
  'the verified club''s owner publishes official content'
);

-- 19-20. Revoking the club's badge clears every piece of its content at once.
set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';
update clubs set is_verified = false where id = '0f1c1111-0000-0000-0000-000000000001';
reset role;
select is(
  (select count(*)::int from routes r
   where r.club_id = '0f1c1111-0000-0000-0000-000000000001' and r.is_official),
  0,
  'revoking the badge clears every official route of the club'
);
select is(
  (select bool_or(x) from (
     select p.is_official as x from training_plans p where p.id = '0f1c3333-0000-0000-0000-000000000001'
     union all select g.is_official from gym_routines g where g.id = '0f1c4444-0000-0000-0000-000000000001'
     union all select c.is_official from challenges c where c.id = '0f1c5555-0000-0000-0000-000000000001'
     union all select s.is_official from session_plans s where s.id = '0f1c6666-0000-0000-0000-000000000001'
   ) t),
  false,
  'revoking the badge clears the club''s plans, routines, challenges and session plans'
);

select * from finish();
rollback;

-- Pins 20271114002381: a verified club claims a race and links its course
-- (issue #1297, decisions § 2381).
--
-- Only an active owner/admin of a public, verified club can claim an
-- unclaimed listing; claiming verifies it and is audit-logged. Only an
-- owner/admin of the listing's organiser club can link a course, and only a
-- route that is public and owned by that club. Another club's admin, a plain
-- member, a plain runner and anon are refused. A runner's direct write cannot
-- reach any of the new columns. Editing a linked route's line flags the
-- course; re-checking clears it. A runner suggests, never links; the
-- organiser club reviews, and approval goes through the same route checks.
-- Deleting the route clears the link and keeps the race verified and claimed.

begin;
select plan(45);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('a1c00000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'rcl-org@rcl.local', '', now(), now()),
  ('a1c00000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'rcl-member@rcl.local', '', now(), now()),
  ('a1c00000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'rcl-other@rcl.local', '', now(), now()),
  ('a1c00000-0000-0000-0000-000000000004', 'authenticated', 'authenticated', 'rcl-runner@rcl.local', '', now(), now())
on conflict (id) do nothing;

select tests.confirm_consent();

-- V: verified organiser (owner org). W: another verified club (owner other).
-- U: the runner's own club, never verified.
insert into clubs (id, owner_id, name, slug, is_public)
values
  ('a1c11111-0000-0000-0000-000000000001', 'a1c00000-0000-0000-0000-000000000001', 'RCL Marathon', 'rcl-marathon', true),
  ('a1c11111-0000-0000-0000-000000000002', 'a1c00000-0000-0000-0000-000000000003', 'RCL Other Org', 'rcl-other', true),
  ('a1c11111-0000-0000-0000-000000000003', 'a1c00000-0000-0000-0000-000000000004', 'RCL Fan Club', 'rcl-fan', true);

set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';
update clubs set is_verified = true
 where id in ('a1c11111-0000-0000-0000-000000000001', 'a1c11111-0000-0000-0000-000000000002');
reset role;
set local "request.jwt.claims" = '';

insert into club_members (club_id, user_id, role, status)
values ('a1c11111-0000-0000-0000-000000000001', 'a1c00000-0000-0000-0000-000000000002', 'member', 'active')
on conflict do nothing;

insert into routes (id, user_id, club_id, name, waypoints, distance_m, elevation_m, surface, is_public)
values
  ('a1c22222-0000-0000-0000-000000000001', 'a1c00000-0000-0000-0000-000000000001', 'a1c11111-0000-0000-0000-000000000001',
   'RCL official course', '[]'::jsonb, 42195, 150, 'road', true),
  ('a1c22222-0000-0000-0000-000000000002', 'a1c00000-0000-0000-0000-000000000001', 'a1c11111-0000-0000-0000-000000000001',
   'RCL draft course', '[]'::jsonb, 42195, 150, 'road', false),
  ('a1c22222-0000-0000-0000-000000000003', 'a1c00000-0000-0000-0000-000000000003', 'a1c11111-0000-0000-0000-000000000002',
   'RCL other club course', '[]'::jsonb, 42195, 150, 'road', true),
  ('a1c22222-0000-0000-0000-000000000004', 'a1c00000-0000-0000-0000-000000000004', null,
   'RCL runner trace', '[]'::jsonb, 42300, 160, 'road', true),
  ('a1c22222-0000-0000-0000-000000000005', 'a1c00000-0000-0000-0000-000000000004', null,
   'RCL runner private trace', '[]'::jsonb, 42300, 160, 'road', false);

set local role service_role;
insert into race_listings (id, provider, provider_race_id, name, race_date, distance_m, is_verified)
values
  ('a1c33333-0000-0000-0000-000000000001', 'runsignup', 'rcl-1', 'RCL City Marathon', '2036-11-14', 42195, false),
  ('a1c33333-0000-0000-0000-000000000002', 'runsignup', 'rcl-2', 'RCL Unclaimed Half', '2036-11-21', 21097, false);
reset role;

-- ── claim ───────────────────────────────────────────────────────────────────

set local role anon;
select throws_ok(
  $$ select claim_race_listing('a1c33333-0000-0000-0000-000000000001', 'a1c11111-0000-0000-0000-000000000001') $$,
  '42501', null,
  'anon cannot claim a race'
);
reset role;

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"a1c00000-0000-0000-0000-000000000004","role":"authenticated"}';
select throws_ok(
  $$ select claim_race_listing('a1c33333-0000-0000-0000-000000000001', 'a1c11111-0000-0000-0000-000000000003') $$,
  '42501', 'only an owner or admin of a verified club can claim a race',
  'the owner of an unverified club cannot claim a race'
);
reset role;

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"a1c00000-0000-0000-0000-000000000002","role":"authenticated"}';
select throws_ok(
  $$ select claim_race_listing('a1c33333-0000-0000-0000-000000000001', 'a1c11111-0000-0000-0000-000000000001') $$,
  '42501', 'only an owner or admin of a verified club can claim a race',
  'a plain member of a verified club cannot claim for it'
);
reset role;

select is(
  (select organiser_club_id from race_listings where id = 'a1c33333-0000-0000-0000-000000000001'),
  null::uuid,
  'the refused claims left the race unclaimed'
);

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"a1c00000-0000-0000-0000-000000000001","role":"authenticated"}';
select lives_ok(
  $$ select claim_race_listing('a1c33333-0000-0000-0000-000000000001', 'a1c11111-0000-0000-0000-000000000001') $$,
  'the verified club''s owner claims the race'
);
reset role;

select results_eq(
  $$ select organiser_club_id, is_verified from race_listings where id = 'a1c33333-0000-0000-0000-000000000001' $$,
  $$ values ('a1c11111-0000-0000-0000-000000000001'::uuid, true) $$,
  'the claim records the organiser club and verifies the race'
);
select results_eq(
  $$ select club_id, actor_id, action from race_listing_audit where listing_id = 'a1c33333-0000-0000-0000-000000000001' $$,
  $$ values ('a1c11111-0000-0000-0000-000000000001'::uuid, 'a1c00000-0000-0000-0000-000000000001'::uuid, 'claim'::text) $$,
  'the claim is audit-logged'
);

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"a1c00000-0000-0000-0000-000000000003","role":"authenticated"}';
select throws_ok(
  $$ select claim_race_listing('a1c33333-0000-0000-0000-000000000001', 'a1c11111-0000-0000-0000-000000000002') $$,
  '23505', 'this race is already claimed by another club',
  'another verified club cannot take a claimed race'
);
reset role;
select is(
  (select organiser_club_id from race_listings where id = 'a1c33333-0000-0000-0000-000000000001'),
  'a1c11111-0000-0000-0000-000000000001'::uuid,
  'the race stays with the club that claimed it'
);

select is(
  (select organiser_club_name from public_race_listings where id = 'a1c33333-0000-0000-0000-000000000001'),
  'RCL Marathon',
  'the calendar names the organiser club'
);

-- ── link ────────────────────────────────────────────────────────────────────

set local role anon;
select throws_ok(
  $$ select link_race_course('a1c33333-0000-0000-0000-000000000001', 'a1c22222-0000-0000-0000-000000000001', 'official') $$,
  '42501', null,
  'anon cannot link a course'
);
reset role;

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"a1c00000-0000-0000-0000-000000000003","role":"authenticated"}';
select throws_ok(
  $$ select link_race_course('a1c33333-0000-0000-0000-000000000001', 'a1c22222-0000-0000-0000-000000000003', 'official') $$,
  '42501', 'only an owner or admin of the race''s verified organiser club can link its course',
  'another verified club''s admin cannot link a course'
);
reset role;

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"a1c00000-0000-0000-0000-000000000004","role":"authenticated"}';
select throws_ok(
  $$ select link_race_course('a1c33333-0000-0000-0000-000000000001', 'a1c22222-0000-0000-0000-000000000004', 'official') $$,
  '42501', 'only an owner or admin of the race''s verified organiser club can link its course',
  'a plain runner cannot link a course'
);
reset role;

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"a1c00000-0000-0000-0000-000000000002","role":"authenticated"}';
select throws_ok(
  $$ select link_race_course('a1c33333-0000-0000-0000-000000000001', 'a1c22222-0000-0000-0000-000000000001', 'official') $$,
  '42501', 'only an owner or admin of the race''s verified organiser club can link its course',
  'a plain member of the organiser club cannot link a course'
);
reset role;

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"a1c00000-0000-0000-0000-000000000001","role":"authenticated"}';
select throws_ok(
  $$ select link_race_course('a1c33333-0000-0000-0000-000000000001', 'a1c22222-0000-0000-0000-000000000004', 'official') $$,
  '42501', 'the course must be a public route owned by the organiser club',
  'the organiser cannot link a runner''s personal route'
);
select throws_ok(
  $$ select link_race_course('a1c33333-0000-0000-0000-000000000001', 'a1c22222-0000-0000-0000-000000000002', 'official') $$,
  '42501', 'the course must be a public route owned by the organiser club',
  'the organiser cannot link its own private route'
);
select throws_ok(
  $$ select link_race_course('a1c33333-0000-0000-0000-000000000001', 'a1c22222-0000-0000-0000-000000000003', 'official') $$,
  '42501', 'the course must be a public route owned by the organiser club',
  'the organiser cannot link another club''s route'
);
select throws_ok(
  $$ select link_race_course('a1c33333-0000-0000-0000-000000000001', 'a1c22222-0000-0000-0000-000000000001', 'guessed') $$,
  '22023', 'course source must be official or traced',
  'the course source is one of official or traced'
);
reset role;

select is(
  (select route_id from race_listings where id = 'a1c33333-0000-0000-0000-000000000001'),
  null::uuid,
  'every refused link left the race without a course'
);

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"a1c00000-0000-0000-0000-000000000001","role":"authenticated"}';
select lives_ok(
  $$ select link_race_course('a1c33333-0000-0000-0000-000000000001', 'a1c22222-0000-0000-0000-000000000001', 'traced') $$,
  'the organiser links its own public route'
);
reset role;

select results_eq(
  $$ select route_id, course_source, course_checked_at is not null, course_updated_at
       from race_listings where id = 'a1c33333-0000-0000-0000-000000000001' $$,
  $$ values ('a1c22222-0000-0000-0000-000000000001'::uuid, 'traced'::text, true, null::timestamptz) $$,
  'the link stores the route, its source and the checked date'
);

set local role anon;
set local "request.jwt.claims" = '';
select results_eq(
  $$ select course_route_id, course_source, course_checked_at is not null, organiser_club_slug
       from public_race_listings where id = 'a1c33333-0000-0000-0000-000000000001' $$,
  $$ values ('a1c22222-0000-0000-0000-000000000001'::uuid, 'traced'::text, true, 'rcl-marathon'::text) $$,
  'anon reads the course, where it came from, and the organiser'
);
reset role;

-- ── direct writes stay closed ───────────────────────────────────────────────

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"a1c00000-0000-0000-0000-000000000004","role":"authenticated"}';
insert into race_listings (id, provider, name, race_date, submitted_by, organiser_club_id, course_source,
                           course_checked_at, course_updated_at)
values ('a1c33333-0000-0000-0000-000000000003', 'manual', 'RCL Runner 5K', '2036-12-05',
        'a1c00000-0000-0000-0000-000000000004', 'a1c11111-0000-0000-0000-000000000001', 'official', now(), now());
update race_listings
   set organiser_club_id = 'a1c11111-0000-0000-0000-000000000001', course_source = 'official',
       name = 'RCL Runner 5K (renamed)'
 where id = 'a1c33333-0000-0000-0000-000000000003';
reset role;

select results_eq(
  $$ select name, organiser_club_id, course_source, course_checked_at, course_updated_at
       from race_listings where id = 'a1c33333-0000-0000-0000-000000000003' $$,
  $$ values ('RCL Runner 5K (renamed)'::text, null::uuid, null::text, null::timestamptz, null::timestamptz) $$,
  'a submitter''s insert and update cannot set the organiser or the course provenance'
);

-- ── decision 4: an edit to the linked route is flagged ──────────────────────

update routes set waypoints = '[{"lat":37.54,"lng":-77.43}]'::jsonb
 where id = 'a1c22222-0000-0000-0000-000000000001';
select isnt(
  (select course_updated_at from race_listings where id = 'a1c33333-0000-0000-0000-000000000001'),
  null::timestamptz,
  'editing the linked route''s line flags the course as updated'
);
update routes set name = 'RCL official course (renamed)'
 where id = 'a1c22222-0000-0000-0000-000000000003';
select is(
  (select count(*)::int from race_listings where course_updated_at is not null
      and id in ('a1c33333-0000-0000-0000-000000000001', 'a1c33333-0000-0000-0000-000000000002')),
  1,
  'only the race on the edited route is flagged'
);

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"a1c00000-0000-0000-0000-000000000001","role":"authenticated"}';
select lives_ok(
  $$ select link_race_course('a1c33333-0000-0000-0000-000000000001', 'a1c22222-0000-0000-0000-000000000001', 'traced') $$,
  'the organiser re-checks the course'
);
reset role;
select is(
  (select course_updated_at from race_listings where id = 'a1c33333-0000-0000-0000-000000000001'),
  null::timestamptz,
  're-checking clears the updated flag'
);

-- ── suggestions ─────────────────────────────────────────────────────────────

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"a1c00000-0000-0000-0000-000000000004","role":"authenticated"}';
select throws_ok(
  $$ select suggest_race_course('a1c33333-0000-0000-0000-000000000001', 'a1c22222-0000-0000-0000-000000000005', null) $$,
  '42501', 'only a public route can be suggested as a course',
  'a private route cannot be suggested'
);
select lives_ok(
  $$ select suggest_race_course('a1c33333-0000-0000-0000-000000000001', 'a1c22222-0000-0000-0000-000000000004', 'Traced from the 2036 map') $$,
  'a runner suggests a public route for a claimed race'
);
select lives_ok(
  $$ select suggest_race_course('a1c33333-0000-0000-0000-000000000002', 'a1c22222-0000-0000-0000-000000000004', null) $$,
  'a runner suggests a public route for an unclaimed race'
);
select is(
  (select count(*)::int from race_course_suggestions where status = 'pending'),
  2,
  'the runner reads their own two pending suggestions'
);
reset role;

select is(
  (select route_id from race_listings where id = 'a1c33333-0000-0000-0000-000000000002'),
  null::uuid,
  'a suggestion links nothing'
);

-- A reviewer cannot read the suggestion table itself, so its id is handed in.
create temporary table rcl_suggestion as
  select id from race_course_suggestions where listing_id = 'a1c33333-0000-0000-0000-000000000001';
grant select on rcl_suggestion to authenticated;

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"a1c00000-0000-0000-0000-000000000001","role":"authenticated"}';
select results_eq(
  $$ select route_id, note from race_course_suggestions_for_review('a1c33333-0000-0000-0000-000000000001') $$,
  $$ values ('a1c22222-0000-0000-0000-000000000004'::uuid, 'Traced from the 2036 map'::text) $$,
  'the organiser sees the pending suggestion for its race'
);
reset role;

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"a1c00000-0000-0000-0000-000000000003","role":"authenticated"}';
select is(
  (select count(*)::int from race_course_suggestions_for_review('a1c33333-0000-0000-0000-000000000001')),
  0,
  'another club''s admin does not see a claimed race''s suggestions'
);
select is(
  (select count(*)::int from race_course_suggestions_for_review('a1c33333-0000-0000-0000-000000000002')),
  1,
  'a verified club''s admin sees an unclaimed race''s suggestion'
);
select throws_ok(
  $$ select review_race_course_suggestion(
       (select id from rcl_suggestion),
       true, 'a1c22222-0000-0000-0000-000000000003', 'official') $$,
  '42501', 'only an owner or admin of the race''s verified organiser club can review its suggestions',
  'another club''s admin cannot approve a claimed race''s suggestion'
);
reset role;

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"a1c00000-0000-0000-0000-000000000002","role":"authenticated"}';
select is(
  (select count(*)::int from race_course_suggestions_for_review('a1c33333-0000-0000-0000-000000000002')),
  0,
  'a plain member does not see an unclaimed race''s suggestion'
);
reset role;

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"a1c00000-0000-0000-0000-000000000001","role":"authenticated"}';
select throws_ok(
  $$ select review_race_course_suggestion(
       (select id from rcl_suggestion),
       true, null, 'official') $$,
  '42501', 'the course must be a public route owned by the organiser club',
  'approving cannot link the runner''s personal route itself'
);
select lives_ok(
  $$ select review_race_course_suggestion(
       (select id from rcl_suggestion),
       true, 'a1c22222-0000-0000-0000-000000000001', 'official') $$,
  'the organiser approves, linking the club''s own copy'
);
reset role;

select results_eq(
  $$ select s.status, s.reviewed_by, l.route_id, l.course_source
       from race_course_suggestions s join race_listings l on l.id = s.listing_id
      where s.listing_id = 'a1c33333-0000-0000-0000-000000000001' $$,
  $$ values ('approved'::text, 'a1c00000-0000-0000-0000-000000000001'::uuid,
             'a1c22222-0000-0000-0000-000000000001'::uuid, 'official'::text) $$,
  'approval marks the suggestion and links the club''s course'
);

-- ── unlink + route deletion ─────────────────────────────────────────────────

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"a1c00000-0000-0000-0000-000000000001","role":"authenticated"}';
select lives_ok(
  $$ select link_race_course('a1c33333-0000-0000-0000-000000000001', null, null) $$,
  'the organiser unlinks the course'
);
reset role;
select results_eq(
  $$ select route_id, course_source from race_listings where id = 'a1c33333-0000-0000-0000-000000000001' $$,
  $$ values (null::uuid, null::text) $$,
  'unlinking clears the course and its source'
);

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"a1c00000-0000-0000-0000-000000000001","role":"authenticated"}';
select lives_ok(
  $$ select link_race_course('a1c33333-0000-0000-0000-000000000001', 'a1c22222-0000-0000-0000-000000000001', 'official') $$,
  'the organiser links the course again'
);
delete from routes where id = 'a1c22222-0000-0000-0000-000000000001';
reset role;

select results_eq(
  $$ select route_id, is_verified, organiser_club_id from race_listings where id = 'a1c33333-0000-0000-0000-000000000001' $$,
  $$ values (null::uuid, true, 'a1c11111-0000-0000-0000-000000000001'::uuid) $$,
  'deleting the route clears the link and keeps the race verified and claimed'
);
select is(
  (select array_agg(action order by id) from race_listing_audit where listing_id = 'a1c33333-0000-0000-0000-000000000001'),
  array['claim', 'link', 'link', 'suggestion_approved', 'unlink', 'link']::text[],
  'every claim, link, review and unlink is in the audit log'
);

select * from finish();
rollback;

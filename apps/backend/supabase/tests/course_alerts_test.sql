-- Pins 20271124002407 / 002408: organiser course alerts (issue #1190,
-- decisions § 2407).
--
-- Only an active owner/admin of the verified club that organises the race
-- (or owns the route) can post or remove an alert; a member, another
-- verified club's owner, a plain runner and anon are refused, and no client
-- can write the table directly. Posting tells the runners training for the
-- race and the runners who saved its course, once each, never the author and
-- never for a past race. Reads follow the club's standing and the route's
-- visibility, and never expose who typed the alert.

begin;
select plan(29);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('a1e00000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'cal-org@cal.local', '', now(), now()),
  ('a1e00000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'cal-member@cal.local', '', now(), now()),
  ('a1e00000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'cal-other@cal.local', '', now(), now()),
  ('a1e00000-0000-0000-0000-000000000004', 'authenticated', 'authenticated', 'cal-runner@cal.local', '', now(), now()),
  ('a1e00000-0000-0000-0000-000000000005', 'authenticated', 'authenticated', 'cal-saver@cal.local', '', now(), now()),
  ('a1e00000-0000-0000-0000-000000000006', 'authenticated', 'authenticated', 'cal-done@cal.local', '', now(), now())
on conflict (id) do nothing;

select tests.confirm_consent();

-- V: verified organiser (owner org, member member). W: another verified club.
insert into clubs (id, owner_id, name, slug, is_public)
values
  ('a1e11111-0000-0000-0000-000000000001', 'a1e00000-0000-0000-0000-000000000001', 'CAL Marathon', 'cal-marathon', true),
  ('a1e11111-0000-0000-0000-000000000002', 'a1e00000-0000-0000-0000-000000000003', 'CAL Other Org', 'cal-other', true);

set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';
update clubs set is_verified = true where id::text like 'a1e11111%';
reset role;
set local "request.jwt.claims" = '';

insert into club_members (club_id, user_id, role, status)
values ('a1e11111-0000-0000-0000-000000000001', 'a1e00000-0000-0000-0000-000000000002', 'member', 'active')
on conflict do nothing;

insert into routes (id, user_id, club_id, name, waypoints, distance_m, elevation_m, surface, is_public)
values
  ('a1e22222-0000-0000-0000-000000000001', 'a1e00000-0000-0000-0000-000000000001', 'a1e11111-0000-0000-0000-000000000001',
   'CAL course', '[]'::jsonb, 42195, 150, 'road', true),
  ('a1e22222-0000-0000-0000-000000000002', 'a1e00000-0000-0000-0000-000000000001', 'a1e11111-0000-0000-0000-000000000001',
   'CAL private recce', '[]'::jsonb, 10000, 50, 'road', false),
  ('a1e22222-0000-0000-0000-000000000003', 'a1e00000-0000-0000-0000-000000000004', null,
   'CAL runner loop', '[]'::jsonb, 5000, 10, 'road', true);

set local role service_role;
insert into race_listings (id, provider, provider_race_id, name, race_date, distance_m, is_verified)
values
  ('a1e33333-0000-0000-0000-000000000001', 'runsignup', 'cal-1', 'CAL City Marathon', current_date + 60, 42195, true),
  ('a1e33333-0000-0000-0000-000000000002', 'runsignup', 'cal-2', 'CAL Last Year', current_date - 30, 42195, true),
  ('a1e33333-0000-0000-0000-000000000003', 'runsignup', 'cal-3', 'CAL Unclaimed', current_date + 90, 21097, true);
reset role;

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"a1e00000-0000-0000-0000-000000000001","role":"authenticated"}';
select claim_race_listing('a1e33333-0000-0000-0000-000000000001', 'a1e11111-0000-0000-0000-000000000001');
select claim_race_listing('a1e33333-0000-0000-0000-000000000002', 'a1e11111-0000-0000-0000-000000000001');
select link_race_course('a1e33333-0000-0000-0000-000000000001', 'a1e22222-0000-0000-0000-000000000001', 'official');
reset role;

-- runner trains for the race; done finished a plan for it; saver saved the course.
insert into training_plans (id, user_id, name, goal_event, goal_distance_m, start_date, end_date,
  days_per_week, status, race_listing_id)
values
  ('a1e44444-0000-0000-0000-000000000001', 'a1e00000-0000-0000-0000-000000000004', 'CAL build',
   'distance_full', 42195, current_date, current_date + 60, 4, 'active', 'a1e33333-0000-0000-0000-000000000001'),
  ('a1e44444-0000-0000-0000-000000000002', 'a1e00000-0000-0000-0000-000000000006', 'CAL abandoned',
   'distance_full', 42195, current_date - 10, current_date + 60, 4, 'abandoned', 'a1e33333-0000-0000-0000-000000000001'),
  ('a1e44444-0000-0000-0000-000000000003', 'a1e00000-0000-0000-0000-000000000004', 'CAL last year',
   'distance_full', 42195, current_date - 120, current_date - 30, 4, 'active', 'a1e33333-0000-0000-0000-000000000002');
insert into saved_routes (user_id, route_id)
values
  ('a1e00000-0000-0000-0000-000000000005', 'a1e22222-0000-0000-0000-000000000001'),
  ('a1e00000-0000-0000-0000-000000000004', 'a1e22222-0000-0000-0000-000000000001'),
  ('a1e00000-0000-0000-0000-000000000001', 'a1e22222-0000-0000-0000-000000000001');

-- ── who may post ────────────────────────────────────────────────────────────

set local role anon;
select throws_ok(
  $$ select post_course_alert('a1e33333-0000-0000-0000-000000000001', null, 'closure', 'Bridge closed') $$,
  '42501', null,
  'anon cannot post a course alert'
);
reset role;

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"a1e00000-0000-0000-0000-000000000004","role":"authenticated"}';
select throws_ok(
  $$ select post_course_alert('a1e33333-0000-0000-0000-000000000001', null, 'closure', 'Bridge closed') $$,
  '42501', 'only an owner or admin of the verified organiser club can post a course alert',
  'a runner cannot post an alert on a race'
);
select throws_ok(
  $$ insert into course_alerts (club_id, listing_id, kind, message)
     values ('a1e11111-0000-0000-0000-000000000001', 'a1e33333-0000-0000-0000-000000000001', 'closure', 'Forged') $$,
  '42501', null,
  'a client cannot write the alerts table directly'
);
reset role;

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"a1e00000-0000-0000-0000-000000000002","role":"authenticated"}';
select throws_ok(
  $$ select post_course_alert('a1e33333-0000-0000-0000-000000000001', null, 'closure', 'Bridge closed') $$,
  '42501', 'only an owner or admin of the verified organiser club can post a course alert',
  'a plain member of the organiser club cannot post'
);
reset role;

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"a1e00000-0000-0000-0000-000000000003","role":"authenticated"}';
select throws_ok(
  $$ select post_course_alert('a1e33333-0000-0000-0000-000000000001', null, 'closure', 'Bridge closed') $$,
  '42501', 'only an owner or admin of the verified organiser club can post a course alert',
  'another verified club''s owner cannot post on a race it does not organise'
);
select throws_ok(
  $$ select post_course_alert('a1e33333-0000-0000-0000-000000000003', null, 'closure', 'Bridge closed') $$,
  '42501', 'only an owner or admin of the verified organiser club can post a course alert',
  'nobody can post on an unclaimed race'
);
select throws_ok(
  $$ select post_course_alert(null, 'a1e22222-0000-0000-0000-000000000001', 'closure', 'Bridge closed') $$,
  '42501', 'only an owner or admin of the verified organiser club can post a course alert',
  'another verified club''s owner cannot post on a route it does not own'
);
reset role;

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"a1e00000-0000-0000-0000-000000000001","role":"authenticated"}';
select throws_ok(
  $$ select post_course_alert(null, 'a1e22222-0000-0000-0000-000000000003', 'closure', 'Bridge closed') $$,
  '42501', 'only an owner or admin of the verified organiser club can post a course alert',
  'an organiser cannot post on a runner''s personal route'
);
select throws_ok(
  $$ select post_course_alert('a1e33333-0000-0000-0000-000000000001', null, 'party', 'Bridge closed') $$,
  '22023', 'unknown course alert kind',
  'an unknown kind is refused'
);
select throws_ok(
  $$ select post_course_alert('a1e33333-0000-0000-0000-000000000001', null, 'closure', '   ') $$,
  '22001', 'a course alert is 1 to 500 characters',
  'a blank message is refused'
);
select throws_ok(
  $$ select post_course_alert('a1e33333-0000-0000-0000-000000000001', 'a1e22222-0000-0000-0000-000000000001', 'closure', 'Both') $$,
  '22023', 'a course alert names one race or one route',
  'an alert names exactly one target'
);
select lives_ok(
  $$ select post_course_alert('a1e33333-0000-0000-0000-000000000001', null, 'reroute', '  Mile 12 now turns left at the bridge.  ') $$,
  'the organiser club''s owner posts an alert on its race'
);
reset role;

select results_eq(
  $$ select club_id, author_id, kind, message from course_alerts
      where listing_id = 'a1e33333-0000-0000-0000-000000000001' $$,
  $$ values ('a1e11111-0000-0000-0000-000000000001'::uuid, 'a1e00000-0000-0000-0000-000000000001'::uuid,
             'reroute'::text, 'Mile 12 now turns left at the bridge.'::text) $$,
  'the alert is stored against the organiser club, trimmed'
);

-- ── who is told ─────────────────────────────────────────────────────────────

select results_eq(
  $$ select n.user_id, n.actor_id, n.club_id from notifications n
       join course_alerts a on a.id = n.course_alert_id
      where n.kind = 'course_alert' and a.listing_id = 'a1e33333-0000-0000-0000-000000000001'
      order by n.user_id $$,
  $$ values
       ('a1e00000-0000-0000-0000-000000000004'::uuid, 'a1e00000-0000-0000-0000-000000000001'::uuid, 'a1e11111-0000-0000-0000-000000000001'::uuid),
       ('a1e00000-0000-0000-0000-000000000005'::uuid, 'a1e00000-0000-0000-0000-000000000001'::uuid, 'a1e11111-0000-0000-0000-000000000001'::uuid) $$,
  'the runner training for the race and the runner who saved its course are told once each; not the author, not an abandoned plan'
);

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"a1e00000-0000-0000-0000-000000000001","role":"authenticated"}';
select lives_ok(
  $$ select post_course_alert('a1e33333-0000-0000-0000-000000000002', null, 'notice', 'Results are final.') $$,
  'an alert on a past race still posts'
);
select lives_ok(
  $$ select post_course_alert(null, 'a1e22222-0000-0000-0000-000000000001', 'direction', 'This year runs down, finishing in the city.') $$,
  'the organiser posts an alert on its club''s route'
);
reset role;

select is(
  (select count(*)::int from notifications n join course_alerts a on a.id = n.course_alert_id
    where a.listing_id = 'a1e33333-0000-0000-0000-000000000002'),
  0,
  'nobody is told about a race whose date has passed'
);
select results_eq(
  $$ select n.user_id from notifications n join course_alerts a on a.id = n.course_alert_id
      where a.route_id = 'a1e22222-0000-0000-0000-000000000001' order by n.user_id $$,
  $$ values ('a1e00000-0000-0000-0000-000000000004'::uuid), ('a1e00000-0000-0000-0000-000000000005'::uuid) $$,
  'a route alert reaches its savers and the runners training for a race on it, once each'
);

-- ── reads ───────────────────────────────────────────────────────────────────

set local role anon;
select is(
  (select count(*)::int from course_alerts where listing_id = 'a1e33333-0000-0000-0000-000000000001'),
  1,
  'anyone reads a race''s alerts'
);
select throws_ok(
  $$ select author_id from course_alerts $$,
  '42501', null,
  'who typed an alert is not readable'
);
reset role;

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"a1e00000-0000-0000-0000-000000000001","role":"authenticated"}';
select lives_ok(
  $$ select post_course_alert(null, 'a1e22222-0000-0000-0000-000000000002', 'closure', 'Recce path closed.') $$,
  'the organiser posts on its private club route'
);
reset role;
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"a1e00000-0000-0000-0000-000000000004","role":"authenticated"}';
select is(
  (select count(*)::int from course_alerts where route_id = 'a1e22222-0000-0000-0000-000000000002'),
  0,
  'a route alert is hidden from someone who cannot see the route'
);
reset role;
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"a1e00000-0000-0000-0000-000000000002","role":"authenticated"}';
select is(
  (select count(*)::int from course_alerts where route_id = 'a1e22222-0000-0000-0000-000000000002'),
  1,
  'a club member who can see the club route reads its alert'
);
reset role;

set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';
update clubs set is_verified = false where id = 'a1e11111-0000-0000-0000-000000000001';
reset role;
set local "request.jwt.claims" = '';
set local role anon;
select is(
  (select count(*)::int from course_alerts where club_id = 'a1e11111-0000-0000-0000-000000000001'),
  0,
  'revoking the club withdraws its alerts with its badge'
);
reset role;
set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';
update clubs set is_verified = true where id = 'a1e11111-0000-0000-0000-000000000001';
reset role;
set local "request.jwt.claims" = '';

-- ── remove ──────────────────────────────────────────────────────────────────

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"a1e00000-0000-0000-0000-000000000004","role":"authenticated"}';
select throws_ok(
  format($$ select delete_course_alert(%L) $$,
    (select id from course_alerts where listing_id = 'a1e33333-0000-0000-0000-000000000001')),
  '42501', 'only an owner or admin of the verified organiser club can remove a course alert',
  'a runner cannot remove an alert'
);
reset role;

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"a1e00000-0000-0000-0000-000000000001","role":"authenticated"}';
select lives_ok(
  format($$ select delete_course_alert(%L) $$,
    (select id from course_alerts where listing_id = 'a1e33333-0000-0000-0000-000000000001')),
  'the organiser removes its alert'
);
reset role;
select is(
  (select count(*)::int from notifications n
    where n.kind = 'course_alert'
      and n.user_id in ('a1e00000-0000-0000-0000-000000000004', 'a1e00000-0000-0000-0000-000000000005')),
  2,
  'removing the alert withdraws its notices; the route alert''s two remain'
);
select is(
  (select count(*)::int from course_alerts where listing_id = 'a1e33333-0000-0000-0000-000000000001'),
  0,
  'the alert is gone'
);

-- ── rate limit ──────────────────────────────────────────────────────────────

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"a1e00000-0000-0000-0000-000000000001","role":"authenticated"}';
select post_course_alert('a1e33333-0000-0000-0000-000000000001', null, 'notice', 'Update ' || g)
  from generate_series(1, 5) g;
select throws_ok(
  $$ select post_course_alert('a1e33333-0000-0000-0000-000000000001', null, 'notice', 'Sixth') $$,
  '54000', 'this course already has five alerts today',
  'a sixth alert on one race inside a day is refused'
);
reset role;

select * from finish();
rollback;

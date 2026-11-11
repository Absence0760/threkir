-- Pins 20271213000001..5: park course problem reports (issue #1346,
-- decisions § 2449).
--
-- Only the service role files a report (the park-course-report Edge Function
-- is the one door), signed in or signed out; anon and authenticated can
-- neither call the filing RPC nor write or read anyone's report. The filing
-- validates its input, caps pending reports per course and signed-out
-- reports an hour, and notifies the app admins. A report never changes the
-- course: only a site admin closes or reopens one, with a note the course
-- page shows, and every action is logged. A contact email goes with the
-- reporter's account and 30 days after resolution.

begin;
select plan(58);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('c0c00000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'pcr-runner@pcr.local', '', now(), now()),
  ('c0c00000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'pcr-admin@pcr.local', '', now(), now()),
  ('c0c00000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'pcr-leaver@pcr.local', '', now(), now()),
  ('c0c00000-0000-0000-0000-000000000004', 'authenticated', 'authenticated', 'pcr-other@pcr.local', '', now(), now())
on conflict (id) do nothing;

select tests.confirm_consent();

insert into app_admins (user_id) values ('c0c00000-0000-0000-0000-000000000002');

insert into global_segments (id, name, waypoints, distance_m, is_active)
values
  ('c0c01111-0000-0000-0000-000000000001', 'PCR Loop',
   '[{"lat":37.0,"lng":-77.0},{"lat":37.004,"lng":-77.0}]', 450, true),
  ('c0c01111-0000-0000-0000-000000000002', 'PCR Second Loop',
   '[{"lat":37.1,"lng":-77.0},{"lat":37.104,"lng":-77.0}]', 450, true),
  ('c0c01111-0000-0000-0000-000000000003', 'PCR Pulled Loop',
   '[{"lat":37.2,"lng":-77.0},{"lat":37.204,"lng":-77.0}]', 450, true),
  ('c0c01111-0000-0000-0000-000000000004', 'PCR Removed Loop',
   '[{"lat":37.3,"lng":-77.0},{"lat":37.304,"lng":-77.0}]', 450, true);

insert into parks (id, slug, name, agency, region_code, country_code, timezone, is_active)
values
  ('c0c02222-0000-0000-0000-000000000001', 'pcr-state-park', 'PCR State Park', 'state', 'US-VA', 'US', 'America/New_York', true),
  ('c0c02222-0000-0000-0000-000000000002', 'pcr-pulled-park', 'PCR Pulled Park', 'state', 'US-VA', 'US', 'America/New_York', false);

insert into park_courses (id, park_id, global_segment_id, slug, course_shape, geometry_source, status, status_note)
values
  ('c0c03333-0000-0000-0000-000000000001', 'c0c02222-0000-0000-0000-000000000001',
   'c0c01111-0000-0000-0000-000000000001', 'pcr-loop', 'loop', 'osm', 'open', null),
  ('c0c03333-0000-0000-0000-000000000002', 'c0c02222-0000-0000-0000-000000000001',
   'c0c01111-0000-0000-0000-000000000002', 'pcr-second', 'loop', 'osm', 'open', null),
  ('c0c03333-0000-0000-0000-000000000003', 'c0c02222-0000-0000-0000-000000000002',
   'c0c01111-0000-0000-0000-000000000003', 'pcr-pulled', 'loop', 'osm', 'open', null),
  ('c0c03333-0000-0000-0000-000000000004', 'c0c02222-0000-0000-0000-000000000001',
   'c0c01111-0000-0000-0000-000000000004', 'pcr-removed', 'loop', 'osm', 'closed', 'Removed from the park catalogue.');

-- ── Who may file ────────────────────────────────────────────────────────────

set local role anon;
select throws_ok(
  $$select submit_park_course_report('c0c03333-0000-0000-0000-000000000001', 'course_hazard', 'A tree is down.', null, null)$$,
  '42501', null, 'anon cannot call the filing RPC directly');
select throws_ok(
  $$insert into reports (target_kind, target_id, reason, notes, signed_out)
    values ('park_course', 'c0c03333-0000-0000-0000-000000000001', 'course_hazard', 'x', true)$$,
  '42501', null, 'anon cannot insert a report directly');
reset role;

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"c0c00000-0000-0000-0000-000000000001","role":"authenticated"}';
select throws_ok(
  $$select submit_park_course_report('c0c03333-0000-0000-0000-000000000001', 'course_hazard', 'A tree is down.', null, 'c0c00000-0000-0000-0000-000000000004')$$,
  '42501', null, 'a signed-in user cannot call the filing RPC directly, nor name another reporter');
select throws_ok(
  $$select submit_report('park_course', 'c0c03333-0000-0000-0000-000000000001', 'other', 'x')$$,
  '22023', null, 'the general submit_report refuses a park course');
reset role;

-- ── The insert path (as the Edge Function: the service role) ───────────────

set local role service_role;

select lives_ok(
  $$select submit_park_course_report('c0c03333-0000-0000-0000-000000000001', 'course_hazard',
      E'  A tree is down across the trail\u0007 at the bridge.  ', '  ranger@pcr-park.example  ', null)$$,
  'a signed-out report with a contact email is filed');
reset role;

select is(
  (select count(*)::int from reports where target_kind = 'park_course'
     and target_id = 'c0c03333-0000-0000-0000-000000000001'),
  1, 'one report is stored');
select is(
  (select row(reporter_id, signed_out, contact_email, notes, status)::text from reports
    where target_kind = 'park_course' and target_id = 'c0c03333-0000-0000-0000-000000000001'),
  row(null::uuid, true, 'ranger@pcr-park.example', 'A tree is down across the trail at the bridge.', 'pending')::text,
  'signed out, no reporter, the email and notes trimmed, control characters removed, pending');
select is(
  (select count(*)::int from notifications where kind = 'park_course_report'
     and user_id = 'c0c00000-0000-0000-0000-000000000002'),
  1, 'the first pending report on a course notifies the app admin');
select is(
  (select count(*)::int from notifications n where n.kind = 'park_course_report'
     and not exists (select 1 from app_admins a where a.user_id = n.user_id)),
  0, 'only app admins are notified');

set local role service_role;
select lives_ok(
  $$select submit_park_course_report('c0c03333-0000-0000-0000-000000000001', 'course_off_trail',
      'The line cuts the switchback.', null, 'c0c00000-0000-0000-0000-000000000001')$$,
  'a signed-in report is filed with its reporter');
reset role;
select is(
  (select count(*)::int from notifications where kind = 'park_course_report'
     and user_id = 'c0c00000-0000-0000-0000-000000000002'),
  1, 'a second ordinary report on the same course adds no notice');
select is(
  (select signed_out from reports where reporter_id = 'c0c00000-0000-0000-0000-000000000001'
     and target_kind = 'park_course'),
  false, 'a signed-in report is not marked signed out');

set local role service_role;
select throws_ok(
  $$select submit_park_course_report('c0c03333-0000-0000-0000-000000000001', 'other',
      'Again.', null, 'c0c00000-0000-0000-0000-000000000001')$$,
  '23505', null, 'a signed-in reporter has one pending report per course');
select throws_ok(
  $$select submit_park_course_report('c0c03333-0000-0000-0000-000000000001', 'other',
      'Again.', 'RANGER@pcr-park.example', null)$$,
  '23505', null, 'a signed-out reporter has one pending report per course per email');
select lives_ok(
  $$select submit_park_course_report('c0c03333-0000-0000-0000-000000000001', 'land_manager_request',
      'Please close this course: the trail is closed for restoration.', 'office@pcr-park.example', null)$$,
  'a land-manager request is filed');
reset role;
select is(
  (select count(*)::int from notifications where kind = 'park_course_report'
     and user_id = 'c0c00000-0000-0000-0000-000000000002'),
  2, 'every land-manager request notifies the admin, even with reports pending');

-- ── Input validation ────────────────────────────────────────────────────────

set local role service_role;
select throws_ok(
  $$select submit_park_course_report('c0c03333-0000-0000-0000-000000000002', 'spam', 'x', null, null)$$,
  '22023', null, 'a general reason is refused');
select throws_ok(
  $$select submit_park_course_report('c0c03333-0000-0000-0000-000000000002', 'course_hazard', E'  \n ', null, null)$$,
  '22023', null, 'empty notes are refused');
select throws_ok(
  $$select submit_park_course_report('c0c03333-0000-0000-0000-000000000002', 'course_hazard', repeat('a', 1001), null, null)$$,
  '22023', null, 'notes over 1000 characters are refused');
select throws_ok(
  $$select submit_park_course_report('c0c03333-0000-0000-0000-000000000002', 'course_hazard',
      'see http://a.example http://b.example https://c.example', null, null)$$,
  '22023', null, 'notes with more than two links are refused');
select throws_ok(
  $$select submit_park_course_report('c0c03333-0000-0000-0000-000000000002', 'course_hazard', 'x', 'not an email', null)$$,
  '22023', null, 'a malformed contact email is refused');
select throws_ok(
  $$select submit_park_course_report('c0c03333-0000-0000-0000-000000000002', 'course_hazard', 'x',
      repeat('a', 250) || '@b.example', null)$$,
  '22023', null, 'a contact email over 254 characters is refused');
select throws_ok(
  $$select submit_park_course_report('c0c03333-0000-0000-0000-000000000003', 'course_hazard', 'x', null, null)$$,
  '02000', null, 'a course of an inactive park is refused');
select throws_ok(
  $$select submit_park_course_report('c0c09999-0000-0000-0000-000000000009', 'course_hazard', 'x', null, null)$$,
  '02000', null, 'an unknown course is refused');
select throws_ok(
  $$select submit_park_course_report('c0c03333-0000-0000-0000-000000000002', 'course_hazard', 'x', null,
      'c0c09999-0000-0000-0000-000000000009')$$,
  '42501', null, 'an unknown reporter is refused');
reset role;

select throws_ok(
  $$insert into reports (reporter_id, target_kind, target_id, reason, notes)
    values ('c0c00000-0000-0000-0000-000000000004', 'route', gen_random_uuid(), 'course_hazard', 'x')$$,
  '23514', null, 'a course reason on another kind violates reports_park_course_check');
select throws_ok(
  $$insert into reports (reporter_id, target_kind, target_id, reason, notes, contact_email)
    values ('c0c00000-0000-0000-0000-000000000004', 'route', gen_random_uuid(), 'spam', 'x', 'a@b.example')$$,
  '23514', null, 'a contact email on another kind is refused');

-- ── Anon cannot read ────────────────────────────────────────────────────────

set local "request.jwt.claims" = '{"role":"anon"}';
set local role anon;
select is((select count(*)::int from reports), 0, 'anon reads no report, not even a signed-out one');
select throws_ok($$select count(*) from park_course_status_actions$$, '42501', null, 'anon cannot read the status log');
reset role;

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"c0c00000-0000-0000-0000-000000000004","role":"authenticated"}';
select is((select count(*)::int from reports where target_kind = 'park_course'), 0,
  'another signed-in user reads nobody''s course report');
reset role;

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"c0c00000-0000-0000-0000-000000000001","role":"authenticated"}';
select is((select count(*)::int from reports where target_kind = 'park_course'), 1,
  'a signed-in reporter reads only their own course report');
reset role;

-- ── A report never closes a course ──────────────────────────────────────────

select is(
  (select row(status, status_note)::text from park_courses where id = 'c0c03333-0000-0000-0000-000000000001'),
  row('open', null::text)::text,
  'a hazard, an off-trail report and a land-manager request leave the course open');

-- Three closure reports still change nothing: the auto-hide trigger fires on
-- each, and auto_hide_target knows no park course.
set local role service_role;
select lives_ok(
  $$select submit_park_course_report('c0c03333-0000-0000-0000-000000000002', 'course_closure', 'Closed sign at the gate.', null, u)
      from unnest(array['c0c00000-0000-0000-0000-000000000001', 'c0c00000-0000-0000-0000-000000000002',
                        'c0c00000-0000-0000-0000-000000000004']::uuid[]) u$$,
  'three signed-in closure reports are filed');
reset role;
select is(
  (select status from park_courses where id = 'c0c03333-0000-0000-0000-000000000002'),
  'open', 'three closure reports do not close the course');

-- ── The caps ────────────────────────────────────────────────────────────────

-- 22 more pending on the second course make 25 (three above).
insert into reports (target_kind, target_id, reason, notes, signed_out, created_at)
select 'park_course', 'c0c03333-0000-0000-0000-000000000002', 'other', 'filler ' || i, true, now() - interval '2 hours'
  from generate_series(1, 22) i;
set local role service_role;
select throws_ok(
  $$select submit_park_course_report('c0c03333-0000-0000-0000-000000000002', 'course_hazard', 'One more.', null, null)$$,
  'PT429', null, 'a course with 25 pending reports takes no more');
select lives_ok(
  $$select submit_park_course_report('c0c03333-0000-0000-0000-000000000002', 'land_manager_request',
      'Please close this course.', 'office2@pcr-park.example', null)$$,
  'a land-manager request still gets into a full course''s queue');
reset role;
select is(
  (select count(*)::int from reports where target_id = 'c0c03333-0000-0000-0000-000000000002'
     and reason = 'land_manager_request' and signed_out and status = 'pending'),
  1, 'the land-manager request on the full course is stored');

-- The hourly signed-out cap counts every course: 2 signed-out reports on the
-- first course this hour, so 58 more reach 60.
insert into reports (target_kind, target_id, reason, notes, signed_out, status, reviewed_at)
select 'park_course', 'c0c03333-0000-0000-0000-000000000004', 'other', 'burst ' || i, true, 'dismissed', now()
  from generate_series(1, 58) i;
set local role service_role;
select throws_ok(
  $$select submit_park_course_report('c0c03333-0000-0000-0000-000000000001', 'course_hazard', 'Burst.', 'new@pcr.example', null)$$,
  'PT429', null, 'the 61st signed-out report in an hour is refused, on any course');
select lives_ok(
  $$select submit_park_course_report('c0c03333-0000-0000-0000-000000000001', 'course_hazard', 'Signed in.', null,
      'c0c00000-0000-0000-0000-000000000004')$$,
  'the signed-out cap does not hold back a signed-in reporter');
reset role;

-- ── Admin reads ─────────────────────────────────────────────────────────────

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"c0c00000-0000-0000-0000-000000000002","role":"authenticated"}';
select ok(
  (select land_manager_since is not null from fetch_pending_reports()
    where target_kind = 'park_course' and target_id = 'c0c03333-0000-0000-0000-000000000001'),
  'the queue carries the land-manager request''s age');
select is(
  (select target_id from fetch_pending_reports() where organiser_dispute = false limit 1),
  'c0c03333-0000-0000-0000-000000000001'::uuid,
  'a target with a land-manager request sorts first');
select is(
  (select count(*)::int from fetch_reports_for_target('park_course', 'c0c03333-0000-0000-0000-000000000001')
    where signed_out and contact_email = 'office@pcr-park.example'),
  1, 'the detail carries the contact email and the signed-out flag');
reset role;

-- ── The admin close and reopen ──────────────────────────────────────────────

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"c0c00000-0000-0000-0000-000000000001","role":"authenticated"}';
select throws_ok(
  $$select admin_set_park_course_status('c0c03333-0000-0000-0000-000000000001', 'closed', 'Closed.')$$,
  '42501', null, 'a non-admin cannot close a course');
reset role;

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"c0c00000-0000-0000-0000-000000000002","role":"authenticated"}';
select throws_ok(
  $$select admin_set_park_course_status('c0c03333-0000-0000-0000-000000000001', 'closed', '  ')$$,
  '22023', null, 'a closure needs a note');
select throws_ok(
  $$select admin_set_park_course_status('c0c03333-0000-0000-0000-000000000001', 'closed', 'Removed from the park catalogue.')$$,
  '22023', null, 'an operator closure cannot carry the catalogue''s own note');
select throws_ok(
  $$select admin_set_park_course_status('c0c03333-0000-0000-0000-000000000001', 'open', null)$$,
  '22023', null, 'an open course cannot be reopened');
select is(
  admin_set_park_course_status('c0c03333-0000-0000-0000-000000000001', 'closed',
    'Closed at the park''s request for trail restoration.'),
  4, 'closing resolves the course''s four pending reports');
reset role;

select is(
  (select row(status, status_note)::text from park_courses where id = 'c0c03333-0000-0000-0000-000000000001'),
  row('closed', 'Closed at the park''s request for trail restoration.')::text,
  'the course is closed with the note the course page shows');
select is(
  (select count(*)::int from reports where target_kind = 'park_course'
     and target_id = 'c0c03333-0000-0000-0000-000000000001' and status = 'pending'),
  0, 'no report on it is left pending');
select is(
  (select row(action, actor_id, status_before, reports_resolved)::text from park_course_status_actions
    where park_course_id = 'c0c03333-0000-0000-0000-000000000001'),
  row('close', 'c0c00000-0000-0000-0000-000000000002'::uuid, 'open', 4)::text,
  'the close is logged with the admin');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"c0c00000-0000-0000-0000-000000000002","role":"authenticated"}';
select is(admin_set_park_course_status('c0c03333-0000-0000-0000-000000000001', 'open', 'Trail reopened.'), 0,
  'reopening resolves nothing');
select throws_ok(
  $$select admin_set_park_course_status('c0c03333-0000-0000-0000-000000000004', 'open', null)$$,
  '22023', null, 'a closure the catalogue made cannot be reopened from the admin');
select is(
  (select array_agg(action order by created_at desc, id desc) from park_course_status_history('c0c03333-0000-0000-0000-000000000001')),
  array['reopen', 'close'], 'the history reads both actions, newest first');
reset role;

select is(
  (select row(status, status_note)::text from park_courses where id = 'c0c03333-0000-0000-0000-000000000001'),
  row('open', null::text)::text,
  'the reopened course is open with no note');

-- ── Personal data ───────────────────────────────────────────────────────────

-- A signed-in reporter who gave an address, then deleted their account.
insert into reports (reporter_id, target_kind, target_id, reason, notes, contact_email)
values ('c0c00000-0000-0000-0000-000000000003', 'park_course', 'c0c03333-0000-0000-0000-000000000004',
        'course_hazard', 'Mud.', 'leaver@pcr.example');
delete from auth.users where id = 'c0c00000-0000-0000-0000-000000000003';
select is(
  (select row(reporter_id, contact_email, notes)::text from reports where notes = 'Mud.'),
  row(null::uuid, null::text, 'Mud.')::text,
  'a deleted reporter''s report is kept without the address they gave');

-- Resolved 31 and 29 days ago, and one held.
insert into reports (target_kind, target_id, reason, notes, contact_email, signed_out, status, reviewed_at, legal_hold)
values
  ('park_course', 'c0c03333-0000-0000-0000-000000000004', 'other', 'old', 'old@pcr.example', true, 'reviewed', now() - interval '31 days', false),
  ('park_course', 'c0c03333-0000-0000-0000-000000000004', 'other', 'recent', 'recent@pcr.example', true, 'reviewed', now() - interval '29 days', false),
  ('park_course', 'c0c03333-0000-0000-0000-000000000004', 'other', 'held', 'held@pcr.example', true, 'reviewed', now() - interval '31 days', true);
insert into private.feature_flags (name, enabled) values ('reports_retention_purge', true)
  on conflict (name) do update set enabled = true;
select private.purge_stale_reports();
select is(
  (select array_agg(notes || ':' || coalesce(contact_email, '-') order by notes) from reports
    where notes in ('old', 'recent', 'held')),
  array['held:held@pcr.example', 'old:-', 'recent:recent@pcr.example'],
  'the purge clears an address 30 days after resolution, keeps the report, and spares a held one');

select throws_ok(
  $$insert into park_course_status_actions (course_slug, action, status_before)
    values ('probe', 'close', 'shut')$$,
  '23514', null, 'the status log takes only a park course status as status_before');
select throws_ok(
  $$insert into park_course_status_actions (course_slug, action, status_before, reports_resolved)
    values ('probe', 'close', 'open', -1)$$,
  '23514', null, 'the status log refuses a negative resolved count');

select * from finish();
rollback;

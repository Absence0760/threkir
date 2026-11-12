-- Pins 20271224000600 (audit of PR #1359, Medium): signed-out park course
-- reports are capped an hour in two buckets, so ordinary reports cannot lock
-- out the land-manager and rights-holder intake and deadline requests cannot
-- flood either bucket.
--
--   1-2.  Deadline requests do not count toward the ordinary cap.
--   3.    The 61st ordinary signed-out report in an hour is refused.
--   4-5.  A land-manager request is still filed past the ordinary cap.
--   6.    The 121st deadline request in an hour is refused.
--   7-8.  A signed-in reporter is held by neither bucket.

begin;
select plan(8);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values ('c0c24000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'pcd-runner@pcd.local', '', now(), now());

insert into global_segments (id, name, waypoints, distance_m, is_active)
values ('c0c24111-0000-0000-0000-000000000001', 'PCD Loop',
        '[{"lat":36.0,"lng":-77.0},{"lat":36.004,"lng":-77.0}]', 450, true);
insert into parks (id, slug, name, agency, region_code, country_code, timezone, is_active)
values ('c0c24222-0000-0000-0000-000000000001', 'pcd-state-park', 'PCD State Park', 'state', 'US-VA', 'US',
        'America/New_York', true);
insert into park_courses (id, park_id, global_segment_id, slug, course_shape, geometry_source, status, status_note)
values ('c0c24333-0000-0000-0000-000000000001', 'c0c24222-0000-0000-0000-000000000001',
        'c0c24111-0000-0000-0000-000000000001', 'pcd-loop', 'loop', 'osm', 'open', null);

-- This hour: 59 ordinary signed-out reports and 100 deadline requests,
-- all already reviewed so the per-course pending cap plays no part.
insert into reports (target_kind, target_id, reason, notes, signed_out, status, reviewed_at)
select 'park_course', 'c0c24333-0000-0000-0000-000000000001', 'other', 'ordinary ' || i, true, 'dismissed', now()
  from generate_series(1, 59) i;
insert into reports (target_kind, target_id, reason, notes, signed_out, status, reviewed_at)
select 'park_course', 'c0c24333-0000-0000-0000-000000000001', 'land_manager_request', 'deadline ' || i, true,
       'dismissed', now()
  from generate_series(1, 100) i;

set local role service_role;
select lives_ok(
  $$select submit_park_course_report('c0c24333-0000-0000-0000-000000000001', 'course_hazard', 'Tree down.', null, null)$$,
  'the 60th ordinary report is filed: the deadline requests this hour do not count toward its cap');
reset role;
select is(
  (select signed_out from reports where notes = 'Tree down.'),
  true,
  'the 60th ordinary report is stored signed out');
set local role service_role;
select throws_ok(
  $$select submit_park_course_report('c0c24333-0000-0000-0000-000000000001', 'course_off_trail', 'Gone off trail.', null, null)$$,
  'PT429', 'submit_park_course_report: rate limited',
  'the 61st ordinary signed-out report in an hour is refused');
select lives_ok(
  $$select submit_park_course_report('c0c24333-0000-0000-0000-000000000001', 'land_manager_request',
      'Please close this course for restoration.', 'office@pcd-park.example', null)$$,
  'a land-manager request is filed although the ordinary bucket is spent');

reset role;
select is(
  (select signed_out::text || '|' || status from reports
    where notes = 'Please close this course for restoration.'),
  'true|pending',
  'the land-manager request is stored pending, signed out');
insert into reports (target_kind, target_id, reason, notes, signed_out, status, reviewed_at)
select 'park_course', 'c0c24333-0000-0000-0000-000000000001', 'rights_holder_request', 'more ' || i, true,
       'dismissed', now()
  from generate_series(1, 19) i;
set local role service_role;
select throws_ok(
  $$select submit_park_course_report('c0c24333-0000-0000-0000-000000000001', 'rights_holder_request',
      'Our map is used without permission.', 'rights@pcd.example', null)$$,
  'PT429', 'submit_park_course_report: rate limited',
  'the 121st deadline request in an hour is refused, so they cannot flood either');
select lives_ok(
  $$select submit_park_course_report('c0c24333-0000-0000-0000-000000000001', 'course_hazard', 'Signed in.', null,
      'c0c24000-0000-0000-0000-000000000001')$$,
  'neither bucket holds back a signed-in reporter');
reset role;
select is(
  (select signed_out::text || '|' || reporter_id::text from reports where notes = 'Signed in.'),
  'false|c0c24000-0000-0000-0000-000000000001',
  'the signed-in report is stored with its reporter, not signed out');

select * from finish();
rollback;

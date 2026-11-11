-- Pins 20271220002469..12469: a rights holder's request on a park course
-- (decisions § 2469, closing the gap § 2460 recorded).
--
-- 'rights_holder_request' is routed like 'land_manager_request': a park
-- course's reason only, never refused by or counted toward the 25-pending
-- cap, a notice to every app admin on each one, and its own age on the admin
-- queue, sorted with the land-manager requests after disputes. Unlike every
-- other course reason it needs a contact email, because it is answered by
-- hand. A request changes nothing about the course.

begin;
select plan(18);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('c0c10000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'rhr-runner@rhr.local', '', now(), now()),
  ('c0c10000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'rhr-admin@rhr.local', '', now(), now())
on conflict (id) do nothing;

select tests.confirm_consent();

insert into app_admins (user_id) values ('c0c10000-0000-0000-0000-000000000002');

insert into global_segments (id, name, waypoints, distance_m, is_active)
values
  ('c0c11111-0000-0000-0000-000000000001', 'RHR Loop',
   '[{"lat":38.0,"lng":-77.0},{"lat":38.004,"lng":-77.0}]', 450, true),
  ('c0c11111-0000-0000-0000-000000000002', 'RHR Full Loop',
   '[{"lat":38.1,"lng":-77.0},{"lat":38.104,"lng":-77.0}]', 450, true);

insert into parks (id, slug, name, agency, region_code, country_code, timezone, is_active)
values
  ('c0c12222-0000-0000-0000-000000000001', 'rhr-state-park', 'RHR State Park', 'state', 'US-VA', 'US', 'America/New_York', true);

insert into park_courses (id, park_id, global_segment_id, slug, course_shape, geometry_source, status, status_note)
values
  ('c0c13333-0000-0000-0000-000000000001', 'c0c12222-0000-0000-0000-000000000001',
   'c0c11111-0000-0000-0000-000000000001', 'rhr-loop', 'loop', 'osm', 'open', null),
  ('c0c13333-0000-0000-0000-000000000002', 'c0c12222-0000-0000-0000-000000000001',
   'c0c11111-0000-0000-0000-000000000002', 'rhr-full', 'loop', 'osm', 'open', null);

-- ── The vocabulary ──────────────────────────────────────────────────────────

select throws_ok(
  $$insert into reports (reporter_id, target_kind, target_id, reason, notes)
    values ('c0c10000-0000-0000-0000-000000000001', 'route', gen_random_uuid(), 'rights_holder_request', 'x')$$,
  '23514', null, 'a rights-holder request belongs to a park course only');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"c0c10000-0000-0000-0000-000000000001","role":"authenticated"}';
select throws_ok(
  $$select submit_report('park_course', 'c0c13333-0000-0000-0000-000000000001', 'rights_holder_request', 'x')$$,
  '22023', null, 'the general submit_report refuses a rights-holder request');
select throws_ok(
  $$select submit_park_course_report('c0c13333-0000-0000-0000-000000000001', 'rights_holder_request',
      'Our mark.', 'legal@brand.example', null)$$,
  '42501', null, 'a signed-in user cannot file a rights-holder request around the Edge Function');
reset role;

-- ── Filing ──────────────────────────────────────────────────────────────────

set local role service_role;
select throws_ok(
  $$select submit_park_course_report('c0c13333-0000-0000-0000-000000000001', 'rights_holder_request',
      'This course description uses our event name.', null, null)$$,
  '22023', null, 'a rights-holder request with no contact email is refused');
select throws_ok(
  $$select submit_park_course_report('c0c13333-0000-0000-0000-000000000001', 'rights_holder_request',
      'This course description uses our event name.', '   ', null)$$,
  '22023', null, 'a blank contact email is no email for a rights-holder request');
select lives_ok(
  $$select submit_park_course_report('c0c13333-0000-0000-0000-000000000001', 'course_hazard',
      'A tree is down.', null, null)$$,
  'an ordinary report opens the course''s queue');
select lives_ok(
  $$select submit_park_course_report('c0c13333-0000-0000-0000-000000000001', 'rights_holder_request',
      'This course description uses our event name.', '  Legal@Brand.example ', null)$$,
  'a signed-out rights-holder request with an address is filed');
reset role;

select is(
  (select row(reason, contact_email, signed_out, reporter_id, status)::text from reports
    where target_kind = 'park_course' and target_id = 'c0c13333-0000-0000-0000-000000000001'
      and reason = 'rights_holder_request'),
  row('rights_holder_request', 'Legal@Brand.example', true, null::uuid, 'pending')::text,
  'the request is stored pending, signed out, with its trimmed address');
select is(
  (select count(*)::int from reports
    where target_kind = 'park_course' and target_id = 'c0c13333-0000-0000-0000-000000000001'
      and status = 'pending' and signed_out),
  2, 'both filings on the course are stored signed out');
select is(
  (select count(*)::int from notifications where kind = 'park_course_report'
     and user_id = 'c0c10000-0000-0000-0000-000000000002'),
  2, 'a rights-holder request notifies the admin even with a report already pending');
select is(
  (select status from park_courses where id = 'c0c13333-0000-0000-0000-000000000001'),
  'open', 'a rights-holder request does not close the course');

-- ── The per-course cap ──────────────────────────────────────────────────────

insert into reports (target_kind, target_id, reason, notes, signed_out, created_at)
select 'park_course', 'c0c13333-0000-0000-0000-000000000002', 'other', 'filler ' || i, true, now() - interval '2 hours'
  from generate_series(1, 25) i;
set local role service_role;
select throws_ok(
  $$select submit_park_course_report('c0c13333-0000-0000-0000-000000000002', 'course_hazard',
      'One more.', null, 'c0c10000-0000-0000-0000-000000000001')$$,
  'PT429', null, 'the full course takes no more ordinary reports');
select lives_ok(
  $$select submit_park_course_report('c0c13333-0000-0000-0000-000000000002', 'rights_holder_request',
      'Please rename this course.', 'counsel@brand.example', null)$$,
  'a rights-holder request still gets into a full course''s queue');
select throws_ok(
  $$select submit_park_course_report('c0c13333-0000-0000-0000-000000000002', 'course_hazard',
      'Still one more.', null, 'c0c10000-0000-0000-0000-000000000001')$$,
  'PT429', null, 'the rights-holder request is not counted toward the cap either way');
reset role;
select is(
  (select count(*)::int from reports where target_id = 'c0c13333-0000-0000-0000-000000000002'
     and reason = 'rights_holder_request' and signed_out and status = 'pending'),
  1, 'the rights-holder request on the full course is stored');

-- ── The admin queue ─────────────────────────────────────────────────────────

update reports set created_at = now() - interval '3 days'
 where target_id = 'c0c13333-0000-0000-0000-000000000002' and reason = 'rights_holder_request';

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"c0c10000-0000-0000-0000-000000000002","role":"authenticated"}';
select ok(
  (select rights_holder_since is not null and land_manager_since is null from fetch_pending_reports()
    where target_kind = 'park_course' and target_id = 'c0c13333-0000-0000-0000-000000000001'),
  'the queue carries the rights-holder request''s age, apart from a land manager''s');
select is(
  (select target_id from fetch_pending_reports() where organiser_dispute = false limit 1),
  'c0c13333-0000-0000-0000-000000000002'::uuid,
  'the oldest rights-holder request sorts first after disputes');
select is(
  (select array_agg(target_id order by ord) from (
     select target_id, row_number() over () as ord from fetch_pending_reports()
      where target_id in ('c0c13333-0000-0000-0000-000000000001', 'c0c13333-0000-0000-0000-000000000002')) q),
  array['c0c13333-0000-0000-0000-000000000002', 'c0c13333-0000-0000-0000-000000000001']::uuid[],
  'both rights-holder targets sort by their oldest request');
reset role;

select * from finish();
rollback;

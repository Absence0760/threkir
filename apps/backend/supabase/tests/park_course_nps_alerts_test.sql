-- Pins 20271214131302 + 20271214131303: NPS closures flagged for review
-- (issue #1313 Phase 6, decisions § 2454).
--
-- Only an `nps` park takes an NPS park code. The sweep's two calls are the
-- service role's alone: the targets list holds active NPS parks with a code
-- and their courses that are not closed; recording upserts flags, sends a
-- flag whose alert text changed back to pending, stamps one NPS no longer
-- lists as gone, and refuses a flag outside the park or for an alert the
-- sweep did not see. No client reads or writes the table. Only an app admin
-- reads the queue and acts on it, and closing from it closes the course with
-- its note and marks every pending flag on it reviewed. A flag never changes
-- a course by itself. The daily schedule is armed.

begin;
select plan(42);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('d1300000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'nps-runner@nps.local', '', now(), now()),
  ('d1300000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'nps-admin@nps.local', '', now(), now())
on conflict (id) do nothing;

select tests.confirm_consent();

insert into app_admins (user_id) values ('d1300000-0000-0000-0000-000000000002');

insert into global_segments (id, name, waypoints, distance_m, is_active)
values
  ('d1301111-0000-0000-0000-000000000001', 'Big Meadows Loop',
   '[{"lat":38.5,"lng":-78.4},{"lat":38.504,"lng":-78.4}]', 450, true),
  ('d1301111-0000-0000-0000-000000000002', 'Rapidan Trail',
   '[{"lat":38.6,"lng":-78.4},{"lat":38.604,"lng":-78.4}]', 450, true),
  ('d1301111-0000-0000-0000-000000000003', 'Closed Loop',
   '[{"lat":38.7,"lng":-78.4},{"lat":38.704,"lng":-78.4}]', 450, true),
  ('d1301111-0000-0000-0000-000000000004', 'State Loop',
   '[{"lat":37.0,"lng":-77.4},{"lat":37.004,"lng":-77.4}]', 450, true),
  ('d1301111-0000-0000-0000-000000000005', 'Pulled Loop',
   '[{"lat":39.0,"lng":-77.4},{"lat":39.004,"lng":-77.4}]', 450, true);

insert into parks (id, slug, name, agency, region_code, country_code, timezone, is_active, nps_park_code)
values
  ('d1302222-0000-0000-0000-000000000001', 'nps-shen', 'NPS Shenandoah', 'nps', 'US-VA', 'US', 'America/New_York', true, 'shen'),
  ('d1302222-0000-0000-0000-000000000002', 'nps-state', 'NPS State Park', 'state', 'US-VA', 'US', 'America/New_York', true, null),
  ('d1302222-0000-0000-0000-000000000003', 'nps-pulled', 'NPS Pulled', 'nps', 'US-VA', 'US', 'America/New_York', false, 'prwi');

insert into park_courses (id, park_id, global_segment_id, slug, course_shape, geometry_source, status, status_note)
values
  ('d1303333-0000-0000-0000-000000000001', 'd1302222-0000-0000-0000-000000000001',
   'd1301111-0000-0000-0000-000000000001', 'big-meadows-loop', 'loop', 'nps', 'open', null),
  ('d1303333-0000-0000-0000-000000000002', 'd1302222-0000-0000-0000-000000000001',
   'd1301111-0000-0000-0000-000000000002', 'rapidan-trail', 'out_and_back', 'nps', 'seasonal', null),
  ('d1303333-0000-0000-0000-000000000003', 'd1302222-0000-0000-0000-000000000001',
   'd1301111-0000-0000-0000-000000000003', 'closed-loop', 'loop', 'nps', 'closed', 'Bridge out.'),
  ('d1303333-0000-0000-0000-000000000004', 'd1302222-0000-0000-0000-000000000002',
   'd1301111-0000-0000-0000-000000000004', 'state-loop', 'loop', 'osm', 'open', null),
  ('d1303333-0000-0000-0000-000000000005', 'd1302222-0000-0000-0000-000000000003',
   'd1301111-0000-0000-0000-000000000005', 'pulled-loop', 'loop', 'nps', 'open', null);

-- ── The park code ───────────────────────────────────────────────────────────

select throws_ok(
  $$update parks set nps_park_code = 'pcrx' where id = 'd1302222-0000-0000-0000-000000000002'$$,
  '23514', null, 'a park that is not nps cannot take an NPS park code');
select throws_ok(
  $$update parks set nps_park_code = 'SHEN' where id = 'd1302222-0000-0000-0000-000000000001'$$,
  '23514', null, 'an NPS park code is lower-case letters');

-- The release's park sync writes the code with the rest of the park.
insert into clubs (id, owner_id, name, slug, is_public)
values ('d1304444-0000-0000-0000-000000000001', 'd1300000-0000-0000-0000-000000000002', 'NPS Official', 'nps-official', true);

set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';
update clubs set is_verified = true where id = 'd1304444-0000-0000-0000-000000000001';
create temp table nps_manifest (j jsonb);
insert into nps_manifest values ($json${
  "park": {"slug": "nps-loaded", "name": "NPS Loaded", "agency": "nps", "region_code": "US-VA",
           "country_code": "US", "timezone": "America/New_York", "website_url": "https://www.nps.gov/blri/",
           "nps_park_code": "blri"},
  "region": "NPS Loaded, Virginia",
  "attribution": "National Park Service",
  "courses": [
    {"slug": "nps-loaded-loop", "name": "NPS Loaded Loop", "course_shape": "loop", "surface": "trail",
     "difficulty": "easy", "geometry_source": "nps", "source_ref": "", "source_checked_at": "2026-11-10",
     "distance_m": 1990, "elevation_m": 4, "official_distance_m": null, "description": null, "checkpoints": [],
     "waypoints": [{"lat": 36.0, "lng": -81.0}, {"lat": 36.0045, "lng": -81.0}, {"lat": 36.0045, "lng": -80.9955},
                   {"lat": 36.0, "lng": -80.9955}, {"lat": 36.0, "lng": -81.0}]}
  ]
}$json$);
create temp table nps_loads as
  select 1 as n, * from private.load_park_catalogue((select j from nps_manifest),
    'd1304444-0000-0000-0000-000000000001', 'd1300000-0000-0000-0000-000000000002');
reset role;
set local "request.jwt.claims" = '{}';
select is((select nps_park_code from parks where slug = 'nps-loaded'), 'blri', 'the catalogue load writes the park code');

set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';
insert into nps_loads
  select 2, * from private.load_park_catalogue((select j from nps_manifest),
    'd1304444-0000-0000-0000-000000000001', 'd1300000-0000-0000-0000-000000000002');
insert into nps_loads
  select 3, * from private.load_park_catalogue(jsonb_set((select j from nps_manifest), '{park,nps_park_code}', '"blrx"'),
    'd1304444-0000-0000-0000-000000000001', 'd1300000-0000-0000-0000-000000000002');
reset role;
set local "request.jwt.claims" = '{}';
select is((select action from nps_loads where n = 2), 'unchanged', 'an unchanged park and course load writes nothing');
select is((select nps_park_code from parks where slug = 'nps-loaded'), 'blrx', 'a changed code is written');
delete from parks where slug = 'nps-loaded';

-- ── Grants ──────────────────────────────────────────────────────────────────

select ok(not has_table_privilege('anon', 'public.park_course_nps_alerts', 'SELECT'), 'anon cannot read the flags');
select ok(not has_table_privilege('authenticated', 'public.park_course_nps_alerts', 'SELECT'), 'authenticated cannot read the flags');
select ok(not has_table_privilege('authenticated', 'public.park_course_nps_alerts', 'INSERT'), 'authenticated cannot write a flag');
select ok(not has_function_privilege('authenticated', 'public.park_nps_sweep_targets()', 'execute'),
  'authenticated cannot list the sweep targets');
select ok(not has_function_privilege('authenticated', 'public.record_park_nps_alerts(uuid, jsonb, text[])', 'execute'),
  'authenticated cannot record flags');
select ok(not has_function_privilege('anon', 'public.record_park_nps_alerts(uuid, jsonb, text[])', 'execute'),
  'anon cannot record flags');
select ok(not has_function_privilege('anon', 'public.admin_park_nps_alerts(text)', 'execute'), 'anon cannot read the queue');
select ok(not has_function_privilege('authenticated', 'public.invoke_park_closures_sweep()', 'execute'),
  'authenticated cannot fire the sweep');

-- ── The sweep's calls (as the Edge Function: the service role) ─────────────

set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';

select is(
  (select jsonb_agg(jsonb_build_object('code', t.nps_park_code, 'courses', t.courses)) from park_nps_sweep_targets() t),
  jsonb_build_array(jsonb_build_object('code', 'shen', 'courses', jsonb_build_array(
    jsonb_build_object('id', 'd1303333-0000-0000-0000-000000000001', 'name', 'Big Meadows Loop'),
    jsonb_build_object('id', 'd1303333-0000-0000-0000-000000000002', 'name', 'Rapidan Trail')))),
  'the targets are active NPS parks with a code, with their courses that are not closed');

create temp table recorded (n int, created int, seen int, gone int);
grant select, insert on recorded to service_role;

insert into recorded select 1, * from record_park_nps_alerts(
  'd1302222-0000-0000-0000-000000000001',
  '[{"course_id":"d1303333-0000-0000-0000-000000000001","alert_id":"FIRE-1","category":"Caution",
     "title":"Prescribed Fire in Big Meadows","description":"Big Meadows will be closed.","url":null,"match":"named"},
    {"course_id":"d1303333-0000-0000-0000-000000000002","alert_id":"FIRE-1","category":"Caution",
     "title":"Prescribed Fire in Big Meadows","description":"Big Meadows will be closed.","url":null,"match":"named"}]',
  array['FIRE-1', 'INFO-1']);
select is((select created from recorded where n = 1), 2, 'two flags are created');
select is(
  (select count(*)::int from park_course_nps_alerts where review_status = 'pending' and gone_at is null), 2,
  'both are pending');
select is(
  (select status from park_courses where id = 'd1303333-0000-0000-0000-000000000001'), 'open',
  'a flag never changes the course');

insert into recorded select 2, * from record_park_nps_alerts(
  'd1302222-0000-0000-0000-000000000001',
  '[{"course_id":"d1303333-0000-0000-0000-000000000001","alert_id":"FIRE-1","category":"Caution",
     "title":"Prescribed Fire in Big Meadows","description":"Big Meadows will be closed.","url":null,"match":"named"}]',
  array['FIRE-1']);
select is((select (created, seen, gone)::text from recorded where n = 2), '(0,1,0)',
  'the same alert again is seen, not created');

select throws_ok(
  $$select * from record_park_nps_alerts('d1302222-0000-0000-0000-000000000001',
     '[{"course_id":"d1303333-0000-0000-0000-000000000004","alert_id":"X","category":"Caution","title":"T","match":"named"}]',
     array['X'])$$,
  '22023', null, 'a flag on a course outside the park is refused');
select throws_ok(
  $$select * from record_park_nps_alerts('d1302222-0000-0000-0000-000000000002', '[]', array[]::text[])$$,
  '22023', null, 'a park that is not nps is refused');
select throws_ok(
  $$select * from record_park_nps_alerts('d1302222-0000-0000-0000-000000000001',
     '[{"course_id":"d1303333-0000-0000-0000-000000000001","alert_id":"UNSEEN","category":"Caution","title":"T","match":"named"}]',
     array['FIRE-1'])$$,
  '22023', null, 'a flag for an alert the sweep did not see is refused');
select throws_ok(
  $$select * from record_park_nps_alerts('d1302222-0000-0000-0000-000000000001',
     '[{"course_id":"d1303333-0000-0000-0000-000000000001","alert_id":"FIRE-1","category":"Caution","title":"T","match":"guess"}]',
     array['FIRE-1'])$$,
  '23514', null, 'a match outside the vocabulary is refused');
select throws_ok(
  $$select * from record_park_nps_alerts('d1302222-0000-0000-0000-000000000001', '{}', array[]::text[])$$,
  '22023', null, 'flags that are not a list are refused');
reset role;

-- ── The queue ───────────────────────────────────────────────────────────────

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"d1300000-0000-0000-0000-000000000001","role":"authenticated"}';
select throws_ok($$select * from admin_park_nps_alerts()$$, '42501', null, 'a runner cannot read the queue');
select throws_ok(
  $$select admin_review_park_nps_alert((select 1::bigint), 'dismissed')$$,
  '42501', null, 'a runner cannot act on a flag');
reset role;

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"d1300000-0000-0000-0000-000000000002","role":"authenticated"}';
select is(
  (select string_agg(course_slug || ':' || match || ':' || course_status, ',' order by course_slug) from admin_park_nps_alerts()),
  'big-meadows-loop:named:open,rapidan-trail:named:seasonal',
  'an admin reads the pending flags with their course');
select throws_ok($$select * from admin_park_nps_alerts('later')$$, '22023', null, 'an unknown status is refused');

create temp table flag_ids as
  select course_slug, id from admin_park_nps_alerts();

select is(
  admin_review_park_nps_alert((select id from flag_ids where course_slug = 'rapidan-trail'), 'dismissed'), 1,
  'an admin dismisses a flag');
select is(
  (select string_agg(course_slug, ',') from admin_park_nps_alerts('dismissed')), 'rapidan-trail',
  'the dismissed flag leaves the pending queue');
select throws_ok(
  $$select admin_review_park_nps_alert((select id from flag_ids where course_slug = 'big-meadows-loop'), 'close')$$,
  '22023', null, 'closing from a flag needs the note the course page shows');
select throws_ok(
  $$select admin_review_park_nps_alert((select id from flag_ids where course_slug = 'big-meadows-loop'), 'reopen')$$,
  '22023', null, 'an unknown action is refused');
select is(
  admin_review_park_nps_alert((select id from flag_ids where course_slug = 'big-meadows-loop'), 'close',
    'Closed by the park for a prescribed fire.'), 1,
  'an admin closes the course from its flag');
reset role;

select is(
  (select status || ':' || status_note from park_courses where id = 'd1303333-0000-0000-0000-000000000001'),
  'closed:Closed by the park for a prescribed fire.', 'the course is closed with the admin''s note');
select is(
  (select action || ':' || coalesce(actor_id::text, '') from park_course_status_actions
    where park_course_id = 'd1303333-0000-0000-0000-000000000001'),
  'close:d1300000-0000-0000-0000-000000000002', 'the closure is logged against the admin');
select is(
  (select review_status || ':' || coalesce(reviewed_by::text, '') from park_course_nps_alerts
    where park_course_id = 'd1303333-0000-0000-0000-000000000001'),
  'reviewed:d1300000-0000-0000-0000-000000000002', 'the course''s flag is marked reviewed');

-- ── Changed and gone alerts ─────────────────────────────────────────────────

set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';
insert into recorded select 3, * from record_park_nps_alerts(
  'd1302222-0000-0000-0000-000000000001',
  '[{"course_id":"d1303333-0000-0000-0000-000000000002","alert_id":"FIRE-1","category":"Park Closure",
     "title":"Prescribed Fire in Big Meadows","description":"Rapidan Road is now closed too.","url":null,"match":"named"}]',
  array['FIRE-1']);
select is(
  (select review_status || ':' || coalesce(reviewed_by::text, 'none') from park_course_nps_alerts
    where park_course_id = 'd1303333-0000-0000-0000-000000000002'),
  'pending:none', 'a dismissed flag whose alert text changed is pending again');
select is(
  (select gone_at is null from park_course_nps_alerts where park_course_id = 'd1303333-0000-0000-0000-000000000001'),
  true, 'an alert still listed is not gone');

insert into recorded select 4, * from record_park_nps_alerts('d1302222-0000-0000-0000-000000000001', '[]', array[]::text[]);
select is((select gone from recorded where n = 4), 2, 'an alert NPS no longer lists is stamped gone on both courses');
select is(
  (select count(*)::int from park_course_nps_alerts where gone_at is not null), 2,
  'each gone flag keeps its row for the record');

insert into recorded select 5, * from record_park_nps_alerts(
  'd1302222-0000-0000-0000-000000000001',
  '[{"course_id":"d1303333-0000-0000-0000-000000000002","alert_id":"FIRE-1","category":"Park Closure",
     "title":"Prescribed Fire in Big Meadows","description":"Rapidan Road is now closed too.","url":null,"match":"named"}]',
  array['FIRE-1']);
select is(
  (select gone_at is null from park_course_nps_alerts where park_course_id = 'd1303333-0000-0000-0000-000000000002'),
  true, 'an alert listed again is no longer gone');
reset role;

-- ── The schedule ────────────────────────────────────────────────────────────

select is(
  (select schedule from cron.job where jobname = 'park-closures-sweep'), '41 11 * * *',
  'the sweep runs daily');
select is(public.invoke_park_closures_sweep(), null::bigint,
  'with no Vault URL the invoker calls nothing');

select * from finish();
rollback;

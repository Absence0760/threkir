-- Pins migration 20271122002402_global_segment_gates.sql (#1308, decisions
-- § 2402): the start and end lines derived from a catalogue segment's own
-- polyline, a curator's override and reset, global_segment_efforts.matched_by
-- (its default and its CHECK), record_segment_match writing it, and the
-- owner's delete-then-insert re-match under RLS.

begin;
select plan(29);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('5c000000-0000-0000-0000-0000000000a1', 'authenticated', 'authenticated',
   'gate-owner@sg.local', '', now(), now()),
  ('5c000000-0000-0000-0000-0000000000b2', 'authenticated', 'authenticated',
   'gate-other@sg.local', '', now(), now()),
  ('5c000000-0000-0000-0000-0000000000c3', 'authenticated', 'authenticated',
   'gate-admin@sg.local', '', now(), now());
insert into app_admins (user_id) values ('5c000000-0000-0000-0000-0000000000c3');
insert into user_profiles (id, display_name)
values
  ('5c000000-0000-0000-0000-0000000000a1', 'Gate Owner'),
  ('5c000000-0000-0000-0000-0000000000b2', 'Gate Other'),
  ('5c000000-0000-0000-0000-0000000000c3', 'Gate Admin');
select tests.confirm_consent();

-- North 445 m; east 400 m with string coordinates; a 400 m square loop that
-- leaves east and arrives heading south; a polyline 5 m long; and one with
-- nothing readable.
insert into global_segments (id, name, waypoints, distance_m)
values
  ('5c5c0000-0000-0000-0000-0000000000d1', 'SG North',
   '[{"lat":37.500,"lng":-77.500},{"lat":37.502,"lng":-77.500},{"lat":37.504,"lng":-77.500}]', 445),
  ('5c5c0000-0000-0000-0000-0000000000d2', 'SG East strings',
   '[{"lat":"37.5","lng":"-77.5"},{"lat":"37.5","lng":"-77.4954"}]', 400),
  ('5c5c0000-0000-0000-0000-0000000000d3', 'SG Loop',
   '[{"lat":37.5,"lng":-77.5},{"lat":37.5,"lng":-77.49887},{"lat":37.5009,"lng":-77.49887},
     {"lat":37.5009,"lng":-77.5},{"lat":37.5,"lng":-77.5}]', 400),
  ('5c5c0000-0000-0000-0000-0000000000d4', 'SG Stub',
   '[{"lat":37.5,"lng":-77.5},{"lat":37.500045,"lng":-77.5}]', 100),
  ('5c5c0000-0000-0000-0000-0000000000d5', 'SG Unreadable',
   '[{"lat":"north","lng":null},7]', 200);

-- ── derivation ─────────────────────────────────────────────────────────────

select ok(
  (select start_gate_lat = 37.5 and start_gate_lng = -77.5
          and start_gate_bearing_deg < 0.01 and start_gate_half_width_m = 15
          and start_gate_source = 'derived'
     from global_segments where id = '5c5c0000-0000-0000-0000-0000000000d1'),
  'the start line sits on the first point, faces along the line (north), 15 m each side, derived');
select ok(
  (select end_gate_lat = 37.504 and end_gate_lng = -77.5
          and end_gate_bearing_deg < 0.01 and end_gate_half_width_m = 15
          and end_gate_source = 'derived'
     from global_segments where id = '5c5c0000-0000-0000-0000-0000000000d1'),
  'the end line sits on the last point, facing the way the line arrives');
select ok(
  (select abs(start_gate_bearing_deg - 90) < 0.01 and abs(end_gate_bearing_deg - 90) < 0.01
          and end_gate_lng = -77.4954
     from global_segments where id = '5c5c0000-0000-0000-0000-0000000000d2'),
  'numeric-string coordinates are read, and an eastbound segment faces 90');
select ok(
  (select start_gate_lat = end_gate_lat and start_gate_lng = end_gate_lng
          and abs(start_gate_bearing_deg - 90) < 0.01 and abs(end_gate_bearing_deg - 180) < 0.01
     from global_segments where id = '5c5c0000-0000-0000-0000-0000000000d3'),
  'a loop gets two lines on one point: leaving east, arriving south');
select ok(
  (select num_nulls(start_gate_lat, start_gate_source, end_gate_lat, end_gate_source) = 4
     from global_segments where id = '5c5c0000-0000-0000-0000-0000000000d4'),
  'a polyline under 10 m long gets no lines');
select ok(
  (select num_nulls(start_gate_lat, start_gate_source, end_gate_lat, end_gate_source) = 4
     from global_segments where id = '5c5c0000-0000-0000-0000-0000000000d5'),
  'an unreadable polyline gets no lines, and the write still succeeds');

update global_segments
   set waypoints = '[{"lat":37.504,"lng":-77.500},{"lat":37.500,"lng":-77.500}]'
 where id = '5c5c0000-0000-0000-0000-0000000000d1';
select ok(
  (select start_gate_lat = 37.504 and abs(start_gate_bearing_deg - 180) < 0.01
          and end_gate_lat = 37.5 and abs(end_gate_bearing_deg - 180) < 0.01
     from global_segments where id = '5c5c0000-0000-0000-0000-0000000000d1'),
  'redrawing the polyline (reversed) re-derives both lines');

select is(
  (select count(*)::int from pg_trigger
    where tgrelid = 'public.global_segments'::regclass and tgname = 'global_segments_set_gates_trg'),
  1, 'the derivation runs from a trigger on global_segments');

-- ── a curator's override ───────────────────────────────────────────────────

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"5c000000-0000-0000-0000-0000000000c3","role":"authenticated"}';

update global_segments
   set start_gate_lat = 37.5041, start_gate_lng = -77.5, start_gate_bearing_deg = -170,
       start_gate_half_width_m = 25, start_gate_source = 'curator'
 where id = '5c5c0000-0000-0000-0000-0000000000d1';
select ok(
  (select start_gate_lat = 37.5041 and start_gate_bearing_deg = 190
          and start_gate_half_width_m = 25 and start_gate_source = 'curator'
     from global_segments where id = '5c5c0000-0000-0000-0000-0000000000d1'),
  'an admin places a curator line; its direction is wrapped into [0, 360)');

update global_segments
   set waypoints = '[{"lat":37.503,"lng":-77.500},{"lat":37.500,"lng":-77.500}]'
 where id = '5c5c0000-0000-0000-0000-0000000000d1';
select ok(
  (select start_gate_lat = 37.5041 and start_gate_source = 'curator'
          and end_gate_source = 'derived' and end_gate_lat = 37.5
     from global_segments where id = '5c5c0000-0000-0000-0000-0000000000d1'),
  'a redrawn polyline leaves the curator line alone and re-derives the other end');

select throws_ok(
  $$ update global_segments set end_gate_source = 'curator', end_gate_half_width_m = null
      where id = '5c5c0000-0000-0000-0000-0000000000d1' $$,
  '23514', null, 'a curator line missing a value is refused');
select throws_ok(
  $$ update global_segments set end_gate_source = 'curator', end_gate_half_width_m = 200
      where id = '5c5c0000-0000-0000-0000-0000000000d1' $$,
  '23514', null, 'a curator line reaching past 100 m is refused');
select throws_ok(
  $$ update global_segments set end_gate_source = 'organiser'
      where id = '5c5c0000-0000-0000-0000-0000000000d1' $$,
  '23514', null, 'a source outside derived / curator is refused');

update global_segments set start_gate_source = 'derived'
 where id = '5c5c0000-0000-0000-0000-0000000000d1';
select ok(
  (select start_gate_lat = 37.503 and start_gate_half_width_m = 15 and start_gate_source = 'derived'
     from global_segments where id = '5c5c0000-0000-0000-0000-0000000000d1'),
  'writing source derived resets the line to the derived one');

set local "request.jwt.claims" = '{"sub":"5c000000-0000-0000-0000-0000000000a1","role":"authenticated"}';
update global_segments
   set start_gate_lat = 0, start_gate_lng = 0, start_gate_bearing_deg = 0,
       start_gate_half_width_m = 5, start_gate_source = 'curator'
 where id = '5c5c0000-0000-0000-0000-0000000000d1';
reset role;
select is(
  (select start_gate_source from global_segments where id = '5c5c0000-0000-0000-0000-0000000000d1'),
  'derived', 'a non-admin cannot place a line (the admin-only write policy holds)');

-- ── matched_by ─────────────────────────────────────────────────────────────

insert into runs (id, user_id, started_at, distance_m, duration_s, source, activity_type, track_url, is_public)
values ('5d000000-0000-0000-0000-000000000001', '5c000000-0000-0000-0000-0000000000a1',
        '2026-09-01 09:00:00+00', 5000, 1800, 'app', 'run',
        '5c000000-0000-0000-0000-0000000000a1/5d000000-0000-0000-0000-000000000001.json.gz', true);
insert into storage.objects (bucket_id, name, version) values
  ('runs', '5c000000-0000-0000-0000-0000000000a1/5d000000-0000-0000-0000-000000000001.json.gz', 'v1');

insert into global_segment_efforts (global_segment_id, run_id, user_id, time_seconds, started_at)
values ('5c5c0000-0000-0000-0000-0000000000d2', '5d000000-0000-0000-0000-000000000001',
        '5c000000-0000-0000-0000-0000000000a1', 100, '2026-09-01T09:05:00Z');
select is(
  (select matched_by from global_segment_efforts
    where run_id = '5d000000-0000-0000-0000-000000000001'
      and global_segment_id = '5c5c0000-0000-0000-0000-0000000000d2'),
  'zone', 'an effort written without matched_by is a circle match');
select col_not_null('public', 'global_segment_efforts', 'matched_by', 'matched_by is not null');
select throws_ok(
  $$ insert into global_segment_efforts (global_segment_id, run_id, user_id, time_seconds, started_at, matched_by)
     values ('5c5c0000-0000-0000-0000-0000000000d3', '5d000000-0000-0000-0000-000000000001',
             '5c000000-0000-0000-0000-0000000000a1', 100, '2026-09-01T09:05:00Z', 'circle') $$,
  '23514', null, 'matched_by outside zone / gate is refused');

select is(
  record_segment_match('5d000000-0000-0000-0000-000000000001', 'v1', 37.5, -77.5, 37.6, -77.4,
    array['5c5c0000-0000-0000-0000-0000000000d2', '5c5c0000-0000-0000-0000-0000000000d3']::uuid[],
    '[{"global_segment_id":"5c5c0000-0000-0000-0000-0000000000d2","time_seconds":96.5,"started_at":"2026-09-01T09:05:01Z","matched_by":"gate"},
      {"global_segment_id":"5c5c0000-0000-0000-0000-0000000000d3","time_seconds":120,"started_at":"2026-09-01T09:10:00Z"}]'::jsonb),
  'recorded', 'the processor records a pass with matched_by');
select is(
  (select matched_by || ':' || time_seconds from global_segment_efforts
    where run_id = '5d000000-0000-0000-0000-000000000001'
      and global_segment_id = '5c5c0000-0000-0000-0000-0000000000d2'),
  'gate:96.5', 'a corrected effort takes the new matched_by and time');
select is(
  (select matched_by from global_segment_efforts
    where run_id = '5d000000-0000-0000-0000-000000000001'
      and global_segment_id = '5c5c0000-0000-0000-0000-0000000000d3'),
  'zone', 'an effort with no matched_by in the payload is recorded as a circle match');

-- ── the owner's re-match: delete then insert, under RLS ────────────────────

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"5c000000-0000-0000-0000-0000000000b2","role":"authenticated"}';
delete from global_segment_efforts where run_id = '5d000000-0000-0000-0000-000000000001';
select throws_ok(
  $$ insert into global_segment_efforts (global_segment_id, run_id, user_id, time_seconds, started_at, matched_by)
     values ('5c5c0000-0000-0000-0000-0000000000d1', '5d000000-0000-0000-0000-000000000001',
             '5c000000-0000-0000-0000-0000000000b2', 50, '2026-09-01T09:05:00Z', 'gate') $$,
  '42501', null, 'another user cannot insert an effort on the owner''s run');
reset role;
select is(
  (select count(*)::int from global_segment_efforts where run_id = '5d000000-0000-0000-0000-000000000001'),
  2, 'another user''s delete removes nothing');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"5c000000-0000-0000-0000-0000000000a1","role":"authenticated"}';
delete from global_segment_efforts
 where run_id = '5d000000-0000-0000-0000-000000000001'
   and global_segment_id = '5c5c0000-0000-0000-0000-0000000000d3';
select is(
  (select count(*)::int from global_segment_efforts
    where run_id = '5d000000-0000-0000-0000-000000000001'
      and global_segment_id = '5c5c0000-0000-0000-0000-0000000000d3'),
  0, 'the owner deletes the effort an older matcher wrote');
select lives_ok(
  $$ insert into global_segment_efforts (global_segment_id, run_id, user_id, time_seconds, started_at, matched_by)
     values ('5c5c0000-0000-0000-0000-0000000000d3', '5d000000-0000-0000-0000-000000000001',
             '5c000000-0000-0000-0000-0000000000a1', 117.25, '2026-09-01T09:10:02Z', 'gate') $$,
  'and inserts the re-matched one under the existing insert policy');
select is(
  (select matched_by || ':' || time_seconds from global_segment_efforts
    where run_id = '5d000000-0000-0000-0000-000000000001'
      and global_segment_id = '5c5c0000-0000-0000-0000-0000000000d3'),
  'gate:117.25', 'the run now holds the gate-matched effort');
select throws_ok(
  $$ insert into global_segment_efforts (global_segment_id, run_id, user_id, time_seconds, started_at, matched_by)
     values ('5c5c0000-0000-0000-0000-0000000000d3', '5d000000-0000-0000-0000-000000000001',
             '5c000000-0000-0000-0000-0000000000a1', 110, '2026-09-01T09:10:02Z', 'gate') $$,
  '23505', null, 'a second effort for the same run and segment is still refused');

select throws_ok(
  $$ update global_segment_efforts set time_seconds = 1
      where run_id = '5d000000-0000-0000-0000-000000000001' $$,
  '42501', null, 'there is still no update path for a client: re-matching is delete then insert');
reset role;

select ok(
  not has_function_privilege('authenticated', 'private.global_segment_line(jsonb)', 'execute')
  and not has_function_privilege('authenticated', 'public.global_segments_set_gates()', 'execute'),
  'the derivation helpers are not callable by clients');

select * from finish();
rollback;

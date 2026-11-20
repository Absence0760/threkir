-- Pins migration 20280106001446_park_course_attempts.sql (issue #1446): why a
-- run that set out on a park course got no time. The service-role write and
-- its refusals, the table's CHECKs, the owner-only read (table and RPC), the
-- grants, and the cascade on a run delete.

begin;
select plan(26);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('a7000000-0000-0000-0000-0000000000a1', 'authenticated', 'authenticated',
   'attempt-owner@pca.local', '', now(), now()),
  ('a7000000-0000-0000-0000-0000000000b2', 'authenticated', 'authenticated',
   'attempt-other@pca.local', '', now(), now());
insert into user_profiles (id, display_name)
values
  ('a7000000-0000-0000-0000-0000000000a1', 'Attempt Owner'),
  ('a7000000-0000-0000-0000-0000000000b2', 'Attempt Other');
select tests.confirm_consent();

insert into global_segments (id, name, waypoints, distance_m, is_active)
values
  ('a7a70000-0000-0000-0000-0000000000d1', 'PCA Loop',
   '[{"lat":37.0,"lng":-77.0},{"lat":37.004,"lng":-77.0}]', 450, true);
insert into parks (id, slug, name, agency, region_code, country_code, timezone, is_active)
values
  ('a7a70000-0000-0000-0000-0000000000e1', 'pca-park', 'PCA Park',
   'state', 'US-VA', 'US', 'America/New_York', true);
insert into park_courses (id, park_id, global_segment_id, slug, course_shape, geometry_source, checkpoints)
values
  ('a7a70000-0000-0000-0000-0000000000f1', 'a7a70000-0000-0000-0000-0000000000e1',
   'a7a70000-0000-0000-0000-0000000000d1', 'pca-loop', 'loop', 'osm',
   '[{"lat":37.001,"lng":-77.0},{"lat":37.002,"lng":-77.0},{"lat":37.003,"lng":-77.0},{"lat":37.0035,"lng":-77.0}]');

insert into runs (id, user_id, started_at, distance_m, duration_s, source, activity_type, track_url, is_public)
values ('a7b00000-0000-0000-0000-000000000001', 'a7000000-0000-0000-0000-0000000000a1',
        '2026-09-01 09:00:00+00', 5000, 1800, 'app', 'run',
        'a7000000-0000-0000-0000-0000000000a1/a7b00000-0000-0000-0000-000000000001.json.gz', true);
insert into storage.objects (bucket_id, name, version) values
  ('runs', 'a7000000-0000-0000-0000-0000000000a1/a7b00000-0000-0000-0000-000000000001.json.gz', 'v1');

-- ── the write ─────────────────────────────────────────────────────────────

select is(
  record_park_course_attempts('a7b00000-0000-0000-0000-000000000001', 'v1', 4,
    '[{"park_course_id":"a7a70000-0000-0000-0000-0000000000f1","outcome":"skipped_checkpoint","progress_m":1447,"course_m":3595,"missed_checkpoint":2,"checkpoint_count":4},
      {"park_course_id":"a7a70000-0000-0000-0000-0000000000ff","outcome":"stopped_short","progress_m":10,"course_m":100,"missed_checkpoint":null,"checkpoint_count":0}]'::jsonb),
  'recorded', 'the processor records the run''s attempts for the bytes it read');

select is(
  (select row(user_id, outcome, progress_m, course_m, missed_checkpoint, checkpoint_count, matcher_version)::text
     from park_course_attempts where run_id = 'a7b00000-0000-0000-0000-000000000001'),
  row('a7000000-0000-0000-0000-0000000000a1'::uuid, 'skipped_checkpoint', 1447, 3595, 2::smallint, 4::smallint, 4::smallint)::text,
  'the row carries the run''s owner, the attempt and the matcher version');

select is(
  (select count(*)::int from park_course_attempts where run_id = 'a7b00000-0000-0000-0000-000000000001'),
  1, 'an attempt naming a course that does not exist is dropped');

select is(
  record_park_course_attempts('a7b00000-0000-0000-0000-000000000001', 'v0', 4, '[]'::jsonb),
  'stale', 'bytes that are no longer stored are refused');
select is(
  (select count(*)::int from park_course_attempts where run_id = 'a7b00000-0000-0000-0000-000000000001'),
  1, 'a stale write leaves the attempts as they were');

select is(
  record_park_course_attempts('a7b00000-0000-0000-0000-0000000000ff', 'v1', 4, '[]'::jsonb),
  'missing', 'a run that is gone is missing');

select throws_ok(
  $$ select record_park_course_attempts('a7b00000-0000-0000-0000-000000000001', 'v1', 4, '{}'::jsonb) $$,
  '22023', null, 'p_attempts must be an array');
select throws_ok(
  $$ select record_park_course_attempts('a7b00000-0000-0000-0000-000000000001', 'v1', 0, '[]'::jsonb) $$,
  '22023', null, 'p_matcher_version must be positive');

select is(
  record_park_course_attempts('a7b00000-0000-0000-0000-000000000001', 'v1', 4,
    '[{"park_course_id":"a7a70000-0000-0000-0000-0000000000f1","outcome":"stopped_short","progress_m":3445,"course_m":3595,"missed_checkpoint":null,"checkpoint_count":4}]'::jsonb),
  'recorded', 're-scoring records again');
select is(
  (select array_agg(outcome) from park_course_attempts where run_id = 'a7b00000-0000-0000-0000-000000000001'),
  array['stopped_short'], 're-scoring replaces the run''s attempts');

-- ── the checks ────────────────────────────────────────────────────────────

select throws_ok(
  $$ insert into park_course_attempts (run_id, user_id, park_course_id, outcome, progress_m, course_m, missed_checkpoint, checkpoint_count, matcher_version)
     values ('a7b00000-0000-0000-0000-000000000001', 'a7000000-0000-0000-0000-0000000000a1', 'a7a70000-0000-0000-0000-0000000000f1', 'lost', 1, 10, null, 0, 4) $$,
  '23514', null, 'an outcome outside the four is refused');
select throws_ok(
  $$ update park_course_attempts set outcome = 'skipped_checkpoint' where run_id = 'a7b00000-0000-0000-0000-000000000001' $$,
  '23514', null, 'skipped_checkpoint needs the checkpoint it missed');
select throws_ok(
  $$ update park_course_attempts set missed_checkpoint = 1 where run_id = 'a7b00000-0000-0000-0000-000000000001' $$,
  '23514', null, 'only skipped_checkpoint names a missed checkpoint');
select throws_ok(
  $$ update park_course_attempts set outcome = 'skipped_checkpoint', missed_checkpoint = 5 where run_id = 'a7b00000-0000-0000-0000-000000000001' $$,
  '23514', null, 'the missed checkpoint is one of the course''s');
select throws_ok(
  $$ update park_course_attempts set progress_m = 4000 where run_id = 'a7b00000-0000-0000-0000-000000000001' $$,
  '23514', null, 'progress cannot pass the course length');
select throws_ok(
  $$ update park_course_attempts set course_m = 0, progress_m = 0 where run_id = 'a7b00000-0000-0000-0000-000000000001' $$,
  '23514', null, 'a course has a length');
select throws_ok(
  $$ insert into park_course_attempts (run_id, user_id, park_course_id, outcome, progress_m, course_m, missed_checkpoint, checkpoint_count, matcher_version)
     values ('a7b00000-0000-0000-0000-000000000001', 'a7000000-0000-0000-0000-0000000000a1', 'a7a70000-0000-0000-0000-0000000000f1', 'off_course', 3595, 3595, null, 4, 4) $$,
  '23505', null, 'one attempt per run and course');

-- ── the owner-only read ───────────────────────────────────────────────────

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"a7000000-0000-0000-0000-0000000000a1","role":"authenticated"}';

select is(
  (select count(*)::int from park_course_attempts where run_id = 'a7b00000-0000-0000-0000-000000000001'),
  1, 'the owner reads their own attempt');
select is(
  (select row(park_course_id, course_name, park_name, region_code, park_slug, course_slug, outcome, progress_m, course_m, missed_checkpoint, checkpoint_count)::text
     from get_run_park_course_attempts('a7b00000-0000-0000-0000-000000000001')),
  row('a7a70000-0000-0000-0000-0000000000f1'::uuid, 'PCA Loop', 'PCA Park', 'US-VA', 'pca-park', 'pca-loop',
      'stopped_short', 3445, 3595, null::smallint, 4::smallint)::text,
  'the owner''s RPC returns the attempt with its course and park');

set local "request.jwt.claims" = '{"sub":"a7000000-0000-0000-0000-0000000000b2","role":"authenticated"}';

select is_empty(
  $$ select 1 from park_course_attempts where run_id = 'a7b00000-0000-0000-0000-000000000001' $$,
  'another runner reads none of it');
select is_empty(
  $$ select 1 from get_run_park_course_attempts('a7b00000-0000-0000-0000-000000000001') $$,
  'the RPC returns nothing for another runner''s run');
select throws_ok(
  $$ select record_park_course_attempts('a7b00000-0000-0000-0000-000000000001', 'v1', 4, '[]'::jsonb) $$,
  '42501', null, 'a client cannot call the write');
select throws_ok(
  $$ delete from park_course_attempts $$,
  '42501', null, 'a client cannot delete an attempt');

reset role;
set local role anon;
select throws_ok(
  $$ select 1 from park_course_attempts $$,
  '42501', null, 'anon cannot read the table at all');
select throws_ok(
  $$ select 1 from get_run_park_course_attempts('a7b00000-0000-0000-0000-000000000001') $$,
  '42501', null, 'anon cannot call the read');

-- ── the cascade ───────────────────────────────────────────────────────────

reset role;
set local "request.jwt.claims" = '{"sub":"a7000000-0000-0000-0000-0000000000a1","role":"authenticated"}';
delete from runs where id = 'a7b00000-0000-0000-0000-000000000001';
select is(
  (select count(*)::int from park_course_attempts where run_id = 'a7b00000-0000-0000-0000-000000000001'),
  0, 'deleting the run deletes its attempts');

select * from finish();
rollback;

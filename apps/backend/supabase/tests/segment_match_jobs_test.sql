-- Pins migration 20271117002392_segment_match_jobs.sql (issue #1313 Phase 1,
-- decisions § 2392): the segment_match enqueue triggers, the
-- global_segments_in_bbox candidate lookup, record_segment_match's write and
-- its refusal for bytes that are no longer stored, the backfill entry point
-- and batch query, and that no client role reaches run_track_extents or the
-- service-role RPCs.

begin;
select plan(41);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('5a000000-0000-0000-0000-0000000000a1', 'authenticated', 'authenticated',
   'seg-owner@sm.local', '', now(), now()),
  ('5a000000-0000-0000-0000-0000000000b2', 'authenticated', 'authenticated',
   'seg-other@sm.local', '', now(), now()),
  ('5a000000-0000-0000-0000-0000000000c3', 'authenticated', 'authenticated',
   'seg-admin@sm.local', '', now(), now());
insert into app_admins (user_id) values ('5a000000-0000-0000-0000-0000000000c3');
insert into user_profiles (id, display_name)
values
  ('5a000000-0000-0000-0000-0000000000a1', 'Seg Owner'),
  ('5a000000-0000-0000-0000-0000000000b2', 'Seg Other'),
  ('5a000000-0000-0000-0000-0000000000c3', 'Seg Admin');
select tests.confirm_consent();

-- Two segments near Richmond (one pulled), one in Sydney, one whose
-- waypoints carry string coordinates and one that is unreadable.
insert into global_segments (id, name, waypoints, distance_m, is_active)
values
  ('5a5a0000-0000-0000-0000-0000000000d1', 'SM Near',
   '[{"lat":37.500,"lng":-77.500},{"lat":37.504,"lng":-77.500}]', 445, true),
  ('5a5a0000-0000-0000-0000-0000000000d2', 'SM Near Pulled',
   '[{"lat":37.500,"lng":-77.500},{"lat":37.504,"lng":-77.500}]', 445, false),
  ('5a5a0000-0000-0000-0000-0000000000d3', 'SM Far',
   '[{"lat":-33.89,"lng":151.27},{"lat":-33.90,"lng":151.27}]', 1100, true),
  ('5a5a0000-0000-0000-0000-0000000000d4', 'SM Strings',
   '[{"lat":"37.5005","lng":"-77.5005"},{"lat":"37.5030","lng":"-77.5005"}]', 280, true),
  ('5a5a0000-0000-0000-0000-0000000000d5', 'SM Unreadable',
   '[{"lat":"north","lng":null},7]', 200, true);

-- ── the candidate lookup ─────────────────────────────────────────────────

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"5a000000-0000-0000-0000-0000000000a1","role":"authenticated"}';

select is(
  (select array_agg(id order by id) from global_segments_in_bbox(37.5010, -77.5010, 37.5020, -77.4990)
    where id::text like '5a5a0000-%'),
  array['5a5a0000-0000-0000-0000-0000000000d1', '5a5a0000-0000-0000-0000-0000000000d4']::uuid[],
  'a box inside the Richmond segments returns both active ones (number and string coordinates), not the pulled one, not Sydney');

select is(
  (select count(*)::int from global_segments_in_bbox(37.5050, -77.4999, 37.5060, -77.4990, 0)),
  0, 'a box 100 m past the segment with no pad overlaps nothing');

select is(
  (select array_agg(id order by id) from global_segments_in_bbox(37.5044, -77.4999, 37.5060, -77.4990, 50)
    where id::text like '5a5a0000-%'),
  array['5a5a0000-0000-0000-0000-0000000000d1']::uuid[],
  'the same side of the segment within the 50 m pad is admitted');

select is(
  (select count(*)::int from global_segments_in_bbox(37.5010, -77.5010, 37.5020, -77.4990, 50, 1)),
  1, 'p_limit caps the result');

select throws_ok(
  $$ select * from global_segments_in_bbox(38, -77, 37, -76) $$,
  '22023', null, 'an inverted box is refused');
select throws_ok(
  $$ select * from global_segments_in_bbox('NaN'::float8, -77, 37, -76) $$,
  '22023', null, 'a NaN bound is refused');
select throws_ok(
  $$ select * from global_segments_in_bbox(37, -77, 38, -76, 99999) $$,
  '22023', null, 'an absurd pad is refused');

reset role;
select ok(
  not has_function_privilege('anon', 'public.global_segments_in_bbox(double precision, double precision, double precision, double precision, double precision, integer)', 'execute')
  and has_function_privilege('authenticated', 'public.global_segments_in_bbox(double precision, double precision, double precision, double precision, double precision, integer)', 'execute'),
  'global_segments_in_bbox is for signed-in callers and the service role, not anon');

select ok(
  exists (select 1 from pg_indexes where indexname = 'global_segments_extent'),
  'the extent index exists');
select is(private.waypoints_box('[{"lat":"north","lng":null},7]'::jsonb), null::box,
  'an unreadable polyline has no extent and raises nothing');

-- ── enqueue on a new track ───────────────────────────────────────────────

-- Row first, then the upload: both enqueue, and the queued dedupe keeps one.
insert into runs (id, user_id, started_at, distance_m, duration_s, source, activity_type, track_url, is_public)
values ('5b000000-0000-0000-0000-000000000001', '5a000000-0000-0000-0000-0000000000a1',
        '2026-09-01 09:00:00+00', 5000, 1800, 'app', 'run',
        '5a000000-0000-0000-0000-0000000000a1/5b000000-0000-0000-0000-000000000001.json.gz', true);

select is(
  (select count(*)::int from jobs
    where kind = 'segment_match' and status = 'queued'
      and payload ->> 'run_id' = '5b000000-0000-0000-0000-000000000001'),
  1, 'a run inserted with a track queues one segment_match job');

insert into storage.objects (bucket_id, name, version) values
  ('runs', '5a000000-0000-0000-0000-0000000000a1/5b000000-0000-0000-0000-000000000001.json.gz', 'v1');

select is(
  (select count(*)::int from jobs
    where kind = 'segment_match' and status = 'queued'
      and payload ->> 'run_id' = '5b000000-0000-0000-0000-000000000001'),
  1, 'the upload that follows is absorbed by the queued job');

-- While the job runs, a rewrite of the bytes gets a job of its own.
update jobs set status = 'running', locked_at = now()
 where kind = 'segment_match' and payload ->> 'run_id' = '5b000000-0000-0000-0000-000000000001';
update storage.objects set version = 'v2'
 where bucket_id = 'runs'
   and name = '5a000000-0000-0000-0000-0000000000a1/5b000000-0000-0000-0000-000000000001.json.gz';

select is(
  (select count(*)::int from jobs
    where kind = 'segment_match' and status = 'queued'
      and payload ->> 'run_id' = '5b000000-0000-0000-0000-000000000001'),
  1, 'a rewrite while the job runs queues a fresh one rather than being swallowed');

update storage.objects set metadata = '{"cacheControl":"max-age=60"}'
 where bucket_id = 'runs'
   and name = '5a000000-0000-0000-0000-0000000000a1/5b000000-0000-0000-0000-000000000001.json.gz';
select is(
  (select count(*)::int from jobs
    where kind = 'segment_match' and payload ->> 'run_id' = '5b000000-0000-0000-0000-000000000001'),
  2, 'a metadata-only object update queues nothing');

update runs set metadata = '{"title":"renamed"}' where id = '5b000000-0000-0000-0000-000000000001';
select is(
  (select count(*)::int from jobs
    where kind = 'segment_match' and payload ->> 'run_id' = '5b000000-0000-0000-0000-000000000001'),
  2, 'an update that leaves track_url alone queues nothing');

insert into runs (id, user_id, started_at, distance_m, duration_s, source, activity_type)
values ('5b000000-0000-0000-0000-000000000002', '5a000000-0000-0000-0000-0000000000a1',
        '2026-09-02 09:00:00+00', 5000, 1800, 'app', 'run');
select is(
  (select count(*)::int from jobs
    where kind = 'segment_match' and payload ->> 'run_id' = '5b000000-0000-0000-0000-000000000002'),
  0, 'a run with no track queues nothing');

-- A failing enqueue never fails the run write.
create function pg_temp.fail_segment_enqueue() returns trigger language plpgsql as $$
begin
  if new.kind = 'segment_match' then
    raise exception 'injected';
  end if;
  return new;
end;
$$;
create trigger fail_segment_enqueue before insert on jobs
  for each row execute function pg_temp.fail_segment_enqueue();
select lives_ok(
  $$ insert into runs (id, user_id, started_at, distance_m, duration_s, source, activity_type, track_url)
     values ('5b000000-0000-0000-0000-000000000003', '5a000000-0000-0000-0000-0000000000a1',
             '2026-09-03 09:00:00+00', 5000, 1800, 'app', 'run',
             '5a000000-0000-0000-0000-0000000000a1/5b000000-0000-0000-0000-000000000003.json.gz') $$,
  'the run is saved when the segment_match enqueue fails');
drop trigger fail_segment_enqueue on jobs;

-- ── the processor's read and write ───────────────────────────────────────

select is(
  (select track_version from segment_match_run_source('5b000000-0000-0000-0000-000000000001')),
  'v2', 'segment_match_run_source reports the version of the stored bytes');

select is(
  record_segment_match('5b000000-0000-0000-0000-000000000001', 'v1', 37.5, -77.5, 37.6, -77.4,
    array['5a5a0000-0000-0000-0000-0000000000d1']::uuid[],
    '[{"global_segment_id":"5a5a0000-0000-0000-0000-0000000000d1","time_seconds":120,"started_at":"2026-09-01T09:05:00Z"}]'::jsonb),
  'stale', 'a result for bytes that have been replaced is refused');
select is(
  (select count(*)::int from global_segment_efforts where run_id = '5b000000-0000-0000-0000-000000000001'),
  0, 'and writes no effort');
select is(
  (select count(*)::int from run_track_extents where run_id = '5b000000-0000-0000-0000-000000000001'),
  0, 'and no extent');

select is(
  record_segment_match('5b000000-0000-0000-0000-000000000001', 'v2', 37.5, -77.5, 37.6, -77.4,
    array['5a5a0000-0000-0000-0000-0000000000d1', '5a5a0000-0000-0000-0000-0000000000d2',
          '5a5a0000-0000-0000-0000-0000000000d4']::uuid[],
    '[{"global_segment_id":"5a5a0000-0000-0000-0000-0000000000d1","time_seconds":120,"started_at":"2026-09-01T09:05:00Z"},
      {"global_segment_id":"5a5a0000-0000-0000-0000-0000000000d2","time_seconds":121,"started_at":"2026-09-01T09:05:00Z"},
      {"global_segment_id":"5a5a0000-0000-0000-0000-0000000000d3","time_seconds":99,"started_at":"2026-09-01T09:05:00Z"}]'::jsonb),
  'recorded', 'a result for the stored bytes is recorded');
select is(
  (select array_agg(global_segment_id order by global_segment_id)
     from global_segment_efforts where run_id = '5b000000-0000-0000-0000-000000000001'),
  array['5a5a0000-0000-0000-0000-0000000000d1']::uuid[],
  'only an active candidate is written: the pulled segment and a non-candidate are ignored');
select is(
  (select user_id from global_segment_efforts where run_id = '5b000000-0000-0000-0000-000000000001'),
  '5a000000-0000-0000-0000-0000000000a1'::uuid, 'the effort is owned by the run''s owner');
select is(
  (select track_version from run_track_extents where run_id = '5b000000-0000-0000-0000-000000000001'),
  'v2', 'the extent is stored against the version scored');

-- A planted effort outside the candidates survives; a candidate the run no
-- longer earns is removed; a repeated match is corrected in place.
insert into global_segment_efforts (global_segment_id, run_id, user_id, time_seconds, started_at)
values ('5a5a0000-0000-0000-0000-0000000000d3', '5b000000-0000-0000-0000-000000000001',
        '5a000000-0000-0000-0000-0000000000a1', 400, '2026-09-01T09:20:00Z');
select is(
  record_segment_match('5b000000-0000-0000-0000-000000000001', 'v2', 37.5, -77.5, 37.6, -77.4,
    array['5a5a0000-0000-0000-0000-0000000000d1', '5a5a0000-0000-0000-0000-0000000000d4']::uuid[],
    '[{"global_segment_id":"5a5a0000-0000-0000-0000-0000000000d4","time_seconds":80,"started_at":"2026-09-01T09:06:00Z"}]'::jsonb),
  'recorded', 'a second pass is recorded');
select is(
  (select array_agg(global_segment_id order by global_segment_id)
     from global_segment_efforts where run_id = '5b000000-0000-0000-0000-000000000001'),
  array['5a5a0000-0000-0000-0000-0000000000d3', '5a5a0000-0000-0000-0000-0000000000d4']::uuid[],
  'the dropped candidate is removed, the new match added, the non-candidate kept');
select is(
  record_segment_match('5b000000-0000-0000-0000-000000000001', 'v2', 37.5, -77.5, 37.6, -77.4,
    array['5a5a0000-0000-0000-0000-0000000000d4']::uuid[],
    '[{"global_segment_id":"5a5a0000-0000-0000-0000-0000000000d4","time_seconds":79.5,"started_at":"2026-09-01T09:06:00Z"}]'::jsonb),
  'recorded', 'the same match again is recorded');
select is(
  (select array_agg(time_seconds) from global_segment_efforts
    where run_id = '5b000000-0000-0000-0000-000000000001'
      and global_segment_id = '5a5a0000-0000-0000-0000-0000000000d4'),
  array[79.5]::numeric[], 'as one row, corrected in place');
select is(
  record_segment_match('5b000000-0000-0000-0000-0000000000ff', 'v2', 0, 0, 0, 0, '{}'::uuid[], '[]'::jsonb),
  'missing', 'a deleted run is reported missing');

-- ── the backfill ─────────────────────────────────────────────────────────

set local "request.jwt.claims" = '{}';

-- Run 1 is scored with an extent over the Richmond segment. Run 4 has an
-- extent in Sydney. Run 5 has never been scored. Run 6 is too short.
insert into runs (id, user_id, started_at, distance_m, duration_s, source, activity_type, track_url)
values
  ('5b000000-0000-0000-0000-000000000004', '5a000000-0000-0000-0000-0000000000b2',
   '2026-09-04 09:00:00+00', 5000, 1800, 'app', 'run',
   '5a000000-0000-0000-0000-0000000000b2/5b000000-0000-0000-0000-000000000004.json.gz'),
  ('5b000000-0000-0000-0000-000000000005', '5a000000-0000-0000-0000-0000000000b2',
   '2026-09-05 09:00:00+00', 5000, 1800, 'app', 'run',
   '5a000000-0000-0000-0000-0000000000b2/5b000000-0000-0000-0000-000000000005.json.gz'),
  ('5b000000-0000-0000-0000-000000000006', '5a000000-0000-0000-0000-0000000000b2',
   '2026-09-06 09:00:00+00', 100, 60, 'app', 'run',
   '5a000000-0000-0000-0000-0000000000b2/5b000000-0000-0000-0000-000000000006.json.gz');
insert into run_track_extents (run_id, track_version, min_lat, min_lng, max_lat, max_lng)
values ('5b000000-0000-0000-0000-000000000004', 'x', -33.95, 151.2, -33.85, 151.3);

select is(
  (select array_agg(run_id order by run_id)
     from segment_backfill_runs('5a5a0000-0000-0000-0000-0000000000d1',
                                '5affffff-ffff-ffff-ffff-ffffffffffff', 100)
    where run_id::text like '5b000000-%'),
  array['5b000000-0000-0000-0000-000000000001', '5b000000-0000-0000-0000-000000000003',
        '5b000000-0000-0000-0000-000000000005']::uuid[],
  'a batch takes the scored run whose extent overlaps and every unscored run, not the far or short ones');
select is(
  (select array_agg(run_id order by run_id)
     from segment_backfill_runs('5a5a0000-0000-0000-0000-0000000000d1',
                                '5b000000-0000-0000-0000-000000000003', 100)
    where run_id::text like '5b000000-%'),
  array['5b000000-0000-0000-0000-000000000005']::uuid[],
  'the next batch starts after the cursor');
select is(
  (select count(*)::int from segment_backfill_runs('5a5a0000-0000-0000-0000-0000000000d2', null, 25)),
  0, 'a pulled segment has no batch');

select ok(
  enqueue_segment_backfill('5a5a0000-0000-0000-0000-0000000000d1') =
  enqueue_segment_backfill('5a5a0000-0000-0000-0000-0000000000d1'),
  'a second start while a backfill is queued returns the same job');
select ok(
  enqueue_segment_backfill('5a5a0000-0000-0000-0000-0000000000d1', '5b000000-0000-0000-0000-000000000003') <>
  enqueue_segment_backfill('5a5a0000-0000-0000-0000-0000000000d1'),
  'a continuation is its own job');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"5a000000-0000-0000-0000-0000000000b2","role":"authenticated"}';
select throws_ok(
  $$ select enqueue_segment_backfill('5a5a0000-0000-0000-0000-0000000000d1') $$,
  '42501', null, 'a signed-in non-admin cannot start a backfill');
set local "request.jwt.claims" = '{"sub":"5a000000-0000-0000-0000-0000000000c3","role":"authenticated"}';
select throws_ok(
  $$ select enqueue_segment_backfill('5a5a0000-0000-0000-0000-0000000000d2') $$,
  '22023', null, 'a pulled segment cannot be backfilled');
select lives_ok(
  $$ select enqueue_segment_backfill('5a5a0000-0000-0000-0000-0000000000d3') $$,
  'an admin can start a backfill');
reset role;
select is(
  (select array_agg(payload order by id) from jobs
    where kind = 'segment_match' and payload ->> 'segment_id' = '5a5a0000-0000-0000-0000-0000000000d3'),
  array['{"segment_id":"5a5a0000-0000-0000-0000-0000000000d3"}'::jsonb],
  'the admin''s start is queued as one backfill job for that segment, from the first run');
set local role authenticated;

-- ── no client role reaches the service-role surface ──────────────────────

select throws_ok(
  $$ select * from run_track_extents $$,
  '42501', null, 'authenticated cannot read run_track_extents');
reset role;

select ok(
  not has_function_privilege('authenticated', 'public.record_segment_match(uuid, text, double precision, double precision, double precision, double precision, uuid[], jsonb)', 'execute')
  and not has_function_privilege('authenticated', 'public.segment_match_run_source(uuid)', 'execute')
  and not has_function_privilege('authenticated', 'public.segment_backfill_runs(uuid, uuid, integer)', 'execute')
  and not has_function_privilege('anon', 'public.enqueue_segment_backfill(uuid, uuid)', 'execute')
  and has_function_privilege('service_role', 'public.record_segment_match(uuid, text, double precision, double precision, double precision, double precision, uuid[], jsonb)', 'execute'),
  'the processor RPCs are service-role only and the backfill start is closed to anon');

select * from finish();
rollback;

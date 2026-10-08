-- Pins migration 20270719000020_runs_track_rewrite_invalidates_match.sql.
--
-- A run's track_url is one fixed path, so a client re-uploading the track
-- rewrites the same storage.objects row and only its version changes. The
-- road distance and the matched track then describe bytes that are gone.
-- This file drives a rewrite through storage.objects the way storage-api's
-- upsert does (same name, new version) and checks that: the derived road
-- figure is dropped and cannot be written back from a stale bag or a stale
-- job; run_matched_tracks goes pending and a re-match is queued; the
-- worker's write is refused for the old bytes; finish_job re-queues a job
-- that ends with its run pending; and a failure in the invalidation never
-- fails the upload.

begin;
select plan(25);

insert into auth.users (id, email, encrypted_password, email_confirmed_at,
                        instance_id, aud, role)
values
  ('b1000000-0000-0000-0000-0000000000a1', 'track-rewrite@test.local', '', now(),
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated');

-- Staged before the runs, as a client uploads the track before saving the
-- row: the rewrite trigger finds no run and does nothing.
insert into storage.objects (bucket_id, name, version) values
  ('runs', 'b1000000-0000-0000-0000-0000000000a1/b1000001-0000-0000-0000-000000000001.json.gz', 'a1');

insert into runs (id, user_id, started_at, distance_m, duration_s, source,
                  activity_type, track_url, metadata)
values
  ('b1000001-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-0000000000a1',
   '2026-09-01 09:00:00+00', 5000, 1800, 'app', 'run',
   'b1000000-0000-0000-0000-0000000000a1/b1000001-0000-0000-0000-000000000001.json.gz',
   '{"activity_type":"run","distance_map_matched_m":4990.5,"distance_map_matched_track_version":"a1"}');

select ok(
  exists (select 1 from pg_trigger
           where tgrelid = 'storage.objects'::regclass
             and tgname = 'runs_track_object_rewritten'
             and not tgisinternal),
  'the rewrite trigger is installed on storage.objects');

select is((select (metadata ->> 'distance_map_matched_m')::numeric from runs where id = 'b1000001-0000-0000-0000-000000000001'),
  4990.5::numeric, 'a road distance stamped with the stored track''s version is kept on insert');

-- The worker has matched version a1 and its job is done.
update run_matched_tracks
   set status = 'matched',
       matched_track_url = 'b1000000-0000-0000-0000-0000000000a1/b1000001-0000-0000-0000-000000000001.matched.json.gz',
       matched_at = now()
 where run_id = 'b1000001-0000-0000-0000-000000000001';
update jobs set status = 'done', finished_at = now()
 where kind = 'map_match' and payload ->> 'run_id' = 'b1000001-0000-0000-0000-000000000001';

-- ── writes to the object that are not a new upload ──────────────────────

update storage.objects
   set metadata = '{"cacheControl":"max-age=60"}'
 where bucket_id = 'runs'
   and name = 'b1000000-0000-0000-0000-0000000000a1/b1000001-0000-0000-0000-000000000001.json.gz';

select is((select (metadata ->> 'distance_map_matched_m')::numeric from runs where id = 'b1000001-0000-0000-0000-000000000001'),
  4990.5::numeric, 'a metadata-only update of the object (same version) keeps the road distance');
select is((select status from run_matched_tracks where run_id = 'b1000001-0000-0000-0000-000000000001'),
  'matched', 'and keeps the matched track');

insert into storage.objects (bucket_id, name, version) values
  ('runs', 'b1000000-0000-0000-0000-0000000000a1/b1000001-0000-0000-0000-000000000001.matched.json.gz', 'm1'),
  ('runs', 'b1000000-0000-0000-0000-0000000000a1/b1000001-0000-0000-0000-000000000001.smoothed.json.gz', 's1');

select is((select status from run_matched_tracks where run_id = 'b1000001-0000-0000-0000-000000000001'),
  'matched', 'the worker''s matched-track and smoothed-sidecar objects beside the track are not a track rewrite');
select is((select count(*)::int from jobs
            where kind = 'map_match' and status in ('queued', 'running')
              and payload ->> 'run_id' = 'b1000001-0000-0000-0000-000000000001'),
  0, 'and queue nothing');

-- ── the re-upload in place ───────────────────────────────────────────────

update storage.objects
   set version = 'a2'
 where bucket_id = 'runs'
   and name = 'b1000000-0000-0000-0000-0000000000a1/b1000001-0000-0000-0000-000000000001.json.gz';

select ok((select not (metadata ? 'distance_map_matched_m') and not (metadata ? 'distance_map_matched_track_version')
             from runs where id = 'b1000001-0000-0000-0000-000000000001'),
  'a new version of the track drops the road distance and its version');
select is((select metadata ->> 'activity_type' from runs where id = 'b1000001-0000-0000-0000-000000000001'),
  'run', 'and leaves the rest of the bag alone');
select is((select status from run_matched_tracks where run_id = 'b1000001-0000-0000-0000-000000000001'),
  'pending', 'resets run_matched_tracks to pending');
select ok((select matched_track_url is null and matched_at is null
             from run_matched_tracks where run_id = 'b1000001-0000-0000-0000-000000000001'),
  'so no reader is handed the old bytes'' matched track');
select is((select count(*)::int from jobs
            where kind = 'map_match' and status = 'queued'
              and payload ->> 'run_id' = 'b1000001-0000-0000-0000-000000000001'),
  1, 'and queues a re-match');
select results_eq(
  $$ select track_url, track_version from map_match_track_source('b1000001-0000-0000-0000-000000000001') $$,
  $$ values ('b1000000-0000-0000-0000-0000000000a1/b1000001-0000-0000-0000-000000000001.json.gz'::text, 'a2'::text) $$,
  'the worker reads the path and the new version together');

-- ── a stale client copy cannot write the old figure back ────────────────

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"b1000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);

update runs
   set metadata = '{"activity_type":"run","title":"Tempo","distance_map_matched_m":4990.5,"distance_map_matched_track_version":"a1"}'
 where id = 'b1000001-0000-0000-0000-000000000001';

select ok((select not (metadata ? 'distance_map_matched_m') from runs where id = 'b1000001-0000-0000-0000-000000000001'),
  'a bag loaded before the re-upload cannot put the old track''s road distance back');
select is((select metadata ->> 'title' from runs where id = 'b1000001-0000-0000-0000-000000000001'),
  'Tempo', 'the rest of that write still lands');

reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;

-- ── the worker's write is refused for the old bytes ─────────────────────

select is(
  record_map_match_result('b1000001-0000-0000-0000-000000000001',
    'b1000000-0000-0000-0000-0000000000a1/b1000001-0000-0000-0000-000000000001.json.gz', 'a1',
    'matched', 'b1000000-0000-0000-0000-0000000000a1/b1000001-0000-0000-0000-000000000001.matched.json.gz',
    now(), 'osrm', '1', null),
  false, 'a job that downloaded the replaced bytes cannot record its match');
select is((select status from run_matched_tracks where run_id = 'b1000001-0000-0000-0000-000000000001'),
  'pending', 'and the row stays pending');
select is(
  record_map_match_result('b1000001-0000-0000-0000-000000000001',
    'b1000000-0000-0000-0000-0000000000a1/b1000001-0000-0000-0000-000000000001.json.gz', 'a2',
    'matched', 'b1000000-0000-0000-0000-0000000000a1/b1000001-0000-0000-0000-000000000001.matched.json.gz',
    now(), 'osrm', '1', null),
  true, 'a job that matched the stored bytes records its match');

update runs
   set metadata = '{"activity_type":"run","title":"Tempo","distance_map_matched_m":4993.1,"distance_map_matched_track_version":"a2"}'
 where id = 'b1000001-0000-0000-0000-000000000001';
update runs
   set metadata = '{"activity_type":"run","title":"Tempo","distance_map_matched_m":4990.5,"distance_map_matched_track_version":"a1"}'
 where id = 'b1000001-0000-0000-0000-000000000001';

select results_eq(
  $$ select (metadata ->> 'distance_map_matched_m')::numeric, metadata ->> 'distance_map_matched_track_version'
       from runs where id = 'b1000001-0000-0000-0000-000000000001' $$,
  $$ values (4993.1::numeric, 'a2'::text) $$,
  'a write carrying the old bytes'' figure keeps the stored, current one');

reset role;

-- ── finish_job re-queues a job that leaves its run pending ──────────────

update jobs set status = 'running', attempts = 1, locked_at = now(), locked_by = 'pgtap'
 where kind = 'map_match' and status = 'queued'
   and payload ->> 'run_id' = 'b1000001-0000-0000-0000-000000000001';

-- A rewrite after the job recorded its match: the reset lands on the row,
-- and the re-match it queues is a no-op beside the running job.
update storage.objects
   set version = 'a3'
 where bucket_id = 'runs'
   and name = 'b1000000-0000-0000-0000-0000000000a1/b1000001-0000-0000-0000-000000000001.json.gz';

select finish_job((select id from jobs
                    where kind = 'map_match' and status = 'running'
                      and payload ->> 'run_id' = 'b1000001-0000-0000-0000-000000000001'),
                  'done');

select results_eq(
  $$ select status, locked_by from jobs
      where kind = 'map_match' and payload ->> 'run_id' = 'b1000001-0000-0000-0000-000000000001'
        and status in ('queued', 'running') $$,
  $$ values ('queued'::text, null::text) $$,
  'a map_match job finishing while its run is pending goes back in the queue');

update jobs set status = 'running', attempts = 2
 where kind = 'map_match' and status = 'queued'
   and payload ->> 'run_id' = 'b1000001-0000-0000-0000-000000000001';
update run_matched_tracks set status = 'matched'
 where run_id = 'b1000001-0000-0000-0000-000000000001';

select finish_job((select id from jobs
                    where kind = 'map_match' and status = 'running'
                      and payload ->> 'run_id' = 'b1000001-0000-0000-0000-000000000001'),
                  'done');

select is((select count(*)::int from jobs
            where kind = 'map_match' and status in ('queued', 'running')
              and payload ->> 'run_id' = 'b1000001-0000-0000-0000-000000000001'),
  0, 'one that leaves it matched finishes done');

insert into jobs (kind, payload, status, attempts, max_attempts)
values ('map_match',
        jsonb_build_object('run_id', 'b1000001-0000-0000-0000-000000000001',
                           'user_id', 'b1000000-0000-0000-0000-0000000000a1'),
        'running', 5, 5);
update run_matched_tracks set status = 'pending'
 where run_id = 'b1000001-0000-0000-0000-000000000001';

select finish_job((select id from jobs
                    where kind = 'map_match' and status = 'running'
                      and payload ->> 'run_id' = 'b1000001-0000-0000-0000-000000000001'),
                  'done');

select is((select count(*)::int from jobs
            where kind = 'map_match' and status in ('queued', 'running')
              and payload ->> 'run_id' = 'b1000001-0000-0000-0000-000000000001'),
  0, 'and one out of attempts finishes done rather than sitting queued where claim_next_job never takes it');

-- ── a restore that inserts an old bag ───────────────────────────────────

insert into storage.objects (bucket_id, name, version) values
  ('runs', 'b1000000-0000-0000-0000-0000000000a1/b1000001-0000-0000-0000-000000000002.json.gz', 'c2');
insert into runs (id, user_id, started_at, distance_m, duration_s, source,
                  activity_type, track_url, metadata)
values
  ('b1000001-0000-0000-0000-000000000002', 'b1000000-0000-0000-0000-0000000000a1',
   '2026-09-02 09:00:00+00', 5000, 1800, 'app', 'run',
   'b1000000-0000-0000-0000-0000000000a1/b1000001-0000-0000-0000-000000000002.json.gz',
   '{"activity_type":"run","distance_map_matched_m":4990.5,"distance_map_matched_track_version":"c1"}');

select ok((select not (metadata ? 'distance_map_matched_m') from runs where id = 'b1000001-0000-0000-0000-000000000002'),
  'a row inserted with a road distance for other bytes than its stored track gets none');

-- ── the invalidation never fails the upload ─────────────────────────────

update run_matched_tracks set status = 'matched'
 where run_id = 'b1000001-0000-0000-0000-000000000002';

create function public.pgtap_refuse_job_insert() returns trigger
language plpgsql as $refuse$ begin raise exception 'pgtap: jobs refused'; end; $refuse$;
create trigger zzz_pgtap_refuse_job_insert
  before insert on jobs
  for each row execute function public.pgtap_refuse_job_insert();

select lives_ok(
  $$ update storage.objects set version = 'c3'
      where bucket_id = 'runs'
        and name = 'b1000000-0000-0000-0000-0000000000a1/b1000001-0000-0000-0000-000000000002.json.gz' $$,
  'a re-upload whose re-match cannot be queued still lands');
select is((select version from storage.objects
            where bucket_id = 'runs'
              and name = 'b1000000-0000-0000-0000-0000000000a1/b1000001-0000-0000-0000-000000000002.json.gz'),
  'c3', 'with the new version stored');
select is((select status from run_matched_tracks where run_id = 'b1000001-0000-0000-0000-000000000002'),
  'pending', 'and the matched track still invalidated, its own step apart from the enqueue that failed');

select * from finish();
rollback;

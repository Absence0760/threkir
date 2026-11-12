-- Pins migration 20270719000016_runs_keep_smoothed_sidecar_key.sql: the
-- smoothed-sidecar hash the job_worker records (metadata.smoothed_sidecar_sha256)
-- survives a signed-in client's bag that was loaded before the worker wrote
-- it, and a stale copy of a recomputed run; the worker (service role) can
-- still remove it, a client that sends the key sets it as sent, a change to
-- track_url drops it, and the road distance keeps the carry it already had.
-- Since 20270719000020 that road distance is kept only beside a
-- distance_map_matched_track_version naming the stored object, so run 1's
-- track object is staged before the run, leaving the rewrite trigger on
-- storage.objects no run to act on.

begin;
select plan(10);

insert into storage.objects (bucket_id, name, version) values
  ('runs', 'b5000000-0000-0000-0000-0000000000a1/b5000001-0000-0000-0000-000000000001.json.gz', 'k1');

insert into auth.users (id, email, encrypted_password, email_confirmed_at,
                        instance_id, aud, role)
values
  ('b5000000-0000-0000-0000-0000000000a1', 'keep-sidecar-key@test.local', '', now(),
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated');

-- Run 1: a watch run map_match gave a sidecar, never recomputed.
-- Run 2: recomputed on the smoothed pass, so the recompute named the sidecar.
-- Run 3: never recomputed (the worker-removal and new-track cases).
insert into runs (id, user_id, started_at, distance_m, duration_s, source,
                  activity_type, track_url, metadata)
values
  ('b5000001-0000-0000-0000-000000000001', 'b5000000-0000-0000-0000-0000000000a1',
   '2026-09-01 09:00:00+00', 5000, 1800, 'watch', 'run',
   'b5000000-0000-0000-0000-0000000000a1/b5000001-0000-0000-0000-000000000001.json.gz',
   '{"smoothed_sidecar_sha256":"1111111111111111111111111111111111111111111111111111111111111111","distance_map_matched_m":4990.5,"distance_map_matched_track_version":"k1"}'),
  ('b5000001-0000-0000-0000-000000000002', 'b5000000-0000-0000-0000-0000000000a1',
   '2026-09-02 09:00:00+00', 5000, 1800, 'app', 'run',
   'b5000000-0000-0000-0000-0000000000a1/b5000001-0000-0000-0000-000000000002.json.gz',
   '{"smoothed_sidecar_sha256":"2222222222222222222222222222222222222222222222222222222222222222","distance_recorded_m":6300,"distance_estimator":"kalman_v2","distance_estimator_pass":"smoothed","distance_recomputed_at":"2026-10-08T12:00:00Z"}'),
  ('b5000001-0000-0000-0000-000000000003', 'b5000000-0000-0000-0000-0000000000a1',
   '2026-09-03 09:00:00+00', 5000, 1800, 'watch', 'run',
   'b5000000-0000-0000-0000-0000000000a1/b5000001-0000-0000-0000-000000000003.json.gz',
   '{"smoothed_sidecar_sha256":"3333333333333333333333333333333333333333333333333333333333333333"}');

-- ── the owner, signed in, edits from a copy loaded before the worker ─────

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"b5000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);

update runs
   set metadata = '{"title":"Tempo"}'
 where id = 'b5000001-0000-0000-0000-000000000001';

select is((select metadata ->> 'smoothed_sidecar_sha256' from runs where id = 'b5000001-0000-0000-0000-000000000001'),
  '1111111111111111111111111111111111111111111111111111111111111111',
  'a signed-in write without the sidecar hash keeps it');
select is((select (metadata ->> 'distance_map_matched_m')::numeric from runs where id = 'b5000001-0000-0000-0000-000000000001'),
  4990.5::numeric, 'and the road distance beside it keeps its own carry');
select is((select metadata ->> 'title' from runs where id = 'b5000001-0000-0000-0000-000000000001'),
  'Tempo', 'the rest of that write still lands');

update runs
   set metadata = '{"title":"Tempo","smoothed_sidecar_sha256":"4444444444444444444444444444444444444444444444444444444444444444"}'
 where id = 'b5000001-0000-0000-0000-000000000001';

select is((select metadata ->> 'smoothed_sidecar_sha256' from runs where id = 'b5000001-0000-0000-0000-000000000001'),
  '4444444444444444444444444444444444444444444444444444444444444444',
  'a write that carries the key sets it as sent');

-- runs_track_url_path_shape allows one non-null track_url per run, so the
-- only track change a write can name is to or from null.
update runs
   set track_url = null,
       metadata = '{}'
 where id = 'b5000001-0000-0000-0000-000000000003';

select ok((select not (metadata ? 'smoothed_sidecar_sha256') from runs where id = 'b5000001-0000-0000-0000-000000000003'),
  'a write that changes track_url does not carry the old track''s sidecar hash');

reset role;

-- ── the worker removes it as the service role ────────────────────────────

update runs
   set metadata = '{"smoothed_sidecar_sha256":"3333333333333333333333333333333333333333333333333333333333333333"}'
 where id = 'b5000001-0000-0000-0000-000000000003';
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;

update runs
   set metadata = '{}'
 where id = 'b5000001-0000-0000-0000-000000000003';

select ok((select not (metadata ? 'smoothed_sidecar_sha256') from runs where id = 'b5000001-0000-0000-0000-000000000003'),
  'the worker, writing as the service role, can remove the key');

-- A forward-pass recompute: the worker's own bag carries
-- distance_recomputed_at and drops the hash with the sidecar it deletes.
update runs
   set metadata = '{"distance_recorded_m":6300,"distance_estimator":"kalman_v2","distance_estimator_pass":"forward","distance_recomputed_at":"2026-10-09T12:00:00Z"}'
 where id = 'b5000001-0000-0000-0000-000000000002';

select ok((select not (metadata ? 'smoothed_sidecar_sha256') from runs where id = 'b5000001-0000-0000-0000-000000000002'),
  'a forward-pass recompute removes the hash the earlier smoothed pass recorded');

reset role;

-- ── a stale copy of a recomputed run ────────────────────────────────────

update runs
   set metadata = '{"smoothed_sidecar_sha256":"2222222222222222222222222222222222222222222222222222222222222222","distance_recorded_m":6300,"distance_estimator":"kalman_v2","distance_estimator_pass":"smoothed","distance_recomputed_at":"2026-10-08T12:00:00Z"}'
 where id = 'b5000001-0000-0000-0000-000000000002';
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;

update runs
   set distance_m = 6300,
       metadata = '{"title":"Long"}'
 where id = 'b5000001-0000-0000-0000-000000000002';

reset role;

select is((select metadata ->> 'smoothed_sidecar_sha256' from runs where id = 'b5000001-0000-0000-0000-000000000002'),
  '2222222222222222222222222222222222222222222222222222222222222222',
  'a stale copy of a recomputed run keeps the sidecar hash');
select is((select metadata ->> 'distance_recomputed_at' from runs where id = 'b5000001-0000-0000-0000-000000000002'),
  '2026-10-08T12:00:00Z', 'and keeps the recompute keys beside it');

select ok(
  not has_function_privilege('authenticated', 'public.runs_keep_distance_recompute()', 'EXECUTE'),
  'authenticated cannot call the trigger function directly');

select * from finish();
rollback;

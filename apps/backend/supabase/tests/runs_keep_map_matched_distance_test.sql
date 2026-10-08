-- Pins migration 20270719000004_runs_keep_map_matched_distance.sql: the
-- road-matched distance the job_worker writes (metadata.distance_map_matched_m)
-- survives a signed-in client's bag that was loaded before the matcher ran,
-- and a stale copy of a recomputed run; the worker (service role) can still
-- clear it, a client that has the current value can still change it, and a
-- new track drops it.

begin;
select plan(9);

insert into auth.users (id, email, encrypted_password, email_confirmed_at,
                        instance_id, aud, role)
values
  ('af000000-0000-0000-0000-0000000000a1', 'keep-map-matched@test.local', '', now(),
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated');

-- Run 1: road-matched, never recomputed.
-- Run 2: road-matched and recomputed.
-- Run 3: road-matched, never recomputed (the worker-clear and new-track cases).
insert into runs (id, user_id, started_at, distance_m, duration_s, source,
                  activity_type, track_url, metadata)
values
  ('af000001-0000-0000-0000-000000000001', 'af000000-0000-0000-0000-0000000000a1',
   '2026-09-01 09:00:00+00', 5000, 1800, 'app', 'run',
   'af000000-0000-0000-0000-0000000000a1/af000001-0000-0000-0000-000000000001.json.gz',
   '{"activity_type":"run","distance_map_matched_m":4990.5}'),
  ('af000001-0000-0000-0000-000000000002', 'af000000-0000-0000-0000-0000000000a1',
   '2026-09-02 09:00:00+00', 5000, 1800, 'app', 'run',
   'af000000-0000-0000-0000-0000000000a1/af000001-0000-0000-0000-000000000002.json.gz',
   '{"activity_type":"run","distance_map_matched_m":4985.2,"distance_recorded_m":6300,"distance_estimator":"kalman_v2","distance_recomputed_at":"2026-10-08T12:00:00Z"}'),
  ('af000001-0000-0000-0000-000000000003', 'af000000-0000-0000-0000-0000000000a1',
   '2026-09-03 09:00:00+00', 5000, 1800, 'app', 'run',
   'af000000-0000-0000-0000-0000000000a1/af000001-0000-0000-0000-000000000003.json.gz',
   '{"activity_type":"run","distance_map_matched_m":4970.0}');

-- ── the owner, signed in, edits from a copy loaded before the match ─────

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"af000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);

update runs
   set metadata = '{"activity_type":"run","title":"Tempo"}'
 where id = 'af000001-0000-0000-0000-000000000001';

select is((select (metadata ->> 'distance_map_matched_m')::numeric from runs where id = 'af000001-0000-0000-0000-000000000001'),
  4990.5::numeric, 'a signed-in write without the road distance keeps it');
select is((select metadata ->> 'title' from runs where id = 'af000001-0000-0000-0000-000000000001'),
  'Tempo', 'the rest of that write still lands');

update runs
   set metadata = '{"activity_type":"run","title":"Tempo","distance_map_matched_m":4991.0}'
 where id = 'af000001-0000-0000-0000-000000000001';

select is((select (metadata ->> 'distance_map_matched_m')::numeric from runs where id = 'af000001-0000-0000-0000-000000000001'),
  4991.0::numeric, 'a write that carries the key sets it as sent');

update runs
   set track_url = 'af000000-0000-0000-0000-0000000000a1/af000001-0000-0000-0000-000000000003-v2.json.gz',
       metadata = '{"activity_type":"run"}'
 where id = 'af000001-0000-0000-0000-000000000003';

select ok((select not (metadata ? 'distance_map_matched_m') from runs where id = 'af000001-0000-0000-0000-000000000003'),
  'a write that replaces the track does not carry the old track''s road distance');

reset role;

-- ── the worker clears it as the service role ─────────────────────────────

update runs
   set metadata = '{"activity_type":"run","distance_map_matched_m":4970.0}'
 where id = 'af000001-0000-0000-0000-000000000003';
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;

update runs
   set metadata = '{"activity_type":"run"}'
 where id = 'af000001-0000-0000-0000-000000000003';

select ok((select not (metadata ? 'distance_map_matched_m') from runs where id = 'af000001-0000-0000-0000-000000000003'),
  'the road matcher, writing as the service role, can clear the key');

-- ── a stale copy of a recomputed run, whoever writes it ──────────────────

update runs
   set distance_m = 6300,
       metadata = '{"activity_type":"run","title":"Long"}'
 where id = 'af000001-0000-0000-0000-000000000002';

reset role;

select is((select (metadata ->> 'distance_map_matched_m')::numeric from runs where id = 'af000001-0000-0000-0000-000000000002'),
  4985.2::numeric, 'a stale copy of a recomputed run keeps the road distance');
select is((select metadata ->> 'distance_recomputed_at' from runs where id = 'af000001-0000-0000-0000-000000000002'),
  '2026-10-08T12:00:00Z', 'and keeps the recompute keys beside it');
select is((select distance_m from runs where id = 'af000001-0000-0000-0000-000000000002'),
  5000.00::numeric, 'and keeps the recomputed distance');

select ok(
  not has_function_privilege('authenticated', 'public.runs_keep_distance_recompute()', 'EXECUTE'),
  'authenticated cannot call the trigger function directly');

select * from finish();
rollback;

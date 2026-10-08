-- Pins migration 20270719000003_runs_keep_distance_recompute.sql: a write from
-- a client that loaded a run before its distance was recomputed cannot put the
-- inflated figure back or drop the recompute's metadata keys, while a write
-- from a client that has the recomputed row, a deliberate distance edit, and a
-- run that was never recomputed all pass through untouched.

begin;
select plan(12);

insert into auth.users (id, email, encrypted_password, email_confirmed_at,
                        instance_id, aud, role)
values
  ('ae000000-0000-0000-0000-0000000000a1', 'keep-recompute@test.local', '', now(),
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated');

-- Run 1: recorded at 6300 m, recomputed to 5000 m (as the worker leaves it).
-- Run 2: never recomputed.
insert into runs (id, user_id, started_at, distance_m, duration_s, source,
                  activity_type, metadata, fastest_5k_s)
values
  ('ae000001-0000-0000-0000-000000000001', 'ae000000-0000-0000-0000-0000000000a1',
   '2026-09-01 09:00:00+00', 5000, 1800, 'app', 'run',
   '{"activity_type":"run","distance_recorded_m":6300,"distance_estimator":"kalman_v1","distance_recomputed_at":"2026-10-08T12:00:00Z"}',
   1790),
  ('ae000001-0000-0000-0000-000000000002', 'ae000000-0000-0000-0000-0000000000a1',
   '2026-09-02 09:00:00+00', 6300, 1800, 'app', 'run', '{"activity_type":"run"}', 1400);

-- ── a stale client write ────────────────────────────────────────────────

update runs
   set distance_m = 6300,
       fastest_5k_s = 1400,
       metadata = '{"activity_type":"run","title":"Tempo"}'
 where id = 'ae000001-0000-0000-0000-000000000001';

select is((select distance_m from runs where id = 'ae000001-0000-0000-0000-000000000001'),
  5000.00::numeric, 'a stale write of the original recorded distance keeps the recomputed one');
select is((select fastest_5k_s from runs where id = 'ae000001-0000-0000-0000-000000000001'),
  1790, 'a stale write keeps the recomputed fastest_5k_s');
select is((select metadata ->> 'distance_recomputed_at' from runs where id = 'ae000001-0000-0000-0000-000000000001'),
  '2026-10-08T12:00:00Z', 'a stale write keeps distance_recomputed_at');
select is((select (metadata ->> 'distance_recorded_m')::numeric from runs where id = 'ae000001-0000-0000-0000-000000000001'),
  6300::numeric, 'a stale write keeps distance_recorded_m');
select is((select metadata ->> 'distance_estimator' from runs where id = 'ae000001-0000-0000-0000-000000000001'),
  'kalman_v1', 'a stale write keeps distance_estimator');
select is((select metadata ->> 'title' from runs where id = 'ae000001-0000-0000-0000-000000000001'),
  'Tempo', 'the rest of a stale write still lands');

-- ── a stale write that types a new distance ─────────────────────────────

update runs
   set distance_m = 5100,
       metadata = '{"activity_type":"run","title":"Tempo"}'
 where id = 'ae000001-0000-0000-0000-000000000001';

select is((select distance_m from runs where id = 'ae000001-0000-0000-0000-000000000001'),
  5100.00::numeric, 'a distance the owner deliberately typed is kept');
select ok((select metadata ? 'distance_recomputed_at' from runs where id = 'ae000001-0000-0000-0000-000000000001'),
  'the recompute keys survive a deliberate distance edit from a stale copy');

-- ── an up-to-date client write ──────────────────────────────────────────

update runs
   set distance_m = 6300,
       fastest_5k_s = 1500,
       metadata = '{"activity_type":"run","distance_recorded_m":6300,"distance_estimator":"kalman_v1","distance_recomputed_at":"2026-10-08T12:00:00Z"}'
 where id = 'ae000001-0000-0000-0000-000000000001';

select is((select distance_m from runs where id = 'ae000001-0000-0000-0000-000000000001'),
  6300.00::numeric, 'a client that has the recomputed row may set any distance');
select is((select fastest_5k_s from runs where id = 'ae000001-0000-0000-0000-000000000001'),
  1500, 'a client that has the recomputed row may set fastest_5k_s');

-- ── a run that was never recomputed ─────────────────────────────────────

update runs
   set distance_m = 6200,
       fastest_5k_s = 1450,
       metadata = '{"activity_type":"run","title":"Easy"}'
 where id = 'ae000001-0000-0000-0000-000000000002';

select is((select distance_m from runs where id = 'ae000001-0000-0000-0000-000000000002'),
  6200.00::numeric, 'a run never recomputed is written as sent');
select ok(
  not has_function_privilege('authenticated', 'public.runs_keep_distance_recompute()', 'EXECUTE'),
  'authenticated cannot call the trigger function directly');

select * from finish();
rollback;

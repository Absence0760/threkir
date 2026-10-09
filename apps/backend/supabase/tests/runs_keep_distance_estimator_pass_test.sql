-- Pins migration 20270719000006_runs_keep_distance_estimator_pass.sql: a
-- stale client copy of a recomputed run keeps metadata.distance_estimator_pass
-- with the recompute's other keys, and a run recomputed before the key
-- existed does not gain a null one.

begin;
select plan(4);

insert into auth.users (id, email, encrypted_password, email_confirmed_at,
                        instance_id, aud, role)
values
  ('ae000000-0000-0000-0000-0000000000b1', 'keep-pass@test.local', '', now(),
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated');

insert into runs (id, user_id, started_at, distance_m, duration_s, source,
                  activity_type, metadata)
values
  ('ae000002-0000-0000-0000-000000000001', 'ae000000-0000-0000-0000-0000000000b1',
   '2026-09-01 09:00:00+00', 5000, 1800, 'app', 'run',
   '{"distance_recorded_m":6300,"distance_estimator":"kalman_v2","distance_estimator_pass":"forward","distance_recomputed_at":"2026-10-08T12:00:00Z"}'),
  ('ae000002-0000-0000-0000-000000000002', 'ae000000-0000-0000-0000-0000000000b1',
   '2026-09-02 09:00:00+00', 5000, 1800, 'app', 'run',
   '{"distance_recorded_m":6300,"distance_estimator":"kalman_v1","distance_recomputed_at":"2026-10-08T12:00:00Z"}');

update runs set metadata = '{"title":"Trail"}'
 where id in ('ae000002-0000-0000-0000-000000000001', 'ae000002-0000-0000-0000-000000000002');

select is((select metadata ->> 'distance_estimator_pass' from runs where id = 'ae000002-0000-0000-0000-000000000001'),
  'forward', 'a stale write keeps distance_estimator_pass');
select is((select metadata ->> 'distance_estimator' from runs where id = 'ae000002-0000-0000-0000-000000000001'),
  'kalman_v2', 'a stale write still keeps distance_estimator beside it');
select ok(not (select metadata ? 'distance_estimator_pass' from runs where id = 'ae000002-0000-0000-0000-000000000002'),
  'a run recomputed before the key existed does not gain a null distance_estimator_pass');

update runs
   set metadata = '{"distance_recorded_m":6300,"distance_estimator":"kalman_v2","distance_estimator_pass":"smoothed","distance_recomputed_at":"2026-10-09T12:00:00Z"}'
 where id = 'ae000002-0000-0000-0000-000000000001';

select is((select metadata ->> 'distance_estimator_pass' from runs where id = 'ae000002-0000-0000-0000-000000000001'),
  'smoothed', 'a write that carries the recompute keys (the next recompute) replaces the pass');

select * from finish();
rollback;

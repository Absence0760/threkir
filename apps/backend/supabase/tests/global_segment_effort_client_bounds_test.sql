-- Pins 20271224000500 (audit of PR #1359, Medium): a catalogue effort a
-- client writes must fit inside its run, so a runner cannot post a forged
-- time onto a park course board. The server matcher is not held to it.
--
--   1.  A forged 1 s effort on a 400 m segment is refused.
--   2.  An effort starting hours before its run is refused.
--   3.  An effort longer than its run is refused.
--   4.  A genuine effort inside the run, at a running pace, is accepted.
--   5.  On a ride, a pace no runner holds but a cyclist does is accepted.
--   6.  The service role still writes an effort the client bounds refuse.

begin;
select plan(6);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values ('e5240000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'gseb@gseb.local', '', now(), now());

select tests.confirm_consent();

insert into global_segments (id, name, waypoints, distance_m, is_active)
values
  ('e5241111-0000-0000-0000-000000000001', 'GSEB Hill',
   '[{"lat":38.0,"lng":-77.0},{"lat":38.0036,"lng":-77.0}]', 400, true),
  ('e5241111-0000-0000-0000-000000000002', 'GSEB Flat',
   '[{"lat":38.1,"lng":-77.0},{"lat":38.1036,"lng":-77.0}]', 400, true);

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"e5240000-0000-0000-0000-000000000001","role":"authenticated"}';

insert into runs (id, user_id, started_at, distance_m, duration_s, source, activity_type, metadata)
values
  ('e5242222-0000-0000-0000-000000000001', 'e5240000-0000-0000-0000-000000000001',
   now() - interval '1 hour', 5000, 1800, 'app', 'run', '{"activity_type":"run"}'),
  ('e5242222-0000-0000-0000-000000000002', 'e5240000-0000-0000-0000-000000000001',
   now() - interval '3 hours', 20000, 2400, 'app', 'cycle', '{"activity_type":"cycle"}');

select throws_ok(
  $$insert into global_segment_efforts (global_segment_id, run_id, user_id, time_seconds, started_at, matched_by)
    values ('e5241111-0000-0000-0000-000000000001', 'e5242222-0000-0000-0000-000000000001',
            'e5240000-0000-0000-0000-000000000001', 1, now() - interval '50 minutes', 'zone')$$,
  '23514', 'global_segment_effort_implausible: faster than the activity allows',
  'a forged 1 s effort on a 400 m segment is refused');

select throws_ok(
  $$insert into global_segment_efforts (global_segment_id, run_id, user_id, time_seconds, started_at, matched_by)
    values ('e5241111-0000-0000-0000-000000000001', 'e5242222-0000-0000-0000-000000000001',
            'e5240000-0000-0000-0000-000000000001', 120, now() - interval '4 hours', 'zone')$$,
  '23514', 'global_segment_effort_implausible: starts outside the run',
  'an effort starting hours before its run is refused');

select throws_ok(
  $$insert into global_segment_efforts (global_segment_id, run_id, user_id, time_seconds, started_at, matched_by)
    values ('e5241111-0000-0000-0000-000000000001', 'e5242222-0000-0000-0000-000000000001',
            'e5240000-0000-0000-0000-000000000001', 1801, now() - interval '1 hour', 'zone')$$,
  '23514', 'global_segment_effort_implausible: longer than the run',
  'an effort longer than its run is refused');

select lives_ok(
  $$insert into global_segment_efforts (global_segment_id, run_id, user_id, time_seconds, started_at, matched_by)
    values ('e5241111-0000-0000-0000-000000000001', 'e5242222-0000-0000-0000-000000000001',
            'e5240000-0000-0000-0000-000000000001', 95.4, now() - interval '50 minutes', 'zone')$$,
  'a genuine effort inside the run at a running pace is accepted');

select lives_ok(
  $$insert into global_segment_efforts (global_segment_id, run_id, user_id, time_seconds, started_at, matched_by)
    values ('e5241111-0000-0000-0000-000000000002', 'e5242222-0000-0000-0000-000000000002',
            'e5240000-0000-0000-0000-000000000001', 25, now() - interval '170 minutes', 'zone')$$,
  'on a ride, 16 m/s over a segment is accepted');

reset role;
set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';
select lives_ok(
  $$insert into global_segment_efforts (global_segment_id, run_id, user_id, time_seconds, started_at, matched_by)
    values ('e5241111-0000-0000-0000-000000000002', 'e5242222-0000-0000-0000-000000000001',
            'e5240000-0000-0000-0000-000000000001', 1, now() - interval '4 hours', 'zone')$$,
  'the service role is not held to the client bounds');

select * from finish();
rollback;

-- Pins the client bounds on a catalogue effort (20271224000500, corrected by
-- 20271225000200): a client-written effort may not start more than a minute
-- before its run, nor cover its segment faster than anyone covers ground on
-- foot (11 m/s) or on a ride (25 m/s). runs.duration_s is moving time, so it
-- bounds neither the end of an effort nor its length: a paused run's genuine
-- late effort lands. The server matcher is not held to any of it, and a
-- plausible forged time is not refused here (issue #1313).
--
--   1.  A forged 1 s effort on a 400 m segment is refused.
--   2.  An effort starting hours before its run is refused.
--   3.  An effort 61 s before the run's start is refused.
--   4.  An effort 60 s before the run's start is accepted.
--   5.  A genuine effort inside the run, at a running pace, is accepted.
--   6.  On a paused run, an effort starting after started_at + duration_s
--       is accepted.
--   7.  On a paused run, an effort longer than duration_s is accepted.
--   8.  On a ride, a pace no runner holds but a cyclist does is accepted.
--   9.  On a walk, that pace is refused (foot cap).
--  10.  On a hike, that pace is refused (foot cap).
--  11.  On a stroller run, that pace is refused (foot cap).
--  12.  A client UPDATE is refused by privilege.
--  13.  Were a client UPDATE admitted, the trigger still refuses a forged time.
--  14.  The service role still writes an effort the client bounds refuse.

begin;
select plan(14);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values ('e5240000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'gseb@gseb.local', '', now(), now());

select tests.confirm_consent();

insert into global_segments (id, name, waypoints, distance_m, is_active)
values
  ('e5241111-0000-0000-0000-000000000001', 'GSEB Hill',
   '[{"lat":38.0,"lng":-77.0},{"lat":38.0036,"lng":-77.0}]', 400, true),
  ('e5241111-0000-0000-0000-000000000002', 'GSEB Flat',
   '[{"lat":38.1,"lng":-77.0},{"lat":38.1036,"lng":-77.0}]', 400, true),
  ('e5241111-0000-0000-0000-000000000003', 'GSEB Long',
   '[{"lat":38.2,"lng":-77.0},{"lat":38.236,"lng":-77.0}]', 4000, true),
  ('e5241111-0000-0000-0000-000000000004', 'GSEB Edge',
   '[{"lat":38.3,"lng":-77.0},{"lat":38.3036,"lng":-77.0}]', 400, true);

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"e5240000-0000-0000-0000-000000000001","role":"authenticated"}';

-- Run 3 is the paused run: started 08:00, paused 08:20-08:30, stopped 09:00,
-- so duration_s is 3000 against a 3600 s wall-clock span.
insert into runs (id, user_id, started_at, distance_m, duration_s, source, activity_type, metadata)
values
  ('e5242222-0000-0000-0000-000000000001', 'e5240000-0000-0000-0000-000000000001',
   now() - interval '1 hour', 5000, 1800, 'app', 'run', '{"activity_type":"run"}'),
  ('e5242222-0000-0000-0000-000000000002', 'e5240000-0000-0000-0000-000000000001',
   now() - interval '3 hours', 20000, 2400, 'app', 'cycle', '{"activity_type":"cycle"}'),
  ('e5242222-0000-0000-0000-000000000003', 'e5240000-0000-0000-0000-000000000001',
   '2027-06-01 08:00:00+00', 10000, 3000, 'app', 'run', '{"activity_type":"run"}'),
  ('e5242222-0000-0000-0000-000000000004', 'e5240000-0000-0000-0000-000000000001',
   now() - interval '5 hours', 5000, 3600, 'app', 'walk', '{"activity_type":"walk"}'),
  ('e5242222-0000-0000-0000-000000000005', 'e5240000-0000-0000-0000-000000000001',
   now() - interval '7 hours', 5000, 3600, 'app', 'hike', '{"activity_type":"hike"}'),
  ('e5242222-0000-0000-0000-000000000006', 'e5240000-0000-0000-0000-000000000001',
   now() - interval '9 hours', 5000, 3600, 'app', 'stroller', '{"activity_type":"stroller"}');

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
  '23514', 'global_segment_effort_implausible: starts before the run',
  'an effort starting hours before its run is refused');

select throws_ok(
  $$insert into global_segment_efforts (global_segment_id, run_id, user_id, time_seconds, started_at, matched_by)
    values ('e5241111-0000-0000-0000-000000000004', 'e5242222-0000-0000-0000-000000000003',
            'e5240000-0000-0000-0000-000000000001', 120, '2027-06-01 07:58:59+00', 'zone')$$,
  '23514', 'global_segment_effort_implausible: starts before the run',
  'an effort 61 s before the run starts is refused');

select lives_ok(
  $$insert into global_segment_efforts (global_segment_id, run_id, user_id, time_seconds, started_at, matched_by)
    values ('e5241111-0000-0000-0000-000000000004', 'e5242222-0000-0000-0000-000000000003',
            'e5240000-0000-0000-0000-000000000001', 120, '2027-06-01 07:59:00+00', 'zone')$$,
  'an effort 60 s before the run starts is accepted (the slack is inclusive)');

select lives_ok(
  $$insert into global_segment_efforts (global_segment_id, run_id, user_id, time_seconds, started_at, matched_by)
    values ('e5241111-0000-0000-0000-000000000001', 'e5242222-0000-0000-0000-000000000001',
            'e5240000-0000-0000-0000-000000000001', 95.4, now() - interval '50 minutes', 'zone')$$,
  'a genuine effort inside the run at a running pace is accepted');

select lives_ok(
  $$insert into global_segment_efforts (global_segment_id, run_id, user_id, time_seconds, started_at, matched_by)
    values ('e5241111-0000-0000-0000-000000000001', 'e5242222-0000-0000-0000-000000000003',
            'e5240000-0000-0000-0000-000000000001', 100, '2027-06-01 08:52:00+00', 'zone')$$,
  'on a paused run, an effort at 08:52 (after started_at + duration_s) is accepted');

select lives_ok(
  $$insert into global_segment_efforts (global_segment_id, run_id, user_id, time_seconds, started_at, matched_by)
    values ('e5241111-0000-0000-0000-000000000003', 'e5242222-0000-0000-0000-000000000003',
            'e5240000-0000-0000-0000-000000000001', 3300, '2027-06-01 08:01:00+00', 'zone')$$,
  'on a paused run, an effort spanning the pause and longer than duration_s is accepted');

select lives_ok(
  $$insert into global_segment_efforts (global_segment_id, run_id, user_id, time_seconds, started_at, matched_by)
    values ('e5241111-0000-0000-0000-000000000002', 'e5242222-0000-0000-0000-000000000002',
            'e5240000-0000-0000-0000-000000000001', 25, now() - interval '170 minutes', 'zone')$$,
  'on a ride, 16 m/s over a segment is accepted');

select throws_ok(
  $$insert into global_segment_efforts (global_segment_id, run_id, user_id, time_seconds, started_at, matched_by)
    values ('e5241111-0000-0000-0000-000000000002', 'e5242222-0000-0000-0000-000000000004',
            'e5240000-0000-0000-0000-000000000001', 25, now() - interval '290 minutes', 'zone')$$,
  '23514', 'global_segment_effort_implausible: faster than the activity allows',
  'on a walk, 16 m/s is refused by the foot cap');

select throws_ok(
  $$insert into global_segment_efforts (global_segment_id, run_id, user_id, time_seconds, started_at, matched_by)
    values ('e5241111-0000-0000-0000-000000000002', 'e5242222-0000-0000-0000-000000000005',
            'e5240000-0000-0000-0000-000000000001', 25, now() - interval '410 minutes', 'zone')$$,
  '23514', 'global_segment_effort_implausible: faster than the activity allows',
  'on a hike, 16 m/s is refused by the foot cap');

select throws_ok(
  $$insert into global_segment_efforts (global_segment_id, run_id, user_id, time_seconds, started_at, matched_by)
    values ('e5241111-0000-0000-0000-000000000002', 'e5242222-0000-0000-0000-000000000006',
            'e5240000-0000-0000-0000-000000000001', 25, now() - interval '530 minutes', 'zone')$$,
  '23514', 'global_segment_effort_implausible: faster than the activity allows',
  'on a stroller run, 16 m/s is refused by the foot cap');

select throws_ok(
  $$update global_segment_efforts set time_seconds = 1
     where global_segment_id = 'e5241111-0000-0000-0000-000000000001'
       and run_id = 'e5242222-0000-0000-0000-000000000001'$$,
  '42501', null,
  'a client UPDATE of an effort is refused by privilege');

-- The trigger fires on UPDATE too, so a later grant or policy that let a
-- client update an effort would still meet the bounds. Admit one inside this
-- transaction (rolled back) to show it.
reset role;
grant update on global_segment_efforts to authenticated;
create policy gseb_test_update on global_segment_efforts for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"e5240000-0000-0000-0000-000000000001","role":"authenticated"}';

select throws_ok(
  $$update global_segment_efforts set time_seconds = 1
     where global_segment_id = 'e5241111-0000-0000-0000-000000000001'
       and run_id = 'e5242222-0000-0000-0000-000000000001'$$,
  '23514', 'global_segment_effort_implausible: faster than the activity allows',
  'a client UPDATE to a forged time meets the trigger');

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

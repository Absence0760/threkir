-- Pins migration 20280107000001_park_course_attempt_closures.sql: real runs
-- check a park course after launch. A course whose recent runs fail the same
-- way, from enough different runners, is closed the way an operator closes
-- one; too few runs, too few runners, runner-side outcomes, old evidence and
-- evidence from before an admin reopen close nothing. The flag gates it, a
-- dry run changes nothing, a second pass closes nothing new, and no attempt
-- or effort is ever deleted.

begin;
select plan(37);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
select ('a8000000-0000-0000-0000-0000000000' || lpad(n::text, 2, '0'))::uuid,
       'authenticated', 'authenticated', 'pcac-' || n || '@pcac.local', '', now(), now()
  from generate_series(1, 12) n;
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values ('a8000000-0000-0000-0000-0000000000ad', 'authenticated', 'authenticated',
        'pcac-admin@pcac.local', '', now(), now());
select tests.confirm_consent();
insert into app_admins (user_id) values ('a8000000-0000-0000-0000-0000000000ad');

insert into parks (id, slug, name, agency, region_code, country_code, timezone, is_active)
values ('a8a80000-0000-0000-0000-0000000000e1', 'pcac-park', 'PCAC Park',
        'state', 'US-VA', 'US', 'America/New_York', true);

-- Course n: segment ...d<n>, course ...c<n>, four checkpoints.
create function pg_temp.course(n integer, slug text) returns void language sql as $$
  insert into global_segments (id, name, waypoints, distance_m, is_active)
  values (('a8a80000-0000-0000-0000-0000000000d' || n)::uuid, 'PCAC ' || slug,
          ('[{"lat":3' || n || '.0,"lng":-77.0},{"lat":3' || n || '.004,"lng":-77.0}]')::jsonb, 450, true);
  insert into park_courses (id, park_id, global_segment_id, slug, course_shape, geometry_source, checkpoints)
  values (('a8a80000-0000-0000-0000-0000000000c' || n)::uuid, 'a8a80000-0000-0000-0000-0000000000e1',
          ('a8a80000-0000-0000-0000-0000000000d' || n)::uuid, slug, 'loop', 'osm',
          '[{"lat":37.001,"lng":-77.0},{"lat":37.002,"lng":-77.0},{"lat":37.003,"lng":-77.0},{"lat":37.0035,"lng":-77.0}]');
$$;

create function pg_temp.c(n integer) returns uuid language sql as $$
  select ('a8a80000-0000-0000-0000-0000000000c' || n)::uuid
$$;

create function pg_temp.runner(n integer) returns uuid language sql as $$
  select ('a8000000-0000-0000-0000-0000000000' || lpad(n::text, 2, '0'))::uuid
$$;

create function pg_temp.run(p_runner integer, p_age interval) returns uuid language plpgsql as $$
declare v uuid := gen_random_uuid();
begin
  insert into runs (id, user_id, started_at, distance_m, duration_s, source, metadata)
  values (v, pg_temp.runner(p_runner), now() - p_age, 5000, 1800, 'app', '{"activity_type":"run"}');
  return v;
end $$;

-- A run on course n that got no time.
create function pg_temp.attempt(n integer, p_runner integer, p_outcome text, p_k integer, p_progress integer,
                                p_age interval default interval '2 days')
returns void language sql as $$
  insert into park_course_attempts
    (run_id, user_id, park_course_id, outcome, progress_m, course_m, missed_checkpoint, checkpoint_count, matcher_version)
  values (pg_temp.run(p_runner, p_age), pg_temp.runner(p_runner), pg_temp.c(n), p_outcome, p_progress, 1000,
          p_k::smallint, 4, 4);
$$;

-- A run on course n that was timed.
create function pg_temp.effort(n integer, p_runner integer, p_age interval default interval '2 days')
returns void language plpgsql as $$
declare v uuid := pg_temp.run(p_runner, p_age);
begin
  insert into global_segment_efforts (global_segment_id, run_id, user_id, time_seconds, started_at)
  values (('a8a80000-0000-0000-0000-0000000000d' || n)::uuid, v, pg_temp.runner(p_runner), 1500,
          now() - p_age + interval '1 minute');
end $$;

-- 1: closes. 10 runs: 6 runners missed checkpoint 3, 2 stopped short, 2 timed.
select pg_temp.course(1, 'pcac-missed');
select pg_temp.attempt(1, r, 'skipped_checkpoint', 3, 500) from generate_series(1, 6) r;
select pg_temp.attempt(1, 7, 'stopped_short', null, 300);
select pg_temp.attempt(1, 8, 'stopped_short', null, 200);
select pg_temp.effort(1, 9);
select pg_temp.effort(1, 10);

-- 2: too few. 9 runs, every one a missed checkpoint, 9 runners.
select pg_temp.course(2, 'pcac-few');
select pg_temp.attempt(2, r, 'skipped_checkpoint', 2, 400) from generate_series(1, 9) r;

-- 3: too few runners. 10 runs, 8 missed checkpoint 2 but from 4 runners.
select pg_temp.course(3, 'pcac-same-people');
select pg_temp.attempt(3, ((r - 1) % 4) + 1, 'skipped_checkpoint', 2, 400) from generate_series(1, 8) r;
select pg_temp.effort(3, 11);
select pg_temp.effort(3, 12);

-- 4: runner-side outcomes. 10 runs from 10 runners: 7 stopped short at the
-- same place, 3 GPS gaps at the finish.
select pg_temp.course(4, 'pcac-runner-side');
select pg_temp.attempt(4, r, 'stopped_short', null, 100) from generate_series(1, 7) r;
select pg_temp.attempt(4, r, 'gps_gap', null, 1000) from generate_series(8, 10) r;

-- 5: evidence from before an admin reopen. 10 runners missed checkpoint 1
-- three days ago; an admin closes and reopens the course below.
select pg_temp.course(5, 'pcac-reopened');
select pg_temp.attempt(5, r, 'skipped_checkpoint', 1, 100, interval '3 days') from generate_series(1, 10) r;

-- 6: closes at exactly half. 10 runs: 5 runners went off course 40-50 % of
-- the way along, 5 timed.
select pg_temp.course(6, 'pcac-off-course');
select pg_temp.attempt(6, r, 'off_course', null, 450 + r) from generate_series(1, 5) r;
select pg_temp.effort(6, r) from generate_series(6, 10) r;

-- 7: old evidence. 10 runners missed checkpoint 2, 100 days ago.
select pg_temp.course(7, 'pcac-old');
select pg_temp.attempt(7, r, 'skipped_checkpoint', 2, 400, interval '100 days') from generate_series(1, 10) r;

-- 8: the newest 50 runs only. 50 timed runs in the last few days; behind
-- them, 60 runs by 12 runners went the wrong way a month ago, which would be
-- most of the 110 if every run in the window counted.
select pg_temp.course(8, 'pcac-busy');
select pg_temp.effort(8, ((r - 1) % 12) + 1, interval '1 hour' * r) from generate_series(1, 50) r;
select pg_temp.attempt(8, ((r - 1) % 12) + 1, 'wrong_direction', null, 0, interval '30 days' + interval '1 hour' * r)
  from generate_series(1, 60) r;

-- 9: the wrong way round. 10 runners, 7 wrong way, 3 timed.
select pg_temp.course(9, 'pcac-reversed');
select pg_temp.attempt(9, r, 'wrong_direction', null, 0) from generate_series(1, 7) r;
select pg_temp.effort(9, r) from generate_series(8, 10) r;

-- The admin closes and reopens course 5, so its runs predate the reopen.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"a8000000-0000-0000-0000-0000000000ad","role":"authenticated"}';
select admin_set_park_course_status(pg_temp.c(5), 'closed', 'Checking a fallen tree.');
select admin_set_park_course_status(pg_temp.c(5), 'open', null);
reset role;
set local "request.jwt.claims" = '{}';

create temp table pcac_before as
select (select count(*) from park_course_attempts a where a.park_course_id in (select id from park_courses where slug like 'pcac-%')) as attempts,
       (select count(*) from global_segment_efforts e where e.global_segment_id in (select global_segment_id from park_courses where slug like 'pcac-%')) as efforts;

-- ── who may run it ─────────────────────────────────────────────────────────

set local role authenticated;
select throws_ok(
  $$ select * from private.close_park_courses_failing_runs(true) $$,
  '42501', null, 'a signed-in account cannot run the sweep');
reset role;
set local role anon;
select throws_ok(
  $$ select * from private.close_park_courses_failing_runs(true) $$,
  '42501', null, 'anon cannot run the sweep');
reset role;
select ok(
  has_function_privilege('service_role', 'private.close_park_courses_failing_runs(boolean, timestamptz)', 'execute'),
  'the service role may run the sweep');

-- ── the flag ───────────────────────────────────────────────────────────────

select is(
  (select f.enabled from private.feature_flags f where f.name = 'park_course_attempt_closures'),
  false, 'the flag is seeded off');

create temp table pcac_off as select * from private.close_park_courses_failing_runs();
-- refusal: the flag is off, so the sweep returns no course though course 1 qualifies (the dry run below lists it)
select is((select count(*)::int from pcac_off), 0, 'with the flag off the sweep returns nothing');
select is((select status from park_courses where id = pg_temp.c(1)), 'open',
  'with the flag off the sweep closes nothing');

-- ── a dry run ──────────────────────────────────────────────────────────────

create temp table pcac_dry as select * from private.close_park_courses_failing_runs(true);
select set_eq(
  $$ select park_course_id from pcac_dry $$,
  array[pg_temp.c(1), pg_temp.c(6), pg_temp.c(9)],
  'a dry run lists the courses whose runs fail the same way, with the flag off');
select ok((select bool_and(not closed) from pcac_dry), 'a dry run says it closed nothing');
select is((select status from park_courses where id = pg_temp.c(1)), 'open', 'a dry run leaves the course open');
select is(
  (select row(outcome, missed_checkpoint, tries, signature_tries, signature_runners)::text
     from pcac_dry where park_course_id = pg_temp.c(1)),
  row('skipped_checkpoint', 3::smallint, 10, 6, 6)::text,
  'the dry run names the failure and the evidence behind it');

-- ── the sweep ──────────────────────────────────────────────────────────────

update private.feature_flags set enabled = true where name = 'park_course_attempt_closures';

create temp table pcac_on as select * from private.close_park_courses_failing_runs();
select set_eq(
  $$ select park_course_id from pcac_on where closed $$,
  array[pg_temp.c(1), pg_temp.c(6), pg_temp.c(9)],
  'with the flag on the sweep closes those courses');

select is(
  (select row(status, status_note)::text from park_courses where id = pg_temp.c(1)),
  row('closed', 'Closed automatically: most recent runs on this course missed checkpoint 3. We are checking the course.')::text,
  'a missed checkpoint closes the course with a plain note naming it');
select is(
  (select status_note from park_courses where id = pg_temp.c(6)),
  'Closed automatically: most recent runs on this course left it between 40% and 50% of the way along. We are checking the course.',
  'leaving the course in one tenth of its length, by exactly half the runs, closes it');
select is(
  (select status_note from park_courses where id = pg_temp.c(9)),
  'Closed automatically: most recent runs on this course went the opposite way round to it. We are checking the course.',
  'runs going the wrong way round close the course');
select isnt(
  (select status_checked_at from park_courses where id = pg_temp.c(1)), null,
  'the closure stamps when the status was checked');

select is((select status from park_courses where id = pg_temp.c(2)), 'open', 'fewer than ten runs close nothing');
select is((select status from park_courses where id = pg_temp.c(3)), 'open',
  'one failure from fewer than five runners closes nothing');
select is((select status from park_courses where id = pg_temp.c(4)), 'open',
  'stopped short and GPS gaps are never a course failure');
select is((select status from park_courses where id = pg_temp.c(5)), 'open',
  'runs from before an admin reopen close nothing');
select is((select status from park_courses where id = pg_temp.c(7)), 'open', 'runs older than 90 days close nothing');
select is((select status from park_courses where id = pg_temp.c(8)), 'open',
  'only the newest 50 runs count, so older failures behind them close nothing');

-- ── what a closure leaves ──────────────────────────────────────────────────

select is(
  (select row(action, actor_id, status_before, note, reports_resolved)::text
     from park_course_status_actions where park_course_id = pg_temp.c(1)),
  row('close', null::uuid, 'open',
      'Closed automatically: most recent runs on this course missed checkpoint 3. We are checking the course.', 0)::text,
  'the closure is logged as a close by no person, with its note');
select is(
  (select row(reporter_id, reason, status, signed_out, notes)::text
     from reports where target_kind = 'park_course' and target_id = pg_temp.c(1)),
  row(null::uuid, 'other', 'pending', false,
      'Closed automatically: most recent runs on this course missed checkpoint 3. We are checking the course.')::text,
  'the closure files a pending report so the course is in the admin queue');
select is(
  (select count(*)::int from notifications
    where user_id = 'a8000000-0000-0000-0000-0000000000ad' and kind = 'park_course_report'),
  3, 'every app admin gets a notice for each course closed');

select is(
  (select count(*) from park_course_attempts a
    where a.park_course_id in (select id from park_courses where slug like 'pcac-%')),
  (select attempts from pcac_before),
  'no attempt is deleted');
select is(
  (select count(*) from global_segment_efforts e
    where e.global_segment_id in (select global_segment_id from park_courses where slug like 'pcac-%')),
  (select efforts from pcac_before),
  'no effort is deleted');

-- ── idempotent ─────────────────────────────────────────────────────────────

create temp table pcac_again as select * from private.close_park_courses_failing_runs();
-- refusal: every qualifying course is already closed, so a second pass has nothing to close
select is((select count(*)::int from pcac_again), 0, 'a second pass closes nothing new');
select is(
  (select count(*)::int from park_course_status_actions
    where park_course_id in (select id from park_courses where slug like 'pcac-%')),
  5, 'a second pass logs nothing new (three closures, the admin''s close and reopen)');
select is(
  (select count(*)::int from reports where target_kind = 'park_course'
      and target_id in (select id from park_courses where slug like 'pcac-%')),
  3, 'a second pass files no new report');

-- ── after a closure ────────────────────────────────────────────────────────

select is(
  (select count(*)::int from park_course_attempts where park_course_id = pg_temp.c(1)),
  8, 'the closed course keeps every attempt that closed it');

-- An admin reopens an automatic closure, which resets the evidence.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"a8000000-0000-0000-0000-0000000000ad","role":"authenticated"}';
select admin_set_park_course_status(pg_temp.c(1), 'open', null);
reset role;
set local "request.jwt.claims" = '{}';
select is((select row(status, status_note)::text from park_courses where id = pg_temp.c(1)),
  row('open', null::text)::text, 'an admin can reopen a course the sweep closed, which clears the note');
select is(
  (select row(action, actor_id)::text from park_course_status_actions
    where park_course_id = pg_temp.c(1) order by created_at desc, id desc limit 1),
  row('reopen', 'a8000000-0000-0000-0000-0000000000ad'::uuid)::text,
  'the admin''s reopen is logged after the automatic close');

create temp table pcac_reopened as select * from private.close_park_courses_failing_runs();
select is((select status from park_courses where id = pg_temp.c(1)), 'open',
  'after the reopen the same runs do not close the course again');

-- New failures after the reopen do.
select pg_temp.attempt(1, r, 'skipped_checkpoint', 3, 500, interval '-1 minute') from generate_series(1, 10) r;
select is(
  (select count(*)::int from private.close_park_courses_failing_runs(true) where park_course_id = pg_temp.c(1)),
  0, 'runs in the future of the sweep''s clock do not count');
select is(
  (select count(*)::int from private.close_park_courses_failing_runs(true, now() + interval '1 hour')
    where park_course_id = pg_temp.c(1)),
  1, 'new failing runs after the reopen are evidence again');

-- A closed park's courses are left alone.
update parks set is_active = false where id = 'a8a80000-0000-0000-0000-0000000000e1';
select is(
  (select count(*)::int from private.close_park_courses_failing_runs(true, now() + interval '1 hour')),
  0, 'a course in a park that is not active is never considered');
update parks set is_active = true where id = 'a8a80000-0000-0000-0000-0000000000e1';

select is(
  (select count(*)::int from cron.job where jobname = 'close-park-courses-failing-runs' and schedule = '37 5 * * *'),
  1, 'the sweep is scheduled daily');

select * from finish();
rollback;

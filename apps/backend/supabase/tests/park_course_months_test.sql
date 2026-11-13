-- Monthly park course boards (issue #1343, decisions § 2426 / § 2511;
-- migration 20271226001343).
--
-- A month is the calendar month of the effort's started_at in the PARK's
-- timezone. The fixture park is in America/New_York, and 2026's DST changes
-- are 8 March (02:00 EST -> 03:00 EDT) and 1 November (02:00 EDT -> 01:00
-- EST), so the second one falls on a 1st:
--   A  300  2026-11-01 03:30Z  = 31 Oct 23:30 EDT        -> October
--   A  330  2026-10-15 14:00Z  = 15 Oct 10:00 EDT        -> October
--   A  340  2026-10-15 20:00Z  = 15 Oct 16:00, same day  -> October
--   A  290  2026-11-01 04:30Z  =  1 Nov 00:30 EDT        -> November
--   B  400  2026-03-01 04:59Z  = 28 Feb 23:59 EST        -> February
--   B  390  2026-03-08 07:30Z  =  8 Mar 03:30 EDT        -> March
--   B  380  2026-04-01 03:30Z  = 31 Mar 23:30 EDT        -> March
--   B  310  2026-10-20 12:00Z                            -> October
--   B  305  2026-11-01 06:30Z  =  1 Nov 01:30 EST (the repeated hour) -> November
--   D  320  2026-10-10 12:00Z                            -> October
--   A on the second course only in September.
-- C has no effort and reads every board.

begin;

select plan(27);

-- ── Fixture ──
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-00000000a601', 'authenticated', 'authenticated', 'month-a@pcm.local', '', now(), now()),
  ('00000000-0000-0000-0000-00000000b602', 'authenticated', 'authenticated', 'month-b@pcm.local', '', now(), now()),
  ('00000000-0000-0000-0000-00000000c603', 'authenticated', 'authenticated', 'month-c@pcm.local', '', now(), now()),
  ('00000000-0000-0000-0000-00000000d604', 'authenticated', 'authenticated', 'month-d@pcm.local', '', now(), now());

insert into user_profiles (id, display_name)
values
  ('00000000-0000-0000-0000-00000000a601', 'Month A'),
  ('00000000-0000-0000-0000-00000000b602', 'Month B'),
  ('00000000-0000-0000-0000-00000000c603', 'Month C'),
  ('00000000-0000-0000-0000-00000000d604', 'Month D');

select tests.confirm_consent();

insert into global_segments (id, name, waypoints, distance_m, is_active)
values
  ('a6a6a6a6-0000-0000-0000-0000000000e1', 'Month Loop',
   '[{"lat":37.0,"lng":-77.0},{"lat":37.004,"lng":-77.0}]', 450, true),
  ('a6a6a6a6-0000-0000-0000-0000000000e2', 'Quiet Loop',
   '[{"lat":37.01,"lng":-77.0},{"lat":37.014,"lng":-77.0}]', 450, true);

insert into parks (id, slug, name, agency, region_code, country_code, timezone, is_active)
values ('a6a6a6a6-0000-0000-0000-0000000000a1', 'month-state-park', 'Month State Park',
        'state', 'US-VA', 'US', 'America/New_York', true);

insert into park_courses (id, park_id, global_segment_id, slug, course_shape, geometry_source)
values
  ('a6a6a6a6-0000-0000-0000-0000000000c1', 'a6a6a6a6-0000-0000-0000-0000000000a1',
   'a6a6a6a6-0000-0000-0000-0000000000e1', 'month-loop', 'loop', 'osm'),
  ('a6a6a6a6-0000-0000-0000-0000000000c2', 'a6a6a6a6-0000-0000-0000-0000000000a1',
   'a6a6a6a6-0000-0000-0000-0000000000e2', 'quiet-loop', 'loop', 'osm');

create temp table pcm_efforts (run_id uuid, user_id uuid, seg uuid, t integer, at timestamptz);
insert into pcm_efforts values
  ('b6b6b6b6-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a601', 'a6a6a6a6-0000-0000-0000-0000000000e1', 300, '2026-11-01T03:30:00Z'),
  ('b6b6b6b6-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-00000000a601', 'a6a6a6a6-0000-0000-0000-0000000000e1', 330, '2026-10-15T14:00:00Z'),
  ('b6b6b6b6-0000-0000-0000-0000000000a3', '00000000-0000-0000-0000-00000000a601', 'a6a6a6a6-0000-0000-0000-0000000000e1', 340, '2026-10-15T20:00:00Z'),
  ('b6b6b6b6-0000-0000-0000-0000000000a4', '00000000-0000-0000-0000-00000000a601', 'a6a6a6a6-0000-0000-0000-0000000000e1', 290, '2026-11-01T04:30:00Z'),
  ('b6b6b6b6-0000-0000-0000-0000000000a5', '00000000-0000-0000-0000-00000000a601', 'a6a6a6a6-0000-0000-0000-0000000000e2', 280, '2026-09-10T12:00:00Z'),
  ('b6b6b6b6-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-00000000b602', 'a6a6a6a6-0000-0000-0000-0000000000e1', 400, '2026-03-01T04:59:00Z'),
  ('b6b6b6b6-0000-0000-0000-0000000000b2', '00000000-0000-0000-0000-00000000b602', 'a6a6a6a6-0000-0000-0000-0000000000e1', 390, '2026-03-08T07:30:00Z'),
  ('b6b6b6b6-0000-0000-0000-0000000000b3', '00000000-0000-0000-0000-00000000b602', 'a6a6a6a6-0000-0000-0000-0000000000e1', 380, '2026-04-01T03:30:00Z'),
  ('b6b6b6b6-0000-0000-0000-0000000000b4', '00000000-0000-0000-0000-00000000b602', 'a6a6a6a6-0000-0000-0000-0000000000e1', 310, '2026-10-20T12:00:00Z'),
  ('b6b6b6b6-0000-0000-0000-0000000000b5', '00000000-0000-0000-0000-00000000b602', 'a6a6a6a6-0000-0000-0000-0000000000e1', 305, '2026-11-01T06:30:00Z'),
  ('b6b6b6b6-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-00000000d604', 'a6a6a6a6-0000-0000-0000-0000000000e1', 320, '2026-10-10T12:00:00Z');

insert into runs (id, user_id, started_at, distance_m, duration_s, source, metadata, is_public)
select run_id, user_id, at, 5000, 1200, 'app', '{"activity_type":"run"}'::jsonb, true
from pcm_efforts;

insert into global_segment_efforts (global_segment_id, run_id, user_id, time_seconds, started_at)
select seg, run_id, user_id, t, at from pcm_efforts;

create function pg_temp.pcm_board(p_season integer, p_month integer)
returns table (who text, t integer)
language sql
as $$
  select user_id::text, time_seconds
  from global_segment_leaderboard('a6a6a6a6-0000-0000-0000-0000000000e1'::uuid,
                                  p_season => p_season, p_month => p_month)
$$;

-- ── Boards, read by C ──
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000c603"}';

-- 1. 23:30 on 31 October in New York (03:30 UTC on 1 November) is October.
select results_eq(
  $$ select * from pg_temp.pcm_board(2026, 10) $$,
  $$ values ('00000000-0000-0000-0000-00000000a601', 300),
            ('00000000-0000-0000-0000-00000000b602', 310),
            ('00000000-0000-0000-0000-00000000d604', 320) $$,
  'October board: an effort at 23:30 local on the 31st counts in October, not in UTC''s November'
);

-- 2. November opens at 00:30 local on the 1st, and the repeated 01:30 hour
--    after DST ends (06:30 UTC) is still November.
select results_eq(
  $$ select * from pg_temp.pcm_board(2026, 11) $$,
  $$ values ('00000000-0000-0000-0000-00000000a601', 290),
            ('00000000-0000-0000-0000-00000000b602', 305) $$,
  'November board: the first local minutes and the repeated fall-back hour of the 1st count'
);

-- 3. 23:59 EST on 28 February (04:59 UTC on 1 March) is February.
select results_eq(
  $$ select * from pg_temp.pcm_board(2026, 2) $$,
  $$ values ('00000000-0000-0000-0000-00000000b602', 400) $$,
  'February board: the last local minute of February is February'
);

-- 4. March spans the spring-forward day and ends at 23:30 EDT on the 31st
--    (03:30 UTC on 1 April); B's best of the two is the board time.
select results_eq(
  $$ select * from pg_temp.pcm_board(2026, 3) $$,
  $$ values ('00000000-0000-0000-0000-00000000b602', 380) $$,
  'March board: efforts after the DST change and late on the 31st local both count'
);

-- 5. A month board is a narrowing of the season board: no month misses one.
select is(
  (select count(*)::int from pg_temp.pcm_board(2026, 4)),
  0,
  'April board is empty: the 31 March 23:30 local effort is not April'
);

-- 6. Completions in October count distinct local days: A ran twice on the
--    15th and once on the 31st.
select results_eq(
  $$ select user_id::text, completions from global_segment_completions(
       'a6a6a6a6-0000-0000-0000-0000000000e1'::uuid, p_season => 2026, p_month => 10) $$,
  $$ values ('00000000-0000-0000-0000-00000000a601', 2),
            ('00000000-0000-0000-0000-00000000d604', 1),
            ('00000000-0000-0000-0000-00000000b602', 1) $$,
  'October completions count distinct local days, so two efforts on one day count once'
);

-- 7. March completions: two local days across the DST change.
select is(
  (select completions from global_segment_completions(
     'a6a6a6a6-0000-0000-0000-0000000000e1'::uuid, p_season => 2026, p_month => 3)
    where user_id = '00000000-0000-0000-0000-00000000b602'),
  2,
  'March completions count both local days'
);

-- ── Refusals ──

-- 8-10. The leaderboard refuses a month without a season, and outside 1-12.
select throws_ok(
  $$ select * from global_segment_leaderboard('a6a6a6a6-0000-0000-0000-0000000000e1'::uuid, p_month => 10) $$,
  '22023', null, 'leaderboard: p_month without p_season raises 22023');
select throws_ok(
  $$ select * from global_segment_leaderboard('a6a6a6a6-0000-0000-0000-0000000000e1'::uuid, p_season => 2026, p_month => 13) $$,
  '22023', null, 'leaderboard: p_month 13 raises 22023');
select throws_ok(
  $$ select * from global_segment_leaderboard('a6a6a6a6-0000-0000-0000-0000000000e1'::uuid, p_season => 2026, p_month => 0) $$,
  '22023', null, 'leaderboard: p_month 0 raises 22023');

-- 11-12. The completions board refuses the same.
select throws_ok(
  $$ select * from global_segment_completions('a6a6a6a6-0000-0000-0000-0000000000e1'::uuid, p_month => 10) $$,
  '22023', null, 'completions: p_month without p_season raises 22023');
select throws_ok(
  $$ select * from global_segment_completions('a6a6a6a6-0000-0000-0000-0000000000e1'::uuid, p_season => 2026, p_month => 13) $$,
  '22023', null, 'completions: p_month 13 raises 22023');

-- ── Older call shapes ──

-- 13. The five named arguments the segment pages pass.
select is(
  (select count(*)::int from global_segment_leaderboard(
     p_segment_id => 'a6a6a6a6-0000-0000-0000-0000000000e1'::uuid, p_gender => null,
     p_age_band => null, p_limit => 50, p_club_id => null)),
  3,
  'leaderboard: the five named arguments still resolve to the all-time board'
);

-- 14. Six positional arguments, the shape park_course_records() and
--     run_park_course_times use.
select results_eq(
  $$ select user_id::text, time_seconds from global_segment_leaderboard(
       'a6a6a6a6-0000-0000-0000-0000000000e1'::uuid, null, null, 50, null, 2026) $$,
  $$ values ('00000000-0000-0000-0000-00000000a601', 290),
            ('00000000-0000-0000-0000-00000000b602', 305),
            ('00000000-0000-0000-0000-00000000d604', 320) $$,
  'leaderboard: six positional arguments still give the season board'
);

-- 15. The positional (segment, season, limit) completions call keeps its
--     third argument as the limit, because p_month is trailing.
select is(
  (select count(*)::int from global_segment_completions(
     'a6a6a6a6-0000-0000-0000-0000000000e1'::uuid, 2026, 1)),
  1,
  'completions: a positional (segment, season, limit) call still reads its third argument as the limit'
);

-- 16. park_course_records() still resolves over the new signature.
select is(
  (select count(*)::int from park_course_records()
    where course_id = 'a6a6a6a6-0000-0000-0000-0000000000c1'),
  (case when extract(year from (now() at time zone 'America/New_York'))::int = 2026 then 1 else 0 end),
  'park_course_records() still resolves over the seven-argument leaderboard'
);

-- 17. park_month is the current month where the park is.
select is(
  (select park_month(p) from parks p where p.slug = 'month-state-park'),
  extract(month from (now() at time zone 'America/New_York'))::integer,
  'park_month is the current calendar month in the park timezone'
);

-- ── The run's month place (owner-only) ──

-- 18. A's 31 October run: October in the park, first that month, and not A's
--     season best (the November 290 is), so it has a month place and no
--     season place.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000a601"}';
select results_eq(
  $$ select season, season_rank, month, month_rank
       from run_park_course_times('b6b6b6b6-0000-0000-0000-0000000000a1'::uuid) $$,
  $$ values (2026, null::integer, 10, 1) $$,
  'run_park_course_times: the owner gets the park-local month and its place'
);

-- 19. B's 20 October run is second in October.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000b602"}';
select is(
  (select month_rank from run_park_course_times('b6b6b6b6-0000-0000-0000-0000000000b4'::uuid)),
  2,
  'run_park_course_times: month_rank is the place on that month''s board'
);

-- 20. Another runner asking about A's run gets nothing.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000c603"}';
select is_empty(
  $$ select 1 from run_park_course_times('b6b6b6b6-0000-0000-0000-0000000000a1'::uuid) $$,
  'run_park_course_times: month_rank is owner-only; another runner gets no rows'
);

-- ── Privacy, inherited ──

-- 21. Shadow-hidden: B's row stays on C's monthly board, unnamed.
reset role;
update user_profiles set shadow_hidden = true where id = '00000000-0000-0000-0000-00000000b602';
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000c603"}';
select is(
  (select display_name from global_segment_leaderboard(
     'a6a6a6a6-0000-0000-0000-0000000000e1'::uuid, p_season => 2026, p_month => 10)
    where user_id = '00000000-0000-0000-0000-00000000b602'),
  null,
  'monthly board masks a shadow-hidden runner''s name'
);

-- 22. ...and B still sees their own name on it.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000b602"}';
select is(
  (select display_name from global_segment_leaderboard(
     'a6a6a6a6-0000-0000-0000-0000000000e1'::uuid, p_season => 2026, p_month => 10)
    where user_id = '00000000-0000-0000-0000-00000000b602'),
  'Month B',
  'a shadow-hidden runner still sees their own name on the monthly board'
);
reset role;
update user_profiles set shadow_hidden = false where id = '00000000-0000-0000-0000-00000000b602';

-- 23-24. C blocks D: D leaves C's monthly fastest and completions boards.
insert into user_blocks (blocker_id, blocked_id)
values ('00000000-0000-0000-0000-00000000c603', '00000000-0000-0000-0000-00000000d604');
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000c603"}';
select is_empty(
  $$ select 1 from pg_temp.pcm_board(2026, 10) where who = '00000000-0000-0000-0000-00000000d604' $$,
  'a blocked runner is hidden from the monthly fastest board'
);
select is_empty(
  $$ select 1 from global_segment_completions('a6a6a6a6-0000-0000-0000-0000000000e1'::uuid,
       p_season => 2026, p_month => 10)
     where user_id = '00000000-0000-0000-0000-00000000d604' $$,
  'a blocked runner is hidden from the monthly completions board'
);

-- 25. A's 31 October run goes private: C's October board falls back to A's
--     next visible effort that month.
reset role;
update runs set is_public = false where id = 'b6b6b6b6-0000-0000-0000-0000000000a1';
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000c603"}';
select is(
  (select t from pg_temp.pcm_board(2026, 10) where who = '00000000-0000-0000-0000-00000000a601'),
  330,
  'an effort on a private run is not on another reader''s monthly board'
);

-- 26-27. Both monthly boards need an account.
set local role anon;
set local "request.jwt.claims" = '{}';
select throws_ok(
  $$ select * from global_segment_leaderboard('a6a6a6a6-0000-0000-0000-0000000000e1'::uuid, p_season => 2026, p_month => 10) $$,
  '42501', null, 'anon cannot read the monthly fastest board');
select throws_ok(
  $$ select * from global_segment_completions('a6a6a6a6-0000-0000-0000-0000000000e1'::uuid, p_season => 2026, p_month => 10) $$,
  '42501', null, 'anon cannot read the monthly completions board');

select * from finish();
rollback;

-- Park courses (migration 20271115002383, issue #1313, decisions § 2383):
-- the parks / park_courses catalogue, the season argument on
-- global_segment_leaderboard and the most-completions board.
--
-- Seasons are calendar years in the PARK's timezone. The boundary assertion
-- puts an effort at 03:00 UTC on 1 January 2027, which is 22:00 on
-- 31 December 2026 in New York, so it must count for 2026 and not 2027.

begin;

select plan(19);

-- ── Fixture ──
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-00000000a501', 'authenticated', 'authenticated',
   'park-a@pc.local', '', now(), now()),
  ('00000000-0000-0000-0000-00000000b502', 'authenticated', 'authenticated',
   'park-b@pc.local', '', now(), now()),
  ('00000000-0000-0000-0000-00000000c503', 'authenticated', 'authenticated',
   'park-c@pc.local', '', now(), now());

insert into user_profiles (id, display_name)
values
  ('00000000-0000-0000-0000-00000000a501', 'Park A'),
  ('00000000-0000-0000-0000-00000000b502', 'Park B'),
  ('00000000-0000-0000-0000-00000000c503', 'Park C');

select tests.confirm_consent();

insert into global_segments (id, name, waypoints, distance_m, is_active)
values
  ('a5a5a5a5-0000-0000-0000-0000000000d1', 'Test Park Loop',
   '[{"lat":37.0,"lng":-77.0},{"lat":37.004,"lng":-77.0}]', 450, true),
  ('a5a5a5a5-0000-0000-0000-0000000000d2', 'Hidden Park Loop',
   '[{"lat":37.1,"lng":-77.0},{"lat":37.104,"lng":-77.0}]', 450, true);

insert into parks (id, slug, name, agency, region_code, country_code, timezone, is_active)
values
  ('a5a5a5a5-0000-0000-0000-0000000000a1', 'test-state-park', 'Test State Park',
   'state', 'US-VA', 'US', 'America/New_York', true),
  ('a5a5a5a5-0000-0000-0000-0000000000a2', 'pulled-park', 'Pulled Park',
   'nps', 'US-VA', 'US', 'America/New_York', false);

insert into park_courses (id, park_id, global_segment_id, slug, course_shape, geometry_source, checkpoints)
values
  ('a5a5a5a5-0000-0000-0000-0000000000b1', 'a5a5a5a5-0000-0000-0000-0000000000a1',
   'a5a5a5a5-0000-0000-0000-0000000000d1', 'loop', 'loop', 'osm',
   '[{"lat":37.002,"lng":-77.0}]'),
  ('a5a5a5a5-0000-0000-0000-0000000000b2', 'a5a5a5a5-0000-0000-0000-0000000000a2',
   'a5a5a5a5-0000-0000-0000-0000000000d2', 'loop', 'loop', 'nps', '[]');

-- A: 2025 at 300 s; two efforts on one New York day in 2026 (330, 320); and
-- the boundary effort at 03:00 UTC 2027-01-01 = 2026-12-31 22:00 local (310).
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000a501"}';
insert into runs (id, user_id, started_at, distance_m, duration_s, source, metadata, is_public)
values
  ('b5b5b5b5-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a501',
   '2025-06-01T12:00:00Z', 5000, 1200, 'app', '{"activity_type":"run"}'::jsonb, true),
  ('b5b5b5b5-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-00000000a501',
   '2026-06-01T12:00:00Z', 5000, 1200, 'app', '{"activity_type":"run"}'::jsonb, true),
  ('b5b5b5b5-0000-0000-0000-0000000000a3', '00000000-0000-0000-0000-00000000a501',
   '2026-06-01T20:00:00Z', 5000, 1200, 'app', '{"activity_type":"run"}'::jsonb, true),
  ('b5b5b5b5-0000-0000-0000-0000000000a4', '00000000-0000-0000-0000-00000000a501',
   '2027-01-01T03:00:00Z', 5000, 1200, 'app', '{"activity_type":"run"}'::jsonb, true);
insert into global_segment_efforts (global_segment_id, run_id, user_id, time_seconds, started_at)
values
  ('a5a5a5a5-0000-0000-0000-0000000000d1', 'b5b5b5b5-0000-0000-0000-0000000000a1',
   '00000000-0000-0000-0000-00000000a501', 300, '2025-06-01T12:00:00Z'),
  ('a5a5a5a5-0000-0000-0000-0000000000d1', 'b5b5b5b5-0000-0000-0000-0000000000a2',
   '00000000-0000-0000-0000-00000000a501', 330, '2026-06-01T12:00:00Z'),
  ('a5a5a5a5-0000-0000-0000-0000000000d1', 'b5b5b5b5-0000-0000-0000-0000000000a3',
   '00000000-0000-0000-0000-00000000a501', 320, '2026-06-01T20:00:00Z'),
  ('a5a5a5a5-0000-0000-0000-0000000000d1', 'b5b5b5b5-0000-0000-0000-0000000000a4',
   '00000000-0000-0000-0000-00000000a501', 310, '2027-01-01T03:00:00Z');

-- B: one 2026 effort at 315.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000b502"}';
insert into runs (id, user_id, started_at, distance_m, duration_s, source, metadata, is_public)
values ('b5b5b5b5-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-00000000b502',
        '2026-03-01T15:00:00Z', 5000, 1200, 'app', '{"activity_type":"run"}'::jsonb, true);
insert into global_segment_efforts (global_segment_id, run_id, user_id, time_seconds, started_at)
values ('a5a5a5a5-0000-0000-0000-0000000000d1', 'b5b5b5b5-0000-0000-0000-0000000000b1',
        '00000000-0000-0000-0000-00000000b502', 315, '2026-03-01T15:00:00Z');

-- ── Catalogue reads ──
set local role anon;
set local "request.jwt.claims" = '{}';

-- 1. Positive control for (2): an active park and its course are readable logged out.
select is(
  (select count(*)::int from park_courses pc join parks p on p.id = pc.park_id
    where p.slug = 'test-state-park'),
  1,
  'anon reads an active park and its course'
);

-- 2. A pulled park and its courses leave the catalogue.
select is_empty(
  $$ select 1 from parks where slug = 'pulled-park'
     union all
     select 1 from park_courses where id = 'a5a5a5a5-0000-0000-0000-0000000000b2' $$,
  'an inactive park and its courses are hidden from readers'
);

-- 3. The current season is the year where the park is.
select is(
  (select park_season(p) from parks p where p.slug = 'test-state-park'),
  extract(year from (now() at time zone 'America/New_York'))::integer,
  'park_season is the current calendar year in the park timezone'
);

-- 4. The completions board needs an account; anon holds no EXECUTE.
select throws_ok(
  $$ select * from global_segment_completions('a5a5a5a5-0000-0000-0000-0000000000d1'::uuid) $$,
  '42501',
  null,
  'anon cannot call global_segment_completions'
);

-- ── Writes ──
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000c503"}';

-- 5. A non-admin cannot add a park.
select throws_ok(
  $$ insert into parks (slug, name, agency, region_code, country_code, timezone)
     values ('rogue-park', 'Rogue', 'state', 'US-VA', 'US', 'America/New_York') $$,
  '42501',
  null,
  'a non-admin cannot insert a park'
);

-- 6. A non-admin cannot repoint a course; the update matches no row it may edit.
update park_courses set status = 'closed' where id = 'a5a5a5a5-0000-0000-0000-0000000000b1';
reset role;
select is(
  (select status from park_courses where id = 'a5a5a5a5-0000-0000-0000-0000000000b1'),
  'open',
  'a non-admin update leaves the course status unchanged'
);

-- 7. The timezone must be an IANA zone.
select throws_ok(
  $$ insert into parks (slug, name, agency, region_code, country_code, timezone)
     values ('bad-tz', 'Bad TZ', 'state', 'US-VA', 'US', 'Mars/Olympus') $$,
  '22023',
  null,
  'a park timezone outside pg_timezone_names is refused'
);

-- 8. The agency vocabulary is closed.
select throws_ok(
  $$ insert into parks (slug, name, agency, region_code, country_code, timezone)
     values ('bad-agency', 'Bad Agency', 'federal', 'US-VA', 'US', 'America/New_York') $$,
  '23514',
  null,
  'an agency outside the vocabulary is refused'
);

-- 9. Checkpoints must be a JSON array.
select throws_ok(
  $$ update park_courses set checkpoints = '{"lat":1}'::jsonb
     where id = 'a5a5a5a5-0000-0000-0000-0000000000b1' $$,
  '23514',
  null,
  'checkpoints that are not an array are refused'
);

-- ── Season time board, read by C (no efforts, no blocks) ──
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000c503"}';

-- 10. All time: A's fastest ever (300, in 2025) leads.
select results_eq(
  $$ select user_id::text, time_seconds from global_segment_leaderboard(
       'a5a5a5a5-0000-0000-0000-0000000000d1'::uuid) $$,
  $$ values ('00000000-0000-0000-0000-00000000a501', 300),
            ('00000000-0000-0000-0000-00000000b502', 315) $$,
  'all-time board: each athlete''s fastest effort ever'
);

-- 11. 2026 in New York: A's best is the 310 run at 22:00 on 31 December local,
--     which UTC would have filed under 2027.
select results_eq(
  $$ select user_id::text, time_seconds from global_segment_leaderboard(
       'a5a5a5a5-0000-0000-0000-0000000000d1'::uuid, p_season => 2026) $$,
  $$ values ('00000000-0000-0000-0000-00000000a501', 310),
            ('00000000-0000-0000-0000-00000000b502', 315) $$,
  'season board counts the year in the park timezone, not UTC'
);

-- 12. 2027 holds nothing yet: the boundary effort belongs to 2026.
select is(
  (select count(*)::int from global_segment_leaderboard(
     'a5a5a5a5-0000-0000-0000-0000000000d1'::uuid, p_season => 2027)),
  0,
  'an effort before local midnight on 1 January is not in the new season'
);

-- 13. The five-argument call shape still resolves.
select is(
  (select count(*)::int from global_segment_leaderboard(
     p_segment_id => 'a5a5a5a5-0000-0000-0000-0000000000d1'::uuid, p_gender => null,
     p_age_band => null, p_limit => 50, p_club_id => null)),
  2,
  'a caller passing the old five named arguments still gets the board'
);

-- 14. An absurd season is refused.
select throws_ok(
  $$ select * from global_segment_leaderboard(
       'a5a5a5a5-0000-0000-0000-0000000000d1'::uuid, p_season => 99) $$,
  '22023',
  null,
  'p_season outside 2000..2200 raises 22023'
);

-- ── Completions board ──

-- 15. 2026: A ran on two local days (two efforts on 1 June count once, plus
--     31 December), B on one.
select results_eq(
  $$ select user_id::text, completions from global_segment_completions(
       'a5a5a5a5-0000-0000-0000-0000000000d1'::uuid, 2026) $$,
  $$ values ('00000000-0000-0000-0000-00000000a501', 2),
            ('00000000-0000-0000-0000-00000000b502', 1) $$,
  'completions count distinct local days, so laps on one day count once'
);

-- 16. All time: A's 2025 day joins.
select results_eq(
  $$ select user_id::text, completions from global_segment_completions(
       'a5a5a5a5-0000-0000-0000-0000000000d1'::uuid) $$,
  $$ values ('00000000-0000-0000-0000-00000000a501', 3),
            ('00000000-0000-0000-0000-00000000b502', 1) $$,
  'all-time completions span every season'
);

-- 17. Positive control for (18): before any block, B is on C's completions board.
select isnt_empty(
  $$ select 1 from global_segment_completions('a5a5a5a5-0000-0000-0000-0000000000d1'::uuid)
     where user_id = '00000000-0000-0000-0000-00000000b502' $$,
  'B appears on the completions board before the block'
);

-- 18. After C blocks B, B leaves C's completions board.
insert into user_blocks (blocker_id, blocked_id)
values ('00000000-0000-0000-0000-00000000c503', '00000000-0000-0000-0000-00000000b502');
select is_empty(
  $$ select 1 from global_segment_completions('a5a5a5a5-0000-0000-0000-0000000000d1'::uuid)
     where user_id = '00000000-0000-0000-0000-00000000b502' $$,
  'a blocked athlete is hidden from the completions board'
);

-- 19. A private run's effort is not counted for another reader.
reset role;
update runs set is_public = false where id = 'b5b5b5b5-0000-0000-0000-0000000000a1';
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000c503"}';
select is(
  (select completions from global_segment_completions(
     'a5a5a5a5-0000-0000-0000-0000000000d1'::uuid)
    where user_id = '00000000-0000-0000-0000-00000000a501'),
  2,
  'an effort on a private run is not counted on another reader''s board'
);

select * from finish();
rollback;

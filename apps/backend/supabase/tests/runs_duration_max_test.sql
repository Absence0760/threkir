-- runs_duration_s_max_check + private.run_duration_in_bound (migration
-- 20271112000020, decisions § 2359, issue #1300 § 5).
--
-- The issue's run: 2.00 km stored at 44,400,094 s (12,333 h 21 m 34 s), the
-- Hours box having held "12333". Written from the ordinary `authenticated`
-- seat, because a runner's own INSERT and UPDATE policies are all the write
-- needs.
--
-- The read-side half needs a row above the bound, which the constraint now
-- refuses; the suite drops it inside its own transaction (rolled back) to
-- plant one, which is exactly the state of a database where the constraint
-- was added NOT VALID over rows that predate it.

begin;

select plan(10);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values ('d0000000-0000-0000-0000-0000000d0001', 'authenticated', 'authenticated',
        'duration-max@spam.local', '', now(), now());

insert into user_profiles (id, display_name, preferred_unit)
values ('d0000000-0000-0000-0000-0000000d0001', 'Duration Max', 'km')
on conflict (id) do nothing;

select tests.confirm_consent();

select is(
  (select convalidated from pg_constraint
    where conname = 'runs_duration_s_max_check' and conrelid = 'runs'::regclass),
  false,
  'the bound ships NOT VALID; VALIDATE waits for the owner-reviewed repair'
);

set local role authenticated;
set local "request.jwt.claims" =
  '{"sub":"d0000000-0000-0000-0000-0000000d0001","role":"authenticated"}';

select lives_ok(
  $$ insert into runs (id, user_id, started_at, duration_s, distance_m, source,
                       activity_type)
     values ('d0000000-0000-0000-0000-0000000da001',
             'd0000000-0000-0000-0000-0000000d0001', now(), 864000, 386243, 'app',
             'run') $$,
  'a run of exactly ten days stores'
);

select throws_ok(
  $$ insert into runs (id, user_id, started_at, duration_s, distance_m, source,
                       activity_type)
     values ('d0000000-0000-0000-0000-0000000da002',
             'd0000000-0000-0000-0000-0000000d0001', now(), 44400094, 2000, 'app',
             'run') $$,
  '23514', null,
  'the issue #1300 run (12,333 h for 2 km) is refused'
);

select throws_ok(
  $$ update runs set duration_s = 864001
      where id = 'd0000000-0000-0000-0000-0000000da001' $$,
  '23514', null,
  'an edit cannot push a stored run past the bound'
);

reset role;

select ok(private.run_duration_in_bound(864000), 'ten days is in bound');
select ok(not private.run_duration_in_bound(864001), 'one second more is not');

-- ── the read side: a pre-constraint row cannot swamp a duration board ───────
alter table runs drop constraint runs_duration_s_max_check;

insert into runs (id, user_id, started_at, duration_s, distance_m, source,
                  activity_type, is_dnf)
values
  ('d0000000-0000-0000-0000-0000000da003', 'd0000000-0000-0000-0000-0000000d0001',
   '2026-06-05 08:00:00+00', 1800, 5000, 'app', 'run', false),
  ('d0000000-0000-0000-0000-0000000da004', 'd0000000-0000-0000-0000-0000000d0001',
   '2026-06-06 08:00:00+00', 44400094, 2000, 'app', 'run', false);

insert into challenges (id, creator_id, title, metric, scope, goal_value, starts_at, ends_at, is_public)
values ('eeeeeeee-eeee-eeee-eeee-eeee000d0001', 'd0000000-0000-0000-0000-0000000d0001',
        'Duration bound', 'duration', 'individual', 36000,
        '2026-06-01 00:00:00+00', '2026-06-30 00:00:00+00', true);

insert into challenge_participants (challenge_id, user_id)
values ('eeeeeeee-eeee-eeee-eeee-eeee000d0001', 'd0000000-0000-0000-0000-0000000d0001');

set local role authenticated;
set local "request.jwt.claims" =
  '{"sub":"d0000000-0000-0000-0000-0000000d0001","role":"authenticated"}';

select is(
  (select value::int from challenge_leaderboard('eeeeeeee-eeee-eeee-eeee-eeee000d0001', false)
    where user_id = 'd0000000-0000-0000-0000-0000000d0001'),
  1800,
  'the leaderboard sums the in-bound run and skips the 12,333-hour one'
);

select is(
  (select value::int from challenge_leaderboard('eeeeeeee-eeee-eeee-eeee-eeee000d0001', true)),
  1800,
  'the team board skips it too'
);

select recompute_challenge_completion(
  'eeeeeeee-eeee-eeee-eeee-eeee000d0001', 'd0000000-0000-0000-0000-0000000d0001');

select is(
  (select count(*)::int from challenge_badges
    where challenge_id = 'eeeeeeee-eeee-eeee-eeee-eeee000d0001'),
  0,
  'the out-of-bound row cannot carry its author over a 10 h goal'
);

reset role;

select is(
  (select count(*)::int from runs
    where user_id = 'd0000000-0000-0000-0000-0000000d0001' and duration_s > 864000),
  1,
  'the repair listing query finds the planted row'
);

select * from finish();

rollback;

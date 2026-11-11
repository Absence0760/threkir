-- The issue #1300 § 5 repair: private.cap_out_of_bound_run_durations, the
-- runs_keep_duration_repair trigger and the VALIDATE of
-- runs_duration_s_max_check (migrations 20271218000001-3, decisions § 2464).
--
-- The rows to repair sit above a constraint that now refuses them, so the
-- suite drops it inside its own transaction (rolled back) to plant them: the
-- state of a database that predates the VALIDATE.

begin;

select plan(19);

select is(
  (select convalidated from pg_constraint
    where conname = 'runs_duration_s_max_check' and conrelid = 'runs'::regclass),
  true,
  'runs_duration_s_max_check is validated'
);

select ok(not private.run_duration_in_bound(864000),
  'the cap itself is outside the read-side bound');
select ok(private.run_duration_in_bound(863999),
  'one second under it is inside');

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values ('d0000000-0000-0000-0000-0000000d0101', 'authenticated', 'authenticated',
        'duration-repair@spam.local', '', now(), now());

insert into user_profiles (id, display_name, preferred_unit)
values ('d0000000-0000-0000-0000-0000000d0101', 'Duration Repair', 'km')
on conflict (id) do nothing;

select tests.confirm_consent();

alter table runs drop constraint runs_duration_s_max_check;

-- 101: the issue's manual run, no track. 102: an app run with a track.
-- 103: an ordinary run.
insert into runs (id, user_id, started_at, duration_s, distance_m, source,
                  activity_type, track_url, metadata)
values
  ('d0000000-0000-0000-0000-0000000da101', 'd0000000-0000-0000-0000-0000000d0101',
   '2026-06-05 08:00:00+00', 44400094, 2000, 'app', 'run', null,
   '{"manual_entry": true, "title": "Nov 5"}'),
  ('d0000000-0000-0000-0000-0000000da102', 'd0000000-0000-0000-0000-0000000d0101',
   '2026-06-06 08:00:00+00', 2000000, 5000, 'app', 'run',
   'd0000000-0000-0000-0000-0000000d0101/d0000000-0000-0000-0000-0000000da102.json.gz',
   '{}'),
  ('d0000000-0000-0000-0000-0000000da103', 'd0000000-0000-0000-0000-0000000d0101',
   '2026-06-07 08:00:00+00', 1800, 5000, 'app', 'run', null,
   '{"title": "Easy"}');

select is(private.cap_out_of_bound_run_durations(), 2,
  'the repair caps the two out-of-bound rows and no others');

select is(
  (select duration_s from runs where id = 'd0000000-0000-0000-0000-0000000da101'),
  864000,
  'the trackless run is capped at the bound'
);

select is(
  (select metadata from runs where id = 'd0000000-0000-0000-0000-0000000da101'),
  '{"manual_entry": true, "title": "Nov 5", "duration_repaired": true,
    "duration_s_original": 44400094}'::jsonb,
  'it is flagged, keeps its original value, and loses no other key'
);

select is(
  (select (metadata ->> 'duration_s_original')::int from runs
    where id = 'd0000000-0000-0000-0000-0000000da102'),
  2000000,
  'the tracked run keeps its original value too'
);

select is(
  (select row(duration_s, metadata, distance_m)::text from runs
    where id = 'd0000000-0000-0000-0000-0000000da103'),
  row(1800, '{"title": "Easy"}'::jsonb, 5000::numeric(10, 2))::text,
  'an in-bound run is untouched'
);

select is(
  (select array_agg(payload ->> 'run_id') from jobs
    where kind = 'duration_repair'
      and payload ->> 'user_id' = 'd0000000-0000-0000-0000-0000000d0101'),
  array['d0000000-0000-0000-0000-0000000da102'],
  'only the run with a track is queued for the track recompute'
);

select is(
  (select status from jobs
    where kind = 'duration_repair'
      and payload ->> 'run_id' = 'd0000000-0000-0000-0000-0000000da102'),
  'queued',
  'the job waits for the worker'
);

select lives_ok(
  $$ alter table runs add constraint runs_duration_s_max_check
       check (duration_s <= 864000) not valid;
     alter table runs validate constraint runs_duration_s_max_check $$,
  'the constraint validates once the repair has run'
);

-- ── the cap does not count as ten days of running ───────────────────────────
insert into challenges (id, creator_id, title, metric, scope, goal_value, starts_at, ends_at, is_public)
values ('eeeeeeee-eeee-eeee-eeee-eeee000d0101', 'd0000000-0000-0000-0000-0000000d0101',
        'Duration repair', 'duration', 'individual', 36000,
        '2026-06-01 00:00:00+00', '2026-06-30 00:00:00+00', true);

insert into challenge_participants (challenge_id, user_id)
values ('eeeeeeee-eeee-eeee-eeee-eeee000d0101', 'd0000000-0000-0000-0000-0000000d0101');

set local role authenticated;
set local "request.jwt.claims" =
  '{"sub":"d0000000-0000-0000-0000-0000000d0101","role":"authenticated"}';

select is(
  (select value::int from challenge_leaderboard('eeeeeeee-eeee-eeee-eeee-eeee000d0101', false)
    where user_id = 'd0000000-0000-0000-0000-0000000d0101'),
  1800,
  'a duration board sums the in-bound run and leaves both capped rows out'
);

-- ── the flag follows the duration ───────────────────────────────────────────
update runs set metadata = '{"title": "Renamed"}'
 where id = 'd0000000-0000-0000-0000-0000000da101';

select is(
  (select metadata from runs where id = 'd0000000-0000-0000-0000-0000000da101'),
  '{"title": "Renamed", "duration_repaired": true,
    "duration_s_original": 44400094}'::jsonb,
  'an edit that leaves the duration alone cannot drop the flag or the original'
);

update runs set duration_s = 1294
 where id = 'd0000000-0000-0000-0000-0000000da101';

select is(
  (select duration_s from runs where id = 'd0000000-0000-0000-0000-0000000da101'),
  1294,
  'the owner can correct a capped duration'
);

select ok(
  (select not (metadata ? 'duration_repaired') from runs
    where id = 'd0000000-0000-0000-0000-0000000da101'),
  'correcting it clears the flag'
);

select is(
  (select metadata ->> 'duration_s_original' from runs
    where id = 'd0000000-0000-0000-0000-0000000da101'),
  '44400094',
  'and keeps the original value'
);

select throws_ok(
  $$ update runs set duration_s = 864001
      where id = 'd0000000-0000-0000-0000-0000000da103' $$,
  '23514', null,
  'the validated bound refuses an edit past it'
);

reset role;

-- The worker's write: service role, duration only.
update runs set duration_s = 2712
 where id = 'd0000000-0000-0000-0000-0000000da102';

select is(
  (select metadata from runs where id = 'd0000000-0000-0000-0000-0000000da102'),
  '{"duration_s_original": 2000000}'::jsonb,
  'the track recompute''s write clears the flag the same way'
);

select is(
  (select value::int from challenge_leaderboard('eeeeeeee-eeee-eeee-eeee-eeee000d0101', false)
    where user_id = 'd0000000-0000-0000-0000-0000000d0101'),
  1800 + 1294 + 2712,
  'both repaired durations now count'
);

select * from finish();

rollback;

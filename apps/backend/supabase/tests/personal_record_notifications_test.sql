-- The `personal_record` notification and the improvement log behind the PR
-- share card (migration 20271104000002, decisions § 2266).
--
-- What is pinned: a first entry and a strictly faster one are recorded with the
-- time they replaced; a run that improves several brackets raises ONE bell
-- row; a no-op recompute, a slower run, a deleted PR run and an old imported
-- run raise nothing; a run that leaves the cache and returns is not announced
-- twice; the log is owner-only and closed to client writes.

begin;

select plan(19);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000000f0001'::uuid, 'authenticated', 'authenticated',
   'pr-notify@pr.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000f0002'::uuid, 'authenticated', 'authenticated',
   'pr-other@pr.local', '', now(), now());

insert into user_profiles (id, display_name)
values ('00000000-0000-0000-0000-0000000f0001', 'PR Notify'),
       ('00000000-0000-0000-0000-0000000f0002', 'PR Other');

select tests.confirm_consent();

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000f0001"}';

-- 1-3. A first 5k: the bracket gains an entry, with no previous time.
insert into runs (id, user_id, started_at, duration_s, distance_m, source)
values ('00000000-0000-0000-0000-0000000f1001',
        '00000000-0000-0000-0000-0000000f0001', now() - interval '3 days',
        1500, 5000, 'app');

select is(
  (select count(*)::int from notifications
   where user_id = '00000000-0000-0000-0000-0000000f0001' and kind = 'personal_record'
     and run_id = '00000000-0000-0000-0000-0000000f1001'),
  1,
  'a first 5k raises a personal_record notification for its run'
);
select is(
  (select best_time_s from personal_record_improvements
   where run_id = '00000000-0000-0000-0000-0000000f1001' and distance = '5k'),
  1500,
  'the improvement records the new best'
);
select ok(
  (select previous_time_s is null from personal_record_improvements
   where run_id = '00000000-0000-0000-0000-0000000f1001' and distance = '5k'),
  'a first entry has no previous time'
);

-- 4. A recompute that changes nothing raises nothing.
select refresh_personal_records_for_user('00000000-0000-0000-0000-0000000f0001');
select is(
  (select count(*)::int from notifications
   where user_id = '00000000-0000-0000-0000-0000000f0001' and kind = 'personal_record'),
  1,
  'a no-op recompute raises no notification'
);

-- 5. A slower 5k is not an improvement.
insert into runs (id, user_id, started_at, duration_s, distance_m, source)
values ('00000000-0000-0000-0000-0000000f1002',
        '00000000-0000-0000-0000-0000000f0001', now() - interval '2 days',
        1600, 5000, 'app');
select is(
  (select count(*)::int from personal_record_improvements
   where user_id = '00000000-0000-0000-0000-0000000f0001'),
  1,
  'a slower run records no improvement'
);

-- 6-7. A faster 5k is, and carries the time it beat.
insert into runs (id, user_id, started_at, duration_s, distance_m, source)
values ('00000000-0000-0000-0000-0000000f1003',
        '00000000-0000-0000-0000-0000000f0001', now() - interval '1 day',
        1440, 5000, 'app');
select is(
  (select previous_time_s from personal_record_improvements
   where run_id = '00000000-0000-0000-0000-0000000f1003' and distance = '5k'),
  1500,
  'a faster run records the previous best it beat'
);
select is(
  (select count(*)::int from notifications
   where user_id = '00000000-0000-0000-0000-0000000f0001' and kind = 'personal_record'
     and run_id = '00000000-0000-0000-0000-0000000f1003'),
  1,
  'a faster run raises its own notification'
);

-- 8-9. One run improving several brackets (a 10k with an embedded 5k and a
--      whole-run 10k) is one notification, and both brackets are logged.
insert into runs (id, user_id, started_at, duration_s, distance_m, source, fastest_5k_s)
values ('00000000-0000-0000-0000-0000000f1004',
        '00000000-0000-0000-0000-0000000f0001', now() - interval '12 hours',
        2900, 10000, 'app', 1400);
select is(
  (select count(*)::int from notifications
   where user_id = '00000000-0000-0000-0000-0000000f0001' and kind = 'personal_record'
     and run_id = '00000000-0000-0000-0000-0000000f1004'),
  1,
  'a run improving two brackets raises one notification'
);
select is(
  (select array_agg(distance order by distance) from personal_record_improvements
   where run_id = '00000000-0000-0000-0000-0000000f1004'),
  array['10k', '5k'],
  'both brackets the run improved are logged'
);

-- 10. Deleting the PR run makes the cache slower: nothing is raised, and the
--     deleted run's own row goes with it (the run_id FK cascades).
delete from runs where id = '00000000-0000-0000-0000-0000000f1004';
select is(
  (select count(*)::int from notifications
   where user_id = '00000000-0000-0000-0000-0000000f0001' and kind = 'personal_record'),
  2,
  'deleting a PR run raises nothing'
);

-- 11. The run it displaced is back in the cache, but it was announced once
--     already and is not announced again.
select is(
  (select run_id from personal_records
   where user_id = '00000000-0000-0000-0000-0000000f0001' and distance = '5k'),
  '00000000-0000-0000-0000-0000000f1003'::uuid,
  'the earlier PR run holds the bracket again'
);
select is(
  (select count(*)::int from personal_record_improvements
   where run_id = '00000000-0000-0000-0000-0000000f1003'),
  1,
  'a run returning to the cache is not logged twice'
);

-- 13. The baseline is the cache as it stood, so after the delete a 5k slower
--     than the deleted one but faster than the survivor is still a record.
insert into runs (id, user_id, started_at, duration_s, distance_m, source)
values ('00000000-0000-0000-0000-0000000f1005',
        '00000000-0000-0000-0000-0000000f0001', now() - interval '6 hours',
        1420, 5000, 'app');
select is(
  (select previous_time_s from personal_record_improvements
   where run_id = '00000000-0000-0000-0000-0000000f1005' and distance = '5k'),
  1440,
  'the previous time is the cache value it replaced, not a deleted best'
);

-- 14-15. An old run (a history import) is logged but not announced.
insert into runs (id, user_id, started_at, duration_s, distance_m, source)
values ('00000000-0000-0000-0000-0000000f1006',
        '00000000-0000-0000-0000-0000000f0001', now() - interval '400 days',
        1300, 5000, 'strava');
select is(
  (select count(*)::int from personal_record_improvements
   where run_id = '00000000-0000-0000-0000-0000000f1006'),
  1,
  'an imported old run that improves the cache is logged'
);
select is(
  (select count(*)::int from notifications
   where run_id = '00000000-0000-0000-0000-0000000f1006'),
  0,
  'an old run raises no notification'
);

-- 16. Owner-only: another user reads none of it.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000f0002"}';
select is(
  (select count(*)::int from personal_record_improvements
   where user_id = '00000000-0000-0000-0000-0000000f0001'),
  0,
  'another user cannot read the improvement log'
);

-- 17-18. And the owner cannot write it.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000f0001"}';
select throws_ok(
  $$insert into personal_record_improvements (user_id, run_id, distance, best_time_s, achieved_at)
    values ('00000000-0000-0000-0000-0000000f0001', '00000000-0000-0000-0000-0000000f1001',
            '10k', 100, now())$$,
  '42501',
  null,
  'a client cannot insert an improvement'
);
select throws_ok(
  $$delete from personal_record_improvements where user_id = '00000000-0000-0000-0000-0000000f0001'$$,
  '42501',
  null,
  'a client cannot delete an improvement'
);

-- 19. The recorder is not callable by a client.
select throws_ok(
  $$select private.record_personal_record_improvements('00000000-0000-0000-0000-0000000f0001', '{}'::jsonb)$$,
  '42501',
  null,
  'a client cannot call the recorder'
);

select * from finish();
rollback;

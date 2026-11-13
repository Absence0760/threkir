-- pgtap: heart rate and the food log follow health-data consent
-- (migrations 20271227100001-100009, decisions § 2513).
--
-- Users:
--   C (…c1) consents throughout.
--   N (…c2) never consents; has heart rate and a meal stored before the gate.
--   W (…c3) consents, stores heart rate and food, then withdraws.
--   P (…c4) never consents; a pre-gate backlog the purge is tested against.
--   D (…c5) consents, then nulls the stamp directly (not through the RPC).

begin;

select plan(48);

select set_config('storage.allow_delete_query', 'true', true);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000000b7ac1', 'authenticated', 'authenticated', 'hg-c@test.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000b7ac2', 'authenticated', 'authenticated', 'hg-n@test.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000b7ac3', 'authenticated', 'authenticated', 'hg-w@test.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000b7ac4', 'authenticated', 'authenticated', 'hg-p@test.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000b7ac5', 'authenticated', 'authenticated', 'hg-d@test.local', '', now(), now());

insert into user_profiles (id, display_name, preferred_unit, age_confirmed_at, health_data_consent_at)
values
  ('00000000-0000-0000-0000-0000000b7ac1', 'HG C', 'km', now(), now()),
  ('00000000-0000-0000-0000-0000000b7ac2', 'HG N', 'km', now(), null),
  ('00000000-0000-0000-0000-0000000b7ac3', 'HG W', 'km', now(), now()),
  ('00000000-0000-0000-0000-0000000b7ac4', 'HG P', 'km', now(), null),
  ('00000000-0000-0000-0000-0000000b7ac5', 'HG D', 'km', now(), now());

-- The pre-gate backlog: rows N and P stored before the gate existed. The
-- gates are switched off for the seeding only.
alter table runs disable trigger runs_health_hr_gate;
alter table food_log disable trigger food_log_health_gate;
insert into runs (id, user_id, started_at, duration_s, distance_m, source, activity_type,
                  hr_series_url, metadata)
values
  ('00000000-0000-0000-0000-0000000b7ad2', '00000000-0000-0000-0000-0000000b7ac2',
   '2026-10-01 08:00+00', 1800, 5000, 'app', 'run',
   '00000000-0000-0000-0000-0000000b7ac2/00000000-0000-0000-0000-0000000b7ad2.hr.json.gz',
   '{"avg_bpm": 150, "max_bpm": 181, "hr_coverage": 0.97, "title": "Before the gate"}'),
  ('00000000-0000-0000-0000-0000000b7ad4', '00000000-0000-0000-0000-0000000b7ac4',
   '2026-10-02 08:00+00', 1800, 5000, 'app', 'run', null,
   '{"avg_bpm": 140, "title": "P before the gate"}'),
  ('00000000-0000-0000-0000-0000000b7ad6', '00000000-0000-0000-0000-0000000b7ac2',
   '2026-10-03 08:00+00', 1800, 5000, 'app', 'run', null,
   '{"avg_bpm": 155, "title": "Edited before the drain"}');
insert into food_log (user_id, item_name, calories, is_public)
values
  ('00000000-0000-0000-0000-0000000b7ac2', 'N porridge', 300, true),
  ('00000000-0000-0000-0000-0000000b7ac4', 'P porridge', 300, false);
alter table runs enable trigger runs_health_hr_gate;
alter table food_log enable trigger food_log_health_gate;

-- ── Runs: new writes ─────────────────────────────────────────────────
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000b7ac2","role":"authenticated"}';
insert into runs (id, user_id, started_at, duration_s, distance_m, source, activity_type,
                  hr_series_url, metadata)
values ('00000000-0000-0000-0000-0000000b7ad1', '00000000-0000-0000-0000-0000000b7ac2',
        '2026-11-01 08:00+00', 1500, 4000, 'app', 'run',
        '00000000-0000-0000-0000-0000000b7ac2/00000000-0000-0000-0000-0000000b7ad1.hr.json.gz',
        '{"avg_bpm": 151, "max_bpm": 170, "hr_coverage": 1, "title": "No consent"}');
reset role;

select is(
  (select metadata from runs where id = '00000000-0000-0000-0000-0000000b7ad1'),
  '{"title": "No consent"}'::jsonb,
  'a run saved without consent keeps every key but the heart-rate ones'
);
select is(
  (select hr_series_url from runs where id = '00000000-0000-0000-0000-0000000b7ad1'),
  null,
  'a run saved without consent keeps no heart-rate sidecar path'
);
select is(
  (select distance_m::int from runs where id = '00000000-0000-0000-0000-0000000b7ad1'),
  4000,
  'the run itself is kept'
);
select is(
  (select count(*)::int from private.withheld_run_hr where run_id = '00000000-0000-0000-0000-0000000b7ad1'),
  0,
  'heart rate arriving without consent is dropped, not held'
);

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000b7ac1","role":"authenticated"}';
insert into runs (id, user_id, started_at, duration_s, distance_m, source, activity_type, metadata)
values ('00000000-0000-0000-0000-0000000b7ad3', '00000000-0000-0000-0000-0000000b7ac1',
        '2026-11-01 08:00+00', 1500, 4000, 'app', 'run', '{"avg_bpm": 149, "max_bpm": 172}');
reset role;
select is(
  (select metadata from runs where id = '00000000-0000-0000-0000-0000000b7ad3'),
  '{"avg_bpm": 149, "max_bpm": 172}'::jsonb,
  'a run saved with consent keeps its heart rate'
);

-- The service role (the Strava importers, the job worker) is gated too.
set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';
insert into runs (id, user_id, started_at, duration_s, distance_m, source, activity_type, metadata)
values ('00000000-0000-0000-0000-0000000b7ad5', '00000000-0000-0000-0000-0000000b7ac2',
        '2026-11-02 08:00+00', 1500, 4000, 'strava', 'run', '{"avg_bpm": 160, "strava_id": "1"}');
reset role;
select is(
  (select metadata from runs where id = '00000000-0000-0000-0000-0000000b7ad5'),
  '{"strava_id": "1"}'::jsonb,
  'an import written by the service role is stripped too'
);

-- ── Runs: the pre-gate backlog ───────────────────────────────────────
-- An owner edit before the drain reaches the row moves the heart rate out
-- rather than deleting it.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000b7ac2","role":"authenticated"}';
update runs set metadata = '{"title": "Renamed"}'
 where id = '00000000-0000-0000-0000-0000000b7ad6';
reset role;
select is(
  (select hr from private.withheld_run_hr where run_id = '00000000-0000-0000-0000-0000000b7ad6'),
  '{"avg_bpm": 155}'::jsonb,
  'an edit to a pre-gate run holds its stored heart rate instead of losing it'
);

-- The local stack's cron may already have finished the drain over the seed;
-- start it again from the first id, as a fresh deploy does.
update private.health_backlog_drain set last_run_id = null, done_at = null;
select cron.schedule('withhold-unconsented-run-hr', '* * * * *',
                     $$select private.drain_unconsented_run_hr(2000)$$);
select is(private.drain_unconsented_run_hr(100000) >= 2, true,
  'the drain moves the pre-gate heart rate of runners without consent');
select is(
  (select metadata from runs where id = '00000000-0000-0000-0000-0000000b7ad2'),
  '{"title": "Before the gate"}'::jsonb,
  'after the drain the run carries no heart rate'
);
select is(
  (select hr || jsonb_build_object('url', hr_series_url) from private.withheld_run_hr
    where run_id = '00000000-0000-0000-0000-0000000b7ad2'),
  jsonb_build_object('avg_bpm', 150, 'max_bpm', 181, 'hr_coverage', 0.97,
                     'url', '00000000-0000-0000-0000-0000000b7ac2/00000000-0000-0000-0000-0000000b7ad2.hr.json.gz'),
  'the drained heart rate and sidecar path are held, not deleted'
);
select is(
  (select metadata from runs where id = '00000000-0000-0000-0000-0000000b7ad3'),
  '{"avg_bpm": 149, "max_bpm": 172}'::jsonb,
  'the drain leaves a consenting runner''s heart rate alone'
);
select is(private.drain_unconsented_run_hr(100000), 0, 'a drain step past the last id finds nothing');
select isnt((select done_at from private.health_backlog_drain), null,
  'the drain records that it is done');
select is((select count(*)::int from cron.job where jobname = 'withhold-unconsented-run-hr'), 0,
  'the finished drain unschedules itself');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000b7ac2","role":"authenticated"}';
select is(
  (select count(*)::int from runs
    where user_id = '00000000-0000-0000-0000-0000000b7ac2' and metadata ?| array['avg_bpm','max_bpm','hr_coverage']),
  0,
  'the owner reads none of their held heart rate'
);
select throws_ok(
  $$ select count(*) from private.withheld_run_hr $$,
  '42501', null,
  'the held table is not readable by a client'
);

-- ── Food log ─────────────────────────────────────────────────────────
select throws_ok(
  $$ insert into food_log (user_id, item_name, calories)
     values ('00000000-0000-0000-0000-0000000b7ac2', 'Toast', 200) $$,
  '42501', null,
  'logging food without consent is refused'
);
select is(
  (select count(*)::int from food_log),
  0,
  'a meal logged before the gate is hidden from its owner without consent'
);
reset role;
select is(
  (select count(*)::int from public_food_log where item_name = 'N porridge'),
  0,
  'a shared meal is hidden from public_food_log while its owner has no consent'
);

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000b7ac1","role":"authenticated"}';
select lives_ok(
  $$ insert into food_log (user_id, item_name, calories)
     values ('00000000-0000-0000-0000-0000000b7ac1', 'Toast', 200) $$,
  'logging food with consent works'
);
select is((select count(*)::int from food_log), 1, 'a consenting runner reads their food log');
reset role;

set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';
select throws_ok(
  $$ insert into food_log (user_id, item_name) values ('00000000-0000-0000-0000-0000000b7ac2', 'Imported') $$,
  '42501', null,
  'the service role cannot store food without consent either'
);
reset role;

-- ── Pings and gym ────────────────────────────────────────────────────
insert into clubs (id, owner_id, name, slug, is_public)
values ('00000000-0000-0000-0000-0000000b7ae1', '00000000-0000-0000-0000-0000000b7ac1',
        'HG Club', 'hg-club', true);
insert into events (id, club_id, title, starts_at, author_id, is_public)
values ('00000000-0000-0000-0000-0000000b7ae2', '00000000-0000-0000-0000-0000000b7ae1',
        'HG race', '2026-09-01 08:00+00', '00000000-0000-0000-0000-0000000b7ac1', true);
insert into race_pings (event_id, instance_start, user_id, lat, lng, bpm)
values
  ('00000000-0000-0000-0000-0000000b7ae2', '2026-09-01 08:00+00',
   '00000000-0000-0000-0000-0000000b7ac2', 51.5, -0.1, 150),
  ('00000000-0000-0000-0000-0000000b7ae2', '2026-09-01 08:00+00',
   '00000000-0000-0000-0000-0000000b7ac3', 51.5, -0.1, 152);
select is(
  (select bpm from race_pings where user_id = '00000000-0000-0000-0000-0000000b7ac2'),
  null,
  'a race ping from a runner without consent keeps no bpm'
);
select is(
  (select bpm from race_pings where user_id = '00000000-0000-0000-0000-0000000b7ac3'),
  152,
  'a race ping from a consenting runner keeps its bpm'
);

insert into gym_workouts (id, user_id, title, metadata)
values ('00000000-0000-0000-0000-0000000b7af1', '00000000-0000-0000-0000-0000000b7ac2',
        'Legs', '{"avg_bpm": 120, "routine_id": "r"}');
select is(
  (select metadata from gym_workouts where id = '00000000-0000-0000-0000-0000000b7af1'),
  '{"routine_id": "r"}'::jsonb,
  'a gym session without consent keeps no heart rate'
);

-- ── Storage: the heart-rate sidecar ──────────────────────────────────
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000b7ac2","role":"authenticated"}';
select throws_ok(
  $$ insert into storage.objects (bucket_id, name, owner)
     values ('runs', '00000000-0000-0000-0000-0000000b7ac2/00000000-0000-0000-0000-0000000b7ad1.hr.json.gz',
             '00000000-0000-0000-0000-0000000b7ac2') $$,
  '42501', null,
  'a heart-rate sidecar cannot be uploaded without consent'
);
select lives_ok(
  $$ insert into storage.objects (bucket_id, name, owner)
     values ('runs', '00000000-0000-0000-0000-0000000b7ac2/00000000-0000-0000-0000-0000000b7ad1.json.gz',
             '00000000-0000-0000-0000-0000000b7ac2') $$,
  'the run''s track still uploads without consent'
);
reset role;
insert into storage.objects (bucket_id, name, owner)
values ('runs', '00000000-0000-0000-0000-0000000b7ac2/00000000-0000-0000-0000-0000000b7ad2.hr.json.gz',
        '00000000-0000-0000-0000-0000000b7ac2');
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000b7ac2","role":"authenticated"}';
select is(
  (select count(*)::int from storage.objects
    where bucket_id = 'runs' and name like '%.hr.json.gz'),
  0,
  'a stored sidecar is unreadable without consent'
);

-- ── Consent restores ─────────────────────────────────────────────────
select isnt((select grant_health_data_consent()), null, 'N gives consent');
reset role;
select is(
  (select metadata from runs where id = '00000000-0000-0000-0000-0000000b7ad2'),
  '{"title": "Before the gate", "avg_bpm": 150, "max_bpm": 181, "hr_coverage": 0.97}'::jsonb,
  'consent puts the held heart rate back on the run'
);
select is(
  (select hr_series_url from runs where id = '00000000-0000-0000-0000-0000000b7ad2'),
  '00000000-0000-0000-0000-0000000b7ac2/00000000-0000-0000-0000-0000000b7ad2.hr.json.gz',
  'consent puts the sidecar path back'
);
select is(
  (select count(*)::int from private.withheld_run_hr where user_id = '00000000-0000-0000-0000-0000000b7ac2'),
  0,
  'nothing stays held once consent is given'
);
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000b7ac2","role":"authenticated"}';
select is((select count(*)::int from food_log), 1, 'consent shows the hidden meal again');
select is(
  (select count(*)::int from storage.objects where bucket_id = 'runs' and name like '%.hr.json.gz'),
  1,
  'consent makes the sidecar readable'
);
reset role;

-- ── Withdrawal erases ────────────────────────────────────────────────
set local "request.jwt.claims" = '{}';
alter table food_log disable trigger food_log_health_gate;
insert into food_log (user_id, item_name) values ('00000000-0000-0000-0000-0000000b7ac3', 'W lunch');
alter table food_log enable trigger food_log_health_gate;
insert into runs (id, user_id, started_at, duration_s, distance_m, source, activity_type, metadata)
values ('00000000-0000-0000-0000-0000000b7ad7', '00000000-0000-0000-0000-0000000b7ac3',
        '2026-11-03 08:00+00', 1500, 4000, 'app', 'run', '{"avg_bpm": 140, "title": "W"}');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000b7ac3","role":"authenticated"}';
select lives_ok($$ select withdraw_health_data_consent() $$, 'W withdraws');
reset role;
select is(
  (select metadata from runs where id = '00000000-0000-0000-0000-0000000b7ad7'),
  '{"title": "W"}'::jsonb,
  'withdrawal erases the heart rate on the runner''s runs and keeps the runs'
);
select is(
  (select count(*)::int from private.withheld_run_hr where user_id = '00000000-0000-0000-0000-0000000b7ac3'),
  0,
  'withdrawal erases rather than holds'
);
select is((select count(*)::int from food_log where user_id = '00000000-0000-0000-0000-0000000b7ac3'), 0,
  'withdrawal erases the food log');
select is((select bpm from race_pings where user_id = '00000000-0000-0000-0000-0000000b7ac3'), null,
  'withdrawal erases bpm on the runner''s race pings');
select is(
  (select count(*)::int from jobs
    where kind = 'health_hr_erase' and payload ->> 'user_id' = '00000000-0000-0000-0000-0000000b7ac3'),
  1,
  'withdrawal queues exactly one Storage clean-up job'
);

-- A runner who never consented: withdrawal deletes the hidden backlog.
insert into private.withheld_run_hr (run_id, user_id, hr)
values ('00000000-0000-0000-0000-0000000b7ad5', '00000000-0000-0000-0000-0000000b7ac2', '{"avg_bpm": 1}')
on conflict do nothing;
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000b7ac2","role":"authenticated"}';
select lives_ok($$ select withdraw_health_data_consent() $$, 'N withdraws');
select lives_ok($$ select withdraw_health_data_consent() $$, 'N withdraws again, with nothing left');
reset role;
select is(
  (select count(*)::int from private.withheld_run_hr where user_id = '00000000-0000-0000-0000-0000000b7ac2')
  + (select count(*)::int from food_log where user_id = '00000000-0000-0000-0000-0000000b7ac2'),
  0,
  'withdrawing without consent on record deletes the hidden heart rate and food'
);

-- A direct null of the stamp (allowed as a withdrawal) erases too.
set local "request.jwt.claims" = '{}';
insert into runs (id, user_id, started_at, duration_s, distance_m, source, activity_type, metadata)
values ('00000000-0000-0000-0000-0000000b7ad8', '00000000-0000-0000-0000-0000000b7ac5',
        '2026-11-03 08:00+00', 1500, 4000, 'app', 'run', '{"avg_bpm": 141}');
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000b7ac5","role":"authenticated"}';
update user_profiles set health_data_consent_at = null where id = '00000000-0000-0000-0000-0000000b7ac5';
reset role;
select is(
  (select metadata from runs where id = '00000000-0000-0000-0000-0000000b7ad8'),
  '{}'::jsonb,
  'nulling the consent stamp directly erases heart rate as the RPC does'
);

-- ── The backlog purge is off until its flag is on ────────────────────
set local "request.jwt.claims" = '{}';
select is(private.purge_health_backlog(100), 0, 'the purge does nothing while its flag is absent');
select is(
  (select count(*)::int from private.withheld_run_hr where user_id = '00000000-0000-0000-0000-0000000b7ac4')
  + (select count(*)::int from food_log where user_id = '00000000-0000-0000-0000-0000000b7ac4'),
  2,
  'the held backlog survives while the purge is off'
);
insert into private.feature_flags (name, enabled) values ('health_backlog_purge', true)
on conflict (name) do update set enabled = true;
select is(private.purge_health_backlog(100) >= 1, true, 'the purge runs once its flag is on');
select is(
  (select count(*)::int from private.withheld_run_hr where user_id = '00000000-0000-0000-0000-0000000b7ac4')
  + (select count(*)::int from food_log where user_id = '00000000-0000-0000-0000-0000000b7ac4'),
  0,
  'the purge erases the held heart rate and hidden food of runners without consent'
);

select * from finish();
rollback;

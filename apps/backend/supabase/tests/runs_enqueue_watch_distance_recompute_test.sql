-- runs_enqueue_watch_distance_recompute — the trigger that queues the
-- server's smoother for a Wear OS / watchOS run once its track lands
-- (migration 20270828000001, issue #1172), queued only for a complete track
-- since 20270829000031.
--
-- Pinned: the function is SECURITY DEFINER with a pinned search_path and the
-- trigger exists; a watch run inserted with a track, a recorder estimator
-- stamp and `track_complete: true` queues exactly one job carrying the run
-- and its owner; a watch row that lands before its track queues when
-- track_url is set, and a later write naming the same track_url queues
-- nothing more, even after the first job finished; an unrelated update queues nothing; and nothing is queued for
-- a watch run whose track is not complete (a build from before track_complete,
-- whose stored track omits the canopy fixes its estimator took), a phone run,
-- a custom-watch run (no estimator stamp), a run already recomputed, an indoor
-- run or a run with no track. Every refused row carries `track_complete: true`
-- unless that is what it is refused for, so each refusal is its own reason.

begin;

select plan(15);

-- ── shape ────────────────────────────────────────────────────────────────

select is(
  (select p.prosecdef from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'runs_enqueue_watch_distance_recompute'),
  true,
  'runs_enqueue_watch_distance_recompute is SECURITY DEFINER (jobs is writable only by the worker)');

select ok(
  (select 'search_path=public' = any(p.proconfig) from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'runs_enqueue_watch_distance_recompute'),
  'runs_enqueue_watch_distance_recompute pins search_path');

select ok(
  exists (select 1 from pg_trigger
           where tgrelid = 'public.runs'::regclass
             and tgname = 'runs_enqueue_watch_distance_recompute'
             and not tgisinternal),
  'the trigger is installed on runs');

-- ── fixtures ─────────────────────────────────────────────────────────────

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values ('00000000-0000-0000-0000-0000de000001', 'authenticated', 'authenticated', 'owner@de.local', '', now(), now());

insert into user_profiles (id, display_name)
values ('00000000-0000-0000-0000-0000de000001', 'Owner') on conflict (id) do nothing;

create or replace function pg_temp.recompute_jobs(p_run uuid)
returns bigint language sql as $$
  select count(*) from jobs
   where kind = 'distance_recompute' and (payload ->> 'run_id')::uuid = p_run;
$$;

-- ── a watch run inserted with its track ──────────────────────────────────

insert into runs (id, user_id, started_at, distance_m, duration_s, source, track_url, metadata)
values ('de000000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-0000de000001',
        '2026-10-01 09:00:00+00', 5210, 1800, 'watch',
        '00000000-0000-0000-0000-0000de000001/de000000-0000-4000-8000-000000000001.json.gz',
        '{"activity_type":"run","distance_estimator":"kalman_v4","track_complete":true}');

select is(pg_temp.recompute_jobs('de000000-0000-4000-8000-000000000001'), 1::bigint,
  'a watch run inserted with a track queues one distance_recompute');

select is(
  (select payload from jobs
    where kind = 'distance_recompute'
      and (payload ->> 'run_id')::uuid = 'de000000-0000-4000-8000-000000000001'),
  jsonb_build_object('run_id', 'de000000-0000-4000-8000-000000000001',
                     'user_id', '00000000-0000-0000-0000-0000de000001'),
  'the job carries the run and its owner, the shape request_distance_recompute writes');

update runs set duration_s = 1801
 where id = 'de000000-0000-4000-8000-000000000001';

select is(pg_temp.recompute_jobs('de000000-0000-4000-8000-000000000001'), 1::bigint,
  'an update that does not touch track_url queues nothing');

-- ── a watch row that lands before its track ──────────────────────────────

insert into runs (id, user_id, started_at, distance_m, duration_s, source, track_url, metadata)
values ('de000000-0000-4000-8000-000000000002', '00000000-0000-0000-0000-0000de000001',
        '2026-10-02 09:00:00+00', 5210, 1800, 'watch', null,
        '{"activity_type":"run","distance_estimator":"kalman_v4","track_complete":true}');

select is(pg_temp.recompute_jobs('de000000-0000-4000-8000-000000000002'), 0::bigint,
  'a watch row with no track yet queues nothing');

update runs
   set track_url = '00000000-0000-0000-0000-0000de000001/de000000-0000-4000-8000-000000000002.json.gz'
 where id = 'de000000-0000-4000-8000-000000000002';

select is(pg_temp.recompute_jobs('de000000-0000-4000-8000-000000000002'), 1::bigint,
  'naming the track on the row queues the recompute');

update jobs set status = 'done', finished_at = now()
 where kind = 'distance_recompute'
   and (payload ->> 'run_id')::uuid = 'de000000-0000-4000-8000-000000000002';

update runs
   set track_url = '00000000-0000-0000-0000-0000de000001/de000000-0000-4000-8000-000000000002.json.gz'
 where id = 'de000000-0000-4000-8000-000000000002';

select is(pg_temp.recompute_jobs('de000000-0000-4000-8000-000000000002'), 1::bigint,
  'a later write naming the same track_url queues nothing, even once the first job is done');

-- ── runs it leaves alone ─────────────────────────────────────────────────

insert into runs (id, user_id, started_at, distance_m, duration_s, source, track_url, metadata)
values
  ('de000000-0000-4000-8000-000000000003', '00000000-0000-0000-0000-0000de000001',
   '2026-10-03 09:00:00+00', 5000, 1800, 'app',
   '00000000-0000-0000-0000-0000de000001/de000000-0000-4000-8000-000000000003.json.gz',
   '{"activity_type":"run","distance_estimator":"kalman_v4","track_complete":true}'),
  ('de000000-0000-4000-8000-000000000004', '00000000-0000-0000-0000-0000de000001',
   '2026-10-04 09:00:00+00', 5000, 1800, 'watch',
   '00000000-0000-0000-0000-0000de000001/de000000-0000-4000-8000-000000000004.json.gz',
   '{"activity_type":"run","track_complete":true}'),
  ('de000000-0000-4000-8000-000000000005', '00000000-0000-0000-0000-0000de000001',
   '2026-10-05 09:00:00+00', 5000, 1800, 'watch',
   '00000000-0000-0000-0000-0000de000001/de000000-0000-4000-8000-000000000005.json.gz',
   '{"activity_type":"run","distance_estimator":"kalman_v3","distance_recomputed_at":"2026-10-05T10:00:00Z","track_complete":true}'),
  ('de000000-0000-4000-8000-000000000006', '00000000-0000-0000-0000-0000de000001',
   '2026-10-06 09:00:00+00', 0, 1800, 'watch',
   '00000000-0000-0000-0000-0000de000001/de000000-0000-4000-8000-000000000006.json.gz',
   '{"activity_type":"run","distance_estimator":"kalman_v4","indoor":true,"track_complete":true}'),
  ('de000000-0000-4000-8000-000000000007', '00000000-0000-0000-0000-0000de000001',
   '2026-10-07 09:00:00+00', 5000, 1800, 'watch',
   '00000000-0000-0000-0000-0000de000001/de000000-0000-4000-8000-000000000007.json.gz',
   '{"activity_type":"run","distance_estimator":"kalman_v1"}'),
  ('de000000-0000-4000-8000-000000000008', '00000000-0000-0000-0000-0000de000001',
   '2026-10-08 09:00:00+00', 5000, 1800, 'watch',
   '00000000-0000-0000-0000-0000de000001/de000000-0000-4000-8000-000000000008.json.gz',
   '{"activity_type":"run","distance_estimator":"kalman_v4","track_complete":"true"}');

select is(pg_temp.recompute_jobs('de000000-0000-4000-8000-000000000007'), 0::bigint,
  'a watch run without track_complete is not queued (its stored track omits the canopy fixes its estimator took)');

select is(pg_temp.recompute_jobs('de000000-0000-4000-8000-000000000008'), 0::bigint,
  'track_complete must be the JSON boolean true, the reading the worker gives it');

select is(pg_temp.recompute_jobs('de000000-0000-4000-8000-000000000003'), 0::bigint,
  'a phone run is not queued (the phone saved the smoother''s figure)');

select is(pg_temp.recompute_jobs('de000000-0000-4000-8000-000000000004'), 0::bigint,
  'a watch run with no estimator stamp (the custom watch''s breadcrumb track) is not queued');

select is(pg_temp.recompute_jobs('de000000-0000-4000-8000-000000000005'), 0::bigint,
  'a watch run already recomputed is not queued again');

select is(pg_temp.recompute_jobs('de000000-0000-4000-8000-000000000006'), 0::bigint,
  'an indoor watch run is not queued');

select * from finish();
rollback;

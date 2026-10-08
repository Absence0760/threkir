-- request_distance_recompute(uuid) — the owner-only enqueue behind the run
-- detail page's "Recalculate distance" action (migration
-- 20270719000001_distance_recompute.sql).
--
-- Pinned: the function's shape (SECURITY DEFINER with a pinned search_path,
-- EXECUTE for authenticated and not anon), the owner path enqueuing exactly
-- one `distance_recompute` job carrying the run and its owner, the dedupe that
-- makes a second tap a no-op while the first is in flight, a fresh request
-- landing once the first finishes, and the refusals: a non-owner, a run that
-- does not exist, a signed-out caller, and a run with no stored track.

begin;

select plan(15);

-- ── shape ────────────────────────────────────────────────────────────────

select is(
  (select p.prosecdef from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'request_distance_recompute'),
  true,
  'request_distance_recompute is SECURITY DEFINER (jobs is writable only by the worker)');

select ok(
  (select 'search_path=public' = any(p.proconfig) from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'request_distance_recompute'),
  'request_distance_recompute pins search_path');

select is(
  has_function_privilege('authenticated', 'public.request_distance_recompute(uuid)', 'execute'),
  true, 'authenticated may call request_distance_recompute');

select is(
  has_function_privilege('anon', 'public.request_distance_recompute(uuid)', 'execute'),
  false, 'anon may not call request_distance_recompute');

-- ── fixtures ─────────────────────────────────────────────────────────────

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000dc000001', 'authenticated', 'authenticated', 'owner@dc.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000dc000002', 'authenticated', 'authenticated', 'other@dc.local', '', now(), now());

insert into user_profiles (id, display_name) values
  ('00000000-0000-0000-0000-0000dc000001', 'Owner'),
  ('00000000-0000-0000-0000-0000dc000002', 'Other') on conflict (id) do nothing;

insert into runs (id, user_id, started_at, distance_m, duration_s, source, track_url, metadata)
values
  ('dc000000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-0000dc000001',
   '2026-10-01 09:00:00+00', 6309, 1800, 'app',
   '00000000-0000-0000-0000-0000dc000001/dc000000-0000-4000-8000-000000000001.json.gz',
   '{"activity_type":"run"}'),
  ('dc000000-0000-4000-8000-000000000002', '00000000-0000-0000-0000-0000dc000001',
   '2026-10-02 09:00:00+00', 5000, 1500, 'app', null, '{"activity_type":"run"}');

-- ── the owner path ───────────────────────────────────────────────────────

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000dc000001","role":"authenticated"}';

select lives_ok(
  $$ select public.request_distance_recompute('dc000000-0000-4000-8000-000000000001') $$,
  'the owner may request a recompute of their tracked run');

-- A second tap while the first is still queued is a no-op, not an error.
select lives_ok(
  $$ select public.request_distance_recompute('dc000000-0000-4000-8000-000000000001') $$,
  'a second request while one is queued does not raise');

reset role;

select is(
  (select count(*)::int from jobs
    where kind = 'distance_recompute'
      and (payload->>'run_id')::uuid = 'dc000000-0000-4000-8000-000000000001'),
  1,
  'two requests in flight enqueue exactly one distance_recompute job');

select is(
  (select payload->>'user_id' from jobs
    where kind = 'distance_recompute'
      and (payload->>'run_id')::uuid = 'dc000000-0000-4000-8000-000000000001'),
  '00000000-0000-0000-0000-0000dc000001',
  'the job payload carries the run owner');

select is(
  (select status from jobs
    where kind = 'distance_recompute'
      and (payload->>'run_id')::uuid = 'dc000000-0000-4000-8000-000000000001'),
  'queued',
  'the job starts queued');

-- Once the first job leaves flight the dedupe index permits a fresh one.
update jobs set status = 'done'
 where kind = 'distance_recompute'
   and (payload->>'run_id')::uuid = 'dc000000-0000-4000-8000-000000000001';

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000dc000001","role":"authenticated"}';
select public.request_distance_recompute('dc000000-0000-4000-8000-000000000001');
reset role;

select is(
  (select count(*)::int from jobs
    where kind = 'distance_recompute'
      and (payload->>'run_id')::uuid = 'dc000000-0000-4000-8000-000000000001'),
  2,
  'a request after the previous job finished enqueues a fresh job');

-- ── refusals ─────────────────────────────────────────────────────────────

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000dc000002","role":"authenticated"}';

select throws_ok(
  $$ select public.request_distance_recompute('dc000000-0000-4000-8000-000000000001') $$,
  '42501',
  'request_distance_recompute: not authorized',
  'a signed-in non-owner is refused');

select throws_ok(
  $$ select public.request_distance_recompute('dc000000-0000-4000-8000-0000000000ff') $$,
  '42501',
  'request_distance_recompute: not authorized',
  'a run that does not exist is refused exactly like someone else''s run');

set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000dc000001","role":"authenticated"}';

select throws_ok(
  $$ select public.request_distance_recompute('dc000000-0000-4000-8000-000000000002') $$,
  '22000',
  'request_distance_recompute: run has no track',
  'a run with no stored track is refused with its own error');

reset role;

-- The privilege layer refuses anon before the body runs.
set local role anon;
set local "request.jwt.claims" = '{"role":"anon"}';

select throws_ok(
  $$ select public.request_distance_recompute('dc000000-0000-4000-8000-000000000001') $$,
  '42501',
  null,
  'anon cannot call request_distance_recompute');

reset role;

-- The body refuses a caller with no uid even where the grant would let it in.
set local "request.jwt.claims" = '{}';

select throws_ok(
  $$ select public.request_distance_recompute('dc000000-0000-4000-8000-000000000001') $$,
  '42501',
  'request_distance_recompute: not authorized',
  'a caller with no auth.uid() is refused by the body');

select * from finish();
rollback;

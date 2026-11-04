-- Pins the route-photo orphan sweep (migration 20271106000020, decisions
-- § 2305): which `route-photos` objects the worklist hands the Go worker,
-- that the gate keeps it empty and enqueues nothing while off, that a
-- transaction's route_photos deletes share one paths job up to 1000 paths,
-- and that a failed enqueue never aborts the delete.
--
--   1-3.   Gate off: the worklist is empty although an orphan exists, and
--          neither the nightly enqueue nor a delete queues a job.
--   4.     Backstop worklist: exactly the unreferenced objects last written
--          over 24 hours ago. Not a referenced original, a referenced thumb,
--          the upload behind a mobile placeholder row, a fresh upload, an old
--          object rewritten inside the window, an object of unknown age, or
--          an object in another bucket.
--   5-6.   The limit is clamped: 1 returns one row, 0 is read as 1.
--   7.     Paths mode: only the handed paths that exist and are unreferenced,
--          with no grace.
--   8-9.   The nightly enqueue queues one backstop job and is a singleton.
--   10-12. Deleting the route as its owner queues ONE paths job holding the
--          cascaded photos' original and thumb paths (no placeholder ''),
--          and those paths are now on the worklist.
--   13.    A delete that removes no photo queues nothing.
--   14-15. anon and authenticated cannot call the worklist.
--   16.    Two routes deleted in one statement cascade as two firings, and
--          both append to the transaction's existing paths job.
--   17-18. Past 1000 paths the firing fills that job and starts one more,
--          so 1100 cascaded paths are two jobs (1000 + the rest), none lost.
--   19-20. With the enqueue made to fail, the photo delete still commits and
--          queues nothing.

begin;
select plan(20);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values ('d2293000-0000-0000-0000-0000000000a1', 'authenticated', 'authenticated', 'ps-owner@ps.local', '', now(), now());

insert into routes (id, user_id, name, waypoints, distance_m, is_public)
values
  ('d2293000-0000-0000-0000-0000000000b1', 'd2293000-0000-0000-0000-0000000000a1', 'Photo route',
   '[{"lat":51.5,"lng":-0.1},{"lat":51.51,"lng":-0.11}]'::jsonb, 5000, true),
  ('d2293000-0000-0000-0000-0000000000b2', 'd2293000-0000-0000-0000-0000000000a1', 'No photos',
   '[{"lat":51.5,"lng":-0.1},{"lat":51.51,"lng":-0.11}]'::jsonb, 5000, true);

insert into storage.objects (bucket_id, name, owner, created_at, updated_at)
values
  ('route-photos', 'd2293000-0000-0000-0000-0000000000a1/live.jpg',
   'd2293000-0000-0000-0000-0000000000a1', now() - interval '3 days', now() - interval '3 days'),
  ('route-photos', 'd2293000-0000-0000-0000-0000000000a1/live_512.jpg',
   'd2293000-0000-0000-0000-0000000000a1', now() - interval '3 days', now() - interval '3 days'),
  ('route-photos', 'd2293000-0000-0000-0000-0000000000a1/d2293000-0000-0000-0000-0000000000f9.jpg',
   'd2293000-0000-0000-0000-0000000000a1', now() - interval '3 days', now() - interval '3 days'),
  ('route-photos', 'd2293000-0000-0000-0000-0000000000a1/orphan1.jpg',
   'd2293000-0000-0000-0000-0000000000a1', now() - interval '2 days', now() - interval '2 days'),
  ('route-photos', 'd2293000-0000-0000-0000-0000000000a1/orphan2.jpg',
   'd2293000-0000-0000-0000-0000000000a1', now() - interval '25 hours', now() - interval '25 hours'),
  ('route-photos', 'd2293000-0000-0000-0000-0000000000a1/fresh.jpg',
   'd2293000-0000-0000-0000-0000000000a1', now() - interval '5 minutes', now() - interval '5 minutes'),
  ('route-photos', 'd2293000-0000-0000-0000-0000000000a1/rewritten.jpg',
   'd2293000-0000-0000-0000-0000000000a1', now() - interval '3 days', now() - interval '1 hour'),
  ('route-photos', 'd2293000-0000-0000-0000-0000000000a1/unknown-age.jpg',
   'd2293000-0000-0000-0000-0000000000a1', null, null),
  ('run-photos', 'd2293000-0000-0000-0000-0000000000a1/not-a-route-photo.jpg',
   'd2293000-0000-0000-0000-0000000000a1', now() - interval '3 days', now() - interval '3 days');

insert into route_photos (id, route_id, owner_id, storage_path, thumb_512_path)
values
  ('d2293000-0000-0000-0000-0000000000f1', 'd2293000-0000-0000-0000-0000000000b1',
   'd2293000-0000-0000-0000-0000000000a1', 'd2293000-0000-0000-0000-0000000000a1/live.jpg',
   'd2293000-0000-0000-0000-0000000000a1/live_512.jpg'),
  ('d2293000-0000-0000-0000-0000000000f9', 'd2293000-0000-0000-0000-0000000000b1',
   'd2293000-0000-0000-0000-0000000000a1', '', null);

create temporary table sweep_jobs_before as
  select count(*)::int as n from public.jobs where kind = 'route_photo_orphan_sweep';

-- ── 1-3: gate off ──────────────────────────────────────────────────────────
delete from private.feature_flags where name = 'route_photo_orphan_sweep';

select is(
  (select count(*)::int from public.route_photo_orphan_paths()),
  0,
  'gate off: the worklist is empty although an orphan exists');

select public.enqueue_route_photo_orphan_sweep();
delete from route_photos where id = 'd2293000-0000-0000-0000-0000000000f9';

select is(
  (select count(*)::int from public.jobs where kind = 'route_photo_orphan_sweep'),
  (select n from sweep_jobs_before),
  'gate off: neither the nightly enqueue nor a delete queues a job');

insert into route_photos (id, route_id, owner_id, storage_path)
values ('d2293000-0000-0000-0000-0000000000f9', 'd2293000-0000-0000-0000-0000000000b1',
        'd2293000-0000-0000-0000-0000000000a1', '');

select is(
  (select count(*)::int from public.route_photo_orphan_paths(array['d2293000-0000-0000-0000-0000000000a1/fresh.jpg'])),
  0,
  'gate off: paths mode is empty too');

insert into private.feature_flags (name, enabled) values ('route_photo_orphan_sweep', true);

-- ── 4: backstop worklist ───────────────────────────────────────────────────
select results_eq(
  $$ select p from public.route_photo_orphan_paths(null, 500) as p
      where p like 'd2293000-0000-0000-0000-0000000000a1/%' $$,
  $$ values ('d2293000-0000-0000-0000-0000000000a1/orphan1.jpg'::text),
            ('d2293000-0000-0000-0000-0000000000a1/orphan2.jpg'::text) $$,
  'backstop returns only unreferenced route-photos objects last written over 24 hours ago');

-- ── 5-6: limit clamp ───────────────────────────────────────────────────────
select is(
  (select count(*)::int from public.route_photo_orphan_paths(null, 1)),
  1,
  'p_limit 1 returns one path');

select is(
  (select count(*)::int from public.route_photo_orphan_paths(null, 0)),
  1,
  'p_limit 0 is clamped to 1, never read as unbounded');

-- ── 7: paths mode ──────────────────────────────────────────────────────────
select results_eq(
  $$ select p from public.route_photo_orphan_paths(array[
       'd2293000-0000-0000-0000-0000000000a1/live.jpg',
       'd2293000-0000-0000-0000-0000000000a1/live_512.jpg',
       'd2293000-0000-0000-0000-0000000000a1/d2293000-0000-0000-0000-0000000000f9.jpg',
       'd2293000-0000-0000-0000-0000000000a1/fresh.jpg',
       'd2293000-0000-0000-0000-0000000000a1/never-uploaded.jpg']) as p $$,
  $$ values ('d2293000-0000-0000-0000-0000000000a1/fresh.jpg'::text) $$,
  'paths mode returns the handed paths that exist and are unreferenced, with no grace');

-- ── 8-9: nightly enqueue ───────────────────────────────────────────────────
select public.enqueue_route_photo_orphan_sweep();

select is(
  (select count(*)::int from public.jobs
    where kind = 'route_photo_orphan_sweep' and payload = '{}'::jsonb and status = 'queued'),
  1,
  'the nightly enqueue queues one backstop job');

select public.enqueue_route_photo_orphan_sweep();

select is(
  (select count(*)::int from public.jobs
    where kind = 'route_photo_orphan_sweep' and payload = '{}'::jsonb and status in ('queued', 'running')),
  1,
  'a second enqueue while one is queued adds nothing');

-- ── 10-12: delete trigger ──────────────────────────────────────────────────
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"d2293000-0000-0000-0000-0000000000a1","role":"authenticated"}';
delete from routes where id = 'd2293000-0000-0000-0000-0000000000b1';
reset role;

select is(
  (select count(*)::int from public.jobs
    where kind = 'route_photo_orphan_sweep' and payload ? 'paths'),
  1,
  'deleting a route whose photos cascade queues one paths job');

select set_eq(
  $$ select jsonb_array_elements_text(payload -> 'paths') from public.jobs
      where kind = 'route_photo_orphan_sweep' and payload ? 'paths' $$,
  array['d2293000-0000-0000-0000-0000000000a1/live.jpg',
        'd2293000-0000-0000-0000-0000000000a1/live_512.jpg'],
  'the job holds the original and thumb paths, not the placeholder''s empty path');

select set_eq(
  $$ select p from public.route_photo_orphan_paths(
       (select array(select jsonb_array_elements_text(payload -> 'paths'))
          from public.jobs where kind = 'route_photo_orphan_sweep' and payload ? 'paths')) as p $$,
  $$ values ('d2293000-0000-0000-0000-0000000000a1/live.jpg'::text),
            ('d2293000-0000-0000-0000-0000000000a1/live_512.jpg'::text) $$,
  'the deleted photo''s paths are on the worklist once its row is gone');

-- ── 13: a delete that removes no photo ─────────────────────────────────────
delete from routes where id = 'd2293000-0000-0000-0000-0000000000b2';

select is(
  (select count(*)::int from public.jobs
    where kind = 'route_photo_orphan_sweep' and payload ? 'paths'),
  1,
  'a delete that cascades no photo queues nothing');

-- ── 14-15: grants ──────────────────────────────────────────────────────────
set local role anon;
select throws_ok(
  $$ select * from public.route_photo_orphan_paths() $$,
  '42501', null,
  'anon cannot read the orphan worklist');
reset role;

set local role authenticated;
select throws_ok(
  $$ select * from public.route_photo_orphan_paths() $$,
  '42501', null,
  'authenticated cannot read the orphan worklist');
reset role;

-- ── 16: one statement, several cascades ────────────────────────────────────
-- The whole test is one transaction, so the paths job test 10 queued is the
-- one every later firing appends to. These are superuser writes, so the
-- owner's claims from test 10 are cleared first.
set local "request.jwt.claims" = '{}';
insert into routes (id, user_id, name, waypoints, distance_m, is_public)
select ('d2293000-0000-0000-0000-0000000000c' || n)::uuid,
       'd2293000-0000-0000-0000-0000000000a1', 'Cascade ' || n,
       '[{"lat":51.5,"lng":-0.1},{"lat":51.51,"lng":-0.11}]'::jsonb, 5000, true
  from generate_series(1, 5) n;

insert into route_photos (route_id, owner_id, storage_path)
values ('d2293000-0000-0000-0000-0000000000c1', 'd2293000-0000-0000-0000-0000000000a1',
        'd2293000-0000-0000-0000-0000000000a1/c1.jpg'),
       ('d2293000-0000-0000-0000-0000000000c2', 'd2293000-0000-0000-0000-0000000000a1',
        'd2293000-0000-0000-0000-0000000000a1/c2.jpg');

delete from routes where id in ('d2293000-0000-0000-0000-0000000000c1',
                                'd2293000-0000-0000-0000-0000000000c2');

select results_eq(
  $$ select count(*)::int, sum(jsonb_array_length(payload -> 'paths'))::int from public.jobs
      where kind = 'route_photo_orphan_sweep' and payload ? 'paths' $$,
  $$ values (1, 4) $$,
  'two routes deleted in one statement append their photos to the one queued paths job');

-- ── 17-18: the 1000-path cap ───────────────────────────────────────────────
insert into route_photos (route_id, owner_id, storage_path)
select case when n <= 600 then 'd2293000-0000-0000-0000-0000000000c3'::uuid
            else 'd2293000-0000-0000-0000-0000000000c4'::uuid end,
       'd2293000-0000-0000-0000-0000000000a1',
       'd2293000-0000-0000-0000-0000000000a1/bulk-' || n || '.jpg'
  from generate_series(1, 1100) n;

delete from routes where id in ('d2293000-0000-0000-0000-0000000000c3',
                                'd2293000-0000-0000-0000-0000000000c4');

select results_eq(
  $$ select jsonb_array_length(payload -> 'paths') from public.jobs
      where kind = 'route_photo_orphan_sweep' and payload ? 'paths' order by id $$,
  $$ values (1000), (104) $$,
  'past 1000 paths the job is filled and one more is started');

select is(
  (select count(distinct p)::int from public.jobs j,
          jsonb_array_elements_text(j.payload -> 'paths') p
    where j.kind = 'route_photo_orphan_sweep'),
  1104,
  'every cascaded path is queued exactly once');

-- ── 19-20: a failed enqueue never aborts the delete ────────────────────────
-- A CHECK no sweep job can pass, added NOT VALID so the rows above stay put:
-- both the append and the insert now raise inside the trigger.
alter table public.jobs
  add constraint test_reject_sweep check (kind <> 'route_photo_orphan_sweep') not valid;

insert into route_photos (id, route_id, owner_id, storage_path)
values ('d2293000-0000-0000-0000-0000000000fa', 'd2293000-0000-0000-0000-0000000000c5',
        'd2293000-0000-0000-0000-0000000000a1', 'd2293000-0000-0000-0000-0000000000a1/fails.jpg');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"d2293000-0000-0000-0000-0000000000a1","role":"authenticated"}';
select lives_ok(
  $$ delete from route_photos where id = 'd2293000-0000-0000-0000-0000000000fa' $$,
  'the owner''s photo delete succeeds although its enqueue fails');
reset role;

select results_eq(
  $$ select (select count(*)::int from route_photos where id = 'd2293000-0000-0000-0000-0000000000fa'),
            (select count(distinct p)::int from public.jobs j,
                    jsonb_array_elements_text(j.payload -> 'paths') p
              where j.kind = 'route_photo_orphan_sweep') $$,
  $$ values (0, 1104) $$,
  'the row is gone and the failed enqueue queued nothing, leaving the bytes to the backstop');

alter table public.jobs drop constraint test_reject_sweep;

select * from finish();
rollback;

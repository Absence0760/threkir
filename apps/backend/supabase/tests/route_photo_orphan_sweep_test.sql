-- Pins the route-photo orphan sweep (migration 20271106000020, decisions
-- § 2305): which `route-photos` objects the worklist hands the Go worker,
-- that the gate keeps it empty and enqueues nothing while off, that a
-- transaction's route_photos deletes are buffered and written at commit as
-- ceil(paths / 1000) jobs, each written once, and that a failed enqueue never
-- aborts the delete.
--
-- The whole file is one transaction that rolls back, so the deferred flush
-- never reaches a commit. pg_temp.commit_sweep() stands in for it: setting
-- the constraint trigger IMMEDIATE fires its pending events retroactively,
-- exactly as commit would, and setting it back to DEFERRED lets the next
-- section buffer again.
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
--   10-12. Deleting the route as its owner queues ONE paths job at commit,
--          holding the cascaded photos' original and thumb paths (no
--          placeholder ''), and those paths are now on the worklist.
--   13.    A delete that removes no photo queues nothing.
--   14-15. anon and authenticated cannot call the worklist.
--   16.    Two routes deleted in one statement (two cascaded firings) and a
--          photo deleted in another statement are one job at commit.
--   17-20. 1,500 paths cascaded from 15 of 25 routes, one statement each, are
--          two jobs (1000, 500), every path once; the jobs table took two
--          inserts and no update, so no payload was rewritten per firing;
--          and the buffer is empty after the flush.
--   21.    A delete rolled back to a savepoint leaves nothing to flush.
--   22-23. With the enqueue made to fail, the photo delete still commits and
--          queues nothing.
--   24-25. A queued paths job another transaction committed, with this
--          transaction's timestamps, is left as it was: the paths go to a
--          job of their own.
--   26-29. The buffer cap: 2,500 single-photo deletes in one transaction
--          (2,500 statements) commit, and queue the first 2,000 paths as two
--          jobs, leaving the rest to the backstop; the count is reset by the
--          flush; and one statement of 2,500 photos, the shape of an account
--          deletion, is queued whole, because the cap is checked before a
--          statement appends.
--   30-31. A serialization failure or a deadlock inside the enqueue is not
--          swallowed: it aborts the commit so the caller retries the whole
--          transaction.

begin;
select plan(31);

create function pg_temp.commit_sweep() returns void language plpgsql as $f$
begin
  set constraints public.route_photos_flush_orphan_sweep immediate;
  set constraints public.route_photos_flush_orphan_sweep deferred;
end;
$f$;

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

insert into route_photos (id, route_id, owner_id, storage_path)
values ('d2293000-0000-0000-0000-0000000000f8', 'd2293000-0000-0000-0000-0000000000b1',
        'd2293000-0000-0000-0000-0000000000a1', 'd2293000-0000-0000-0000-0000000000a1/gate-off.jpg');

select public.enqueue_route_photo_orphan_sweep();
delete from route_photos where id = 'd2293000-0000-0000-0000-0000000000f8';
select pg_temp.commit_sweep();

select is(
  (select count(*)::int from public.jobs where kind = 'route_photo_orphan_sweep'),
  (select n from sweep_jobs_before),
  'gate off: neither the nightly enqueue nor a delete queues a job');

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
select pg_temp.commit_sweep();

select is(
  (select count(*)::int from public.jobs
    where kind = 'route_photo_orphan_sweep' and payload ? 'paths'),
  1,
  'deleting a route whose photos cascade queues one paths job at commit');

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
select pg_temp.commit_sweep();

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

-- ── 16: several statements, one job ────────────────────────────────────────
-- Each later section starts from no paths job, so its counts are its own.
-- These are superuser writes, so the owner's claims from test 10 are cleared.
set local "request.jwt.claims" = '{}';
delete from public.jobs where kind = 'route_photo_orphan_sweep' and payload ? 'paths';

insert into routes (id, user_id, name, waypoints, distance_m, is_public)
select ('d2293000-0000-0000-0000-0000000000' || to_char(n, 'FM00'))::uuid,
       'd2293000-0000-0000-0000-0000000000a1', 'Cascade ' || n,
       '[{"lat":51.5,"lng":-0.1},{"lat":51.51,"lng":-0.11}]'::jsonb, 5000, true
  from generate_series(10, 39) n;

insert into route_photos (id, route_id, owner_id, storage_path)
values ('d2293000-0000-0000-0000-0000000000e1', 'd2293000-0000-0000-0000-000000000010',
        'd2293000-0000-0000-0000-0000000000a1', 'd2293000-0000-0000-0000-0000000000a1/c10.jpg'),
       ('d2293000-0000-0000-0000-0000000000e2', 'd2293000-0000-0000-0000-000000000011',
        'd2293000-0000-0000-0000-0000000000a1', 'd2293000-0000-0000-0000-0000000000a1/c11.jpg'),
       ('d2293000-0000-0000-0000-0000000000e3', 'd2293000-0000-0000-0000-000000000012',
        'd2293000-0000-0000-0000-0000000000a1', 'd2293000-0000-0000-0000-0000000000a1/c12.jpg');

delete from routes where id in ('d2293000-0000-0000-0000-000000000010',
                                'd2293000-0000-0000-0000-000000000011');
delete from route_photos where id = 'd2293000-0000-0000-0000-0000000000e3';
select pg_temp.commit_sweep();

select results_eq(
  $$ select payload -> 'paths' from public.jobs
      where kind = 'route_photo_orphan_sweep' and payload ? 'paths' $$,
  $$ values ('["d2293000-0000-0000-0000-0000000000a1/c10.jpg",
               "d2293000-0000-0000-0000-0000000000a1/c11.jpg",
               "d2293000-0000-0000-0000-0000000000a1/c12.jpg"]'::jsonb) $$,
  'two cascaded firings and a later statement are one job at commit, paths sorted');

-- ── 17-20: ceil(paths / 1000) jobs, each written once (under the cap) ──────────────────────
delete from public.jobs where kind = 'route_photo_orphan_sweep' and payload ? 'paths';

insert into route_photos (route_id, owner_id, storage_path)
select ('d2293000-0000-0000-0000-0000000000' || to_char(15 + (n - 1) / 100, 'FM00'))::uuid,
       'd2293000-0000-0000-0000-0000000000a1',
       'd2293000-0000-0000-0000-0000000000a1/bulk-' || n || '.jpg'
  from generate_series(1, 1500) n;

create temporary table jobs_writes_before as
  select n_tup_ins, n_tup_upd from pg_stat_xact_user_tables
   where schemaname = 'public' and relname = 'jobs';

do $d$
declare r int;
begin
  for r in 15..39 loop
    delete from routes where id = ('d2293000-0000-0000-0000-0000000000' || r)::uuid;
  end loop;
end;
$d$;
select pg_temp.commit_sweep();

select results_eq(
  $$ select jsonb_array_length(payload -> 'paths') from public.jobs
      where kind = 'route_photo_orphan_sweep' and payload ? 'paths' order by id $$,
  $$ values (1000), (500) $$,
  '1,500 paths cascaded from 15 routes are two jobs of at most 1000');

select results_eq(
  $$ select count(*)::int, count(distinct p)::int from public.jobs j,
            jsonb_array_elements_text(j.payload -> 'paths') p
      where j.kind = 'route_photo_orphan_sweep' $$,
  $$ values (1500, 1500) $$,
  'every cascaded path is queued exactly once');

select results_eq(
  $$ select s.n_tup_ins - b.n_tup_ins, s.n_tup_upd - b.n_tup_upd
       from pg_stat_xact_user_tables s, jobs_writes_before b
      where s.schemaname = 'public' and s.relname = 'jobs' $$,
  $$ values (2::bigint, 0::bigint) $$,
  'the 25 statements wrote two job rows and rewrote none');

select is(
  current_setting('threkir.route_photo_orphan_sweep_paths', true),
  '',
  'the flush empties the buffer, so no later firing writes the paths again');

-- ── 21: a rolled-back delete leaves nothing to flush ───────────────────────
delete from public.jobs where kind = 'route_photo_orphan_sweep' and payload ? 'paths';

insert into route_photos (id, route_id, owner_id, storage_path)
values ('d2293000-0000-0000-0000-0000000000fd', 'd2293000-0000-0000-0000-000000000012',
        'd2293000-0000-0000-0000-0000000000a1', 'd2293000-0000-0000-0000-0000000000a1/kept.jpg');

savepoint before_delete;
delete from route_photos where id = 'd2293000-0000-0000-0000-0000000000fd';
rollback to savepoint before_delete;
select pg_temp.commit_sweep();

select is(
  (select count(*)::int from public.jobs
    where kind = 'route_photo_orphan_sweep' and payload ? 'paths'),
  0,
  'a delete rolled back to a savepoint queues nothing at commit');

-- ── 22-23: a failed enqueue never aborts the delete ────────────────────────
-- A CHECK no sweep job can pass, added NOT VALID so the backstop row stays
-- put: the flush's insert now raises inside the trigger.
alter table public.jobs
  add constraint test_reject_sweep check (kind <> 'route_photo_orphan_sweep') not valid;

insert into route_photos (id, route_id, owner_id, storage_path)
values ('d2293000-0000-0000-0000-0000000000fa', 'd2293000-0000-0000-0000-000000000012',
        'd2293000-0000-0000-0000-0000000000a1', 'd2293000-0000-0000-0000-0000000000a1/fails.jpg');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"d2293000-0000-0000-0000-0000000000a1","role":"authenticated"}';
delete from route_photos where id = 'd2293000-0000-0000-0000-0000000000fa';
reset role;
set local "request.jwt.claims" = '{}';

select lives_ok(
  $$ select pg_temp.commit_sweep() $$,
  'the owner''s photo delete commits although its enqueue fails');

select results_eq(
  $$ select (select count(*)::int from route_photos where id = 'd2293000-0000-0000-0000-0000000000fa'),
            (select count(*)::int from public.jobs
              where kind = 'route_photo_orphan_sweep' and payload ? 'paths') $$,
  $$ values (0, 0) $$,
  'the row is gone and the failed enqueue queued nothing, leaving the bytes to the backstop');

alter table public.jobs drop constraint test_reject_sweep;

-- ── 24-25: another transaction's job is never touched ──────────────────────
-- Inserted here by hand, so its created_at and scheduled_at are this
-- transaction's now(), exactly as a job committed by a concurrent transaction
-- that started in the same microsecond would read.
insert into public.jobs (kind, payload, max_attempts)
values ('route_photo_orphan_sweep', '{"paths":["someone-else/x.jpg"]}'::jsonb, 3);

insert into route_photos (id, route_id, owner_id, storage_path)
values ('d2293000-0000-0000-0000-0000000000fb', 'd2293000-0000-0000-0000-000000000012',
        'd2293000-0000-0000-0000-0000000000a1', 'd2293000-0000-0000-0000-0000000000a1/own.jpg');
delete from route_photos where id = 'd2293000-0000-0000-0000-0000000000fb';
select pg_temp.commit_sweep();

select is(
  (select payload from public.jobs
    where kind = 'route_photo_orphan_sweep' and payload -> 'paths' ? 'someone-else/x.jpg'),
  '{"paths":["someone-else/x.jpg"]}'::jsonb,
  'a job another transaction queued is left exactly as it was');

select is(
  (select payload from public.jobs
    where kind = 'route_photo_orphan_sweep'
      and payload -> 'paths' ? 'd2293000-0000-0000-0000-0000000000a1/own.jpg'),
  '{"paths":["d2293000-0000-0000-0000-0000000000a1/own.jpg"]}'::jsonb,
  'the path goes to a job of its own');

-- ── 26-29: the buffer is capped per transaction, never per statement ──────
delete from public.jobs where kind = 'route_photo_orphan_sweep' and payload ? 'paths';

insert into route_photos (route_id, owner_id, storage_path)
select 'd2293000-0000-0000-0000-000000000012', 'd2293000-0000-0000-0000-0000000000a1',
       'd2293000-0000-0000-0000-0000000000a1/cap-' || to_char(n, 'FM0000') || '.jpg'
  from generate_series(1, 2500) n;

select lives_ok(
  $$ do $d$
     declare n int;
     begin
       for n in 1..2500 loop
         delete from route_photos
          where storage_path = 'd2293000-0000-0000-0000-0000000000a1/cap-' || to_char(n, 'FM0000') || '.jpg';
       end loop;
     end;
     $d$;
     select pg_temp.commit_sweep() $$,
  '2,500 single-photo delete statements in one transaction commit past the cap');

select results_eq(
  $$ select (select count(*)::int from route_photos where storage_path like '%/cap-%'),
            (select count(*)::int from public.jobs
              where kind = 'route_photo_orphan_sweep' and payload ? 'paths'),
            (select count(*)::int from public.jobs j, jsonb_array_elements_text(j.payload -> 'paths') p
              where j.kind = 'route_photo_orphan_sweep' and p <= 'd2293000-0000-0000-0000-0000000000a1/cap-2000.jpg'),
            (select count(*)::int from public.jobs j, jsonb_array_elements_text(j.payload -> 'paths') p
              where j.kind = 'route_photo_orphan_sweep') $$,
  $$ values (0, 2, 2000, 2000) $$,
  'every row is gone, and the first 2,000 paths are two jobs; the rest wait for the backstop');

select is(
  current_setting('threkir.route_photo_orphan_sweep_count', true),
  '',
  'the flush resets the count, so the next transaction starts under the cap');

delete from public.jobs where kind = 'route_photo_orphan_sweep' and payload ? 'paths';

insert into route_photos (route_id, owner_id, storage_path)
select 'd2293000-0000-0000-0000-000000000012', 'd2293000-0000-0000-0000-0000000000a1',
       'd2293000-0000-0000-0000-0000000000a1/whole-' || n || '.jpg'
  from generate_series(1, 2500) n;
delete from route_photos where storage_path like 'd2293000-0000-0000-0000-0000000000a1/whole-%';
select pg_temp.commit_sweep();

select results_eq(
  $$ select jsonb_array_length(payload -> 'paths') from public.jobs
      where kind = 'route_photo_orphan_sweep' and payload ? 'paths' order by id $$,
  $$ values (1000), (1000), (500) $$,
  'one statement of 2,500 photos is queued whole: the cap never cuts a statement short');

-- ── 30-31: class 40 errors propagate ───────────────────────────────────────
create function pg_temp.raise_class_40() returns trigger language plpgsql as $f$
begin
  if new.kind = 'route_photo_orphan_sweep' then
    raise exception 'injected' using errcode = current_setting('test.sqlstate');
  end if;
  return new;
end;
$f$;
create trigger test_raise_class_40 before insert or update on public.jobs
  for each row execute function pg_temp.raise_class_40();

insert into route_photos (id, route_id, owner_id, storage_path)
values ('d2293000-0000-0000-0000-0000000000fc', 'd2293000-0000-0000-0000-000000000012',
        'd2293000-0000-0000-0000-0000000000a1', 'd2293000-0000-0000-0000-0000000000a1/retry.jpg');
delete from route_photos where id = 'd2293000-0000-0000-0000-0000000000fc';

-- throws_ok runs its statement in a subtransaction, so the failed flush is
-- undone with it: the buffer and the pending event are back for the second.
set local test.sqlstate = '40001';
select throws_ok(
  $$ select pg_temp.commit_sweep() $$,
  '40001', null,
  'a serialization failure in the enqueue aborts the commit for a retry');

set local test.sqlstate = '40P01';
select throws_ok(
  $$ select pg_temp.commit_sweep() $$,
  '40P01', null,
  'a deadlock in the enqueue aborts the commit for a retry');

drop trigger test_raise_class_40 on public.jobs;

select * from finish();
rollback;

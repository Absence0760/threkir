-- Pin the audit/storage thumb_512_path lockdown added by
-- 20260915_002. Three surface invariants:
--   1. CHECK constraint rejects a thumb_512_path that doesn't start
--      with the row's owner_id (prevents cross-user path injection
--      that would then be approved by the read policy). Exercised as
--      service_role: since 20270820000001 the race-gallery guard refuses
--      ANY client-set thumb_512_path at INSERT with 42501 before the
--      CHECK is consulted, so the CHECK is reachable — and still
--      load-bearing — only for the privileged writers that guard admits.
--   2. A client cannot set thumb_512_path at INSERT at all, even under
--      its own prefix: the photo worker writes it, and a client-set
--      value would pass the raw original off as the re-encoded thumbnail.
--   3. The block-thumb-update trigger rejects user-side UPDATEs of
--      thumb_512_path (the column is service-role only by design;
--      the worker writes it once the thumbnail job runs).
--
-- Positive controls confirm legitimate paths still work:
--   4. A client INSERT with a NULL thumb_512_path is accepted.
--   5. service_role can UPDATE thumb_512_path (the trigger only
--      blocks the authenticated path).

begin;

select plan(5);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-00000000fa01', 'authenticated', 'authenticated',
   'thumb-victim@forge.local', '', now(), now()),
  ('00000000-0000-0000-0000-00000000fa02', 'authenticated', 'authenticated',
   'thumb-attacker@forge.local', '', now(), now());

-- A run owned by the attacker that the SELECT policy will approve
-- (the attacker is the owner). We need a real run row so the FK
-- to runs.id is satisfied and the trigger fires on a realistic
-- update path.
set local role service_role;

insert into runs (id, user_id, started_at, distance_m, duration_s, source, metadata)
values
  ('11111111-1111-1111-1111-111111111101',
   '00000000-0000-0000-0000-00000000fa02',
   now(), 5000, 1800, 'app', jsonb_build_object('activity_type', 'run'));

-- 1. CHECK: as the service role the INSERT guard lets through, insert a
--    row whose thumb_512_path sits under the victim's prefix. The
--    constraint must reject it (check_violation, 23514); the message names
--    the constraint so no other refusal can stand in for it.
select throws_ok(
  $$ insert into run_photos
       (id, run_id, owner_id, storage_path, thumb_512_path)
     values
       (gen_random_uuid(),
        '11111111-1111-1111-1111-111111111101',
        '00000000-0000-0000-0000-00000000fa02',
        '00000000-0000-0000-0000-00000000fa02/photo.jpg',
        '00000000-0000-0000-0000-00000000fa01/stolen.jpg') $$,
  '23514',
  'new row for relation "run_photos" violates check constraint "run_photos_thumb_512_path_shape"',
  'CHECK rejects a thumb_512_path that does not start with the owner_id'
);

-- ── Switch to attacker ──
set local role authenticated;
set local "request.jwt.claims" =
  '{"sub":"00000000-0000-0000-0000-00000000fa02","role":"authenticated"}';

-- 2. A client may not set thumb_512_path at INSERT, even one under its
--    own prefix that the CHECK would accept.
select throws_ok(
  $$ insert into run_photos
       (id, run_id, owner_id, storage_path, thumb_512_path)
     values
       (gen_random_uuid(),
        '11111111-1111-1111-1111-111111111101',
        '00000000-0000-0000-0000-00000000fa02',
        '00000000-0000-0000-0000-00000000fa02/photo.jpg',
        '00000000-0000-0000-0000-00000000fa02/thumb.jpg') $$,
  '42501',
  'thumb_512_path is written by the photo worker only',
  'a client cannot set thumb_512_path at INSERT — the photo worker writes it'
);

-- 3. Insert a legitimate row (proper prefix + no thumb yet) so the
--    next tests have a row to UPDATE.
do $$
begin
  insert into run_photos
    (id, run_id, owner_id, storage_path, thumb_512_path)
  values
    ('22222222-2222-2222-2222-222222222201',
     '11111111-1111-1111-1111-111111111101',
     '00000000-0000-0000-0000-00000000fa02',
     '00000000-0000-0000-0000-00000000fa02/original.jpg',
     null);
end $$;
select pass('legitimate INSERT with NULL thumb_512_path accepted');

-- 4. Owner-side UPDATE of thumb_512_path is rejected (the
--    block-thumb-update trigger fires).
select throws_ok(
  $$ update run_photos
        set thumb_512_path = '00000000-0000-0000-0000-00000000fa02/thumb.jpg'
      where id = '22222222-2222-2222-2222-222222222201' $$,
  '42501',
  null,
  'owner cannot UPDATE thumb_512_path — service-role only column'
);

-- 5. Service role can UPDATE the same column (worker / thumbnail
--    job path).
set local role service_role;
reset "request.jwt.claims";

do $$
begin
  update run_photos
     set thumb_512_path = '00000000-0000-0000-0000-00000000fa02/thumb.jpg'
   where id = '22222222-2222-2222-2222-222222222201';
end $$;
select pass('service_role can UPDATE thumb_512_path (worker path)');

select * from finish();
rollback;

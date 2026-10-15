-- Pins migration 20270820000001 (decisions § 1961): a runner's photo reaches
-- the public, indexed race-listing page only by the owner's per-photo opt-in,
-- and only while every read-time rule holds — its run is public and linked to
-- THIS listing, the worker has produced the stripped thumbnail, it is not
-- hidden, and its owner is not shadow-hidden. The opt-in is written by the
-- owner through set_run_photo_race_gallery and by nothing else.
--
-- Every read below names the exact set a viewer gets, so each exclusion is
-- pinned by a photo that is present in the fixture and absent from the answer.

begin;
select plan(23);

insert into auth.users (id, email, encrypted_password, email_confirmed_at,
                        instance_id, aud, role)
values
  ('99999999-9999-9999-9999-99991961a001', 'ada-1961@example.com', '', now(),
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('99999999-9999-9999-9999-99991961a002', 'ben-1961@example.com', '', now(),
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('99999999-9999-9999-9999-99991961a003', 'out-1961@example.com', '', now(),
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('99999999-9999-9999-9999-99991961a004', 'hid-1961@example.com', '', now(),
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated')
on conflict (id) do nothing;

insert into user_profiles (id, display_name) values
  ('99999999-9999-9999-9999-99991961a001', 'Ada 1961'),
  ('99999999-9999-9999-9999-99991961a002', 'Ben 1961'),
  ('99999999-9999-9999-9999-99991961a003', 'Out 1961'),
  ('99999999-9999-9999-9999-99991961a004', 'Hid 1961')
on conflict (id) do update set display_name = excluded.display_name;

update user_profiles set shadow_hidden = true
 where id = '99999999-9999-9999-9999-99991961a004';

insert into race_listings (id, provider, provider_race_id, name, race_date, distance_m)
values
  ('22222222-0000-0000-0000-000000019611', 'runsignup', 'rs-1961-1',
   'Gallery Half 1961', '2026-06-01', 21097),
  ('22222222-0000-0000-0000-000000019612', 'runsignup', 'rs-1961-2',
   'Other 10K 1961', '2026-06-08', 10000),
  ('22222222-0000-0000-0000-000000019613', 'runsignup', 'rs-1961-3',
   'Crowded Marathon 1961', '2026-06-15', 42195);

insert into runs (id, user_id, started_at, distance_m, duration_s, source, is_public,
                  race_listing_id, metadata)
values
  -- Ada's public run of the half: the one run whose photos may appear.
  ('aaaaaaaa-0000-0000-0000-0000001961f1', '99999999-9999-9999-9999-99991961a001',
   '2026-06-01T08:00:00Z', 21097, 6000, 'app', true,
   '22222222-0000-0000-0000-000000019611', '{"activity_type":"run"}'),
  -- Ada's PRIVATE run linked to the same half.
  ('aaaaaaaa-0000-0000-0000-0000001961f2', '99999999-9999-9999-9999-99991961a001',
   '2026-06-01T09:00:00Z', 21097, 6000, 'app', false,
   '22222222-0000-0000-0000-000000019611', '{"activity_type":"run"}'),
  -- Ada's public run linked to a DIFFERENT listing.
  ('aaaaaaaa-0000-0000-0000-0000001961f3', '99999999-9999-9999-9999-99991961a001',
   '2026-06-08T08:00:00Z', 10000, 2700, 'app', true,
   '22222222-0000-0000-0000-000000019612', '{"activity_type":"run"}'),
  -- Ben's public run of the half.
  ('aaaaaaaa-0000-0000-0000-0000001961f4', '99999999-9999-9999-9999-99991961a002',
   '2026-06-01T08:00:00Z', 21097, 6300, 'app', true,
   '22222222-0000-0000-0000-000000019611', '{"activity_type":"run"}'),
  -- A shadow-hidden runner's public run of the half.
  ('aaaaaaaa-0000-0000-0000-0000001961f5', '99999999-9999-9999-9999-99991961a004',
   '2026-06-01T08:00:00Z', 21097, 6400, 'app', true,
   '22222222-0000-0000-0000-000000019611', '{"activity_type":"run"}'),
  -- Ada's public marathon, carrying more photos than the cap.
  ('aaaaaaaa-0000-0000-0000-0000001961f6', '99999999-9999-9999-9999-99991961a001',
   '2026-06-15T08:00:00Z', 42195, 13000, 'app', true,
   '22222222-0000-0000-0000-000000019613', '{"activity_type":"run"}');

insert into run_photos (id, run_id, owner_id, storage_path, thumb_512_path, caption, created_at)
values
  ('11111111-0000-0000-0000-0000001961b1', 'aaaaaaaa-0000-0000-0000-0000001961f1',
   '99999999-9999-9999-9999-99991961a001', '99999999-9999-9999-9999-99991961a001/ok.jpg',
   '99999999-9999-9999-9999-99991961a001/ok_512.jpg', 'Mile 12', '2026-06-01T10:00:00Z'),
  ('11111111-0000-0000-0000-0000001961b2', 'aaaaaaaa-0000-0000-0000-0000001961f1',
   '99999999-9999-9999-9999-99991961a001', '99999999-9999-9999-9999-99991961a001/noopt.jpg',
   '99999999-9999-9999-9999-99991961a001/noopt_512.jpg', null, '2026-06-01T10:05:00Z'),
  ('11111111-0000-0000-0000-0000001961b3', 'aaaaaaaa-0000-0000-0000-0000001961f2',
   '99999999-9999-9999-9999-99991961a001', '99999999-9999-9999-9999-99991961a001/priv.jpg',
   '99999999-9999-9999-9999-99991961a001/priv_512.jpg', null, '2026-06-01T10:10:00Z'),
  ('11111111-0000-0000-0000-0000001961b4', 'aaaaaaaa-0000-0000-0000-0000001961f3',
   '99999999-9999-9999-9999-99991961a001', '99999999-9999-9999-9999-99991961a001/other.jpg',
   '99999999-9999-9999-9999-99991961a001/other_512.jpg', null, '2026-06-08T10:00:00Z'),
  ('11111111-0000-0000-0000-0000001961b5', 'aaaaaaaa-0000-0000-0000-0000001961f1',
   '99999999-9999-9999-9999-99991961a001', '99999999-9999-9999-9999-99991961a001/raw.jpg',
   null, null, '2026-06-01T10:15:00Z'),
  ('11111111-0000-0000-0000-0000001961b6', 'aaaaaaaa-0000-0000-0000-0000001961f1',
   '99999999-9999-9999-9999-99991961a001', '99999999-9999-9999-9999-99991961a001/hid.jpg',
   '99999999-9999-9999-9999-99991961a001/hid_512.jpg', null, '2026-06-01T10:20:00Z'),
  ('11111111-0000-0000-0000-0000001961b7', 'aaaaaaaa-0000-0000-0000-0000001961f4',
   '99999999-9999-9999-9999-99991961a002', '99999999-9999-9999-9999-99991961a002/ben.jpg',
   '99999999-9999-9999-9999-99991961a002/ben_512.jpg', null, '2026-06-01T11:00:00Z'),
  ('11111111-0000-0000-0000-0000001961b8', 'aaaaaaaa-0000-0000-0000-0000001961f5',
   '99999999-9999-9999-9999-99991961a004', '99999999-9999-9999-9999-99991961a004/sh.jpg',
   '99999999-9999-9999-9999-99991961a004/sh_512.jpg', null, '2026-06-01T11:05:00Z');

insert into run_photos (run_id, owner_id, storage_path, thumb_512_path, race_gallery)
select 'aaaaaaaa-0000-0000-0000-0000001961f6', '99999999-9999-9999-9999-99991961a001',
       '99999999-9999-9999-9999-99991961a001/m' || g || '.jpg',
       '99999999-9999-9999-9999-99991961a001/m' || g || '_512.jpg', true
  from generate_series(1, 65) g;

-- Opted in as the service side would see it; every photo but b2 (left for the
-- owner to share below).
update run_photos set race_gallery = true
 where id in ('11111111-0000-0000-0000-0000001961b1', '11111111-0000-0000-0000-0000001961b3',
              '11111111-0000-0000-0000-0000001961b4', '11111111-0000-0000-0000-0000001961b5',
              '11111111-0000-0000-0000-0000001961b6', '11111111-0000-0000-0000-0000001961b7',
              '11111111-0000-0000-0000-0000001961b8');

update run_photos set hidden_at = now()
 where id = '11111111-0000-0000-0000-0000001961b6';

-- A host photo: run-less, on an occurrence Ada hosts.
insert into clubs (id, owner_id, name, slug, is_public, join_policy)
values ('dddddddd-0000-0000-0000-00000001961c', '99999999-9999-9999-9999-99991961a001',
        'Race Club 1961', 'race-club-1961', true, 'open');

insert into events (id, club_id, title, starts_at, author_id, host_user_id)
values ('eeeeeeee-0000-0000-0000-0000000196e9', 'dddddddd-0000-0000-0000-00000001961c',
        'Half shakeout 1961', '2026-06-01T07:00:00Z',
        '99999999-9999-9999-9999-99991961a001', '99999999-9999-9999-9999-99991961a001');

insert into run_photos (id, owner_id, storage_path, thumb_512_path, event_id, event_instance_start)
values ('11111111-0000-0000-0000-0000001961b9', '99999999-9999-9999-9999-99991961a001',
        '99999999-9999-9999-9999-99991961a001/host.jpg',
        '99999999-9999-9999-9999-99991961a001/host_512.jpg',
        'eeeeeeee-0000-0000-0000-0000000196e9', '2026-06-01T07:00:00Z');

-- ── the read's shape: no run id, no owner id ──
select ok(
  not exists (
    select 1
      from pg_proc p, unnest(p.proargnames, p.proargmodes::text[]) as a(name, mode)
     where p.oid = 'public.race_listing_photos(uuid, int)'::regprocedure
       and a.mode = 't' and a.name = 'run_id'),
  'race_listing_photos never returns run_id');

select ok(
  not exists (
    select 1
      from pg_proc p, unnest(p.proargnames, p.proargmodes::text[]) as a(name, mode)
     where p.oid = 'public.race_listing_photos(uuid, int)'::regprocedure
       and a.mode = 't' and a.name = 'owner_id'),
  'race_listing_photos never returns owner_id');

select throws_ok($$
  update run_photos set race_gallery = true
   where id = '11111111-0000-0000-0000-0000001961b9'
$$, '23514', 'new row for relation "run_photos" violates check constraint "run_photos_race_gallery_needs_run"',
  'a run-less host photo cannot be shared to a race page, even by a privileged writer');

-- ── logged out ──
set local role anon;
set local "request.jwt.claims" = '{"role":"anon"}';

select is(
  (select array_agg(id::text order by id::text)
     from race_listing_photos('22222222-0000-0000-0000-000000019611')),
  array['11111111-0000-0000-0000-0000001961b1', '11111111-0000-0000-0000-0000001961b7'],
  'anon gets only opted-in, processed, unhidden photos on public runs linked to this listing — not the un-opted, private-run, other-listing, unprocessed, hidden or shadow-hidden ones');

select is(
  (select array_agg(p.id::text order by p.o)
     from race_listing_photos('22222222-0000-0000-0000-000000019611')
          with ordinality as p(id, thumb_512_path, caption, created_at, display_name, o)),
  array['11111111-0000-0000-0000-0000001961b7', '11111111-0000-0000-0000-0000001961b1'],
  'newest photo first');

select is(
  (select display_name || ' / ' || caption || ' / ' || thumb_512_path
     from race_listing_photos('22222222-0000-0000-0000-000000019611')
    where id = '11111111-0000-0000-0000-0000001961b1'),
  'Ada 1961 / Mile 12 / 99999999-9999-9999-9999-99991961a001/ok_512.jpg',
  'a photo carries its uploader''s display name, caption and thumbnail path');

select is(
  (select array_agg(id::text)
     from race_listing_photos('22222222-0000-0000-0000-000000019612')),
  array['11111111-0000-0000-0000-0000001961b4'],
  'a photo appears under the listing its run is linked to');

select is(
  (select count(*)::int from race_listing_photos('22222222-0000-0000-0000-000000019613', 1000)),
  60, 'p_limit is capped at 60');

select is(
  (select count(*)::int from race_listing_photos('22222222-0000-0000-0000-000000019613')),
  24, 'the default page is 24');

select throws_ok($$
  select set_run_photo_race_gallery('11111111-0000-0000-0000-0000001961b2', true)
$$, '42501', 'permission denied for function set_run_photo_race_gallery',
  'anon cannot call set_run_photo_race_gallery (refused at the privilege, not in the body)');

-- ── the owner ──
reset role;
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"99999999-9999-9999-9999-99991961a001","role":"authenticated"}';

select throws_ok($$
  update run_photos set race_gallery = true
   where id = '11111111-0000-0000-0000-0000001961b2'
$$, '42501', 'run_photos.race_gallery is set through set_run_photo_race_gallery only',
  'the owner cannot share a photo by a direct UPDATE');

select throws_ok($$
  insert into run_photos (run_id, owner_id, storage_path, race_gallery)
  values ('aaaaaaaa-0000-0000-0000-0000001961f1', '99999999-9999-9999-9999-99991961a001',
          '99999999-9999-9999-9999-99991961a001/new.jpg', true)
$$, '42501', 'a photo is shared to its race page after upload, through set_run_photo_race_gallery',
  'a photo cannot be uploaded already shared');

select throws_ok($$
  insert into run_photos (run_id, owner_id, storage_path, thumb_512_path)
  values ('aaaaaaaa-0000-0000-0000-0000001961f1', '99999999-9999-9999-9999-99991961a001',
          '99999999-9999-9999-9999-99991961a001/raw.jpg',
          '99999999-9999-9999-9999-99991961a001/raw.jpg')
$$, '42501', 'thumb_512_path is written by the photo worker only',
  'a client cannot pass the raw original off as its processed thumbnail');

select throws_ok($$
  select set_run_photo_race_gallery('11111111-0000-0000-0000-0000001961b9', true)
$$, '42501', 'only the owner of a run photo can share it to the race page',
  'the owner of a run-less host photo cannot share it to a race page');

select throws_ok($$
  select set_run_photo_race_gallery('11111111-0000-0000-0000-0000001961b2', null)
$$, '22004', 'p_shared is required',
  'p_shared is required');

select lives_ok($$
  select set_run_photo_race_gallery('11111111-0000-0000-0000-0000001961b2', true)
$$, 'the owner shares a photo to the race page');

select lives_ok($$
  select set_run_photo_race_gallery('11111111-0000-0000-0000-0000001961b1', false)
$$, 'the owner withdraws a shared photo');

select is(
  (select array_agg(race_gallery order by id)
     from run_photos
    where id in ('11111111-0000-0000-0000-0000001961b1', '11111111-0000-0000-0000-0000001961b2')),
  array[false, true],
  'the share and the withdrawal both landed on race_gallery');

-- ── another runner ──
set local "request.jwt.claims" = '{"sub":"99999999-9999-9999-9999-99991961a002","role":"authenticated"}';

select throws_ok($$
  select set_run_photo_race_gallery('11111111-0000-0000-0000-0000001961b2', false)
$$, '42501', 'only the owner of a run photo can share it to the race page',
  'another user cannot withdraw someone else''s photo');

select is(
  (select race_gallery from run_photos where id = '11111111-0000-0000-0000-0000001961b2'),
  true, 'and the photo stays shared');

-- ── a viewer who blocked an uploader ──
reset role;
insert into user_blocks (blocker_id, blocked_id)
values ('99999999-9999-9999-9999-99991961a003', '99999999-9999-9999-9999-99991961a002');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"99999999-9999-9999-9999-99991961a003","role":"authenticated"}';

select is(
  (select array_agg(id::text order by id::text)
     from race_listing_photos('22222222-0000-0000-0000-000000019611')),
  array['11111111-0000-0000-0000-0000001961b2'],
  'a viewer does not see the photos of someone they blocked, and sees the owner''s share and withdrawal');

-- ── the run goes private ──
reset role;
update runs set is_public = false where id = 'aaaaaaaa-0000-0000-0000-0000001961f4';
update runs set is_public = false where id = 'aaaaaaaa-0000-0000-0000-0000001961f3';
update run_photos set race_gallery = true where id = '11111111-0000-0000-0000-0000001961b1';

set local role anon;
set local "request.jwt.claims" = '{"role":"anon"}';

select is(
  (select array_agg(id::text order by id::text)
     from race_listing_photos('22222222-0000-0000-0000-000000019611')),
  array['11111111-0000-0000-0000-0000001961b1', '11111111-0000-0000-0000-0000001961b2'],
  'making a run private takes its shared photos off the race page at once');

-- ── the run is unlinked from the race ──
reset role;
update runs set race_listing_id = '22222222-0000-0000-0000-000000019612'
 where id = 'aaaaaaaa-0000-0000-0000-0000001961f6';

set local role anon;
set local "request.jwt.claims" = '{"role":"anon"}';

select is(
  (select count(*)::int from race_listing_photos('22222222-0000-0000-0000-000000019612', 60)),
  60, 'a run re-linked to another race takes its shared photos with it');

select * from finish();
rollback;

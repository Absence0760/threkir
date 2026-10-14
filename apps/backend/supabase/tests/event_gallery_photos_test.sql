-- Pins migration 20270807000003 (decisions § 1906): the event gallery read
-- drops a hidden photo for everyone but its owner and the event's stewards,
-- even when the photo sits on a PUBLIC run — whose run-path SELECT policy
-- still returns the row, so the photo stays on the runner's own run.

begin;
select plan(9);

insert into auth.users (id, email, encrypted_password, email_confirmed_at,
                        instance_id, aud, role)
values
  ('99999999-9999-9999-9999-99991906a001', 'org-1906@example.com', '', now(),
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('99999999-9999-9999-9999-99991906a003', 'att-1906@example.com', '', now(),
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('99999999-9999-9999-9999-99991906a004', 'out-1906@example.com', '', now(),
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated')
on conflict (id) do nothing;

insert into clubs (id, owner_id, name, slug, is_public, join_policy)
values ('dddddddd-0000-0000-0000-00000001906c',
        '99999999-9999-9999-9999-99991906a001',
        'Gallery Club 1906', 'gallery-club-1906', true, 'open');

insert into events (id, club_id, title, starts_at, author_id)
values ('eeeeeeee-0000-0000-0000-0000000196e1',
        'dddddddd-0000-0000-0000-00000001906c',
        'Gallery 10K', '2026-06-20T08:00:00Z',
        '99999999-9999-9999-9999-99991906a001');

-- A PUBLIC run: the case 20270807000001's policy change could not reach.
insert into runs (id, user_id, started_at, distance_m, duration_s, source, is_public, metadata)
values ('aaaaaaaa-0000-0000-0000-0000001906f1', '99999999-9999-9999-9999-99991906a003',
        '2026-06-20T08:03:00Z', 10000, 2700, 'app', true, '{"activity_type":"run"}');

insert into run_photos (id, run_id, owner_id, storage_path, event_id, event_instance_start)
values
  ('11111111-0000-0000-0000-0000001906a1', 'aaaaaaaa-0000-0000-0000-0000001906f1',
   '99999999-9999-9999-9999-99991906a003', '99999999-9999-9999-9999-99991906a003/a.jpg',
   'eeeeeeee-0000-0000-0000-0000000196e1', '2026-06-20T08:00:00Z'),
  ('11111111-0000-0000-0000-0000001906a2', 'aaaaaaaa-0000-0000-0000-0000001906f1',
   '99999999-9999-9999-9999-99991906a003', '99999999-9999-9999-9999-99991906a003/b.jpg',
   'eeeeeeee-0000-0000-0000-0000000196e1', '2026-06-20T08:00:00Z');

set local role authenticated;

-- ── the organiser hides one ──
set local "request.jwt.claims" = '{"sub":"99999999-9999-9999-9999-99991906a001","role":"authenticated"}';

select lives_ok($$
  select set_event_photo_hidden('11111111-0000-0000-0000-0000001906a1', true)
$$, 'the organiser hides a photo on a public run');

select is(
  (select count(*)::int from event_gallery_photos('eeeeeeee-0000-0000-0000-0000000196e1', '2026-06-20T08:00:00Z')),
  2, 'a steward''s gallery keeps the hidden photo, to restore it');

-- ── an outsider ──
set local "request.jwt.claims" = '{"sub":"99999999-9999-9999-9999-99991906a004","role":"authenticated"}';

select is(
  (select array_agg(id::text order by id)
     from event_gallery_photos('eeeeeeee-0000-0000-0000-0000000196e1', '2026-06-20T08:00:00Z')),
  array['11111111-0000-0000-0000-0000001906a2'],
  'an outsider''s gallery drops the hidden photo although its run is public');

select is(
  (select count(*)::int from run_photos where run_id = 'aaaaaaaa-0000-0000-0000-0000001906f1'),
  2, 'the hidden photo stays on the runner''s public run');

-- ── the owner ──
set local "request.jwt.claims" = '{"sub":"99999999-9999-9999-9999-99991906a003","role":"authenticated"}';

select is(
  (select count(*)::int from event_gallery_photos('eeeeeeee-0000-0000-0000-0000000196e1', '2026-06-20T08:00:00Z')),
  2, 'the owner still sees their hidden photo in the gallery');

select is(
  (select count(*)::int
     from event_gallery_photos('eeeeeeee-0000-0000-0000-0000000196e1', '2026-06-20T08:00:00Z')
    where hidden_at is not null),
  1, 'and the gallery marks it hidden');

-- ── logged out ──
reset role;
set local role anon;
set local "request.jwt.claims" = '{"role":"anon"}';

select is(
  (select count(*)::int from event_gallery_photos('eeeeeeee-0000-0000-0000-0000000196e1', '2026-06-20T08:00:00Z')),
  1, 'a logged-out viewer''s gallery drops the hidden photo');

-- ── restored ──
reset role;
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"99999999-9999-9999-9999-99991906a001","role":"authenticated"}';
select set_event_photo_hidden('11111111-0000-0000-0000-0000001906a1', false);

set local "request.jwt.claims" = '{"sub":"99999999-9999-9999-9999-99991906a004","role":"authenticated"}';

select is(
  (select count(*)::int from event_gallery_photos('eeeeeeee-0000-0000-0000-0000000196e1', '2026-06-20T08:00:00Z')),
  2, 'a restored photo returns to the outsider''s gallery');

select is(
  (select count(*)::int from event_gallery_photos('eeeeeeee-0000-0000-0000-0000000196e1', '2026-06-27T08:00:00Z')),
  0, 'the gallery is scoped to its occurrence');

select * from finish();
rollback;

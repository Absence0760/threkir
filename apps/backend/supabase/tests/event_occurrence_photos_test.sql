-- Pins migration 20270807000001 (issue #1150, decisions § 1904): run-less
-- host photos per occurrence, the organiser's soft hide, and the database's
-- integrity checks on attendee photos (real occurrence, run inside the
-- [occurrence − 2 h, occurrence + 24 h) window).

begin;
select plan(25);

insert into auth.users (id, email, encrypted_password, email_confirmed_at,
                        instance_id, aud, role)
values
  ('99999999-9999-9999-9999-99991150a001', 'org-1150@example.com', '', now(),
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('99999999-9999-9999-9999-99991150a002', 'host-1150@example.com', '', now(),
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('99999999-9999-9999-9999-99991150a003', 'att-1150@example.com', '', now(),
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('99999999-9999-9999-9999-99991150a004', 'out-1150@example.com', '', now(),
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated')
on conflict (id) do nothing;

-- Public club; the owner is enrolled as an 'owner' member by trigger.
insert into clubs (id, owner_id, name, slug, is_public, join_policy)
values ('dddddddd-0000-0000-0000-00000001150c',
        '99999999-9999-9999-9999-99991150a001',
        'Photo Club 1150', 'photo-club-1150', true, 'open');

-- One-off event (2026-06-20 08:00Z) with a named host who is NOT a member.
insert into events (id, club_id, title, starts_at, author_id, host_user_id)
values ('eeeeeeee-0000-0000-0000-0000000115e1',
        'dddddddd-0000-0000-0000-00000001150c',
        'One-off 10K', '2026-06-20T08:00:00Z',
        '99999999-9999-9999-9999-99991150a001',
        '99999999-9999-9999-9999-99991150a002');

-- Weekly Monday series anchored to UTC, six occurrences from 2026-06-01 07:00Z.
insert into events (id, club_id, title, starts_at, author_id, timezone,
                    recurrence_freq, recurrence_byday, recurrence_count)
values ('eeeeeeee-0000-0000-0000-0000000115e2',
        'dddddddd-0000-0000-0000-00000001150c',
        'Monday Club Run', '2026-06-01T07:00:00Z',
        '99999999-9999-9999-9999-99991150a001', 'UTC',
        'weekly', array['MO'], 6);

-- Attendee runs: one inside the one-off's window, one a month earlier.
insert into runs (id, user_id, started_at, distance_m, duration_s, source, is_public, metadata)
values
  ('aaaaaaaa-0000-0000-0000-0000001150f1', '99999999-9999-9999-9999-99991150a003',
   '2026-06-20T08:03:00Z', 10000, 2700, 'app', false, '{"activity_type":"run"}'),
  ('aaaaaaaa-0000-0000-0000-0000001150f2', '99999999-9999-9999-9999-99991150a003',
   '2026-05-20T08:00:00Z', 10000, 2700, 'app', false, '{"activity_type":"run"}');

-- ── the occurrence helper ──
select ok(private.is_event_occurrence('eeeeeeee-0000-0000-0000-0000000115e2', '2026-06-15T07:00:00Z'),
  'a weekly series accepts its third Monday');
select ok(not private.is_event_occurrence('eeeeeeee-0000-0000-0000-0000000115e2', '2026-06-16T07:00:00Z'),
  'a weekly series rejects a Tuesday');
select ok(not private.is_event_occurrence('eeeeeeee-0000-0000-0000-0000000115e2', '2026-06-15T07:30:00Z'),
  'a weekly series rejects the right day at the wrong time');
select ok(not private.is_event_occurrence('eeeeeeee-0000-0000-0000-0000000115e2', '2026-07-13T07:00:00Z'),
  'a count-capped series rejects its seventh Monday');
select ok(private.is_event_occurrence('eeeeeeee-0000-0000-0000-0000000115e2', '2026-07-06T07:00:00Z'),
  'a count-capped series accepts its sixth Monday');
select ok(not private.is_event_occurrence('eeeeeeee-0000-0000-0000-0000000115e1', '2026-06-27T08:00:00Z'),
  'a one-off event has exactly one occurrence');

-- ── as the attendee ──
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"99999999-9999-9999-9999-99991150a003","role":"authenticated"}';

select lives_ok($$
  insert into run_photos (id, run_id, owner_id, storage_path, event_id, event_instance_start)
  values ('11111111-0000-0000-0000-0000001150a1',
          'aaaaaaaa-0000-0000-0000-0000001150f1',
          '99999999-9999-9999-9999-99991150a003',
          '99999999-9999-9999-9999-99991150a003/in.jpg',
          'eeeeeeee-0000-0000-0000-0000000115e1', '2026-06-20T08:00:00Z')
$$, 'an attendee attaches a run that started during the occurrence');

select throws_ok($$
  insert into run_photos (run_id, owner_id, storage_path, event_id, event_instance_start)
  values ('aaaaaaaa-0000-0000-0000-0000001150f2',
          '99999999-9999-9999-9999-99991150a003',
          '99999999-9999-9999-9999-99991150a003/old.jpg',
          'eeeeeeee-0000-0000-0000-0000000115e1', '2026-06-20T08:00:00Z')
$$, '23514', null, 'a run from a month earlier is refused');

select throws_ok($$
  insert into run_photos (run_id, owner_id, storage_path, event_id, event_instance_start)
  values ('aaaaaaaa-0000-0000-0000-0000001150f1',
          '99999999-9999-9999-9999-99991150a003',
          '99999999-9999-9999-9999-99991150a003/fake.jpg',
          'eeeeeeee-0000-0000-0000-0000000115e1', '2026-06-20T08:30:00Z')
$$, '23514', null, 'an instant that is not an occurrence is refused');

select throws_ok($$
  insert into run_photos (owner_id, storage_path, event_id, event_instance_start)
  values ('99999999-9999-9999-9999-99991150a003',
          '99999999-9999-9999-9999-99991150a003/norun.jpg',
          'eeeeeeee-0000-0000-0000-0000000115e1', '2026-06-20T08:00:00Z')
$$, '42501', null, 'an attendee cannot post a photo without a run');

select throws_ok($$
  update run_photos set event_instance_start = '2026-06-27T08:00:00Z'
   where id = '11111111-0000-0000-0000-0000001150a1'
$$, '42501', null, 'the occurrence cannot be re-pointed after upload');

-- The owner's caption policy admits this UPDATE; the trigger refuses it.
select throws_ok($$
  update run_photos set hidden_at = now()
   where id = '11111111-0000-0000-0000-0000001150a1'
$$, '42501', null, 'hidden_at cannot be written directly, not even by the owner');

select is(
  (select can_steward_event_photos('eeeeeeee-0000-0000-0000-0000000115e1')),
  false, 'an attendee is not a steward');

-- ── as the host (named on the event, not a club member) ──
set local "request.jwt.claims" = '{"sub":"99999999-9999-9999-9999-99991150a002","role":"authenticated"}';

select lives_ok($$
  insert into run_photos (id, owner_id, storage_path, event_id, event_instance_start)
  values ('11111111-0000-0000-0000-0000001150b1',
          '99999999-9999-9999-9999-99991150a002',
          '99999999-9999-9999-9999-99991150a002/host.jpg',
          'eeeeeeee-0000-0000-0000-0000000115e1', '2026-06-20T08:00:00Z')
$$, 'the event host posts a photo with no run');

select is(
  (select can_steward_event_photos('eeeeeeee-0000-0000-0000-0000000115e1')),
  true, 'the host is a steward of their event');

-- ── as the outsider ──
set local "request.jwt.claims" = '{"sub":"99999999-9999-9999-9999-99991150a004","role":"authenticated"}';

select throws_ok($$
  insert into run_photos (owner_id, storage_path, event_id, event_instance_start)
  values ('99999999-9999-9999-9999-99991150a004',
          '99999999-9999-9999-9999-99991150a004/x.jpg',
          'eeeeeeee-0000-0000-0000-0000000115e1', '2026-06-20T08:00:00Z')
$$, '42501', null, 'a non-steward cannot post a run-less photo');

select is(
  (select count(*)::int from run_photos where event_id = 'eeeeeeee-0000-0000-0000-0000000115e1'),
  2, 'an outsider sees the attendee photo and the host photo before moderation');

select throws_ok($$
  select set_event_photo_hidden('11111111-0000-0000-0000-0000001150a1', true)
$$, '42501', null, 'a non-steward cannot hide a photo');

-- ── as the organiser (club owner) ──
set local "request.jwt.claims" = '{"sub":"99999999-9999-9999-9999-99991150a001","role":"authenticated"}';

select lives_ok($$
  insert into run_photos (owner_id, storage_path, event_id, event_instance_start)
  values ('99999999-9999-9999-9999-99991150a001',
          '99999999-9999-9999-9999-99991150a001/org.jpg',
          'eeeeeeee-0000-0000-0000-0000000115e2', '2026-06-15T07:00:00Z')
$$, 'an organiser posts a run-less photo to one occurrence of a series');

select lives_ok($$
  select set_event_photo_hidden('11111111-0000-0000-0000-0000001150a1', true)
$$, 'the organiser hides an attendee photo');

select is(
  (select hidden_by::text || ':' || (hidden_at is not null)::text
     from run_photos where id = '11111111-0000-0000-0000-0000001150a1'),
  '99999999-9999-9999-9999-99991150a001:true',
  'the hide stored hidden_at and the organiser as hidden_by');

select is(
  (select count(*)::int from run_photos where id = '11111111-0000-0000-0000-0000001150a1'),
  1, 'the organiser still sees the hidden photo, to restore it');

-- An organiser hides; they do not delete another runner's photo.
delete from run_photos where id = '11111111-0000-0000-0000-0000001150a1';

-- ── back to the outsider: the hidden photo is gone from the gallery ──
set local "request.jwt.claims" = '{"sub":"99999999-9999-9999-9999-99991150a004","role":"authenticated"}';

select is(
  (select count(*)::int from run_photos where event_id = 'eeeeeeee-0000-0000-0000-0000000115e1'),
  1, 'a hidden photo leaves the gallery for everyone else');

-- ── the attendee keeps their photo ──
set local "request.jwt.claims" = '{"sub":"99999999-9999-9999-9999-99991150a003","role":"authenticated"}';

select is(
  (select count(*)::int from run_photos where id = '11111111-0000-0000-0000-0000001150a1'),
  1, 'the hidden photo survives on its owner''s run (the organiser could not delete it)');

select throws_ok($$
  select set_event_photo_hidden('11111111-0000-0000-0000-0000001150b1', true)
$$, '42501', null, 'an attendee cannot hide someone else''s photo');

select * from finish();
rollback;

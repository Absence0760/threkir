-- Pins migrations 20271213001307-001308 (#1307, timing lines phase 4): the
-- server derives a gun-mode result's times from the crossings the device
-- claims, the normaliser clears them, the CHECKs hold, and the redacted view
-- shows the organiser how each result was timed and nobody else anything new.
--
--   1-4.   A gun-mode result with crossings: the gun time is finish_at - GO,
--          the chip time finish_at - start_at, duration_s the gun time,
--          whatever the device sent; the clock offset is kept.
--   5.     A device start before GO caps the chip time at the gun time.
--   6.     A finish before GO carries no gun time.
--   7.     A write with no finish_at keeps the device's numbers (§ 1850).
--   8-11.  event_results_redacted: the organiser reads the detections and the
--          review flag, the public reads none of them, and only the runner
--          reads the clock offset.
--   12-13. A DNF keeps no crossings or detections, and keeps the offset.
--   14.    A host edit clears the crossings, the detections and review.
--   15-17. The detection CHECKs, and finish_detection only beside 'auto'.

begin;
select plan(17);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('e7307000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
   'tl-owner@evt.local', '', now(), now()),
  ('e7307000-0000-0000-0000-000000000002', 'authenticated', 'authenticated',
   'tl-racer-a@evt.local', '', now(), now()),
  ('e7307000-0000-0000-0000-000000000003', 'authenticated', 'authenticated',
   'tl-racer-b@evt.local', '', now(), now()),
  ('e7307000-0000-0000-0000-000000000004', 'authenticated', 'authenticated',
   'tl-racer-c@evt.local', '', now(), now()),
  ('e7307000-0000-0000-0000-000000000005', 'authenticated', 'authenticated',
   'tl-racer-d@evt.local', '', now(), now());

set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';

insert into clubs (id, owner_id, name, slug, is_public)
values ('e7307000-0000-0000-0000-0000000000c1',
        'e7307000-0000-0000-0000-000000000001', 'Lines Club', 'race-timing-lines-c', true);

insert into club_members (club_id, user_id, role, status)
values
  ('e7307000-0000-0000-0000-0000000000c1', 'e7307000-0000-0000-0000-000000000002', 'member', 'active'),
  ('e7307000-0000-0000-0000-0000000000c1', 'e7307000-0000-0000-0000-000000000003', 'member', 'active'),
  ('e7307000-0000-0000-0000-0000000000c1', 'e7307000-0000-0000-0000-000000000004', 'member', 'active'),
  ('e7307000-0000-0000-0000-0000000000c1', 'e7307000-0000-0000-0000-000000000005', 'member', 'active')
on conflict do nothing;

insert into events (id, club_id, title, starts_at, author_id, is_public, race_auto_approve)
values ('e7307000-0000-0000-0000-0000000000e1', 'e7307000-0000-0000-0000-0000000000c1',
        'Line race', '2026-09-03 08:00+00', 'e7307000-0000-0000-0000-000000000001', true, true);

insert into race_sessions (event_id, instance_start, status)
values ('e7307000-0000-0000-0000-0000000000e1', '2026-09-03 08:00+00', 'armed');

-- GO at 08:00:00 sharp; the service role keeps the instant it writes.
update race_sessions set status = 'running', started_at = '2026-09-03 08:00:00+00'
 where event_id = 'e7307000-0000-0000-0000-0000000000e1';

-- ── 1-4: server-derived gun and chip ────────────────────────────────────────
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"e7307000-0000-0000-0000-000000000002","role":"authenticated"}';

-- The device thought GO was later (it missed a delay while offline), so it
-- sent 1500 s; the crossings it claims say 1800.4 s from the real GO.
insert into event_results (event_id, instance_start, user_id, duration_s, distance_m,
                           gun_time_s, chip_time_s, finish_method,
                           start_at, finish_at, start_detection, finish_detection,
                           clock_offset_ms)
values ('e7307000-0000-0000-0000-0000000000e1', '2026-09-03 08:00+00',
        'e7307000-0000-0000-0000-000000000002', 1500, 5000, 1500, 1495, 'auto',
        '2026-09-03 08:00:05.2+00', '2026-09-03 08:30:00.4+00', 'gate', 'gate', 1234);

select is(
  (select gun_time_s from event_results where user_id = 'e7307000-0000-0000-0000-000000000002'),
  1800,
  'the gun time is finish_at minus the session''s GO, truncated, whatever the device sent'
);

select is(
  (select chip_time_s from event_results where user_id = 'e7307000-0000-0000-0000-000000000002'),
  1795,
  'the chip time is finish_at minus start_at, truncated'
);

select is(
  (select duration_s from event_results where user_id = 'e7307000-0000-0000-0000-000000000002'),
  1800,
  'a gun-mode result ranks on the derived gun time'
);

select is(
  (select clock_offset_ms from event_results where user_id = 'e7307000-0000-0000-0000-000000000002'),
  1234::bigint,
  'the clock offset the crossings were converted with is kept'
);

-- ── 5: a device start before GO ─────────────────────────────────────────────
set local "request.jwt.claims" = '{"sub":"e7307000-0000-0000-0000-000000000003","role":"authenticated"}';

insert into event_results (event_id, instance_start, user_id, duration_s, distance_m,
                           gun_time_s, chip_time_s, finish_method,
                           start_at, finish_at, start_detection, finish_detection)
values ('e7307000-0000-0000-0000-0000000000e1', '2026-09-03 08:00+00',
        'e7307000-0000-0000-0000-000000000003', 1120, 5000, 1000, 1120, 'auto',
        '2026-09-03 07:58:00+00', '2026-09-03 08:16:40+00', 'device', 'zone');

select ok(
  (select gun_time_s = 1000 and chip_time_s = 1000 and duration_s = 1000
     from event_results where user_id = 'e7307000-0000-0000-0000-000000000003'),
  'a Start press before GO never makes the chip time longer than the gun time'
);

-- ── 6: a finish before GO ───────────────────────────────────────────────────
set local "request.jwt.claims" = '{"sub":"e7307000-0000-0000-0000-000000000005","role":"authenticated"}';

insert into event_results (event_id, instance_start, user_id, duration_s, distance_m,
                           finish_method, start_at, finish_at, start_detection)
values ('e7307000-0000-0000-0000-0000000000e1', '2026-09-03 08:00+00',
        'e7307000-0000-0000-0000-000000000005', 50, 200, 'manual',
        '2026-09-03 07:58:00+00', '2026-09-03 07:59:30+00', 'device');

select ok(
  (select gun_time_s is null and chip_time_s = 90 and duration_s = 90
     from event_results where user_id = 'e7307000-0000-0000-0000-000000000005'),
  'a finish before GO carries no gun time and ranks on the chip time'
);

-- ── 7: no finish_at, § 1850 as before ───────────────────────────────────────
set local "request.jwt.claims" = '{"sub":"e7307000-0000-0000-0000-000000000004","role":"authenticated"}';

insert into event_results (event_id, instance_start, user_id, duration_s, distance_m,
                           chip_time_s, finish_method)
values ('e7307000-0000-0000-0000-0000000000e1', '2026-09-03 08:00+00',
        'e7307000-0000-0000-0000-000000000004', 2000, 5000, 2000, 'manual');

select ok(
  (select duration_s = 2000 and chip_time_s = 2000 and gun_time_s is null
     from event_results where user_id = 'e7307000-0000-0000-0000-000000000004'),
  'a write with no crossings keeps the device''s own numbers'
);

-- ── 8-11: the redacted view ─────────────────────────────────────────────────
set local "request.jwt.claims" = '{"sub":"e7307000-0000-0000-0000-000000000001","role":"authenticated"}';

select ok(
  (select start_detection = 'device' and finish_detection = 'zone' and needs_review is not null
     from event_results_redacted where user_id = 'e7307000-0000-0000-0000-000000000003'),
  'the organiser reads how a result was timed and whether it needs review'
);

select ok(
  (select clock_offset_ms is null
     from event_results_redacted where user_id = 'e7307000-0000-0000-0000-000000000002'),
  'the organiser does not read a runner''s clock offset'
);

set local "request.jwt.claims" = '{"sub":"e7307000-0000-0000-0000-000000000002","role":"authenticated"}';

select is(
  (select clock_offset_ms from event_results_redacted
    where user_id = 'e7307000-0000-0000-0000-000000000002'),
  1234::bigint,
  'the runner reads their own clock offset, for a re-time'
);

set local role anon;
set local "request.jwt.claims" = '{"role":"anon"}';

select ok(
  (select bool_and(start_detection is null and finish_detection is null
                   and needs_review is null and clock_offset_ms is null)
     from event_results_redacted where event_id = 'e7307000-0000-0000-0000-0000000000e1'),
  'the public reads no detection, review flag or clock offset'
);

-- ── 12-13: a DNF ────────────────────────────────────────────────────────────
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"e7307000-0000-0000-0000-000000000002","role":"authenticated"}';

update event_results set finisher_status = 'dnf', duration_s = 900
 where user_id = 'e7307000-0000-0000-0000-000000000002';

select ok(
  (select start_at is null and finish_at is null and start_detection is null
          and finish_detection is null and not needs_review and gun_time_s is null
     from event_results where user_id = 'e7307000-0000-0000-0000-000000000002'),
  'a DNF keeps no crossing instants, detections or review flag'
);

select is(
  (select clock_offset_ms from event_results where user_id = 'e7307000-0000-0000-0000-000000000002'),
  1234::bigint,
  'a DNF keeps the clock offset a re-time would need'
);

-- ── 14: a host edit ─────────────────────────────────────────────────────────
set local "request.jwt.claims" = '{"sub":"e7307000-0000-0000-0000-000000000001","role":"authenticated"}';

update event_results set duration_s = 1010, gun_time_s = 1010
 where user_id = 'e7307000-0000-0000-0000-000000000003';

select ok(
  (select start_at is null and finish_at is null and start_detection is null
          and finish_detection is null and not needs_review
          and finish_method = 'host' and duration_s = 1010
     from event_results where user_id = 'e7307000-0000-0000-0000-000000000003'),
  'a host edit clears the crossings, the detections and the review flag'
);

-- ── 15-17: CHECKs (the service role skips the normaliser) ───────────────────
set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';

select throws_ok(
  $$ update event_results set start_detection = 'chip'
      where user_id = 'e7307000-0000-0000-0000-000000000004' $$,
  '23514', null,
  'start_detection is gate or device'
);

select throws_ok(
  $$ update event_results set finish_method = 'auto', finish_detection = 'line'
      where user_id = 'e7307000-0000-0000-0000-000000000004' $$,
  '23514', null,
  'finish_detection is gate or zone'
);

select throws_ok(
  $$ update event_results set finish_method = 'manual', finish_detection = 'gate'
      where user_id = 'e7307000-0000-0000-0000-000000000004' $$,
  '23514', null,
  'finish_detection is set only beside an automatic finish'
);

select * from finish();
rollback;

-- Pins migration 20270728000002 (decisions § 1849, § 1850) and the parts
-- of the 20270727000001 race guards race_courses_test does not reach.
--
--   1-2.   An armed race and a cancelled race do not close the result window.
--   3-4.   A second going upsert that omits the course keeps the stored one; a
--          write that explicitly clears it is still refused.
--   5-8.   A runner's own timing write replaces the race columns it implies: a
--          DNF keeps none, a manual resubmit drops the stale gun time, and
--          'host' never survives the runner's own write (sent or left over).
--   9-11.  Negative gun / chip times and an unknown finish method are refused.
--   12.    An organiser's edit of a bib-only row stamps finish_method host.
--   13-16. race_pending_dnf_count: the director's count; NULL for an organiser
--          who is not a director and for a non-member; anon cannot call it.
--   17-19. End files a DNF only for the pinged, non-declined attendee with no
--          result, moves no finisher's rank, and a later update of the
--          finished session files nothing more.
--   20.    A gun-time change more than 24 h after the finish is refused.
--   21.    event_results_redacted carries the four race columns.
--   22.    The NOT VALID constraints were validated by 20270727000002.

begin;
select plan(22);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('e7281000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
   'rg-owner@evt.local', '', now(), now()),
  ('e7281000-0000-0000-0000-000000000002', 'authenticated', 'authenticated',
   'rg-racer-a@evt.local', '', now(), now()),
  ('e7281000-0000-0000-0000-000000000003', 'authenticated', 'authenticated',
   'rg-racer-b@evt.local', '', now(), now()),
  ('e7281000-0000-0000-0000-000000000004', 'authenticated', 'authenticated',
   'rg-declined@evt.local', '', now(), now()),
  ('e7281000-0000-0000-0000-000000000005', 'authenticated', 'authenticated',
   'rg-silent@evt.local', '', now(), now()),
  ('e7281000-0000-0000-0000-000000000006', 'authenticated', 'authenticated',
   'rg-organiser@evt.local', '', now(), now()),
  ('e7281000-0000-0000-0000-000000000007', 'authenticated', 'authenticated',
   'rg-stranger@evt.local', '', now(), now()),
  ('e7281000-0000-0000-0000-000000000008', 'authenticated', 'authenticated',
   'rg-dropout@evt.local', '', now(), now());

set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';

insert into clubs (id, owner_id, name, slug, is_public)
values ('e7281000-0000-0000-0000-0000000000c1',
        'e7281000-0000-0000-0000-000000000001', 'Guard Club', 'race-guard-c', true);

insert into club_members (club_id, user_id, role, status)
values
  ('e7281000-0000-0000-0000-0000000000c1', 'e7281000-0000-0000-0000-000000000002', 'member', 'active'),
  ('e7281000-0000-0000-0000-0000000000c1', 'e7281000-0000-0000-0000-000000000003', 'member', 'active'),
  ('e7281000-0000-0000-0000-0000000000c1', 'e7281000-0000-0000-0000-000000000004', 'member', 'active'),
  ('e7281000-0000-0000-0000-0000000000c1', 'e7281000-0000-0000-0000-000000000005', 'member', 'active'),
  ('e7281000-0000-0000-0000-0000000000c1', 'e7281000-0000-0000-0000-000000000006', 'event_organiser', 'active'),
  ('e7281000-0000-0000-0000-0000000000c1', 'e7281000-0000-0000-0000-000000000008', 'member', 'active');

insert into events (id, club_id, title, starts_at, author_id, is_public)
values
  ('e7281000-0000-0000-0000-0000000000e1', 'e7281000-0000-0000-0000-0000000000c1',
   'Armed race', '2026-09-01 08:00+00', 'e7281000-0000-0000-0000-000000000001', true),
  ('e7281000-0000-0000-0000-0000000000e2', 'e7281000-0000-0000-0000-0000000000c1',
   'Cancelled race', '2026-09-02 08:00+00', 'e7281000-0000-0000-0000-000000000001', true),
  ('e7281000-0000-0000-0000-0000000000e3', 'e7281000-0000-0000-0000-0000000000c1',
   'Main race', '2026-09-03 08:00+00', 'e7281000-0000-0000-0000-000000000001', true);

insert into event_courses (id, event_id, name, distance_m, sort_order)
values
  ('e7281000-0000-0000-0000-0000000000a1', 'e7281000-0000-0000-0000-0000000000e3', '10K', 10000, 0),
  ('e7281000-0000-0000-0000-0000000000a2', 'e7281000-0000-0000-0000-0000000000e3', '5K', 5000, 1);

insert into event_attendees (event_id, user_id, status, instance_start, course_id)
values
  ('e7281000-0000-0000-0000-0000000000e3', 'e7281000-0000-0000-0000-000000000002',
   'going', '2026-09-03 08:00+00', 'e7281000-0000-0000-0000-0000000000a1'),
  ('e7281000-0000-0000-0000-0000000000e3', 'e7281000-0000-0000-0000-000000000003',
   'going', '2026-09-03 08:00+00', 'e7281000-0000-0000-0000-0000000000a2'),
  ('e7281000-0000-0000-0000-0000000000e3', 'e7281000-0000-0000-0000-000000000004',
   'declined', '2026-09-03 08:00+00', 'e7281000-0000-0000-0000-0000000000a2'),
  ('e7281000-0000-0000-0000-0000000000e3', 'e7281000-0000-0000-0000-000000000005',
   'going', '2026-09-03 08:00+00', 'e7281000-0000-0000-0000-0000000000a1'),
  ('e7281000-0000-0000-0000-0000000000e3', 'e7281000-0000-0000-0000-000000000008',
   'going', '2026-09-03 08:00+00', 'e7281000-0000-0000-0000-0000000000a2');

insert into race_sessions (event_id, instance_start, status)
values
  ('e7281000-0000-0000-0000-0000000000e1', '2026-09-01 08:00+00', 'armed'),
  ('e7281000-0000-0000-0000-0000000000e2', '2026-09-02 08:00+00', 'armed'),
  ('e7281000-0000-0000-0000-0000000000e3', '2026-09-03 08:00+00', 'armed');

update race_sessions set status = 'cancelled'
 where event_id = 'e7281000-0000-0000-0000-0000000000e2';

-- ── 1-2: armed and cancelled races do not close the window ──────────────────
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"e7281000-0000-0000-0000-000000000002","role":"authenticated"}';

select lives_ok(
  $$ insert into event_results (event_id, instance_start, user_id, duration_s, distance_m)
     values ('e7281000-0000-0000-0000-0000000000e1', '2026-09-01 08:00+00',
             'e7281000-0000-0000-0000-000000000002', 2500, 10000) $$,
  'a racer submits their own time on an armed race'
);

select lives_ok(
  $$ insert into event_results (event_id, instance_start, user_id, duration_s, distance_m,
                               finisher_status)
     values ('e7281000-0000-0000-0000-0000000000e2', '2026-09-02 08:00+00',
             'e7281000-0000-0000-0000-000000000002', 0, 0, 'dns') $$,
  'a racer files their own DNS on a cancelled race'
);

-- ── 3-4: a repeated going upsert keeps the stored course ────────────────────
insert into event_attendees (event_id, user_id, status, instance_start)
values ('e7281000-0000-0000-0000-0000000000e3',
        'e7281000-0000-0000-0000-000000000002', 'going', '2026-09-03 08:00+00')
on conflict (event_id, user_id, instance_start)
do update set status = excluded.status;

select is(
  (select status || '/' || course_id::text from event_attendees
    where event_id = 'e7281000-0000-0000-0000-0000000000e3'
      and user_id = 'e7281000-0000-0000-0000-000000000002'),
  'going/e7281000-0000-0000-0000-0000000000a1',
  'a second going upsert that omits the course lands and keeps the course the racer picked'
);

select throws_ok(
  $$ insert into event_attendees (event_id, user_id, status, instance_start, course_id)
     values ('e7281000-0000-0000-0000-0000000000e3',
             'e7281000-0000-0000-0000-000000000002', 'going', '2026-09-03 08:00+00', null)
     on conflict (event_id, user_id, instance_start)
     do update set status = excluded.status, course_id = excluded.course_id $$,
  '23514',
  'event_course_required: pick a course for this event',
  'an upsert that explicitly clears the course is still refused'
);

-- ── GO ──────────────────────────────────────────────────────────────────────
set local "request.jwt.claims" = '{"sub":"e7281000-0000-0000-0000-000000000001","role":"authenticated"}';
update race_sessions set status = 'running'
 where event_id = 'e7281000-0000-0000-0000-0000000000e3';

-- ── 5-8: the runner's own write states the whole result ─────────────────────
set local "request.jwt.claims" = '{"sub":"e7281000-0000-0000-0000-000000000002","role":"authenticated"}';

insert into event_results (event_id, instance_start, user_id, duration_s, gun_time_s,
                           chip_time_s, distance_m, finish_method)
values ('e7281000-0000-0000-0000-0000000000e3', '2026-09-03 08:00+00',
        'e7281000-0000-0000-0000-000000000002', 2400, 2400, 2390, 10000, 'auto');

update event_results set finisher_status = 'dnf', duration_s = 1800
 where event_id = 'e7281000-0000-0000-0000-0000000000e3'
   and user_id = 'e7281000-0000-0000-0000-000000000002';

select is(
  (select coalesce(gun_time_s::text, 'null') || '/' || coalesce(chip_time_s::text, 'null')
          || '/' || coalesce(finish_method, 'null')
     from event_results
    where event_id = 'e7281000-0000-0000-0000-0000000000e3'
      and user_id = 'e7281000-0000-0000-0000-000000000002'),
  'null/null/null',
  'a racer''s own DNF over an auto finish keeps no gun time, chip time or method'
);

update event_results
   set finisher_status = 'finished', duration_s = 2400, gun_time_s = 2400,
       chip_time_s = 2390, finish_method = 'auto'
 where event_id = 'e7281000-0000-0000-0000-0000000000e3'
   and user_id = 'e7281000-0000-0000-0000-000000000002';

update event_results set duration_s = 2385, chip_time_s = 2385, finish_method = 'manual'
 where event_id = 'e7281000-0000-0000-0000-0000000000e3'
   and user_id = 'e7281000-0000-0000-0000-000000000002';

select is(
  (select coalesce(gun_time_s::text, 'null') || '/' || chip_time_s || '/' || finish_method
     from event_results
    where event_id = 'e7281000-0000-0000-0000-0000000000e3'
      and user_id = 'e7281000-0000-0000-0000-000000000002'),
  'null/2385/manual',
  'a manual resubmit over an auto finish drops the gun time the new time no longer matches'
);

set local "request.jwt.claims" = '{"sub":"e7281000-0000-0000-0000-000000000003","role":"authenticated"}';

insert into event_results (event_id, instance_start, user_id, duration_s, gun_time_s,
                           chip_time_s, distance_m, finish_method)
values ('e7281000-0000-0000-0000-0000000000e3', '2026-09-03 08:00+00',
        'e7281000-0000-0000-0000-000000000003', 1500, 1500, 1495, 5000, 'host');

select is(
  (select coalesce(finish_method, 'null') || '/' || gun_time_s || '/' || chip_time_s
     from event_results
    where event_id = 'e7281000-0000-0000-0000-0000000000e3'
      and user_id = 'e7281000-0000-0000-0000-000000000003'),
  'null/1500/1495',
  'a racer cannot claim host provenance for their own result'
);

set local "request.jwt.claims" = '{"sub":"e7281000-0000-0000-0000-000000000001","role":"authenticated"}';
update event_results set duration_s = 1520, gun_time_s = 1520
 where event_id = 'e7281000-0000-0000-0000-0000000000e3'
   and user_id = 'e7281000-0000-0000-0000-000000000003';

set local "request.jwt.claims" = '{"sub":"e7281000-0000-0000-0000-000000000003","role":"authenticated"}';
update event_results set duration_s = 1490, gun_time_s = 1490
 where event_id = 'e7281000-0000-0000-0000-0000000000e3'
   and user_id = 'e7281000-0000-0000-0000-000000000003';

select is(
  (select coalesce(finish_method, 'null') || '/' || gun_time_s
     from event_results
    where event_id = 'e7281000-0000-0000-0000-0000000000e3'
      and user_id = 'e7281000-0000-0000-0000-000000000003'),
  'null/1490',
  'a racer''s rewrite of a host-edited time does not keep the host stamp'
);

-- ── 9-11: column CHECKs ────────────────────────────────────────────────────
set local "request.jwt.claims" = '{"sub":"e7281000-0000-0000-0000-000000000005","role":"authenticated"}';

select throws_ok(
  $$ insert into event_results (event_id, instance_start, user_id, duration_s, gun_time_s,
                               distance_m)
     values ('e7281000-0000-0000-0000-0000000000e3', '2026-09-03 08:00+00',
             'e7281000-0000-0000-0000-000000000005', 2000, -5, 10000) $$,
  '23514',
  null,
  'a negative gun time is refused'
);

select throws_ok(
  $$ insert into event_results (event_id, instance_start, user_id, duration_s, chip_time_s,
                               distance_m)
     values ('e7281000-0000-0000-0000-0000000000e3', '2026-09-03 08:00+00',
             'e7281000-0000-0000-0000-000000000005', 2000, -5, 10000) $$,
  '23514',
  null,
  'a negative chip time is refused'
);

select throws_ok(
  $$ insert into event_results (event_id, instance_start, user_id, duration_s, distance_m,
                               finish_method)
     values ('e7281000-0000-0000-0000-0000000000e3', '2026-09-03 08:00+00',
             'e7281000-0000-0000-0000-000000000005', 2000, 10000, 'robot') $$,
  '23514',
  null,
  'an unknown finish method is refused'
);

-- ── 12: a bib-only organiser edit ───────────────────────────────────────────
set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';

insert into event_results (event_id, instance_start, bib, finisher_name, duration_s, distance_m)
values ('e7281000-0000-0000-0000-0000000000e3', '2026-09-03 08:00+00',
        '77', 'Walk-up Runner', 3000, 10000);

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"e7281000-0000-0000-0000-000000000006","role":"authenticated"}';

update event_results set duration_s = 2990
 where event_id = 'e7281000-0000-0000-0000-0000000000e3' and bib = '77';

select is(
  (select duration_s || '/' || finish_method from event_results
    where event_id = 'e7281000-0000-0000-0000-0000000000e3' and bib = '77'),
  '2990/host',
  'an organiser''s edit of a bib-only result is stamped host'
);

-- ── 13-16: what End will do ─────────────────────────────────────────────────
set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';

insert into race_pings (event_id, instance_start, user_id, lat, lng, distance_m, elapsed_s)
values
  ('e7281000-0000-0000-0000-0000000000e3', '2026-09-03 08:00+00',
   'e7281000-0000-0000-0000-000000000002', 51.5, -0.1, 9000, 2100),
  ('e7281000-0000-0000-0000-0000000000e3', '2026-09-03 08:00+00',
   'e7281000-0000-0000-0000-000000000003', 51.5, -0.1, 4000, 1200),
  ('e7281000-0000-0000-0000-0000000000e3', '2026-09-03 08:00+00',
   'e7281000-0000-0000-0000-000000000004', 51.5, -0.1, 1000, 400),
  ('e7281000-0000-0000-0000-0000000000e3', '2026-09-03 08:00+00',
   'e7281000-0000-0000-0000-000000000008', 51.5, -0.1, 2500, 900);

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"e7281000-0000-0000-0000-000000000001","role":"authenticated"}';

select is(
  race_pending_dnf_count('e7281000-0000-0000-0000-0000000000e3', '2026-09-03 08:00+00'),
  1,
  'the director''s count is the one pinged, non-declined attendee with no result'
);

set local "request.jwt.claims" = '{"sub":"e7281000-0000-0000-0000-000000000006","role":"authenticated"}';

select is(
  race_pending_dnf_count('e7281000-0000-0000-0000-0000000000e3', '2026-09-03 08:00+00'),
  null::int,
  'an event organiser who is not a race director gets no count'
);

set local "request.jwt.claims" = '{"sub":"e7281000-0000-0000-0000-000000000007","role":"authenticated"}';

select is(
  race_pending_dnf_count('e7281000-0000-0000-0000-0000000000e3', '2026-09-03 08:00+00'),
  null::int,
  'a non-member gets no count'
);

set local role anon;
set local "request.jwt.claims" = '{"role":"anon"}';

select throws_ok(
  $$ select race_pending_dnf_count('e7281000-0000-0000-0000-0000000000e3',
                                   '2026-09-03 08:00+00') $$,
  '42501',
  null,
  'anon cannot call race_pending_dnf_count'
);

-- ── 17-19: End ──────────────────────────────────────────────────────────────
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"e7281000-0000-0000-0000-000000000001","role":"authenticated"}';

update race_sessions set status = 'finished'
 where event_id = 'e7281000-0000-0000-0000-0000000000e3';

select is(
  (select string_agg(user_id::text || '@' || course_id::text, ',')
     from event_results
    where event_id = 'e7281000-0000-0000-0000-0000000000e3'
      and finisher_status = 'dnf'),
  'e7281000-0000-0000-0000-000000000008@e7281000-0000-0000-0000-0000000000a2',
  'End files a DNF only for the pinged attendee with no result: not the declined one, '
  'not the one who never pinged'
);

select is(
  (select string_agg(coalesce(rank::text, 'null'), '|' order by duration_s)
     from event_results
    where event_id = 'e7281000-0000-0000-0000-0000000000e3'
      and course_id = 'e7281000-0000-0000-0000-0000000000a2'),
  'null|1',
  'the DNF takes no rank and the 5K winner keeps rank 1'
);

update race_sessions set is_auto_approve = false
 where event_id = 'e7281000-0000-0000-0000-0000000000e3';

select is(
  (select count(*)::int from event_results
    where event_id = 'e7281000-0000-0000-0000-0000000000e3'),
  4,
  'a later update of the finished race files no second DNF'
);

-- ── 20: the window 24 h after the finish ────────────────────────────────────
set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';
update race_sessions set finished_at = now() - interval '25 hours'
 where event_id = 'e7281000-0000-0000-0000-0000000000e3';

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"e7281000-0000-0000-0000-000000000002","role":"authenticated"}';

select throws_ok(
  $$ update event_results set gun_time_s = 2380
      where event_id = 'e7281000-0000-0000-0000-0000000000e3'
        and user_id = 'e7281000-0000-0000-0000-000000000002' $$,
  '23514',
  null,
  'a racer cannot change their gun time more than 24 h after the finish'
);

-- ── 21: the redacted read surface ───────────────────────────────────────────
set local "request.jwt.claims" = '{"sub":"e7281000-0000-0000-0000-000000000007","role":"authenticated"}';

select is(
  (select course_id::text || '|' || coalesce(gun_time_s::text, 'null') || '|'
          || chip_time_s || '|' || finish_method
     from event_results_redacted
    where event_id = 'e7281000-0000-0000-0000-0000000000e3'
      and user_id = 'e7281000-0000-0000-0000-000000000002'),
  'e7281000-0000-0000-0000-0000000000a1|null|2385|manual',
  'another viewer reads a result''s course, gun time, chip time and method'
);

-- ── 22: validated constraints ───────────────────────────────────────────────
set local role service_role;

select is(
  (select count(*)::int from pg_constraint
    where convalidated
      and conname in ('event_attendees_course_id_fkey', 'event_results_course_id_fkey',
                      'event_results_gun_time_s_check', 'event_results_chip_time_s_check',
                      'event_results_finish_method_check')),
  5,
  'the five constraints added NOT VALID are validated'
);

select * from finish();
rollback;

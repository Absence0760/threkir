-- Pins 20271224000200 (audit of PR #1359, Low): a runner's own change of
-- course or distance sends an approved result back through approval the way
-- a time change does.
--
--   1-3.  Not auto-approved (host GO): a course move unapproves the result and
--         marks it for review; so does a distance change alone.
--   4.    Auto-approved host GO race: the move keeps its approval, as a time
--         change would.
--   5.    Self-timed race: a moved result is re-checked, and one that is not
--         clean (no gate crossing) waits for review again.
--   6.    The race director's own move of an approved result keeps it approved.

begin;
select plan(6);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('e7282400-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'rr-owner@evt.local', '', now(), now()),
  ('e7282400-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'rr-racer@evt.local', '', now(), now());

set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';

insert into clubs (id, owner_id, name, slug, is_public)
values ('e7282400-0000-0000-0000-0000000000c1', 'e7282400-0000-0000-0000-000000000001',
        'Reapproval Club', 'reapproval-c', true);
insert into club_members (club_id, user_id, role, status)
values ('e7282400-0000-0000-0000-0000000000c1', 'e7282400-0000-0000-0000-000000000002', 'member', 'active');

insert into events (id, club_id, title, starts_at, author_id, is_public)
values
  ('e7282400-0000-0000-0000-0000000000e1', 'e7282400-0000-0000-0000-0000000000c1',
   'Approved race', '2026-09-03 08:00+00', 'e7282400-0000-0000-0000-000000000001', true),
  ('e7282400-0000-0000-0000-0000000000e2', 'e7282400-0000-0000-0000-0000000000c1',
   'Auto race', '2026-09-04 08:00+00', 'e7282400-0000-0000-0000-000000000001', true);
-- A race's start mode comes from its event (race_sessions_apply_start_mode).
insert into events (id, club_id, title, starts_at, author_id, is_public,
                    race_start_mode, race_scheduled_offset_s, race_window_open_offset_s,
                    race_window_length_s, race_auto_approve)
values ('e7282400-0000-0000-0000-0000000000e3', 'e7282400-0000-0000-0000-0000000000c1',
        'Self-timed race', '2026-09-05 08:00+00', 'e7282400-0000-0000-0000-000000000001', true,
        'self_timed', null, 0, 86400, true);

insert into event_courses (id, event_id, name, distance_m, sort_order)
values
  ('e7282400-0000-0000-0000-0000000001a1', 'e7282400-0000-0000-0000-0000000000e1', '10K', 10000, 0),
  ('e7282400-0000-0000-0000-0000000001a2', 'e7282400-0000-0000-0000-0000000000e1', '5K', 5000, 1),
  ('e7282400-0000-0000-0000-0000000002a1', 'e7282400-0000-0000-0000-0000000000e2', '10K', 10000, 0),
  ('e7282400-0000-0000-0000-0000000002a2', 'e7282400-0000-0000-0000-0000000000e2', '5K', 5000, 1),
  ('e7282400-0000-0000-0000-0000000003a1', 'e7282400-0000-0000-0000-0000000000e3', '10K', 10000, 0),
  ('e7282400-0000-0000-0000-0000000003a2', 'e7282400-0000-0000-0000-0000000000e3', '5K', 5000, 1);

insert into race_sessions (event_id, instance_start, status, started_at, is_auto_approve)
values
  ('e7282400-0000-0000-0000-0000000000e1', '2026-09-03 08:00+00', 'running', now() - interval '1 hour', false),
  ('e7282400-0000-0000-0000-0000000000e2', '2026-09-04 08:00+00', 'running', now() - interval '1 hour', true);
insert into race_sessions (event_id, instance_start, status)
values ('e7282400-0000-0000-0000-0000000000e3', '2026-09-05 08:00+00', 'armed');
update race_sessions set status = 'running', started_at = '2026-09-05 08:00:00+00'
 where event_id = 'e7282400-0000-0000-0000-0000000000e3';

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"e7282400-0000-0000-0000-000000000002","role":"authenticated"}';

insert into event_results (event_id, instance_start, user_id, duration_s, distance_m, course_id)
values
  ('e7282400-0000-0000-0000-0000000000e1', '2026-09-03 08:00+00', 'e7282400-0000-0000-0000-000000000002',
   2400, 10000, 'e7282400-0000-0000-0000-0000000001a1'),
  ('e7282400-0000-0000-0000-0000000000e2', '2026-09-04 08:00+00', 'e7282400-0000-0000-0000-000000000002',
   2400, 10000, 'e7282400-0000-0000-0000-0000000002a1'),
  ('e7282400-0000-0000-0000-0000000000e3', '2026-09-05 08:00+00', 'e7282400-0000-0000-0000-000000000002',
   2400, 10000, 'e7282400-0000-0000-0000-0000000003a1');

-- The director approves every result as it stands.
set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';
update event_results
   set organiser_approved = true, needs_review = false,
       organiser_approved_by = 'e7282400-0000-0000-0000-000000000001', organiser_approved_at = now()
 where user_id = 'e7282400-0000-0000-0000-000000000002';

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"e7282400-0000-0000-0000-000000000002","role":"authenticated"}';

-- ── 1-3: not auto-approved ───────────────────────────────────────────────────
update event_results set course_id = 'e7282400-0000-0000-0000-0000000001a2', distance_m = 5000
 where event_id = 'e7282400-0000-0000-0000-0000000000e1';

select is(
  (select organiser_approved::text || '|' || needs_review::text from event_results_redacted
    where event_id = 'e7282400-0000-0000-0000-0000000000e1'),
  'false|true',
  'a racer''s course move in a race that is not auto-approved unapproves the result and marks it for review');

reset role;
select is(
  (select organiser_approved_by from event_results
    where event_id = 'e7282400-0000-0000-0000-0000000000e1'),
  null,
  'the move clears who approved it');

set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';
update event_results set organiser_approved = true, needs_review = false
 where event_id = 'e7282400-0000-0000-0000-0000000000e1';
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"e7282400-0000-0000-0000-000000000002","role":"authenticated"}';

update event_results set distance_m = 5100
 where event_id = 'e7282400-0000-0000-0000-0000000000e1';

select is(
  (select organiser_approved from event_results
    where event_id = 'e7282400-0000-0000-0000-0000000000e1'),
  false,
  'a distance change alone unapproves it too');

-- ── 4: auto-approved host GO ─────────────────────────────────────────────────
update event_results set course_id = 'e7282400-0000-0000-0000-0000000002a2', distance_m = 5000
 where event_id = 'e7282400-0000-0000-0000-0000000000e2';

select is(
  (select organiser_approved from event_results
    where event_id = 'e7282400-0000-0000-0000-0000000000e2'),
  true,
  'in an auto-approved race the move keeps its approval, as a time change does');

-- ── 5: self-timed ────────────────────────────────────────────────────────────
update event_results set course_id = 'e7282400-0000-0000-0000-0000000003a2', distance_m = 5000
 where event_id = 'e7282400-0000-0000-0000-0000000000e3';

select is(
  (select organiser_approved::text || '|' || needs_review::text from event_results_redacted
    where event_id = 'e7282400-0000-0000-0000-0000000000e3'),
  'false|true',
  'a self-timed result moved to another course is re-checked and, with no gate crossing, waits for review');

-- ── 6: the director's own move ──────────────────────────────────────────────
set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';
update event_results set organiser_approved = true, needs_review = false
 where event_id = 'e7282400-0000-0000-0000-0000000000e1';
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"e7282400-0000-0000-0000-000000000001","role":"authenticated"}';

update event_results set course_id = 'e7282400-0000-0000-0000-0000000001a1', distance_m = 10000
 where event_id = 'e7282400-0000-0000-0000-0000000000e1';

select is(
  (select organiser_approved from event_results
    where event_id = 'e7282400-0000-0000-0000-0000000000e1'),
  true,
  'the race director''s own course move keeps the result approved');

select * from finish();
rollback;

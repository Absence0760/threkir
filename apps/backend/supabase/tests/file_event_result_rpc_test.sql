-- Pins 20271225000100 (decisions § 2474): a runner files their own result
-- through public.file_event_result, which runs the clients' merge upsert as
-- its owner and keeps every rule the upsert met.
--
--   1-3.   EXECUTE is authenticated's alone, the function is SECURITY DEFINER
--          with an empty search_path, and anon is refused.
--   4-5.   A runner files their own result.
--   6-7.   Re-filing updates it in place, and a column the body leaves out
--          keeps its stored value.
--   8-9.   A body naming another runner is refused and their row is untouched.
--   10.    A column outside the runner's set (organiser_approved) is refused.
--   11.    An event the caller cannot see is refused.
--   12.    A non-athletic event is refused by its trigger.
--   13-14. With the eight columns 20271224000700 left granted revoked, the
--          plain upsert is refused and the function still files.
--   15.    Re-filing onto another course in a race that is not auto-approved
--          re-opens approval (§ 2474).
--   16.    Past the 24 h window a timing change is refused with the race
--          guard's race_result_window_closed message (§ 1849 / § 2471).

begin;
select plan(16);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('e2475100-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'fer-owner@fer.local', '', now(), now()),
  ('e2475100-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'fer-runner@fer.local', '', now(), now()),
  ('e2475100-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'fer-other@fer.local', '', now(), now());

set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';

insert into clubs (id, owner_id, name, slug, is_public)
values
  ('e2475100-0000-0000-0000-0000000000c1', 'e2475100-0000-0000-0000-000000000001', 'FER Club', 'fer-club', true),
  ('e2475100-0000-0000-0000-0000000000c2', 'e2475100-0000-0000-0000-000000000001', 'FER Private', 'fer-private', false);
insert into club_members (club_id, user_id, role, status)
values
  ('e2475100-0000-0000-0000-0000000000c1', 'e2475100-0000-0000-0000-000000000002', 'member', 'active'),
  ('e2475100-0000-0000-0000-0000000000c1', 'e2475100-0000-0000-0000-000000000003', 'member', 'active');

insert into events (id, club_id, title, starts_at, author_id, is_public)
values
  ('e2475100-0000-0000-0000-0000000000e1', 'e2475100-0000-0000-0000-0000000000c1', 'FER 10K',
   '2026-09-05 08:00+00', 'e2475100-0000-0000-0000-000000000001', true),
  ('e2475100-0000-0000-0000-0000000000e2', 'e2475100-0000-0000-0000-0000000000c2', 'FER private run',
   '2026-09-06 08:00+00', 'e2475100-0000-0000-0000-000000000001', false),
  ('e2475100-0000-0000-0000-0000000000e4', 'e2475100-0000-0000-0000-0000000000c1', 'FER closed race',
   '2026-09-08 08:00+00', 'e2475100-0000-0000-0000-000000000001', true);
insert into events (id, club_id, title, starts_at, author_id, is_public, category)
values ('e2475100-0000-0000-0000-0000000000e3', 'e2475100-0000-0000-0000-0000000000c1', 'FER social',
        '2026-09-07 08:00+00', 'e2475100-0000-0000-0000-000000000001', true, 'social');

insert into event_courses (id, event_id, name, distance_m, sort_order)
values
  ('e2475100-0000-0000-0000-0000000001a1', 'e2475100-0000-0000-0000-0000000000e1', '10K', 10000, 0),
  ('e2475100-0000-0000-0000-0000000001a2', 'e2475100-0000-0000-0000-0000000000e1', '5K', 5000, 1);

insert into race_sessions (event_id, instance_start, status, started_at, is_auto_approve)
values
  ('e2475100-0000-0000-0000-0000000000e1', '2026-09-05 08:00+00', 'running', now() - interval '1 hour', false),
  ('e2475100-0000-0000-0000-0000000000e4', '2026-09-08 08:00+00', 'running', now() - interval '30 hours', true);

insert into event_results (event_id, instance_start, user_id, duration_s, distance_m, note)
values
  ('e2475100-0000-0000-0000-0000000000e1', '2026-09-05 08:00+00', 'e2475100-0000-0000-0000-000000000003',
   3000, 10000, 'other runner'),
  ('e2475100-0000-0000-0000-0000000000e4', '2026-09-08 08:00+00', 'e2475100-0000-0000-0000-000000000002',
   2500, 10000, null);

-- ── 1-3: the grant ───────────────────────────────────────────────────────────
reset role;
select is(
  (select string_agg(r, ', ' order by r) from unnest(array['anon', 'authenticated', 'service_role']) r
    where has_function_privilege(r, 'public.file_event_result(jsonb)', 'EXECUTE')),
  'authenticated',
  'only authenticated may execute file_event_result');

select is(
  (select p.prosecdef::text || '|' || array_to_string(p.proconfig, ',')
     from pg_proc p where p.oid = 'public.file_event_result(jsonb)'::regprocedure),
  'true|search_path=""',
  'file_event_result is SECURITY DEFINER with an empty search_path');

set local role anon;
set local "request.jwt.claims" = '{"role":"anon"}';
select throws_ok(
  $$ select public.file_event_result('{"event_id":"e2475100-0000-0000-0000-0000000000e1"}'::jsonb) $$,
  '42501', 'permission denied for function file_event_result',
  'anon cannot file a result');

-- ── 4-5: file ────────────────────────────────────────────────────────────────
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"e2475100-0000-0000-0000-000000000002","role":"authenticated"}';

select lives_ok(
  $$ select public.file_event_result(jsonb_build_object(
       'event_id', 'e2475100-0000-0000-0000-0000000000e1',
       'instance_start', '2026-09-05T08:00:00Z',
       'user_id', 'e2475100-0000-0000-0000-000000000002',
       'duration_s', 2400, 'distance_m', 10000, 'finisher_status', 'finished',
       'course_id', 'e2475100-0000-0000-0000-0000000001a1',
       'note', 'first try', 'finish_method', 'manual')) $$,
  'a runner files their own result');

select is(
  (select duration_s::text || '|' || note || '|' || course_id::text from event_results_redacted
    where event_id = 'e2475100-0000-0000-0000-0000000000e1'
      and user_id = 'e2475100-0000-0000-0000-000000000002'),
  '2400|first try|e2475100-0000-0000-0000-0000000001a1',
  'the filed result is stored as sent');

-- ── 6-7: re-file ─────────────────────────────────────────────────────────────
select lives_ok(
  $$ select public.file_event_result(jsonb_build_object(
       'event_id', 'e2475100-0000-0000-0000-0000000000e1',
       'instance_start', '2026-09-05T08:00:00Z',
       'duration_s', 2390, 'distance_m', 10000, 'note', 'second try')) $$,
  'the runner re-files the same race');

select is(
  (select count(*)::text || '|' || max(duration_s)::text || '|' || max(note) || '|'
          || max(course_id::text) from event_results_redacted
    where event_id = 'e2475100-0000-0000-0000-0000000000e1'
      and user_id = 'e2475100-0000-0000-0000-000000000002'),
  '1|2390|second try|e2475100-0000-0000-0000-0000000001a1',
  're-filing updates the one row in place, and the course it left out is kept');

-- ── 8-9: another runner's result ─────────────────────────────────────────────
select throws_ok(
  $$ select public.file_event_result(jsonb_build_object(
       'event_id', 'e2475100-0000-0000-0000-0000000000e1',
       'instance_start', '2026-09-05T08:00:00Z',
       'user_id', 'e2475100-0000-0000-0000-000000000003',
       'duration_s', 1, 'distance_m', 10000)) $$,
  '42501', 'file_event_result: a runner files only their own result',
  'a body naming another runner is refused');

reset role;
select is(
  (select duration_s::text || '|' || note from event_results
    where event_id = 'e2475100-0000-0000-0000-0000000000e1'
      and user_id = 'e2475100-0000-0000-0000-000000000003'),
  '3000|other runner',
  'the other runner''s result is untouched');

-- ── 10-12: what the upsert's RLS and triggers refused ────────────────────────
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"e2475100-0000-0000-0000-000000000002","role":"authenticated"}';

select throws_ok(
  $$ select public.file_event_result(jsonb_build_object(
       'event_id', 'e2475100-0000-0000-0000-0000000000e1',
       'instance_start', '2026-09-05T08:00:00Z',
       'duration_s', 2390, 'distance_m', 10000, 'organiser_approved', true)) $$,
  '42501', 'file_event_result: organiser_approved is not a column a runner files',
  'a column outside the runner''s set is refused, not ignored');

select throws_ok(
  $$ select public.file_event_result(jsonb_build_object(
       'event_id', 'e2475100-0000-0000-0000-0000000000e2',
       'instance_start', '2026-09-06T08:00:00Z',
       'duration_s', 2400, 'distance_m', 10000)) $$,
  '42501', 'new row violates row-level security policy for table "event_results"',
  'a result for an event the caller cannot see is refused');

select throws_ok(
  $$ select public.file_event_result(jsonb_build_object(
       'event_id', 'e2475100-0000-0000-0000-0000000000e3',
       'instance_start', '2026-09-07T08:00:00Z',
       'duration_s', 2400, 'distance_m', 10000)) $$,
  '23514', 'event results are only allowed on run/cycle events (event e2475100-0000-0000-0000-0000000000e3 is not athletic)',
  'the athletic-event trigger still fires through the function');

-- ── 13-14: the revoke this function exists to allow ──────────────────────────
reset role;
revoke select (age_grade_pct, note, run_id, start_at, finish_at, start_detection, finish_detection,
               clock_offset_ms) on public.event_results from authenticated;

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"e2475100-0000-0000-0000-000000000002","role":"authenticated"}';

select throws_ok(
  $$ insert into event_results (event_id, instance_start, user_id, duration_s, distance_m, note)
     values ('e2475100-0000-0000-0000-0000000000e1', '2026-09-05 08:00+00',
             'e2475100-0000-0000-0000-000000000002', 2380, 10000, 'upsert')
     on conflict (event_id, instance_start, user_id) do update
       set duration_s = excluded.duration_s, note = excluded.note $$,
  '42501', 'permission denied for table event_results',
  'with the eight columns revoked, the plain merge upsert is refused');

select public.file_event_result(jsonb_build_object(
  'event_id', 'e2475100-0000-0000-0000-0000000000e1',
  'instance_start', '2026-09-05T08:00:00Z',
  'duration_s', 2380, 'distance_m', 10000, 'note', 'after the revoke',
  'start_at', null, 'finish_at', null, 'start_detection', null, 'finish_detection', null));

reset role;
select is(
  (select duration_s::text || '|' || note from event_results
    where event_id = 'e2475100-0000-0000-0000-0000000000e1'
      and user_id = 'e2475100-0000-0000-0000-000000000002'),
  '2380|after the revoke',
  'and the function still files the result');

-- ── 15: a course move re-opens approval ─────────────────────────────────────
set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';
update event_results
   set organiser_approved = true, needs_review = false,
       organiser_approved_by = 'e2475100-0000-0000-0000-000000000001', organiser_approved_at = now()
 where event_id = 'e2475100-0000-0000-0000-0000000000e1'
   and user_id = 'e2475100-0000-0000-0000-000000000002';

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"e2475100-0000-0000-0000-000000000002","role":"authenticated"}';
select public.file_event_result(jsonb_build_object(
  'event_id', 'e2475100-0000-0000-0000-0000000000e1',
  'instance_start', '2026-09-05T08:00:00Z',
  'duration_s', 2380, 'distance_m', 5000,
  'course_id', 'e2475100-0000-0000-0000-0000000001a2'));

reset role;
select is(
  (select organiser_approved::text || '|' || needs_review::text || '|' || course_id::text from event_results
    where event_id = 'e2475100-0000-0000-0000-0000000000e1'
      and user_id = 'e2475100-0000-0000-0000-000000000002'),
  'false|true|e2475100-0000-0000-0000-0000000001a2',
  'a re-file onto another course in a race that is not auto-approved goes back for approval');

-- ── 16: the window ───────────────────────────────────────────────────────────
set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';
update race_sessions set status = 'finished', finished_at = now() - interval '25 hours'
 where event_id = 'e2475100-0000-0000-0000-0000000000e4';

select set_config('fer.window_closed',
  (select 'race_result_window_closed: race finished at ' || finished_at::text
     from race_sessions where event_id = 'e2475100-0000-0000-0000-0000000000e4'),
  true);

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"e2475100-0000-0000-0000-000000000002","role":"authenticated"}';
select throws_ok(
  $$ select public.file_event_result(jsonb_build_object(
       'event_id', 'e2475100-0000-0000-0000-0000000000e4',
       'instance_start', '2026-09-08T08:00:00Z',
       'duration_s', 2000, 'distance_m', 10000)) $$,
  '23514',
  current_setting('fer.window_closed'),
  'past the 24 h window a re-filed time is refused by the race guard');

select * from finish();
rollback;

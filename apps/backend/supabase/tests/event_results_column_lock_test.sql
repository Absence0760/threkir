-- Pins 20271224000700 (audit of PR #1359, Medium): event_results no longer
-- hands a direct reader the columns event_results_redacted withholds.
--
--   1-2.  anon may select none of the withheld columns, and every leaderboard
--         column.
--   3-4.  authenticated may select none of needs_review and the approver
--         columns, and every leaderboard column.
--   5.    A direct anon read of a withheld column is refused.
--   6-7.  Through the view the runner reads their own note and clock offset;
--         another signed-in reader gets nulls.
--   8.    The race director reads needs_review through the view, not the note.
--   9.    anon still reads the public result through the view.
--   10-11. The runner's own result upsert, which reads its columns back from
--          EXCLUDED, still lands.

begin;
select plan(11);

select is(
  (select coalesce(string_agg(c, ', ' order by c), '')
     from unnest(array['age_grade_pct', 'note', 'run_id', 'start_at', 'finish_at', 'start_detection',
                       'finish_detection', 'clock_offset_ms', 'needs_review', 'organiser_approved_by',
                       'organiser_approved_at']) c
    where has_column_privilege('anon', 'public.event_results', c, 'SELECT')),
  '',
  'anon may select none of the columns the redacted view withholds');

select is(
  (select coalesce(string_agg(c, ', ' order by c), '')
     from unnest(array['id', 'event_id', 'instance_start', 'user_id', 'bib', 'finisher_name', 'duration_s',
                       'distance_m', 'rank', 'finisher_status', 'created_at', 'updated_at',
                       'organiser_approved', 'course_id', 'gun_time_s', 'chip_time_s', 'finish_method']) c
    where not has_column_privilege('anon', 'public.event_results', c, 'SELECT')),
  '',
  'anon keeps every leaderboard column');

select is(
  (select coalesce(string_agg(c, ', ' order by c), '')
     from unnest(array['needs_review', 'organiser_approved_by', 'organiser_approved_at']) c
    where has_column_privilege('authenticated', 'public.event_results', c, 'SELECT')),
  '',
  'authenticated may select neither needs_review nor who approved a result');

select is(
  (select coalesce(string_agg(c, ', ' order by c), '')
     from unnest(array['id', 'event_id', 'instance_start', 'user_id', 'bib', 'finisher_name', 'duration_s',
                       'distance_m', 'rank', 'finisher_status', 'created_at', 'updated_at',
                       'organiser_approved', 'course_id', 'gun_time_s', 'chip_time_s', 'finish_method']) c
    where not has_column_privilege('authenticated', 'public.event_results', c, 'SELECT')),
  '',
  'authenticated keeps every leaderboard column');

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('e2470000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'ercl-owner@ercl.local', '', now(), now()),
  ('e2470000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'ercl-runner@ercl.local', '', now(), now()),
  ('e2470000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'ercl-other@ercl.local', '', now(), now());

insert into clubs (id, owner_id, name, slug, is_public)
values ('e2470000-0000-0000-0000-0000000000c1', 'e2470000-0000-0000-0000-000000000001', 'ERCL Club', 'ercl-club', true);
insert into club_members (club_id, user_id, role, status)
values ('e2470000-0000-0000-0000-0000000000c1', 'e2470000-0000-0000-0000-000000000002', 'member', 'active');
insert into events (id, club_id, title, starts_at, author_id, is_public)
values ('e2470000-0000-0000-0000-0000000000e1', 'e2470000-0000-0000-0000-0000000000c1', 'ERCL 5K',
        '2026-09-05 08:00+00', 'e2470000-0000-0000-0000-000000000001', true);
insert into event_results (event_id, instance_start, user_id, duration_s, distance_m, note, clock_offset_ms, needs_review)
values ('e2470000-0000-0000-0000-0000000000e1', '2026-09-05 08:00+00', 'e2470000-0000-0000-0000-000000000002',
        1500, 5000, 'felt strong', -42, true);

set local role anon;
set local "request.jwt.claims" = '{"role":"anon"}';
select throws_ok(
  $$ select note from event_results where event_id = 'e2470000-0000-0000-0000-0000000000e1' $$,
  '42501', 'permission denied for table event_results',
  'a direct anon read of a withheld column is refused');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"e2470000-0000-0000-0000-000000000002","role":"authenticated"}';
select is(
  (select note || '|' || clock_offset_ms::text from event_results_redacted
    where event_id = 'e2470000-0000-0000-0000-0000000000e1'),
  'felt strong|-42',
  'the runner reads their own note and clock offset through the view');

set local "request.jwt.claims" = '{"sub":"e2470000-0000-0000-0000-000000000003","role":"authenticated"}';
select is(
  (select coalesce(note, '-') || '|' || coalesce(clock_offset_ms::text, '-') || '|'
          || coalesce(needs_review::text, '-') from event_results_redacted
    where event_id = 'e2470000-0000-0000-0000-0000000000e1'),
  '-|-|-',
  'another signed-in reader sees the result with every withheld column null');

set local "request.jwt.claims" = '{"sub":"e2470000-0000-0000-0000-000000000001","role":"authenticated"}';
select is(
  (select coalesce(note, '-') || '|' || coalesce(needs_review::text, '-') from event_results_redacted
    where event_id = 'e2470000-0000-0000-0000-0000000000e1'),
  '-|true',
  'the race director reads needs_review through the view, and not the runner''s note');

set local role anon;
set local "request.jwt.claims" = '{"role":"anon"}';
select is(
  (select duration_s from event_results_redacted where event_id = 'e2470000-0000-0000-0000-0000000000e1'),
  1500,
  'anon still reads the public result through the view');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"e2470000-0000-0000-0000-000000000002","role":"authenticated"}';
select lives_ok(
  $$ insert into event_results (event_id, instance_start, user_id, duration_s, distance_m, note, run_id,
                                age_grade_pct, start_at, finish_at, start_detection, finish_detection,
                                clock_offset_ms)
     values ('e2470000-0000-0000-0000-0000000000e1', '2026-09-05 08:00+00',
             'e2470000-0000-0000-0000-000000000002', 1490, 5000, 'faster', null, null, null, null, null,
             null, null)
     on conflict (event_id, instance_start, user_id) do update
       set duration_s = excluded.duration_s, note = excluded.note, run_id = excluded.run_id,
           age_grade_pct = excluded.age_grade_pct, start_at = excluded.start_at,
           finish_at = excluded.finish_at, start_detection = excluded.start_detection,
           finish_detection = excluded.finish_detection, clock_offset_ms = excluded.clock_offset_ms $$,
  'the runner''s own merge upsert, reading every column it writes back from EXCLUDED, still lands');

select is(
  (select note from event_results_redacted where event_id = 'e2470000-0000-0000-0000-0000000000e1'),
  'faster',
  'the upsert''s note is stored');

select * from finish();
rollback;

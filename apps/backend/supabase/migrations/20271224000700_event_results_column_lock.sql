-- event_results stops handing the columns event_results_redacted hides to a
-- caller who reads the table directly (audit of PR #1359, Medium).
--
-- The redacted view nulls age_grade_pct, note, run_id and clock_offset_ms for
-- everyone but the result's runner, and the two detections and needs_review
-- for everyone but the runner and the race director. The base table still
-- carried a table-wide SELECT for anon and authenticated, and its only row
-- gate is the event's visibility, so any reader of a public club's event
-- could ask PostgREST for those columns, and for the start_at / finish_at
-- crossings the view never shows, straight from event_results. The view was
-- a presentation, not a control.
--
-- Two things change.
--
-- 1. The view reads what it withholds through
--    private.event_result_withheld_columns(id), SECURITY DEFINER, which
--    returns a result's withheld columns to its runner and the race director
--    (the detections and needs_review only) and nothing to anyone else. The
--    view stays security_invoker = on, so event_results RLS still decides
--    which rows a caller sees (rls_definer_hygiene_pt3_test); it now needs no
--    caller privilege on the withheld columns, which is what lets them be
--    revoked. It costs a row one call, a primary-key read plus the director
--    test, where the old CASE columns made up to three director tests.
--
-- 2. Table-level SELECT is revoked and re-granted per column
--    (column_grant_lockdown_registry_test holds the withheld set):
--      * anon reads the leaderboard columns only. It writes nothing.
--      * authenticated reads the same, plus the eight columns the runner's
--        own result upsert writes: age_grade_pct, note, run_id, start_at,
--        finish_at, start_detection, finish_detection, clock_offset_ms. An
--        INSERT ... ON CONFLICT DO UPDATE needs SELECT on every column its
--        SET reads from EXCLUDED, and PostgREST's merge upsert sets every
--        column in the body, so withholding them refuses every result the
--        web, the phones and the Wear watch file today, released builds
--        included. Withholding them from authenticated waits for a write
--        path that does not read them back (followups, "Surfaced by the PR
--        #1359 rounds").
--      * Neither role reads needs_review, organiser_approved_by or
--        organiser_approved_at from the table. No client writes needs_review;
--        a director's approval writes the other two with a plain UPDATE,
--        which needs no SELECT on them.
--    A column added to event_results later is withheld from both until a
--    migration grants it.
--
-- Realtime keeps working: postgres_changes needs the primary key selectable
-- and drops from a change event the columns the subscriber cannot select.
--
-- Locks: REVOKE / GRANT and CREATE OR REPLACE VIEW change the catalog only;
-- the view swap takes ACCESS EXCLUSIVE on the view for the replace, not on
-- event_results.

create or replace function private.event_result_withheld_columns(p_id uuid)
returns table (
  age_grade_pct double precision,
  note text,
  run_id uuid,
  start_detection text,
  finish_detection text,
  needs_review boolean,
  clock_offset_ms bigint
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select
    case when r.user_id = auth.uid() then r.age_grade_pct end,
    case when r.user_id = auth.uid() then r.note end,
    case when r.user_id = auth.uid() then r.run_id end,
    r.start_detection,
    r.finish_detection,
    r.needs_review,
    case when r.user_id = auth.uid() then r.clock_offset_ms end
  from event_results r
  where r.id = p_id
    and (r.user_id = auth.uid()
         or private.is_race_director((select e.club_id from events e where e.id = r.event_id)));
$$;

revoke execute on function private.event_result_withheld_columns(uuid) from public;
grant execute on function private.event_result_withheld_columns(uuid) to anon, authenticated;

comment on function private.event_result_withheld_columns(uuid) is
  'The columns event_results_redacted withholds, for one result: all of them '
  'to its runner, start_detection / finish_detection / needs_review to the '
  'race director of its club, no row to anyone else. Lets the security_invoker '
  'view read them although anon and authenticated may not select them from '
  'event_results (20271224000700).';

create or replace view public.event_results_redacted
with (security_invoker = on)
as
select
  r.id,
  r.event_id,
  r.instance_start,
  r.user_id,
  r.bib,
  r.finisher_name,
  r.duration_s,
  r.distance_m,
  r.rank,
  r.finisher_status,
  w.age_grade_pct,
  w.note,
  r.created_at,
  r.updated_at,
  r.organiser_approved,
  w.run_id,
  r.course_id,
  r.gun_time_s,
  r.chip_time_s,
  r.finish_method,
  w.start_detection,
  w.finish_detection,
  w.needs_review,
  w.clock_offset_ms
from public.event_results r
left join lateral private.event_result_withheld_columns(r.id) w on true;

revoke all on public.event_results_redacted from public, anon, authenticated;
grant select on public.event_results_redacted to anon, authenticated;

comment on view public.event_results_redacted is
  'security_invoker=on is DELIBERATE: row visibility is enforced by '
  'event_results RLS evaluated in the caller''s context. Flipping it off would '
  'run the view as owner and bypass RLS, leaking results for private-club '
  'events to anon. The withheld columns (age_grade_pct, note, run_id, '
  'clock_offset_ms for the runner; start_detection, finish_detection, '
  'needs_review for the runner and the race director) come from '
  'private.event_result_withheld_columns, because the callers may not select '
  'them from event_results (20271224000700). Pinned by '
  'rls_definer_hygiene_pt3_test.sql and event_results_column_lock_test.sql.';

revoke select on public.event_results from anon, authenticated;

grant select (
  id, event_id, instance_start, user_id, bib, finisher_name, duration_s, distance_m, rank,
  finisher_status, created_at, updated_at, organiser_approved, course_id, gun_time_s,
  chip_time_s, finish_method
) on public.event_results to anon, authenticated;

grant select (
  age_grade_pct, note, run_id, start_at, finish_at, start_detection, finish_detection, clock_offset_ms
) on public.event_results to authenticated;

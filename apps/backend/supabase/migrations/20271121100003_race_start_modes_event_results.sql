-- Race start modes (#1306, decisions § 2400-§ 2401): the event_results
-- crossing columns and their CHECKs, moved out of 20271121002400 so that no
-- transaction holds ACCESS EXCLUSIVE on two tables
-- (docs/backend/migration_locks.md § One table per migration).
--
-- Locks: ACCESS EXCLUSIVE on event_results for catalogue-only changes, and
-- nothing else.
--
-- Written to be re-runnable, because a database that ran the earlier form of
-- 20271121002400 already has all of this: ADD COLUMN IF NOT EXISTS, each CHECK
-- dropped if present and re-added NOT VALID, and 20271121100007 validates
-- them again in its own transaction.

set search_path = public;

-- ─── event_results: crossing instants (#1307 schema, read here) ────────────

alter table public.event_results
  add column if not exists start_at timestamptz,
  add column if not exists finish_at timestamptz,
  add column if not exists start_detection text,
  add column if not exists finish_detection text,
  add column if not exists needs_review boolean not null default false;

alter table public.event_results
  drop constraint if exists event_results_start_detection_check,
  drop constraint if exists event_results_finish_detection_check,
  drop constraint if exists event_results_finish_detection_auto_check;

alter table public.event_results
  add constraint event_results_start_detection_check
    check (start_detection in ('gate', 'device')) not valid,
  add constraint event_results_finish_detection_check
    check (finish_detection in ('gate', 'zone')) not valid,
  add constraint event_results_finish_detection_auto_check
    check (finish_detection is null or finish_method = 'auto') not valid;

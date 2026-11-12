-- Race start modes (#1306, decisions § 2400-§ 2401): the race_sessions mode
-- and instant columns and their CHECKs, moved out of 20271121002400 so that no
-- transaction holds ACCESS EXCLUSIVE on two tables
-- (docs/backend/migration_locks.md § One table per migration).
--
-- Locks: ACCESS EXCLUSIVE on race_sessions for catalogue-only changes, and
-- nothing else.
--
-- Written to be re-runnable, because a database that ran the earlier form of
-- 20271121002400 already has all of this: ADD COLUMN IF NOT EXISTS, each CHECK
-- dropped if present and re-added NOT VALID, and 20271121100007 validates
-- them again in its own transaction.

set search_path = public;

-- ─── race_sessions: the mode and its instants ──────────────────────────────

alter table public.race_sessions
  add column if not exists start_mode text not null default 'host_go',
  add column if not exists scheduled_start_at timestamptz,
  add column if not exists window_opens_at timestamptz,
  add column if not exists window_closes_at timestamptz;

alter table public.race_sessions
  drop constraint if exists race_sessions_start_mode_check,
  drop constraint if exists race_sessions_start_mode_times_check;

alter table public.race_sessions
  add constraint race_sessions_start_mode_check
    check (start_mode in ('host_go', 'scheduled', 'self_timed')) not valid,
  add constraint race_sessions_start_mode_times_check
    check (
      case start_mode
        when 'host_go' then
          scheduled_start_at is null and window_opens_at is null and window_closes_at is null
        when 'scheduled' then
          scheduled_start_at is not null and window_opens_at is null
          and window_closes_at is not null and window_closes_at > scheduled_start_at
        when 'self_timed' then
          scheduled_start_at is null and window_opens_at is not null
          and window_closes_at is not null and window_closes_at > window_opens_at
          and window_closes_at <= window_opens_at + interval '7 days'
        else false
      end
    ) not valid;

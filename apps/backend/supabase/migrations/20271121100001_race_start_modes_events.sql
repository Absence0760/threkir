-- Race start modes (#1306, decisions § 2400-§ 2401): the events settings
-- columns and their CHECKs, moved out of 20271121002400 so that no transaction
-- holds ACCESS EXCLUSIVE on two tables (docs/backend/migration_locks.md § One
-- table per migration).
--
-- Locks: ACCESS EXCLUSIVE on events for catalogue-only changes (a constant
-- default, NOT VALID CHECKs), then the partial index on that bounded config
-- table.
--
-- Written to be re-runnable, because a database that ran the earlier form of
-- 20271121002400 already has all of this: ADD COLUMN IF NOT EXISTS, each CHECK
-- dropped if present and re-added NOT VALID, and 20271121100007 validates
-- them again in its own transaction.

set search_path = public;

-- ─── events: per-event settings ────────────────────────────────────────────

alter table public.events
  add column if not exists race_start_mode text not null default 'host_go',
  add column if not exists race_scheduled_offset_s integer,
  add column if not exists race_window_open_offset_s integer,
  add column if not exists race_window_length_s integer,
  add column if not exists race_auto_approve boolean;

alter table public.events
  drop constraint if exists events_race_start_mode_check,
  drop constraint if exists events_race_scheduled_offset_s_check,
  drop constraint if exists events_race_window_open_offset_s_check,
  drop constraint if exists events_race_window_length_s_check,
  drop constraint if exists events_race_start_settings_check;

alter table public.events
  add constraint events_race_start_mode_check
    check (race_start_mode in ('host_go', 'scheduled', 'self_timed')) not valid,
  -- A scheduled GO sits within a day either side of the occurrence's start; a
  -- self-timed window opens up to a day before it and up to a week after; a
  -- window (or a scheduled race's auto-end) lasts up to 7 days.
  add constraint events_race_scheduled_offset_s_check
    check (race_scheduled_offset_s between -86400 and 86400) not valid,
  add constraint events_race_window_open_offset_s_check
    check (race_window_open_offset_s between -86400 and 604800) not valid,
  add constraint events_race_window_length_s_check
    check (race_window_length_s between 60 and 604800) not valid,
  add constraint events_race_start_settings_check
    check (
      (race_start_mode <> 'scheduled'
           or (race_scheduled_offset_s is not null and race_window_length_s is not null))
      and (race_start_mode <> 'self_timed'
           or (race_window_open_offset_s is not null and race_window_length_s is not null))
    ) not valid;

-- events carries column-level SELECT grants (20270408_001); a column added
-- after the lockdown is withheld until granted. The race settings are what the
-- event page, the spectator page and the devices read.
grant select (race_start_mode, race_scheduled_offset_s, race_window_open_offset_s,
              race_window_length_s, race_auto_approve)
  on public.events to authenticated, anon;

create index if not exists events_race_start_mode_idx
  on public.events (race_start_mode)
  where race_start_mode <> 'host_go';

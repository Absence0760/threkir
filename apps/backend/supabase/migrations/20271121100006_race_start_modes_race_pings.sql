-- Race start modes (#1306, decisions § 2400-§ 2401): the race_pings column,
-- its CHECK and the live-by-the-clock insert policy, moved out of
-- 20271121002400 so that no transaction holds ACCESS EXCLUSIVE on two tables
-- (docs/backend/migration_locks.md § One table per migration).
--
-- Locks: ACCESS EXCLUSIVE on race_pings, a high-write table, for catalogue-only
-- changes, held only for this short file. The policy calls
-- private.race_session_is_live, redefined by 20271121100005.
--
-- Written to be re-runnable, because a database that ran the earlier form of
-- 20271121002400 already has all of this: ADD COLUMN IF NOT EXISTS, each CHECK
-- dropped if present and re-added NOT VALID, and 20271121100007 validates
-- them again in its own transaction.

set search_path = public;

-- ─── race_pings: seconds since the runner's start-line crossing (M13) ──────

alter table public.race_pings
  add column if not exists since_start_line_s integer;

alter table public.race_pings
  drop constraint if exists race_pings_since_start_line_s_check;

alter table public.race_pings
  add constraint race_pings_since_start_line_s_check
    check (since_start_line_s between 0 and 1209600) not valid;

drop policy if exists race_pings_insert_self_while_running on public.race_pings;
create policy race_pings_insert_self_while_running
  on public.race_pings for insert
  with check (
    (select auth.uid()) = user_id
    and private.race_session_is_live(event_id, instance_start)
  );

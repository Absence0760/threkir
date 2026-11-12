-- Race start modes (#1306, decisions § 2400-§ 2401): the starting-soon
-- dedupe index, moved out of 20271121002400 so it is built alone. It must
-- exist before 20271121100005 schedules race_sessions_tick, whose insert
-- relies on it.
--
-- Locks: the build reads the notifications heap once under SHARE, so the
-- fan-out's inserts wait for that read and readers (the bell) do not. In
-- 20271121002400 it ran under the kind_check swap's ACCESS EXCLUSIVE, which
-- stopped reads for the whole scan. No existing row has the new kind, so the
-- index is empty; the scan is not. IF NOT EXISTS keeps it a no-op on a
-- database that built it from the earlier form of 20271121002400.

set search_path = public;

-- One "starting soon" per runner per occurrence: the per-minute job re-runs.
create unique index if not exists notifications_race_starting_soon_uniq
  on notifications (user_id, event_id, event_instance_start)
  where kind = 'race_starting_soon';

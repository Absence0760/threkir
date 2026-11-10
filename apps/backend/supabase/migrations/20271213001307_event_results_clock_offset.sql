-- Timing lines phase 4 (#1307, M11): the device-to-server clock offset a
-- result's crossing instants were converted with.
--
-- `start_at` / `finish_at` are the device's crossing instants plus its latest
-- server offset. Persisting the offset lets a re-time from the saved track
-- (whose points carry device timestamps) land on the same clock basis the live
-- result used, so its gun time matches. Milliseconds, signed: server minus
-- device. Null for a result filed by a client that predates it, an import or a
-- host-filed row.
--
-- Locks: ACCESS EXCLUSIVE on event_results for a catalogue-only change (a
-- nullable column with no default rewrites nothing), and nothing else.

set search_path = public;

alter table public.event_results
  add column if not exists clock_offset_ms bigint;

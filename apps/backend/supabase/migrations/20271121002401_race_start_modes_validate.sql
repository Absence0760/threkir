-- Second half of 20271121002400: validate the CHECKs it added NOT VALID.
--
-- VALIDATE CONSTRAINT scans under SHARE UPDATE EXCLUSIVE, so reads and writes
-- keep flowing, in its own transaction apart from the ACCESS EXCLUSIVE the
-- additions took (docs/backend/migration_locks.md § CHECK constraints). Every
-- new column is NULL or its constant default on existing rows, and the kind
-- set only widened, so no scan can find a violation.

alter table public.events validate constraint events_race_start_mode_check;
alter table public.events validate constraint events_race_scheduled_offset_s_check;
alter table public.events validate constraint events_race_window_open_offset_s_check;
alter table public.events validate constraint events_race_window_length_s_check;
alter table public.events validate constraint events_race_start_settings_check;
alter table public.race_sessions validate constraint race_sessions_start_mode_check;
alter table public.race_sessions validate constraint race_sessions_start_mode_times_check;
alter table public.event_results validate constraint event_results_start_detection_check;
alter table public.event_results validate constraint event_results_finish_detection_check;
alter table public.event_results validate constraint event_results_finish_detection_auto_check;
alter table public.race_pings validate constraint race_pings_since_start_line_s_check;
alter table notifications validate constraint notifications_kind_check;

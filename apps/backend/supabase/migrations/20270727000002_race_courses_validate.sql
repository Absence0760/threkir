-- Validate the constraints 20270727000001 added NOT VALID to the populated
-- event_attendees and event_results tables (docs/backend/migration_locks.md).
--
-- In its own file, so each scan runs in this transaction under SHARE UPDATE
-- EXCLUSIVE — reads and writes proceed — rather than under the ACCESS
-- EXCLUSIVE the adding file still held. Every existing row passes: the four
-- columns were added NULL with no default in that file, and NULL satisfies
-- each CHECK and each foreign key.

alter table public.event_attendees validate constraint event_attendees_course_id_fkey;

alter table public.event_results validate constraint event_results_course_id_fkey;
alter table public.event_results validate constraint event_results_gun_time_s_check;
alter table public.event_results validate constraint event_results_chip_time_s_check;
alter table public.event_results validate constraint event_results_finish_method_check;

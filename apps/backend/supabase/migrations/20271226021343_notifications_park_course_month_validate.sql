-- Validates the notifications_kind_check, notifications_park_course_time_s_check
-- and notifications_park_course_id_fkey that 20271226011343 added NOT VALID, in their own file so the scan of a
-- high-volume table holds nothing on any other (docs/backend/migration_locks.md
-- § One table per migration). VALIDATE runs under SHARE UPDATE EXCLUSIVE, so
-- inserts proceed; the kind list only widened and both new columns are null on
-- every existing row, so all three pass.

alter table notifications validate constraint notifications_kind_check;
alter table notifications validate constraint notifications_park_course_time_s_check;
alter table notifications validate constraint notifications_park_course_id_fkey;

-- Validates what 20271215000001 added NOT VALID, in this file's own
-- transaction so the scans run under SHARE UPDATE EXCLUSIVE and writes to
-- event_results proceed (docs/backend/migration_locks.md). Every existing row
-- satisfies them: status_before is only ever copied from park_courses.status,
-- reports_resolved from a row count, and a clock_offset_ms is an offset a
-- device measured over TLS.

alter table park_course_status_actions validate constraint park_course_status_actions_status_before_check;
alter table park_course_status_actions validate constraint park_course_status_actions_reports_resolved_check;
alter table event_results validate constraint event_results_clock_offset_ms_check;

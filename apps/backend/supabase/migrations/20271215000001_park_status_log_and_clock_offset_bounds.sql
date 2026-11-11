-- Bounds for three columns that landed with no CHECK, which the catalogue
-- guards (free_text_caps_test, numeric_bounds_reject_nan_test) caught:
--
--   park_course_status_actions.status_before  admin_set_park_course_status
--     copies park_courses.status into it, so it takes that column's vocabulary.
--   park_course_status_actions.reports_resolved  a row count, never negative.
--   event_results.clock_offset_ms  server minus device, in milliseconds. A
--     device can only file a result over TLS, which refuses a clock outside the
--     certificate's validity window, and a publicly trusted certificate lives at
--     most 398 days. 400 days either way therefore never refuses a result a
--     device could have sent, and still refuses an overflowed or garbage value.
--
-- Added NOT VALID; 20271215000002 validates them in its own transaction
-- (docs/backend/migration_locks.md). Each ADD is a metadata-only change.

set search_path = public;

alter table park_course_status_actions
  add constraint park_course_status_actions_status_before_check
  check (status_before in ('open', 'closed', 'seasonal'))
  not valid;

alter table park_course_status_actions
  add constraint park_course_status_actions_reports_resolved_check
  check (reports_resolved >= 0)
  not valid;

alter table event_results
  add constraint event_results_clock_offset_ms_check
  check (clock_offset_ms is null or clock_offset_ms between -34560000000 and 34560000000)
  not valid;

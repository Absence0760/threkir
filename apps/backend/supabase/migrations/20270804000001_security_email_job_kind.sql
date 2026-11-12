-- Admit `security_email` on the jobs queue: the account-security mail the Go
-- worker sends that is neither a notification mirror nor lifecycle mail. Its
-- first template is `new_device_sign_in`, enqueued by the auth.sessions
-- triggers in 20270804000002 (docs/features/email.md § Security emails).
--
-- A kind of its own rather than a `lifecycle_email` template because the two
-- disagree on the one rule that matters: lifecycle mail cannot be opted out of
-- (a receipt is a receipt), while the new-device alert honours the opt-OUT
-- `email_new_device_alerts` pref, and it carries per-sign-in context (device
-- class + time) no lifecycle template has.
--
-- `apps/job_worker/internal/worker_dispatch_coverage_test.go` fails a kind
-- this CHECK admits with no dispatch `case`, so the handler lands in the same
-- change.
--
-- `drop` + `add ... not valid` with no `validate`, for the reason
-- 20270708000010 records at length (decisions § 1148): `jobs` is on
-- migration_locks.md's guarded list, a same-file VALIDATE scans under the
-- drop's ACCESS EXCLUSIVE anyway, and for a strict WIDEN there is nothing for
-- the scan to find — every existing row was admitted by the narrower CHECK
-- this replaces. A NOT VALID CHECK still binds every new write.
alter table public.jobs
  drop constraint jobs_kind_chk;
alter table public.jobs
  add constraint jobs_kind_chk
  check (
    kind in (
      'map_match', 'token_refresh', 'strava_event', 'photo_process',
      'notification_email', 'lifecycle_email', 'safety_email', 'web_push',
      'weekly_digest', 'native_push', 'lifecycle_drip', 'route_photo_process',
      'club_photo_process', 'safety_sms', 'data_export', 'export_blob_reap',
      'distance_recompute', 'security_email'
    )
  )
  not valid;

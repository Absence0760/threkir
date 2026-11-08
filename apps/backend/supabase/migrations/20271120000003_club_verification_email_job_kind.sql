-- The `club_verification_email` job kind (issue #1190 § 2, decisions § 2398).
--
-- The email proof of a club verification request sends one message to an
-- address at the club's claimed domain, carrying a single-use confirm link.
-- It is none of the existing email kinds: the recipient is not a user (so not
-- notification_email or lifecycle_email, which resolve a user's address), and
-- it is not safety mail. It rides the same queue, worker and SMTP transport.
--
-- `drop` + `add ... not valid` and deliberately no `validate`: `jobs` is on
-- migration_locks.md's guarded list, a same-file VALIDATE would scan under the
-- ACCESS EXCLUSIVE the drop still holds, and a strict-superset widen can only
-- confirm what the narrower CHECK already enforced (decisions § 1148).

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
      'distance_recompute', 'security_email', 'route_photo_orphan_sweep',
      'club_verification_email'
    )
  )
  not valid;

-- The `duration_repair` job kind (issue #1300 § 5, decisions § 2464).
--
-- 20271218000002 caps every run stored above runs_duration_s_max_check's ten
-- days and enqueues one of these for each capped run that has a stored track.
-- The worker reads the track's timestamps and, when they give a believable
-- span, replaces the cap with it. It is not `distance_recompute`: that job
-- skips manual entries and every import, which are the rows this one exists
-- for, and it rewrites the distance, which this one must leave alone.
--
-- `drop` + `add ... not valid` and deliberately no `validate`: `jobs` is on
-- migration_locks.md's guarded list, a same-file VALIDATE would scan under the
-- ACCESS EXCLUSIVE the drop still holds, and a strict-superset widen can only
-- confirm what the narrower CHECK already enforced (decisions § 1148). Its own
-- file because the next one takes `runs` locks (§ One table per migration).

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
      'segment_match', 'club_verification_email', 'dm_image_process',
      'dm_image_orphan_sweep', 'duration_repair'
    )
  )
  not valid;

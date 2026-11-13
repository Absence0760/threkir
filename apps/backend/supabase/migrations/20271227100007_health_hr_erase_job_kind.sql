-- The `health_hr_erase` job kind (decisions § 2514).
--
-- Withdrawing health-data consent erases the heart rate a runner has stored.
-- The rows are erased in the withdrawal's own transaction (20271227100008),
-- but two copies live in Storage, where SQL cannot reach them: the
-- {user_id}/{run_id}.hr.json.gz sidecars and the per-point bpm inside each
-- {user_id}/{run_id}.json.gz track. The withdrawal enqueues one of these; the
-- Go worker deletes the sidecars and rewrites each track without bpm.
--
-- `drop` + `add ... not valid` and deliberately no `validate`, as
-- 20271218000001 does: jobs is on migration_locks.md's guarded list and a
-- strict-superset widen can only confirm what the narrower CHECK enforced
-- (decisions § 1148). Its own file: the next one takes locks on runs and
-- food_log (§ One table per migration).

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
      'dm_image_orphan_sweep', 'duration_repair', 'health_hr_erase'
    )
  )
  not valid;

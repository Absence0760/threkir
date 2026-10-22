-- Switch the report retention purge on (decisions § 2234). The
-- 6/12-month windows were approved by the owner as controller, on the memo in
-- reviews/legal-dm-deletion-rule.md. Left off, every resolved report and its
-- direct-message snapshot would be kept forever, which Art 5(1)(e) does not
-- allow. Seeding the row in a migration, rather than by hand in the SQL
-- editor, means a fresh environment or a disaster-recovery rebuild cannot
-- come back with retention silently off. A held report is never purged.
insert into private.feature_flags (name, enabled)
values ('reports_retention_purge', true)
on conflict (name) do update set enabled = true, updated_at = now();

comment on function private.report_retention_window(text) is
  'Retention after resolution per report status: dismissed (no action) 6 '
  'months, reviewed (action taken) 12 months, null (never) otherwise. The '
  'single source for purge_stale_reports() and the admin purge_after column. '
  'Approved by the owner as controller (decisions § 2234).';

comment on function private.purge_stale_reports() is
  'GDPR Art 5(1)(e) storage limitation for reports: deletes resolved, '
  'unheld reports (and their direct-message snapshots) once '
  'private.report_retention_window() has passed since reviewed_at. Never '
  'touches a pending or legal_hold report. Gated on private.feature_flags '
  'reports_retention_purge (absent = off), seeded on by 20271022000001. '
  'Scheduled by pg_cron `purge-stale-reports` (03:59 UTC daily). '
  'decisions § 2231, § 2234.';

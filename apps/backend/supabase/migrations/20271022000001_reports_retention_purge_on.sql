-- Switch the report retention purge on (decisions § 2231 amendment). The
-- 6/12-month windows were approved by the owner as controller, on the memo in
-- reviews/legal-dm-deletion-rule.md. Left off, every resolved report and its
-- direct-message snapshot would be kept forever, which Art 5(1)(e) does not
-- allow. Seeding the row in a migration, rather than by hand in the SQL
-- editor, means a fresh environment or a disaster-recovery rebuild cannot
-- come back with retention silently off. A held report is never purged.
insert into private.feature_flags (name, enabled)
values ('reports_retention_purge', true)
on conflict (name) do update set enabled = true, updated_at = now();

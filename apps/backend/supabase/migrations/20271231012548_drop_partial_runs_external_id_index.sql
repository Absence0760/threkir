-- Drop the partial (user_id, external_id) index that
-- 20271231002548's runs_user_external_id_arbiter replaces (decisions § 2548).
-- The new index enforces the same per-runner uniqueness and is the one an
-- upsert can name, so this one is only a second copy of the same check.
--
-- Lock: DROP INDEX takes a brief ACCESS EXCLUSIVE on runs, catalogue-only,
-- alone in its file.

drop index if exists runs_user_external_id;

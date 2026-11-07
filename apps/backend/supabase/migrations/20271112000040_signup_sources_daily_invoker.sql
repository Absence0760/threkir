-- The sign-up source view runs as its caller (decisions § 2362).
--
-- `private.signup_sources_daily` (20271110000001) left `security_invoker`
-- off, so it ran as its owner: the twelfth owner-run view in the app schemas,
-- which `security_definer_views_test.sql` refuses unless a decision accepts
-- it. Nothing here earns acceptance. The eleven accepted views are redaction
-- layers that a client role reads; this one is read only by the owner in the
-- SQL editor, who can read `auth.users` and `private.signup_sources` directly,
-- so running as the caller changes nothing for that reader.
--
-- Its `service_role` grant goes with it: `service_role` holds no SELECT on
-- `auth.users`, so as the caller it could no longer read the view, and no
-- code path reads it as `service_role` (the Edge Functions, worker and web
-- server never name it). The grant would only advertise a read that fails.
--
-- Locks: ALTER VIEW ... SET takes ACCESS EXCLUSIVE on the view alone for a
-- catalogue update (no table is scanned or rewritten); REVOKE is catalogue
-- only. Neither type generator reads the private schema.

alter view private.signup_sources_daily set (security_invoker = true);

revoke select on private.signup_sources_daily from service_role;

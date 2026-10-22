-- AI disclosure v6: the Coach copy catches up with what the Coach sends
-- (issue #1217). Since the Tier-1 multi-modal work the Coach context has
-- carried a summary of the runner's recent gym sessions and, with health-data
-- consent, a 7-day nutrition rollup. No disclosure version named either, so a
-- runner who accepted v1-v5 never agreed to them. Per decisions.md § 571 the
-- copy that names them is a new rung, not a quiet edit to an older one:
--
--   v1  AI Coach only — profile slice, recent runs, active plan, chat text.
--   v2  v1 plus the AI route assistant.
--   v3  v2 plus the AI plan assistant.
--   v4  v3 plus AI plan edits.
--   v5  v4 plus the plate-photo logger.
--   v6  v5 plus the Coach's cross-training context: recent gym-session
--       summaries and (health-data consent only) a 7-day nutrition summary;
--       the copy also names resting / max HR, the weekly distance goal and
--       the coaching style the Coach already received.
--
-- The Coach's own minimum stays at 1. The gym and nutrition lanes of its
-- context are gated per lane on an accepted version >= 6 server-side
-- (apps/web/src/lib/coach/context.ts, COACH_CONTEXT_REGISTRY), so a holder of
-- v1-v5 keeps a working Coach with the data they agreed to and is invited to
-- accept v6 by the existing Settings notice. record_ai_disclosure_consent()
-- reads its upper bound from this function, so nothing else changes.
--
-- Prod deploy is gated on counsel / CISO sign-off of the v6 disclosure copy
-- (a privacy-boundary change).

create or replace function ai_disclosure_current_version()
returns smallint
language sql
immutable
set search_path = public
as $$ select 6::smallint $$;

comment on function ai_disclosure_current_version() is
  'Highest known AI-disclosure version. The TS mirror is '
  'AI_DISCLOSURE_CURRENT_VERSION in apps/web/src/lib/core/ai_disclosure.ts; '
  'its ai_disclosure.test.ts fails the build if the two drift.';

revoke all on function ai_disclosure_current_version() from public, anon;
grant execute on function ai_disclosure_current_version() to authenticated, service_role;

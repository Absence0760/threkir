-- AI disclosure v7: the coach assistant (issue #1215 Phase 4). A coach who
-- uses it sends their own request and their conversation with an athlete to
-- Anthropic to draft a message, a purpose no earlier copy named, so per
-- decisions § 571 it is a new rung, not an edit to v6:
--
--   v6  all AI features so far.
--   v7  v6 plus the coach assistant, for coaches: with the athlete's own
--       consent on that coaching link, the athlete's messages with the coach,
--       their plan and upcoming workouts and their recent runs, and what the
--       coach types, sent only to draft a message the coach edits and sends.
--
-- /api/coach/assist requires v7 of the coach; nothing else moves. The athlete's
-- data also needs the athlete's per-link consent (20271210001217). A holder of
-- v1-v6 keeps every feature they had and is invited to accept v7 by the
-- existing Settings notice. record_ai_disclosure_consent() reads its upper
-- bound from this function.
--
-- Prod deploy is gated on counsel / CISO sign-off of the v7 copy (a
-- privacy-boundary change), with the coach-assistant sign-off.

create or replace function ai_disclosure_current_version()
returns smallint
language sql
immutable
set search_path = public
as $$ select 7::smallint $$;

comment on function ai_disclosure_current_version() is
  'Highest known AI-disclosure version. The TS mirror is '
  'AI_DISCLOSURE_CURRENT_VERSION in apps/web/src/lib/core/ai_disclosure.ts; '
  'its ai_disclosure.test.ts fails the build if the two drift.';

revoke all on function ai_disclosure_current_version() from public, anon;
grant execute on function ai_disclosure_current_version() to authenticated, service_role;

-- AI plan assistant: the /plans/new wizard gains a free-text box ("sub-2
-- half in March, 4 days a week, last 5k was 26:30") whose text
-- /api/coach/plan-request sends to Anthropic to extract the structured
-- inputs the deterministic plan generator already takes. The model never
-- authors the plan; it only fills in the wizard's fields.
--
-- That is a different payload (the typed plan description: goal race,
-- target and recent times, training days) for a different purpose than
-- either rung below it described, so per decisions.md § 571 it gets a new
-- rung on the monotone disclosure ladder rather than quietly widening what
-- a v2 acceptance covers:
--
--   v1  AI Coach only — profile slice, recent runs, active plan, chat text.
--   v2  v1 plus the AI route assistant (route stats + name, the typed route
--       request and its coarse location label).
--   v3  v2 plus the AI plan assistant — the typed plan request text, sent
--       only to extract plan-wizard settings.
--
-- Existing v1 / v2 acceptances are left exactly as recorded. A v2 holder
-- keeps the Coach and the route assistant and is refused (403) by the plan
-- endpoint until they accept the v3 disclosure; record_ai_disclosure_consent()
-- already reads its upper bound from this function, so nothing else changes.
--
-- Prod deploy is gated on counsel / CISO sign-off of the v3 disclosure copy
-- (a privacy-boundary change) per the compliance-sign-off rule — the code
-- lands now, fail-closed, behind that deploy gate.

create or replace function ai_disclosure_current_version()
returns smallint
language sql
immutable
set search_path = public
as $$ select 3::smallint $$;

comment on function ai_disclosure_current_version() is
  'Highest known AI-disclosure version. The TS mirror is '
  'AI_DISCLOSURE_CURRENT_VERSION in apps/web/src/lib/core/ai_disclosure.ts; '
  'its ai_disclosure.test.ts fails the build if the two drift.';

revoke all on function ai_disclosure_current_version() from public, anon;
grant execute on function ai_disclosure_current_version() to authenticated, service_role;

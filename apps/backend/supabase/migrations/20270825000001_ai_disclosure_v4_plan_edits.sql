-- AI plan edits: /plans/[id] gains an "Adjust with AI" box ("move my long run
-- to Sunday", "make this week easier") whose text /api/coach/plan-edit sends
-- to Anthropic together with the upcoming part of the runner's active plan
-- (each workout's date, type and distance, as short references), so one
-- forced tool call can return a typed list of edit operations against it.
-- The server validates every operation against the caller's own plan, the
-- client applies them with the deterministic plan helpers and re-grades the
-- result, and nothing is saved until the runner confirms the before/after
-- diff. The model never writes a workout, a distance or a pace.
--
-- The v1 Coach copy already lists "the active training plan you have
-- selected", but for a different purpose: so the Coach can comment on it.
-- Sending that plan, with the runner's change request, so a model can
-- propose changes to it is a new purpose, so per decisions.md § 571 it gets a
-- new rung on the monotone disclosure ladder rather than being read into
-- what a v1 / v3 acceptance covers:
--
--   v1  AI Coach only — profile slice, recent runs, active plan, chat text.
--   v2  v1 plus the AI route assistant (route stats + name, the typed route
--       request and its coarse location label).
--   v3  v2 plus the AI plan assistant — the typed plan request text, sent
--       only to extract plan-wizard settings.
--   v4  v3 plus AI plan edits — the active plan's upcoming workouts and the
--       typed change request, sent only to propose edits the runner reviews.
--
-- Existing v1-v3 acceptances are left exactly as recorded. A v3 holder keeps
-- every earlier feature and is refused (403) by the plan-edit endpoint until
-- they accept the v4 disclosure; record_ai_disclosure_consent() already reads
-- its upper bound from this function, so nothing else changes.
--
-- Prod deploy is gated on counsel / CISO sign-off of the v4 disclosure copy
-- (a privacy-boundary change) per the compliance-sign-off rule. Because the
-- function is global, the v4 copy is what every AI surface presents from the
-- deploy that carries this migration, whether or not the feature flag is on.

create or replace function ai_disclosure_current_version()
returns smallint
language sql
immutable
set search_path = public
as $$ select 4::smallint $$;

comment on function ai_disclosure_current_version() is
  'Highest known AI-disclosure version. The TS mirror is '
  'AI_DISCLOSURE_CURRENT_VERSION in apps/web/src/lib/core/ai_disclosure.ts; '
  'its ai_disclosure.test.ts fails the build if the two drift.';

revoke all on function ai_disclosure_current_version() from public, anon;
grant execute on function ai_disclosure_current_version() to authenticated, service_role;

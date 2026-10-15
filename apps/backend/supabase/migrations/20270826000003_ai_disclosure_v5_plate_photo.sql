-- AI plate-photo logging: the /nutrition/log "Log from a photo" control sends
-- a photo of the runner's meal to Anthropic, whose vision model proposes
-- food_log rows the runner then reviews and edits before anything is saved
-- (decisions § 1972). A photograph is a new kind of payload — it can show
-- the runner's home, other people, or anything else in frame — for a new
-- purpose (estimating a meal), so per decisions.md § 571 it gets its own rung
-- on the monotone disclosure ladder instead of widening an older one:
--
--   v1  AI Coach only — profile slice, recent runs, active plan, chat text.
--   v2  v1 plus the AI route assistant.
--   v3  v2 plus the AI plan assistant.
--   v4  v3 plus AI plan edits (a sibling migration that sorts before this one).
--   v5  v4 plus the plate-photo logger — one meal photo per request, metadata
--       stripped server-side before it leaves, never stored by Threkir.
--
-- Older acceptances stay exactly as recorded. A holder of any lower version
-- keeps what they accepted and is refused (403) by the plate-photo endpoint
-- until they accept v5; record_ai_disclosure_consent() reads its upper bound
-- from this function, so nothing else changes.
--
-- Prod deploy is gated on counsel / CISO sign-off of the v5 disclosure copy
-- (a privacy-boundary change) — the code lands now, fail-closed, behind
-- PUBLIC_PLATE_PHOTO_ENABLED / PLATE_PHOTO_ENABLED.

create or replace function ai_disclosure_current_version()
returns smallint
language sql
immutable
set search_path = public
as $$ select 5::smallint $$;

comment on function ai_disclosure_current_version() is
  'Highest known AI-disclosure version. The TS mirror is '
  'AI_DISCLOSURE_CURRENT_VERSION in apps/web/src/lib/core/ai_disclosure.ts; '
  'its ai_disclosure.test.ts fails the build if the two drift.';

revoke all on function ai_disclosure_current_version() from public, anon;
grant execute on function ai_disclosure_current_version() to authenticated, service_role;

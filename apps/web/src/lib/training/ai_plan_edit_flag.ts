/**
 * Fail-closed feature gate for AI plan edits — the "Adjust with AI" option on
 * /plans/[id] (`/api/coach/plan-edit`) and the Coach's handoff link into it.
 *
 * This is the deploy gate for two sign-offs, not for missing code: owner +
 * counsel sign-off on the model proposing changes to a saved plan (decisions
 * § 1961, superseding part of § 1930: the model picks typed operations, the
 * deterministic helpers apply them, the result is re-graded and the runner
 * confirms the diff), and the sign-off on the v4 AI-disclosure copy the
 * endpoint's consent gate requires. Unset / empty / "false" / "0" → the option
 * never renders and the Coach never links to it.
 *
 * It also needs `coachEnabled()`: a plan edit is a coach-equivalent call on the
 * Coach's key and daily counter, so it cannot be live while the Coach is not.
 * Not a Pro storefront gate. Mirrors ai_plan_flag.ts.
 */
import { PUBLIC_AI_PLAN_EDIT_ENABLED } from '$app/env/public';
import { isTruthyFlagValue } from '../core/env_flag';

export function aiPlanEditEnabled(): boolean {
	return isTruthyFlagValue(PUBLIC_AI_PLAN_EDIT_ENABLED);
}

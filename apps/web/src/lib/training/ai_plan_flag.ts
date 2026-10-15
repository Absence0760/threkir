/**
 * Fail-closed feature gate for the AI plan assistant — the "Describe the plan
 * you want" box on the plan wizard (`/api/coach/plan-request`).
 *
 * This is the deploy gate for two sign-offs, not for missing code: the
 * liability sign-off on superseding decisions.md §12 (an LLM now sits in front
 * of plan creation, even though it only fills the wizard's fields and the
 * deterministic generator still authors every workout), and the sign-off on the
 * v3 AI-disclosure copy the endpoint's consent gate requires. The code is
 * complete on main either way; unset / empty / "false" / "0" → the box never
 * renders.
 *
 * The box also needs `coachEnabled()`: a plan request is a coach-equivalent
 * call on the Coach's key and daily counter, so it cannot be live while the
 * Coach is not. This flag does NOT make Pro sellable — free runners use it
 * inside the Coach's daily cap. Mirrors coach_flag.ts.
 */
import { PUBLIC_AI_PLAN_ENABLED } from '$app/env/public';
import { isTruthyFlagValue } from '../core/env_flag';

export function aiPlanEnabled(): boolean {
	return isTruthyFlagValue(PUBLIC_AI_PLAN_ENABLED);
}

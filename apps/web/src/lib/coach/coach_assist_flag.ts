/**
 * Fail-closed feature gate for the coach assistant (issue #1215 Phase 4): the
 * AI draft panel a coach sees in a conversation with an athlete they coach,
 * and the athlete's per-link consent toggle on /coaching.
 *
 * The deploy gate for the CISO + counsel sign-off and the DPIA update, not for
 * missing code. The server half is COACH_ASSIST_ENABLED in the coach Lambda;
 * without it /api/coach/assist answers 503 whatever this says. Unset / empty /
 * "false" / "0" → off. Needs `coachEnabled()` too: the drafts go out on the
 * Coach's key.
 */
import { PUBLIC_COACH_ASSIST_ENABLED } from '$app/env/public';
import { isTruthyFlagValue } from '../core/env_flag';
import { coachEnabled } from './coach_flag';

export function coachAssistEnabled(): boolean {
	return coachEnabled() && isTruthyFlagValue(PUBLIC_COACH_ASSIST_ENABLED);
}

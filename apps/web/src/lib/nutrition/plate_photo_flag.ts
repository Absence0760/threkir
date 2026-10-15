/**
 * Fail-closed feature gate for the plate-photo logger — the "Log from a photo"
 * entry LogFoodPanel puts on every Log food surface (`/api/coach/plate-photo`,
 * decisions § 1972).
 *
 * The deploy gate for sign-offs, not for missing code: counsel / CISO on the
 * v5 AI-disclosure copy (a meal photo is a new payload to a sub-processor) and
 * the owner on the per-call vision spend. Unset / empty / "false" / "0" → the
 * control never renders, and the server half (`PLATE_PHOTO_ENABLED` on the
 * coach Lambda) answers 503 regardless of what a client sends.
 *
 * The control also needs `coachEnabled()`: it runs on the Coach Lambda's
 * Anthropic key, so it cannot be live while the Coach is not. It is a Pro perk
 * (the handler checks `is_pro`); it does NOT on its own make Pro sellable.
 */
import { PUBLIC_PLATE_PHOTO_ENABLED } from '$app/env/public';
import { isTruthyFlagValue } from '../core/env_flag';

export function platePhotoEnabled(): boolean {
	return isTruthyFlagValue(PUBLIC_PLATE_PHOTO_ENABLED);
}

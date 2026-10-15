/**
 * Fail-closed feature gate for the coach fuelling handoff — the
 * `/nutrition/fuel` page the Coach links a fuelling question to (decisions
 * § 1975, superseding § 12 in part).
 *
 * This is the client half. The server half is the coach Lambda's
 * `COACH_FUEL_ENABLED` (a non-secret `coach_config_keys` entry), which decides
 * whether the system prompt carries the handoff at all; this one decides
 * whether the page the link lands on renders. Both stay off until the owner +
 * counsel sign off on the Coach answering fuelling questions through the
 * deterministic plan (the liability surface § 12 named). Unset / empty /
 * "false" / "0" → off.
 *
 * Not a Pro storefront gate, and no new AI payload: the Coach writes the link
 * from context it already sends, so no AI-disclosure version is involved.
 */
import { PUBLIC_COACH_FUEL_ENABLED } from '$app/env/public';
import { isTruthyFlagValue } from '../core/env_flag';

export function coachFuelEnabled(): boolean {
	return isTruthyFlagValue(PUBLIC_COACH_FUEL_ENABLED);
}

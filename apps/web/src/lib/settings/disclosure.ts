/// How much of a metric-dense surface a runner is shown before they ask for
/// more — the "progressive disclosure" level (issue #905 workstream 1).
///
/// The wizard has written `user_settings.prefs.primary_goal` since § 78 and
/// nothing read it back: its only consumer, `planPresetForGoal`, is handed the
/// goal as a `?goal=` URL parameter by the finish-step CTA, so the stored value
/// answered no question anybody asked. This is the read. The stated goal and
/// the size of the account's history each put a FLOOR under the level, the
/// higher floor wins, and the runner can override the result in Preferences.
///
/// Keep in lockstep with the Dart twin `apps/mobile_android/lib/disclosure.dart`.

import type { PrimaryGoal } from './onboarding';

/// Universal-prefs bag key holding the override. Absent means "derive it",
/// which is what `resolveDisclosureLevel` does — an account that has never
/// opened the control is never worse off than before the setting existed.
export const DISCLOSURE_LEVEL_KEY = 'disclosure_level';

/// Ordered least to most: the index IS the rank, so `combine` is a max.
export const DISCLOSURE_LEVELS = ['simple', 'standard', 'full'] as const;

export type DisclosureLevel = (typeof DISCLOSURE_LEVELS)[number];

/// Runs on the account at which history alone stops asking for `simple`, and
/// then for `standard`. Exported because the Preferences hint names them.
export const DISCLOSURE_STANDARD_RUNS = 10;
export const DISCLOSURE_FULL_RUNS = 50;

/// The floor a stated goal puts under the level. A goal is a statement about
/// what the runner wants the app FOR: the three beginner-leaning answers say
/// nothing that needs a training-load model to answer, a 10K or half says the
/// runner is training rather than just moving, and a marathon is the one goal
/// whose whole plan is a load-management problem.
const GOAL_FLOOR: Record<PrimaryGoal, DisclosureLevel> = {
	general_fitness: 'simple',
	weight_loss: 'simple',
	'5k': 'simple',
	'10k': 'standard',
	half_marathon: 'standard',
	marathon: 'full',
};

export function isDisclosureLevel(value: unknown): value is DisclosureLevel {
	return (DISCLOSURE_LEVELS as readonly unknown[]).includes(value);
}

function rank(level: DisclosureLevel): number {
	return DISCLOSURE_LEVELS.indexOf(level);
}

/// The level derived from what onboarding and the account already know.
///
/// An unset, unknown or malformed goal contributes no floor rather than a
/// guess — a value the enum does not carry is not evidence about the runner,
/// so the history floor decides alone. A negative, fractional or non-finite
/// run count is read as zero for the same reason.
export function disclosureLevel(
	primaryGoal: PrimaryGoal | string | null | undefined,
	runCount: number,
): DisclosureLevel {
	const runs = Number.isFinite(runCount) && runCount > 0 ? Math.floor(runCount) : 0;
	const byHistory: DisclosureLevel =
		runs >= DISCLOSURE_FULL_RUNS ? 'full' : runs >= DISCLOSURE_STANDARD_RUNS ? 'standard' : 'simple';
	const byGoal: DisclosureLevel =
		typeof primaryGoal === 'string' && Object.hasOwn(GOAL_FLOOR, primaryGoal)
			? GOAL_FLOOR[primaryGoal as PrimaryGoal]
			: 'simple';
	return rank(byGoal) >= rank(byHistory) ? byGoal : byHistory;
}

/// What a surface should render at. `stored` is the raw bag value: anything
/// that is not one of the three levels — absent, null, a stale spelling, a
/// number — falls through to the derivation rather than to a hard-coded
/// default, so a corrupt bag degrades to the same answer an untouched one gets.
export function resolveDisclosureLevel(
	stored: unknown,
	primaryGoal: PrimaryGoal | string | null | undefined,
	runCount: number,
): DisclosureLevel {
	return isDisclosureLevel(stored) ? stored : disclosureLevel(primaryGoal, runCount);
}

/**
 * The runner facts the plan generator calibrates on: gender (the § 76 pace
 * calibration), age (the § 93 masters recovery calibration) and the
 * `extra_recovery` setting that asks for that recovery calibration at any
 * age. Every surface that builds a plan for the signed-in runner — the
 * wizard, the season planner, the one-click starters — reads them through
 * `loadPlanCalibration` (`plan_calibration_load.ts`), so none of them can
 * quietly skip one. Mobile twin: `TrainingService.fetchPlanCalibration`.
 */
import { healthUseDob, healthUseDobState, type HealthUseDobState } from '#lib/core/health_consent.ts';
import { ageFromDob } from '#lib/nutrition/nutrition_targets.ts';
import { effective, type LoadedSettings } from '#lib/settings/settings_overlay.ts';
import type { TrainingGender } from './training.ts';

export const EXTRA_RECOVERY_KEY = 'extra_recovery';

export interface PlanCalibration {
	gender: TrainingGender;
	age: number | null;
	/// Null when the profile could not be read, so a caller hides the
	/// "add your date of birth" hint rather than tell a runner who has one
	/// that it is missing.
	dobState: HealthUseDobState | null;
	extraRecovery: boolean;
}

/**
 * Grade the two reads. `profile` is undefined when the `get_my_profile()`
 * read failed (distinct from a null row); `settings` is null when the
 * settings bag could not be loaded. Only a literal `true` turns
 * `extra_recovery` on.
 */
export function planCalibrationFrom(
	profile: unknown,
	settings: LoadedSettings | null,
	nowMs: number,
): PlanCalibration {
	const g = (profile as { gender?: unknown } | null | undefined)?.gender;
	return {
		gender: g === 'male' || g === 'female' || g === 'prefer_not_to_say' ? g : null,
		// Parsed by calendar components inside ageFromDob — new Date('YYYY-MM-DD')
		// is UTC midnight and would misfire the 50 gate a day early west of UTC.
		age: profile === undefined ? null : ageFromDob(healthUseDob(profile), nowMs),
		dobState: profile === undefined ? null : healthUseDobState(profile),
		extraRecovery: settings != null && effective<boolean>(settings, EXTRA_RECOVERY_KEY) === true,
	};
}

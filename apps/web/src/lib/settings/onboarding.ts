/// Onboarding wizard contract — shared between the `/onboarding` page,
/// the layout-level routing gate, and the Settings "finish setup"
/// nudge.
///
/// Persona-hunt finding (new-runner persona finding-area #1):
/// "after sign-up the persona is dropped at an empty dashboard with
/// no guidance." The wizard walks through display name, units, goal,
/// optional demographics (gender + DOB + weight with GDPR Art 9
/// consent), privacy default, and push notifications.
///
/// The `onboarded_at` column on `user_profiles` (migration
/// 20261016_001) is the single source of truth — null means the
/// wizard hasn't been seen yet. The wizard stamps `now()` on either
/// Finish or Skip-onboarding, so a returning user never re-sees it.

import type { GoalEvent } from '../training/training';

export const PRIMARY_GOAL_KEY = 'primary_goal';

/// Fixed enum the wizard's Goal step writes into
/// `user_settings.prefs.primary_goal`. The post-onboarding "create my
/// training plan" CTA reads it back through `planPresetForGoal` (below)
/// to deep-link into `/plans/new` preselected, without re-asking — same
/// shape the /plans/new wizard uses for `GoalEvent`.
///
/// `general_fitness` and `weight_loss` are the two non-distance
/// targets. The four distance targets map 1:1 to the
/// `training.ts#GoalEvent` enum so a future plan-creation flow can
/// translate without an extra mapping table.
export const PRIMARY_GOAL_VALUES = [
	'general_fitness',
	'weight_loss',
	'5k',
	'10k',
	'half_marathon',
	'marathon',
] as const;

export type PrimaryGoal = (typeof PRIMARY_GOAL_VALUES)[number];

/// Goal labels are NOT defined here — they resolve through the i18n keys
/// `onboarding.goal.<value>` via `m()` at the call site, so the wizard's
/// Goal step is localized (mobile's twin keeps them ARB-localized
/// likewise). Hard-coding English label strings into this pure parity
/// contract would re-introduce English-in-the-helper.

/// The wizard's steps, in order. Add a step here (and its <section> +
/// bound state in /onboarding/+page.svelte).
///
/// A step id is a quoted string under apps/web/src, and the icon-font
/// generator reads every quoted bare word as a possible icon name. The
/// privacy step's obvious one-word id is a Material Symbols ligature, so it
/// pulled a glyph nothing draws into the subset and failed the build; the
/// hyphen keeps it out. Check a new id against the vocabulary the same way.
export const ONBOARDING_STEPS = [
	'name',
	'units',
	'goal',
	'about',
	'run-privacy',
	'notifications',
	'done',
] as const;

export type OnboardingStep = (typeof ONBOARDING_STEPS)[number];

/// The full wizard. Mobile shows every step, so this is the figure its
/// `onboardingTotalSteps` twin mirrors; web may walk fewer (below).
export const ONBOARDING_TOTAL_STEPS = ONBOARDING_STEPS.length;

export interface PushAvailability {
	/// Browser support AND a deployed notification key (`isPushSupported`).
	supported: boolean;
	permission: NotificationPermission | 'unsupported';
	subscribed: boolean;
}

/// The steps a visitor walks on the web. The notifications step does one
/// thing there — turn on push for THIS browser — so it is shown only when that
/// can happen. Unsupported, blocked, or already on, it was a screen explaining
/// that nothing could be done, placed in the way of finishing. Mobile's step
/// is different (a level that applies wherever the account is signed in, so it
/// always has a choice to make) and keeps its seven; this is web-only.
export function visibleOnboardingSteps(push: PushAvailability): OnboardingStep[] {
	const canEnable =
		push.supported &&
		!push.subscribed &&
		push.permission !== 'denied' &&
		push.permission !== 'unsupported';
	return ONBOARDING_STEPS.filter((step) => step !== 'notifications' || canEnable);
}

export interface PlanPreset {
	goalEvent: GoalEvent;
	beginnerWalkRun: boolean;
}

/// Maps an onboarding primary-goal answer to a create-plan preset, so the
/// post-onboarding CTA can deep-link straight into `/plans/new` with the goal
/// distance preselected and — for the three beginner-leaning goals — the
/// walk-run toggle already ticked (the affordance a brand-new runner would
/// otherwise never discover). The distance goals map 1:1 to `GoalEvent`;
/// `general_fitness` / `weight_loss` / `5k` all seed the beginner walk-run 5K
/// (the beginner toggle itself snaps the goal to `distance_5k`). Keep in
/// lockstep with the Dart twin `onboarding.dart#planPresetForGoal`.
export function planPresetForGoal(goal: PrimaryGoal): PlanPreset {
	switch (goal) {
		case '10k':
			return { goalEvent: 'distance_10k', beginnerWalkRun: false };
		case 'half_marathon':
			return { goalEvent: 'distance_half', beginnerWalkRun: false };
		case 'marathon':
			return { goalEvent: 'distance_full', beginnerWalkRun: false };
		case 'general_fitness':
		case 'weight_loss':
		case '5k':
			return { goalEvent: 'distance_5k', beginnerWalkRun: true };
	}
}

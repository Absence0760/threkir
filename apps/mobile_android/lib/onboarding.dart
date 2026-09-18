/// Post-signup setup-wizard contract — Dart twin of web
/// `apps/web/src/lib/settings/onboarding.ts`. Shared between the
/// [SetupWizardScreen] and the home-screen routing gate.
///
/// The `onboarded_at` column on `user_profiles` (migration
/// 20261016_001) is the single source of truth — null means the wizard
/// hasn't been seen yet. The wizard stamps `now()` on either Finish or
/// Skip, so a returning user never re-sees it.
library;

import 'training.dart';

/// Universal-prefs bag key the wizard's Goal step writes into. Hard-coded
/// by name across the wizard + the plan-suggestion surface (the finish-step
/// "create my training plan" CTA reads it back via [planPresetForGoal]), so
/// a rename without grepping every consumer would orphan the saved value.
/// Matches web's `PRIMARY_GOAL_KEY`.
const String primaryGoalKey = 'primary_goal';

/// Fixed enum the Goal step writes. The four distance goals map 1:1 to
/// `training.dart`'s goal-event enum so a future plan-creation flow can
/// translate without a mapping table; `general_fitness` + `weight_loss`
/// are the two non-distance targets. Mirrors web's `PRIMARY_GOAL_VALUES`
/// (order included).
const List<String> primaryGoalValues = [
  'general_fitness',
  'weight_loss',
  '5k',
  '10k',
  'half_marathon',
  'marathon',
];

/// The wizard's steps, in order. Ids match web's `ONBOARDING_STEPS` so the
/// two wizards can be read side by side; the hyphen in `run-privacy` is
/// web's icon-font constraint, kept here only so the ids stay identical.
const List<String> setupWizardSteps = [
  'name',
  'units',
  'goal',
  'about',
  'run-privacy',
  'notifications',
  'done',
];

/// Total wizard steps. Drives the per-step navigation math and is the
/// figure web's `ONBOARDING_TOTAL_STEPS` mirrors — the FULL wizard, before
/// [visibleSetupWizardSteps] drops anything. Written out rather than read
/// off [setupWizardSteps] because a list's `length` is not a constant
/// expression; `onboarding_test.dart` pins the two together.
const int onboardingTotalSteps = 7;

/// The steps this device actually walks, and the list the progress dots are
/// generated from. Mobile's own, the counterpart of web's web-only
/// `visibleOnboardingSteps` — both wizards drop a step, for different
/// reasons.
///
/// `run-privacy` goes when the first-launch flow already asked. That flow
/// (`OnboardingScreen`) writes `Preferences.privacyDefault` before an
/// account exists, so a second ask is not a second opinion — whatever the
/// wizard's step is left sitting on is written over the launch answer on
/// Finish, silently.
List<String> visibleSetupWizardSteps({required bool privacyAlreadyChosen}) =>
    setupWizardSteps
        .where((s) => s != 'run-privacy' || !privacyAlreadyChosen)
        .toList();

/// A create-plan preset derived from a primary-goal answer — twin of web's
/// `PlanPreset`.
class PlanPreset {
  final GoalEvent goalEvent;
  final bool beginnerWalkRun;
  const PlanPreset(this.goalEvent, this.beginnerWalkRun);
}

/// Maps an onboarding primary-goal answer to a create-plan preset, so the
/// post-onboarding CTA can deep-link straight into the plan wizard with the
/// goal distance preselected and — for the three beginner-leaning goals — the
/// walk-run toggle already ticked (the affordance a brand-new runner would
/// otherwise never discover). Distance goals map 1:1 to [GoalEvent];
/// `general_fitness` / `weight_loss` / `5k` all seed the beginner walk-run 5K.
/// Keep in lockstep with web's `onboarding.ts#planPresetForGoal`.
PlanPreset planPresetForGoal(String goal) {
  switch (goal) {
    case '10k':
      return const PlanPreset(GoalEvent.distance10k, false);
    case 'half_marathon':
      return const PlanPreset(GoalEvent.distanceHalf, false);
    case 'marathon':
      return const PlanPreset(GoalEvent.distanceFull, false);
    default: // general_fitness, weight_loss, 5k
      return const PlanPreset(GoalEvent.distance5k, true);
  }
}

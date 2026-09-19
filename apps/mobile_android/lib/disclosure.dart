/// How much of a metric-dense surface a runner is shown before they ask for
/// more — the "progressive disclosure" level. Dart twin of web
/// `apps/web/src/lib/settings/disclosure.ts` (issue #905 workstream 1).
///
/// The setup wizard has written `user_settings.prefs.primary_goal` since § 78
/// and nothing read it back: its only consumer, [planPresetForGoal], is handed
/// the goal by the finish-step CTA rather than out of the bag, so the stored
/// value answered no question anybody asked. This is the read. The stated goal
/// and the size of the account's history each put a FLOOR under the level, the
/// higher floor wins, and the runner can override the result in Preferences.
library;

/// Universal-prefs bag key holding the override. Absent means "derive it",
/// which is what [resolveDisclosureLevel] does — an account that has never
/// opened the control is never worse off than before the setting existed.
const String disclosureLevelKey = 'disclosure_level';

/// Ordered least to most: the index IS the rank, so the combination below is
/// a max. Mirrors web's `DISCLOSURE_LEVELS`, order included.
const List<String> disclosureLevels = ['simple', 'standard', 'full'];

/// Runs on the account at which history alone stops asking for `simple`, and
/// then for `standard`.
const int disclosureStandardRuns = 10;
const int disclosureFullRuns = 50;

/// The floor a stated goal puts under the level. A goal is a statement about
/// what the runner wants the app FOR: the three beginner-leaning answers say
/// nothing that needs a training-load model to answer, a 10K or half says the
/// runner is training rather than just moving, and a marathon is the one goal
/// whose whole plan is a load-management problem.
const Map<String, String> _goalFloor = {
  'general_fitness': 'simple',
  'weight_loss': 'simple',
  '5k': 'simple',
  '10k': 'standard',
  'half_marathon': 'standard',
  'marathon': 'full',
};

bool isDisclosureLevel(Object? value) =>
    value is String && disclosureLevels.contains(value);

/// The level derived from what onboarding and the account already know.
///
/// An unset, unknown or malformed goal contributes no floor rather than a
/// guess — a value the enum does not carry is not evidence about the runner,
/// so the history floor decides alone. A negative, fractional or non-finite
/// run count is read as zero for the same reason.
String disclosureLevel(String? primaryGoal, num runCount) {
  final int runs =
      runCount.isFinite && runCount > 0 ? runCount.floor() : 0;
  final String byHistory = runs >= disclosureFullRuns
      ? 'full'
      : runs >= disclosureStandardRuns
          ? 'standard'
          : 'simple';
  final String byGoal = _goalFloor[primaryGoal] ?? 'simple';
  return disclosureLevels.indexOf(byGoal) >= disclosureLevels.indexOf(byHistory)
      ? byGoal
      : byHistory;
}

/// What a surface should render at. [stored] is the raw bag value: anything
/// that is not one of the three levels — absent, null, a stale spelling, a
/// number — falls through to the derivation rather than to a hard-coded
/// default, so a corrupt bag degrades to the same answer an untouched one gets.
String resolveDisclosureLevel(
  Object? stored,
  String? primaryGoal,
  num runCount,
) =>
    isDisclosureLevel(stored)
        ? stored as String
        : disclosureLevel(primaryGoal, runCount);

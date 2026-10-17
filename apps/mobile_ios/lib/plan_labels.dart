/// Localized words for a training plan's own facts — its goal, its length,
/// its status and a starter's name — shared by every plan surface (the list,
/// the library, its preview and the wizard) so the same fact cannot read
/// three ways across three screens.
///
/// UI-layer on purpose: `training.dart` is a TS↔Dart parity pair of pure
/// logic and takes no catalogue. The web twin of [goalEventLabel] and
/// [planLengthLabel] is `apps/web/src/lib/training/goal_event_label.ts`.
library;

import 'l10n/gen/app_localizations.dart';
import 'preferences.dart' show formatDistanceForPref;
import 'training.dart';

String goalEventLabel(AppLocalizations l10n, GoalEvent g) => switch (g) {
      GoalEvent.distance5k => '5K',
      GoalEvent.distance10k => '10K',
      GoalEvent.distanceHalf => l10n.plansEventHalf,
      GoalEvent.distanceFull => l10n.plansEventFull,
      GoalEvent.custom => l10n.plansEventCustom,
    };

/// A plan row's goal. A `custom` plan names its distance when it has one: an
/// ultra is stored as `custom` with `goal_distance_m`, and "Custom" says
/// nothing about a 50 km block.
String planGoalLabel(
    AppLocalizations l10n, String goalEventDb, num? goalDistanceM) {
  final g = goalEventFromDb(goalEventDb);
  if (g == GoalEvent.custom && goalDistanceM != null && goalDistanceM > 0) {
    return formatDistanceForPref(goalDistanceM.toDouble());
  }
  return goalEventLabel(l10n, g);
}

/// "12 weeks · 4 days/week".
String planLengthLabel(AppLocalizations l10n, int weeks, int daysPerWeek) =>
    l10n.plansMetaWeeks(weeks, daysPerWeek);

/// Whole weeks a plan spans, both endpoints inclusive, never below one.
int planWeekCount(DateTime start, DateTime end) {
  final days = DateTime.utc(end.year, end.month, end.day)
          .difference(DateTime.utc(start.year, start.month, start.day))
          .inDays +
      1;
  final w = (days / 7).ceil();
  return w < 1 ? 1 : w;
}

String planStatusLabel(AppLocalizations l10n, String status) =>
    switch (status) {
      'active' => l10n.plansStatusActive,
      'paused' => l10n.plansStatusPaused,
      'completed' => l10n.plansStatusCompleted,
      'abandoned' => l10n.plansStatusAbandoned,
      _ => status,
    };

String starterPlanName(AppLocalizations l10n, String id) => switch (id) {
      'c25k' => l10n.planNewStarterC25k,
      'half_12wk' => l10n.planNewStarterHalf12,
      'marathon_16wk' => l10n.planNewStarterMarathon16,
      _ => id,
    };

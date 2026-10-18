import 'package:core_models/core_models.dart' show PlanWorkoutRow;

import 'l10n/gen/app_localizations.dart';
import 'training.dart' show fmtKm;
import 'workout_summary.dart';
import 'workout_summary_format.dart';

/// A plan workout's size as a card states it ([plannedWorkoutSize]): a
/// walk-run session in minutes, the graduation 5K as its distance, any
/// other session as its target distance. Null for a rest day.
String? plannedSizeLabel(AppLocalizations l10n, PlanWorkoutRow w,
    [int digits = 1]) {
  final size = plannedWorkoutSize(
    kind: w.kind,
    targetDistanceM: w.targetDistanceM,
    targetDurationS: w.targetDurationSeconds,
    structure: w.structure,
  );
  return size == null
      ? null
      : formatPlannedSize(l10n, size, (m) => fmtKm(m, digits));
}

import 'l10n/gen/app_localizations.dart';
import 'workout_prescription.dart';

/// The read-only line for a planned workout's effort and heart-rate targets:
/// "RPE 3–4", "Cap 125 bpm". The shape comes from [rangeShape]; the words
/// are the catalogue's, so every surface that shows a target (workout
/// detail, the coach's view, the live runner) reads the same. Mirrors web's
/// `training/workout_target_label.ts`.
String? rpeTargetLabel(AppLocalizations l10n, int? min, int? max) {
  switch (rangeShape(min, max)) {
    case RangeShape.between:
      return l10n.workoutTargetRpeBetween(min!, max!);
    case RangeShape.exact:
      return l10n.workoutTargetRpeExact(min!);
    case RangeShape.atMost:
      return l10n.workoutTargetRpeAtMost(max!);
    case RangeShape.atLeast:
      return l10n.workoutTargetRpeAtLeast(min!);
    case null:
      return null;
  }
}

String? hrTargetLabel(AppLocalizations l10n, int? min, int? max) {
  switch (rangeShape(min, max)) {
    case RangeShape.between:
      return l10n.workoutTargetHrBetween(min!, max!);
    case RangeShape.exact:
      return l10n.workoutTargetHrExact(min!);
    case RangeShape.atMost:
      return l10n.workoutTargetHrAtMost(max!);
    case RangeShape.atLeast:
      return l10n.workoutTargetHrAtLeast(min!);
    case null:
      return null;
  }
}

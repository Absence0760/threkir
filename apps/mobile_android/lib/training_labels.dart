import 'l10n/gen/app_localizations.dart';
import 'training.dart';

// Presentation-layer labels for the training enums. They live here rather
// than in training.dart so that module stays a pure, locale-free twin of
// the web training.ts; the localized strings come from the gen-l10n
// catalogue. Mirrors apps/web/src/lib/training/workout_labels.ts.

String workoutKindLabel(AppLocalizations l10n, WorkoutKind k) => switch (k) {
      WorkoutKind.easy => l10n.workoutKindEasy,
      WorkoutKind.long => l10n.workoutKindLong,
      WorkoutKind.recovery => l10n.workoutKindRecovery,
      WorkoutKind.tempo => l10n.workoutKindTempo,
      WorkoutKind.interval => l10n.workoutKindInterval,
      WorkoutKind.marathonPace => l10n.workoutKindMarathonPace,
      WorkoutKind.walkRun => l10n.workoutKindWalkRun,
      WorkoutKind.race => l10n.workoutKindRace,
      WorkoutKind.rest => l10n.workoutKindRest,
    };

/// A `plan_workouts.race_priority` value as a picker option.
String racePriorityOptionLabel(AppLocalizations l10n, String priority) =>
    switch (priority) {
      'A' => l10n.racePriorityOptionA,
      'B' => l10n.racePriorityOptionB,
      'C' => l10n.racePriorityOptionC,
      _ => l10n.racePriorityOptionC,
    };

String planPhaseLabel(AppLocalizations l10n, PlanPhase p) => switch (p) {
      PlanPhase.base => l10n.planPhaseBase,
      PlanPhase.build => l10n.planPhaseBuild,
      PlanPhase.peak => l10n.planPhasePeak,
      PlanPhase.taper => l10n.planPhaseTaper,
      PlanPhase.race => l10n.planPhaseRace,
      PlanPhase.graduation => l10n.planPhaseGraduation,
    };

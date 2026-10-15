/// P4 "next target" hints for a logged session that ran a routine
/// (gym_programming.md): one suggestion per scheme-tracked lift, from THIS
/// session's logged sets. Pure suggestion — never auto-applied.
///
/// Dart twin of `apps/web/src/lib/gym/next_target_hints.ts` — keep the
/// algorithm, edge cases, outputs, and test counts in lockstep.
///
/// Pure — no Flutter / Supabase deps. The routine row's raw `progression`
/// string is parsed to a [ProgressionScheme] by the caller.
library;

import 'gym_progression.dart';
import 'gym_prs.dart' show normaliseExerciseName;
import 'progression_prefill.dart';

class HintRoutineExercise {
  final String exerciseName;
  final ProgressionScheme progression;
  final Map<String, Object?>? progressionParams;
  final List<({num? targetRepsMin, num? targetRepsMax})> sets;
  const HintRoutineExercise({
    required this.exerciseName,
    required this.progression,
    required this.progressionParams,
    required this.sets,
  });
}

class HintLoggedSet extends ProgressionSetLike {
  final String exerciseName;
  const HintLoggedSet({
    required this.exerciseName,
    super.reps,
    super.weightKg,
    super.rpe,
    super.setType,
  });
}

/// One hint on the workout review. Weights canonical kg.
class NextTargetHint {
  final String exerciseKey;
  final String exerciseName;
  final double? suggestedWeightKg;
  final double? suggestedRepsMin;
  final double? suggestedRepsMax;

  /// Heaviest weighted set this exercise logged this session, for the +/- delta.
  final double? currentTopKg;

  /// Reps at the heaviest logged set this session, for a rep-climb hint.
  final num? currentTopReps;
  final ProgressionReason reason;
  const NextTargetHint({
    required this.exerciseKey,
    required this.exerciseName,
    required this.suggestedWeightKg,
    required this.suggestedRepsMin,
    required this.suggestedRepsMax,
    required this.currentTopKg,
    required this.currentTopReps,
    required this.reason,
  });
}

/// One hint per lift, never one per routine block. The logged sets are pooled
/// by the canonical key, so a lift programmed into two blocks (a heavy top set
/// then back-offs) would otherwise yield two hints judged on the same sets.
/// The first block that produces a suggestion speaks for the lift.
List<NextTargetHint> buildNextTargetHints({
  required List<HintRoutineExercise> exercises,
  required List<HintLoggedSet> sets,
  required List<DatedLoggedSet> history,
}) {
  final setsByKey = <String, List<ProgressionSetLike>>{};
  for (final s in sets) {
    final key = normaliseExerciseName(s.exerciseName);
    if (key.isEmpty) continue;
    (setsByKey[key] ??= []).add(ProgressionSetLike(
      reps: s.reps,
      weightKg: s.weightKg,
      rpe: s.rpe,
      setType: s.setType,
    ));
  }

  final out = <NextTargetHint>[];
  final hinted = <String>{};
  for (final ex in exercises) {
    if (ex.progression == ProgressionScheme.none) continue;
    final key = normaliseExerciseName(ex.exerciseName);
    if (hinted.contains(key)) continue;
    final lastSets = setsByKey[key];
    if (lastSets == null || lastSets.isEmpty) continue;
    final firstSet = ex.sets.isNotEmpty ? ex.sets.first : null;
    final sug = nextPrescription(ProgressionInput(
      scheme: ex.progression,
      lastSets: lastSets,
      targetRepsMin: firstSet?.targetRepsMin,
      targetRepsMax: firstSet?.targetRepsMax,
      // The 5×5 back-off needs a miss count across sessions, which no
      // authored params bag carries — the history supplies it.
      params: progressionParamsWithStreak(
        scheme: ex.progression,
        params: ex.progressionParams,
        targetRepsMin: firstSet?.targetRepsMin,
        targetRepsMax: firstSet?.targetRepsMax,
        history: history,
        exerciseName: ex.exerciseName,
      ),
    ));
    if (sug.reason == ProgressionReason.none) continue;

    double? topKg;
    num? topReps;
    for (final s in lastSets) {
      final wt = s.weightKg;
      if (wt != null && wt > 0 && (topKg == null || wt > topKg)) {
        topKg = wt.toDouble();
        topReps = s.reps;
      }
    }
    hinted.add(key);
    out.add(NextTargetHint(
      exerciseKey: key,
      exerciseName: ex.exerciseName,
      suggestedWeightKg: sug.suggestedWeightKg,
      suggestedRepsMin: sug.suggestedRepsMin,
      suggestedRepsMax: sug.suggestedRepsMax,
      currentTopKg: topKg,
      currentTopReps: topReps,
      reason: sug.reason,
    ));
  }
  return out;
}

// The catalogue half of workout_summary.dart: the walk-run pattern and the
// zone chip as a reader sees them. Mirrors
// apps/web/src/lib/training/workout_summary_format.ts, a registered parity
// pair (docs/architecture/parity_pairs.md).

import 'l10n/gen/app_localizations.dart';
import 'workout_summary.dart';

String formatSpokenDuration(AppLocalizations l10n, SpokenDuration d) =>
    switch (d) {
      SpokenMinutes(:final minutes) => l10n.workoutSummaryMin(minutes),
      SpokenSeconds(:final seconds) => l10n.workoutSummarySec(seconds),
      SpokenMinSec(:final minutes, :final seconds) =>
        l10n.workoutSummaryMinSec(minutes, seconds),
    };

/// "5 min warm-up, 8 × (1 min run / 90 s walk), 5 min cool-down", or
/// "5 min warm-up, 5 km run, 5 min cool-down" for the graduation 5K.
String formatWalkRunPattern(AppLocalizations l10n, WalkRunPattern p,
    String Function(num metres) fmtDistance) {
  String say(num sec) => formatSpokenDuration(l10n, spokenDuration(sec));
  final main = p.runM != null
      ? l10n.workoutSummaryContinuous(fmtDistance(p.runM!))
      : p.walkS != null
          ? l10n.workoutSummaryIntervals(p.count, say(p.runS), say(p.walkS!))
          : l10n.workoutSummaryContinuous(say(p.count * p.runS));
  final warmup =
      p.warmupS != null ? l10n.workoutSummaryWarmup(say(p.warmupS!)) : null;
  final cooldown = p.cooldownS != null
      ? l10n.workoutSummaryCooldown(say(p.cooldownS!))
      : null;
  if (warmup != null && cooldown != null) {
    return l10n.workoutSummaryWithBoth(warmup, main, cooldown);
  }
  if (warmup != null) return l10n.workoutSummaryWithWarmup(warmup, main);
  if (cooldown != null) return l10n.workoutSummaryWithCooldown(main, cooldown);
  return main;
}

/// A plan card's size for a session ([plannedWorkoutSize]): "29 min" for a
/// timed one, the distance otherwise.
String formatPlannedSize(AppLocalizations l10n, StructureTotal size,
        String Function(num metres) fmtDistance) =>
    switch (size) {
      StructureTotalDistance(:final metres) => fmtDistance(metres),
      StructureTotalDuration(:final seconds) =>
        l10n.workoutSummaryMin(aboutMinutes(seconds)),
    };

/// "about 29 min", or "5 km run" for a session that ends on a distance.
String formatWalkRunTotal(AppLocalizations l10n, WalkRunPattern p,
    String Function(num metres) fmtDistance) {
  if (p.runM != null) return l10n.workoutSummaryContinuous(fmtDistance(p.runM!));
  return l10n.workoutSummaryAbout(
      l10n.workoutSummaryMin(aboutMinutes(p.totalS)));
}

String _zoneName(AppLocalizations l10n, PaceZoneName n) => switch (n) {
      PaceZoneName.easy => l10n.planNewPaceEasy,
      PaceZoneName.marathon => l10n.planNewPaceMarathon,
      PaceZoneName.tempo => l10n.planNewPaceTempo,
      PaceZoneName.interval => l10n.planNewPaceInterval,
      PaceZoneName.repetition => l10n.planNewPaceRep,
    };

/// "Zone T · Tempo" for a Daniels code, "Zone Z2" for free text.
String formatPaceZone(AppLocalizations l10n, String code, PaceZoneName? name) =>
    name != null
        ? l10n.workoutZoneNamed(code.trim(), _zoneName(l10n, name))
        : l10n.workoutZoneRaw(code.trim());

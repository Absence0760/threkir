/// Plan-adherence feedback — does the runner's actual training match the
/// plan? Two signals, both pure (no Supabase / Flutter):
///
///  1. Weekly mileage drift — flags when actual weekly volume runs more
///     than ±20% off the plan. BOTH directions matter: under-running loses
///     the adaptation; over-running the easy weeks is the classic way a
///     motivated runner digs a fatigue hole. `weeklyDrift` takes a finished
///     week's two totals; a week still in progress goes through
///     `weeklyDriftToDate`, which windows both sides to the days that have
///     already ended.
///
///  2. Missed-long-run advice — a make-up / skip recommendation for a long
///     run the runner blew past, driven by training phase and proximity to
///     a recovery week.
///
/// Dart twin of `apps/web/src/lib/training/plan_adherence.ts` — keep the
/// algorithm, edge cases, outputs, and test counts in lockstep.
library;

/// Beyond ±this fraction off the planned weekly volume, surface a drift flag.
const double planDriftThreshold = 0.2;

enum DriftDirection { under, over, onTrack }

class WeeklyDrift {
  final double plannedMetres;
  final double actualMetres;

  /// (actual − planned) / planned. Positive = over-running, negative =
  /// under-running. 0 when there's no planned volume to compare against.
  final double driftFraction;
  final DriftDirection direction;

  /// True when |driftFraction| exceeds the threshold AND there's a real plan
  /// to drift from (planned volume > 0).
  final bool flagged;

  const WeeklyDrift({
    required this.plannedMetres,
    required this.actualMetres,
    required this.driftFraction,
    required this.direction,
    required this.flagged,
  });
}

/// Compare a week's actual mileage to its planned volume. Returns a neutral,
/// unflagged result when the week has no planned volume (a pure rest week, or
/// a week before the plan models distance) so the caller never shows a drift
/// flag against a zero baseline.
WeeklyDrift weeklyDrift(
  double plannedMetres,
  double actualMetres, {
  double threshold = planDriftThreshold,
}) {
  if (!(plannedMetres > 0)) {
    return WeeklyDrift(
      plannedMetres: plannedMetres < 0 ? 0 : plannedMetres,
      actualMetres: actualMetres < 0 ? 0 : actualMetres,
      driftFraction: 0,
      direction: DriftDirection.onTrack,
      flagged: false,
    );
  }
  final actual = actualMetres < 0 ? 0.0 : actualMetres;
  final driftFraction = (actual - plannedMetres) / plannedMetres;
  var direction = DriftDirection.onTrack;
  if (driftFraction > threshold) {
    direction = DriftDirection.over;
  } else if (driftFraction < -threshold) {
    direction = DriftDirection.under;
  }
  return WeeklyDrift(
    plannedMetres: plannedMetres,
    actualMetres: actual,
    driftFraction: driftFraction,
    direction: direction,
    flagged: direction != DriftDirection.onTrack,
  );
}

/// One plan workout, reduced to what the to-date baseline needs.
class DriftWorkout {
  /// Local ISO date (YYYY-MM-DD) the workout is scheduled for.
  final String scheduledDate;

  /// Workout kind from the plan (`long`, `rest`, …).
  final String kind;
  final double? targetDistanceM;

  const DriftWorkout({
    required this.scheduledDate,
    required this.kind,
    required this.targetDistanceM,
  });
}

/// One logged run, already scoped by the caller to the plan week.
class DriftRun {
  /// Local ISO date (YYYY-MM-DD) the run started on.
  final String date;
  final double distanceM;

  const DriftRun({required this.date, required this.distanceM});
}

/// Current-week drift measured against the plan TO DATE rather than the whole
/// week. The window is the week's days that have already ended —
/// `scheduledDate < today` on the planned side, run date `< today` on the
/// actual side — so a session still due at the end of today counts on neither.
/// Against the full seven-day target, a runner who had done exactly what
/// Monday to Wednesday asked for was told they were far under plan, every
/// week, until Sunday night.
///
/// The week's declared `target_volume_m` stays authoritative on how much the
/// week is worth; the per-workout distances only supply its shape, scaled onto
/// that total. A week that declares a volume but places none of it on a
/// workout cannot be placed in time at all, and yields the neutral unflagged
/// result rather than a baseline guessed from elapsed days.
WeeklyDrift weeklyDriftToDate({
  required List<DriftWorkout> workouts,
  required List<DriftRun> runs,

  /// Local ISO date (YYYY-MM-DD) for the runner's today.
  required String today,

  /// The week's declared volume target, when the plan sets one.
  double? weekTargetVolumeM,
  double threshold = planDriftThreshold,
}) {
  var plannedElapsed = 0.0;
  var plannedWeek = 0.0;
  for (final w in workouts) {
    if (w.kind == 'rest') continue;
    final d = (w.targetDistanceM ?? 0) < 0 ? 0.0 : (w.targetDistanceM ?? 0);
    plannedWeek += d;
    if (w.scheduledDate.compareTo(today) < 0) plannedElapsed += d;
  }

  final target =
      (weekTargetVolumeM ?? 0) < 0 ? 0.0 : (weekTargetVolumeM ?? 0);
  final planned = target > 0
      ? (plannedWeek > 0 ? target * plannedElapsed / plannedWeek : 0.0)
      : plannedElapsed;

  var actual = 0.0;
  for (final r in runs) {
    if (r.date.compareTo(today) < 0) {
      actual += r.distanceM < 0 ? 0.0 : r.distanceM;
    }
  }

  return weeklyDrift(planned, actual, threshold: threshold);
}

enum MakeUpRecommendation { makeUp, skip }

enum MissedWorkoutReason { keySession, taper, recoverySoon, notLongRun }

class MissedWorkoutAdvice {
  final MakeUpRecommendation recommendation;
  final MissedWorkoutReason reason;
  const MissedWorkoutAdvice(this.recommendation, this.reason);
}

class MissedWorkoutInput {
  /// Workout kind from the plan (`long`, `tempo`, …).
  final String kind;

  /// Whether the missed workout sits in the taper phase of the plan.
  final bool isTaper;

  /// Whether the very next week is a recovery / step-back week. Null when
  /// unknown (treated as "not imminent").
  final bool? recoveryWeekImminent;

  const MissedWorkoutInput({
    required this.kind,
    required this.isTaper,
    required this.recoveryWeekImminent,
  });
}

/// Recommend whether to make up or skip a missed workout. Only the long run
/// earns a make-up decision; everything else is cheaper to drop than to cram.
/// For a long run: skip in the taper (freshness > one more long run) or when a
/// recovery week is about to absorb the deficit anyway; otherwise make it up.
MissedWorkoutAdvice missedWorkoutAdvice(MissedWorkoutInput input) {
  if (input.kind != 'long') {
    return const MissedWorkoutAdvice(
        MakeUpRecommendation.skip, MissedWorkoutReason.notLongRun);
  }
  if (input.isTaper) {
    return const MissedWorkoutAdvice(
        MakeUpRecommendation.skip, MissedWorkoutReason.taper);
  }
  if (input.recoveryWeekImminent == true) {
    return const MissedWorkoutAdvice(
        MakeUpRecommendation.skip, MissedWorkoutReason.recoverySoon);
  }
  return const MissedWorkoutAdvice(
      MakeUpRecommendation.makeUp, MissedWorkoutReason.keySession);
}

/// What Home says, unprompted, about the runner's plan — and the "+3 km" a
/// workout run long carries. Pure: the rules themselves live in
/// `plan_replan.dart` / `plan_adaptive_replan.dart` and are not restated here
/// (decisions §144); this module only decides WHEN an existing proposal is
/// worth putting in front of the runner, and names each occurrence so a
/// dismissal can stick to it across devices.
///
/// Dart twin of `apps/web/src/lib/training/plan_nudges.ts` — keep in lockstep
/// (TS↔Dart parity pair, equal test counts).
library;

import 'plan_adaptive_replan.dart';
import 'plan_adherence.dart' show DriftDirection;
import 'plan_replan.dart';

/// A run past its target by less than this is not worth a word: GPS drift
/// and a loop home add a few hundred metres to most runs.
const double overrunMinMetres = 1000;

/// ...and nor is an extra kilometre on a 30 km long run. Both bars must be
/// cleared.
const double overrunMinFraction = 0.1;

/// How many trailing completed weeks the rest-day note looks at, and how
/// many of them must hold a run on a rest day before it speaks up.
const int restDayWindow = 3;
const int restDayMinWeeks = 2;

/// Dismissed occurrences kept in the prefs bag
/// (`SettingsKeys.planNudgesDismissed`).
const int dismissedNudgesCap = 20;

enum PlanNudgeKind { adaptiveUnder, easeOver, restDayRuns }

String _kindKey(PlanNudgeKind k) => switch (k) {
      PlanNudgeKind.adaptiveUnder => 'adaptive_under',
      PlanNudgeKind.easeOver => 'ease_over',
      PlanNudgeKind.restDayRuns => 'rest_day_runs',
    };

class PlanNudge {
  final PlanNudgeKind kind;

  /// The last completed plan week the occurrence was judged on.
  final int weekIndex;

  /// Identity of this occurrence, as stored when it is dismissed.
  final String key;

  /// Weeks in the trend window that showed the signal, and the window size.
  final int weeks;
  final int ofWeeks;

  const PlanNudge({
    required this.kind,
    required this.weekIndex,
    required this.key,
    required this.weeks,
    required this.ofWeeks,
  });
}

/// Metres a completed run went past its workout's distance target, or null
/// when there is no distance target, no run distance, or the extra is small
/// enough to be noise. Never negative: a short run is not an over-run.
double? workoutOverrunMetres(double? targetDistanceM, double? runDistanceM) {
  if (targetDistanceM == null || runDistanceM == null) return null;
  if (!(targetDistanceM > 0) || !runDistanceM.isFinite) return null;
  final extra = runDistanceM - targetDistanceM;
  if (extra < overrunMinMetres) return null;
  if (extra < targetDistanceM * overrunMinFraction) return null;
  return extra;
}

/// Decimal places for an over-run shown in the runner's unit: whole units
/// once it reaches ten or when one decimal would read ".0", otherwise one.
int overrunDigits(double valueInUnits) {
  if (valueInUnits >= 10) return 0;
  final tenths = (valueInUnits * 10).round();
  return tenths % 10 == 0 ? 0 : 1;
}

String planNudgeKey(String planId, PlanNudgeKind kind, int weekIndex) =>
    '$planId:${_kindKey(kind)}:$weekIndex';

/// The dismissed list out of the prefs bag. Anything that is not a list of
/// strings reads as nothing dismissed.
List<String> parseDismissedNudges(Object? raw) {
  if (raw is! List) return const [];
  return raw.whereType<String>().toList();
}

/// [dismissed] with [key] added last, de-duplicated, keeping the newest
/// [dismissedNudgesCap].
List<String> withDismissedNudge(List<String> dismissed, String key) {
  final next = dismissed.where((k) => k != key).toList()..add(key);
  return next.length > dismissedNudgesCap
      ? next.sublist(next.length - dismissedNudgesCap)
      : next;
}

String _shiftIso(String iso, int days) {
  final p = iso.split('-').map(int.parse).toList();
  final d = DateTime.utc(p[0], p[1], p[2] + days);
  return '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

class NudgeInputWorkout {
  final String id;

  /// ISO scheduled date (YYYY-MM-DD).
  final String scheduledDate;
  final String kind;
  final double? targetDistanceM;
  final bool completed;
  final bool skipped;

  /// The runner already answered this missed workout — let it go or made it
  /// up through the missed-workout prompt (`missed_ack_at`). Off the books
  /// like a skip, so no re-plan stretches a long run for it a second time.
  final bool answered;

  const NudgeInputWorkout({
    required this.id,
    required this.scheduledDate,
    required this.kind,
    required this.targetDistanceM,
    required this.completed,
    required this.skipped,
    required this.answered,
  });
}

class NudgeInputWeek {
  final int weekIndex;
  final String phase;
  final double? targetVolumeM;
  final List<NudgeInputWorkout> workouts;

  const NudgeInputWeek({
    required this.weekIndex,
    required this.phase,
    required this.targetVolumeM,
    required this.workouts,
  });
}

class NudgeInputRun {
  /// The run's LOCAL calendar day (YYYY-MM-DD).
  final String date;
  final double distanceM;

  const NudgeInputRun({required this.date, required this.distanceM});
}

/// The re-plan engine's input, built the one way every caller builds it:
/// planned volume is the week's target or, when unset, its non-rest
/// distances; actual volume is every run on a local day inside the week; a
/// week is complete once its last day has ended.
List<ReplanWeek> buildReplanWeeks({
  required String startDate,
  required String today,
  required List<NudgeInputWeek> weeks,
  required List<NudgeInputRun> runs,
}) {
  return weeks.map((w) {
    var planned = w.targetVolumeM ?? 0;
    if (!(planned > 0)) {
      planned = 0;
      for (final x in w.workouts) {
        if (x.kind != 'rest') planned += x.targetDistanceM ?? 0;
      }
    }
    final weekStart = _shiftIso(startDate, w.weekIndex * 7);
    final weekEnd = _shiftIso(weekStart, 7);
    var actual = 0.0;
    for (final r in runs) {
      if (r.date.compareTo(weekStart) >= 0 && r.date.compareTo(weekEnd) < 0) {
        actual += r.distanceM;
      }
    }
    return ReplanWeek(
      weekIndex: w.weekIndex,
      phase: w.phase,
      plannedMetres: planned,
      actualMetres: actual,
      isComplete: weekEnd.compareTo(today) <= 0,
      workouts: w.workouts
          .map((x) => ReplanWorkout(
                id: x.id,
                scheduledDate: x.scheduledDate,
                kind: x.kind,
                targetDistanceM: x.targetDistanceM,
                completed: x.completed,
                skipped: x.skipped || x.answered,
                isPast: x.scheduledDate.compareTo(today) < 0,
              ))
          .toList(),
    );
  }).toList();
}

/// Completed weeks that held at least one run on a day with no session
/// planned (a rest day, or a day the plan left empty), among the last
/// [restDayWindow] completed weeks that schedule anything at all.
({int weeks, int ofWeeks}) _restDayRunWeeks(
  String startDate,
  List<ReplanWeek> weeks,
  List<String> runDates,
) {
  final eligible =
      weeks.where((w) => w.isComplete && w.workouts.isNotEmpty).toList();
  final window = eligible.length > restDayWindow
      ? eligible.sublist(eligible.length - restDayWindow)
      : eligible;
  var flagged = 0;
  for (final w in window) {
    final weekStart = _shiftIso(startDate, w.weekIndex * 7);
    final weekEnd = _shiftIso(weekStart, 7);
    final planned = {
      for (final x in w.workouts)
        if (x.kind != 'rest') x.scheduledDate,
    };
    if (runDates.any((d) =>
        d.compareTo(weekStart) >= 0 &&
        d.compareTo(weekEnd) < 0 &&
        !planned.contains(d))) {
      flagged++;
    }
  }
  return (weeks: flagged, ofWeeks: window.length);
}

/// The one plan card Home shows, or null. Only an active, started, unfinished,
/// non-template plan qualifies (the caller owns the "is the viewer the owner"
/// check). In order, the first occurrence not yet dismissed wins:
///
///  1. `adaptiveUnder` — the adaptive re-plan's 2-of-3 under-run trend, and
///     only when it has a change to propose;
///  2. `easeOver` — the last completed week ran over plan and the re-plan
///     eases next week;
///  3. `restDayRuns` — runs on rest days in 2 of the last 3 completed weeks.
PlanNudge? planNudge({
  required String planId,
  required String status,
  required bool isTemplate,
  required String startDate,
  required String endDate,
  required String today,
  required List<ReplanWeek> weeks,
  required List<String> runDates,
  required List<String> dismissed,
}) {
  if (status != 'active' || isTemplate) return null;
  if (today.compareTo(startDate) < 0 || today.compareTo(endDate) > 0) {
    return null;
  }
  final sorted = [...weeks]..sort((a, b) => a.weekIndex.compareTo(b.weekIndex));
  ReplanWeek? lastComplete;
  for (final w in sorted.reversed) {
    if (w.isComplete) {
      lastComplete = w;
      break;
    }
  }
  if (lastComplete == null) return null;
  final at = lastComplete.weekIndex;
  final gone = dismissed.toSet();
  final candidates = <PlanNudge>[];

  // P1 only, by construction: no fitness snapshot reaches Home (decisions
  // § 2125), so the gated P2 load input keeps its one call site.
  final adaptive = adaptiveReplanRemaining(weeks: sorted, today: today);
  if (adaptive.reason == AdaptiveReason.trendUnderfitness &&
      adaptive.changes.isNotEmpty) {
    candidates.add(PlanNudge(
      kind: PlanNudgeKind.adaptiveUnder,
      weekIndex: at,
      key: planNudgeKey(planId, PlanNudgeKind.adaptiveUnder, at),
      weeks: adaptive.trailingDirections
          .where((d) => d == DriftDirection.under)
          .length,
      ofWeeks: adaptive.trailingDirections.length,
    ));
  }

  final replan = replanRemaining(weeks: sorted, today: today);
  if (replan.changes.any((c) => c.reason == ReplanReason.easeOverRunning)) {
    candidates.add(PlanNudge(
      kind: PlanNudgeKind.easeOver,
      weekIndex: at,
      key: planNudgeKey(planId, PlanNudgeKind.easeOver, at),
      weeks: 1,
      ofWeeks: 1,
    ));
  }

  final rest = _restDayRunWeeks(startDate, sorted, runDates);
  if (rest.weeks >= restDayMinWeeks) {
    candidates.add(PlanNudge(
      kind: PlanNudgeKind.restDayRuns,
      weekIndex: at,
      key: planNudgeKey(planId, PlanNudgeKind.restDayRuns, at),
      weeks: rest.weeks,
      ofWeeks: rest.ofWeeks,
    ));
  }

  for (final c in candidates) {
    if (!gone.contains(c.key)) return c;
  }
  return null;
}

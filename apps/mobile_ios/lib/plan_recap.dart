/// The end-of-plan recap (issue #1186): what the block added up to, read off
/// the plan, its workouts and the runner's runs and records inside its window,
/// and what comes after it. Pure: every date is a local `yyyy-mm-dd` the
/// caller has already put in the runner's zone, so nothing here reads a clock
/// or a zone.
///
/// Dart twin of `apps/web/src/lib/training/plan_recap.ts` — keep the
/// algorithm, edge cases, outputs, and test counts in lockstep.
library;

import 'package:core_models/core_models.dart' show PlanWorkoutRow;

import 'plan_bulk_ops.dart' show shiftIsoDate;
import 'plan_current.dart' show isWorkoutMissed;
import 'plan_progress.dart';
import 'plan_races.dart';
import 'plan_restart.dart' show RestartWorkout, isWalkRunPlan;
import 'plan_start.dart' show defaultPlanStart, nextSunday;
import 'recent_5k_suggestion.dart' show isPlausibleRecent5k, kRecent5kWindowDays;
import 'season_plan.dart' show seasonRecoveryDays;
import 'training.dart' show parseIsoDate, toIsoDate, vdotFromRace;

/// The share of a race's distance a run on race day must cover to stand for a
/// race the plan has no workout row for: the run-to-workout matcher's own
/// lower bound (decisions § 2079), so a shakeout jog is never read as the race.
const double kRecapRaceRunMinShare = 0.75;

/// The distances Daniels' VDOT formula is calibrated over: 1500 m to the
/// marathon, with 5% of headroom for a GPS trace that over-measures the
/// course. An ultra's time says nothing about a 5K, so it seeds no plan.
const double kRecapVdotMinM = 1500;
const double kRecapVdotMaxM = 42195 * 1.05;

class RecapPlan {
  final String startDate;
  final String endDate;
  final double goalDistanceM;
  final int? goalTimeSeconds;
  final DateTime? trimmedAt;

  const RecapPlan({
    required this.startDate,
    required this.endDate,
    required this.goalDistanceM,
    required this.goalTimeSeconds,
    required this.trimmedAt,
  });
}

class RecapWorkout {
  final String id;
  final String scheduledDate;
  final String kind;
  final double? targetDistanceM;
  final int? targetDurationSeconds;
  final String? completedRunId;
  final bool manuallyCompleted;
  final String? skippedAt;
  final String? missedAckAt;
  final String? raceName;
  final String? racePriority;

  const RecapWorkout({
    required this.id,
    required this.scheduledDate,
    required this.kind,
    this.targetDistanceM,
    this.targetDurationSeconds,
    this.completedRunId,
    this.manuallyCompleted = false,
    this.skippedAt,
    this.missedAckAt,
    this.raceName,
    this.racePriority,
  });

  factory RecapWorkout.fromRow(PlanWorkoutRow w) => RecapWorkout(
        id: w.id,
        scheduledDate: toIsoDate(w.scheduledDate),
        kind: w.kind,
        targetDistanceM: w.targetDistanceM,
        targetDurationSeconds: w.targetDurationSeconds,
        completedRunId: w.completedRunId,
        manuallyCompleted: w.manuallyCompleted,
        skippedAt: w.skippedAt?.toIso8601String(),
        missedAckAt: w.missedAckAt?.toIso8601String(),
        raceName: w.raceName,
        racePriority: w.racePriority,
      );

  bool get _completed => manuallyCompleted || completedRunId != null;
}

class PlanRecapRun {
  final String id;

  /// The local day the run started on.
  final String date;
  final double? distanceM;
  final int? durationS;
  final String? activityType;
  final bool? isDnf;

  const PlanRecapRun({
    required this.id,
    required this.date,
    required this.distanceM,
    required this.durationS,
    this.activityType = 'run',
    this.isDnf = false,
  });
}

/// A `personal_records` row: the best time the runner holds for a bracket.
class PlanRecapRecord {
  final String distance;
  final int timeS;

  /// The local day the record was set.
  final String date;
  final String? runId;

  const PlanRecapRecord({
    required this.distance,
    required this.timeS,
    required this.date,
    this.runId,
  });
}

enum RecapVolumeBasis { distance, time }

class PlanRecapRaceRun {
  final String id;
  final double? distanceM;
  final int? durationS;
  final bool isDnf;

  const PlanRecapRaceRun({
    required this.id,
    required this.distanceM,
    required this.durationS,
    required this.isDnf,
  });

  @override
  bool operator ==(Object other) =>
      other is PlanRecapRaceRun &&
      other.id == id &&
      other.distanceM == distanceM &&
      other.durationS == durationS &&
      other.isDnf == isDnf;

  @override
  int get hashCode => Object.hash(id, distanceM, durationS, isDnf);
}

class RecapRace {
  final String date;
  final String? name;
  final String priority;
  final double? distanceM;
  final int? goalTimeSec;
  final PlanRecapRaceRun? run;

  /// The race was run: a run stands for it, or its workout was ticked done.
  final bool raced;

  /// VDOT of the race run, one decimal. Null for a DNF, a non-run, a distance
  /// outside the formula's range or a run with no time.
  final double? vdot;

  const RecapRace({
    required this.date,
    required this.name,
    required this.priority,
    required this.distanceM,
    required this.goalTimeSec,
    required this.run,
    required this.raced,
    required this.vdot,
  });
}

class RecapRecovery {
  final int days;
  final String untilIso;
  const RecapRecovery({required this.days, required this.untilIso});

  @override
  bool operator ==(Object other) =>
      other is RecapRecovery && other.days == days && other.untilIso == untilIso;

  @override
  int get hashCode => Object.hash(days, untilIso);
}

class RecapNext {
  /// Easy days still owed to the race, through `untilIso`. Null when nothing
  /// was raced or the recovery is already behind the runner.
  final RecapRecovery? recovery;

  /// The Sunday the next plan should start: the wizard's default, or the
  /// first Sunday after the recovery when that is later.
  final String startIso;

  /// The 5K time at the race's VDOT, to seed the next plan's paces with. Null
  /// without a VDOT, when the race is older than the recent-5K window, or when
  /// the time falls outside what the wizard's field takes.
  final int? seed5kSec;

  const RecapNext({
    required this.recovery,
    required this.startIso,
    required this.seed5kSec,
  });
}

class RecapSessions {
  final int completed;
  final int total;
  final int pct;
  final int skipped;
  final int missed;

  const RecapSessions({
    required this.completed,
    required this.total,
    required this.pct,
    required this.skipped,
    required this.missed,
  });

  @override
  bool operator ==(Object other) =>
      other is RecapSessions &&
      other.completed == completed &&
      other.total == total &&
      other.pct == pct &&
      other.skipped == skipped &&
      other.missed == missed;

  @override
  int get hashCode => Object.hash(completed, total, pct, skipped, missed);

  @override
  String toString() =>
      'RecapSessions($completed/$total, $pct%, skipped $skipped, missed $missed)';
}

class RecapVolume {
  final RecapVolumeBasis basis;
  final double done;
  final double planned;

  const RecapVolume(
      {required this.basis, required this.done, required this.planned});

  @override
  bool operator ==(Object other) =>
      other is RecapVolume &&
      other.basis == basis &&
      other.done == done &&
      other.planned == planned;

  @override
  int get hashCode => Object.hash(basis, done, planned);

  @override
  String toString() => 'RecapVolume($basis, $done of $planned)';
}

class RecapLongRuns {
  /// Long runs done, of those still on the books (skipped ones leave both).
  final int done;
  final int planned;

  /// The earliest-dated long run done, and the longest: the block's
  /// progression. Each is the linked run's distance, else the target.
  final double? first;
  final double? longest;

  const RecapLongRuns({
    required this.done,
    required this.planned,
    required this.first,
    required this.longest,
  });

  @override
  bool operator ==(Object other) =>
      other is RecapLongRuns &&
      other.done == done &&
      other.planned == planned &&
      other.first == first &&
      other.longest == longest;

  @override
  int get hashCode => Object.hash(done, planned, first, longest);

  @override
  String toString() => 'RecapLongRuns($done/$planned, $first → $longest)';
}

class PlanRecap {
  /// The ring's counts, plus the sessions it leaves out (skipped) and the
  /// ones it counts as not done whose day has passed (missed). An answered
  /// miss is still missed: answering it changes the plan ahead, not what was
  /// run.
  final RecapSessions sessions;
  final RecapVolume volume;
  final RecapLongRuns longRuns;
  final List<PlanRecapRecord> records;
  final RecapRace? race;
  final RecapNext next;

  const PlanRecap({
    required this.sessions,
    required this.volume,
    required this.longRuns,
    required this.records,
    required this.race,
    required this.next,
  });
}

/// The race the plan was built toward: the one on its end date, else its last
/// A race, else its last race. Expects [races] sorted, as [planRaces] returns.
PlanRace? recapGoalRace(List<PlanRace> races, String endDate) {
  final onEnd = races.where((r) => r.date == endDate).toList();
  if (onEnd.isNotEmpty) return onEnd.last;
  final a = races.where((r) => r.priority == 'A').toList();
  if (a.isNotEmpty) return a.last;
  return races.isNotEmpty ? races.last : null;
}

bool _isRunFamily(String? activityType) => activityType != 'cycle';

PlanRecapRaceRun _toRaceRun(PlanRecapRun r) => PlanRecapRaceRun(
      id: r.id,
      distanceM: r.distanceM,
      durationS: r.durationS,
      isDnf: r.isDnf == true,
    );

/// The run that stands for the race. A race with a workout row answers with
/// that row's link and nothing else: the matcher already put the closest run
/// on it, and an unlinked race workout is one the runner did not race or took
/// a run off. A race the plan has no row for (the plan's goal on its end
/// date) takes the longest run-family run that day covering at least
/// [kRecapRaceRunMinShare] of its distance.
PlanRecapRaceRun? recapRaceRun(
  PlanRace race,
  List<RecapWorkout> workouts,
  List<PlanRecapRun> runs,
) {
  if (race.workoutId != null) {
    final w = workouts.where((x) => x.id == race.workoutId).firstOrNull;
    final runId = w?.completedRunId;
    if (runId == null) return null;
    final run = runs.where((r) => r.id == runId).firstOrNull;
    return run == null ? null : _toRaceRun(run);
  }
  final raceM = race.distanceM;
  final floor =
      raceM != null && raceM > 0 ? raceM * kRecapRaceRunMinShare : 0.0;
  PlanRecapRun? best;
  for (final r in runs) {
    if (r.date != race.date || !_isRunFamily(r.activityType)) continue;
    final d = r.distanceM ?? 0;
    if (!(d > 0) || d < floor) continue;
    final bestD = best?.distanceM ?? 0;
    if (best == null ||
        d > bestD ||
        (d == best.distanceM && r.id.compareTo(best.id) < 0)) {
      best = r;
    }
  }
  return best == null ? null : _toRaceRun(best);
}

/// VDOT of a race run, rounded to one decimal, or null when the formula does
/// not apply to it.
double? recapRaceVdot(PlanRecapRaceRun? run, String? activityType) {
  if (run == null || run.isDnf) return null;
  if (activityType != null && activityType != 'run') return null;
  final d = run.distanceM ?? 0;
  final t = run.durationS ?? 0;
  if (!(t > 0) || d < kRecapVdotMinM || d > kRecapVdotMaxM) return null;
  final v = vdotFromRace(d, t);
  return v.isFinite && v > 0 ? (v * 10).round() / 10 : null;
}

/// The 5K time, in whole seconds, that [vdotFromRace] rates closest to
/// [vdot]. Found by bisection: the formula falls as the time grows, and has
/// no closed form.
int? fiveKSecondsAtVdot(double vdot) {
  if (!vdot.isFinite || vdot <= 0) return null;
  var lo = 60;
  var hi = 4 * 60 * 60;
  if (vdotFromRace(5000, lo) < vdot || vdotFromRace(5000, hi) > vdot) {
    return null;
  }
  while (hi - lo > 1) {
    final mid = (lo + hi) ~/ 2;
    if (vdotFromRace(5000, mid) > vdot) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return vdotFromRace(5000, lo) - vdot < vdot - vdotFromRace(5000, hi)
      ? lo
      : hi;
}

RecapVolume _timeBanked(
    List<RecapWorkout> workouts, Map<String, int> durationById) {
  var done = 0;
  var planned = 0;
  for (final w in workouts) {
    if (w.kind == 'rest') continue;
    final target = w.targetDurationSeconds ?? 0;
    if (w.skippedAt == null) planned += target;
    if (w._completed) {
      final actual =
          w.completedRunId != null ? durationById[w.completedRunId] : null;
      done += actual != null && actual > 0 ? actual : target;
    }
  }
  return RecapVolume(
      basis: RecapVolumeBasis.time,
      done: done.toDouble(),
      planned: planned.toDouble());
}

RecapLongRuns _longRunProgression(
    List<RecapWorkout> workouts, Map<String, double> distanceById) {
  var done = 0;
  var planned = 0;
  String? firstDate;
  double? first;
  for (final w in workouts) {
    if (w.kind != 'long' || w.skippedAt != null) continue;
    planned += 1;
    if (!w._completed) continue;
    done += 1;
    final actual =
        w.completedRunId != null ? distanceById[w.completedRunId] : null;
    final d = actual != null && actual > 0 ? actual : (w.targetDistanceM ?? 0);
    if (d > 0 &&
        (firstDate == null || w.scheduledDate.compareTo(firstDate) < 0)) {
      firstDate = w.scheduledDate;
      first = d;
    }
  }
  final longest = longestCompletedLongRunMetres(
    [
      for (final w in workouts)
        LongRunWorkout(
          kind: w.kind,
          targetDistanceM: w.targetDistanceM,
          completedRunId: w.completedRunId,
          manuallyCompleted: w.manuallyCompleted,
        ),
    ],
    distanceById,
  );
  return RecapLongRuns(
      done: done, planned: planned, first: first, longest: longest);
}

int _compareRecords(PlanRecapRecord a, PlanRecapRecord b) {
  final byDate = a.date.compareTo(b.date);
  if (byDate != 0) return byDate;
  return a.distance.compareTo(b.distance);
}

/// Assemble the recap. Sessions and distance count the way the plan page's
/// ring and distance stat do, so the recap never disagrees with them; a
/// walk-run plan, whose sessions are timed, reports time instead of
/// distance. Records are the `personal_records` rows set inside the plan
/// window — the cache holds only the best per bracket, so a record set during
/// the plan and beaten since is not listed.
PlanRecap assemblePlanRecap({
  required RecapPlan plan,
  required List<RecapWorkout> workouts,
  required List<PlanRecapRun> runs,
  required List<PlanRecapRecord> records,
  required String todayIso,
}) {
  var completed = 0;
  var total = 0;
  var skipped = 0;
  var missed = 0;
  for (final w in workouts) {
    final isSkipped = w.skippedAt != null;
    if (w.kind != 'rest') {
      if (isSkipped) {
        skipped += 1;
      } else {
        total += 1;
        if (w._completed) completed += 1;
      }
    }
    if (isWorkoutMissed(
      scheduledIso: w.scheduledDate,
      kind: w.kind,
      completed: w._completed,
      skipped: isSkipped,
      todayIso: todayIso,
    )) {
      missed += 1;
    }
  }
  final pct = total == 0 ? 0 : (completed / total * 100).round();

  final distanceById = <String, double>{};
  final durationById = <String, int>{};
  for (final r in runs) {
    if (r.distanceM != null) distanceById[r.id] = r.distanceM!;
    if (r.durationS != null) durationById[r.id] = r.durationS!;
  }
  final RecapVolume volume;
  if (isWalkRunPlan([
    for (final w in workouts)
      RestartWorkout(kind: w.kind, scheduledDate: w.scheduledDate),
  ])) {
    volume = _timeBanked(workouts, durationById);
  } else {
    final d = planDistanceBanked(
      [
        for (final w in workouts)
          DistanceWorkout(
            kind: w.kind,
            targetDistanceM: w.targetDistanceM,
            completedRunId: w.completedRunId,
            manuallyCompleted: w.manuallyCompleted,
            skippedAt: w.skippedAt,
          ),
      ],
      distanceById,
    );
    volume = RecapVolume(
        basis: RecapVolumeBasis.distance,
        done: d.completedMetres,
        planned: d.plannedMetres);
  }

  final inWindow = records
      .where((r) =>
          r.date.compareTo(plan.startDate) >= 0 &&
          r.date.compareTo(plan.endDate) <= 0)
      .toList()
    ..sort(_compareRecords);

  final goal = recapGoalRace(
    planRaces(
      endDate: plan.endDate,
      goalDistanceM: plan.goalDistanceM,
      goalTimeSec: plan.goalTimeSeconds,
      trimmedAt: plan.trimmedAt,
      workouts: [
        for (final w in workouts)
          PlanRaceWorkout(
            id: w.id,
            scheduledDate: w.scheduledDate,
            kind: w.kind,
            raceName: w.raceName,
            racePriority: w.racePriority,
            targetDistanceM: w.targetDistanceM,
            targetDurationSeconds: w.targetDurationSeconds,
          ),
      ],
    ),
    plan.endDate,
  );
  RecapRace? race;
  if (goal != null) {
    final run = recapRaceRun(goal, workouts, runs);
    final runRow =
        run == null ? null : runs.where((r) => r.id == run.id).firstOrNull;
    final workout = goal.workoutId == null
        ? null
        : workouts.where((w) => w.id == goal.workoutId).firstOrNull;
    race = RecapRace(
      date: goal.date,
      name: goal.name,
      priority: goal.priority,
      distanceM: goal.distanceM,
      goalTimeSec: goal.goalTimeSec,
      run: run,
      raced: run != null || workout?.manuallyCompleted == true,
      vdot: recapRaceVdot(run, runRow?.activityType),
    );
  }

  final defaultStart =
      toIsoDate(defaultPlanStart(parseIsoDate(todayIso), walkRun: false));
  RecapRecovery? recovery;
  if (race != null && race.raced && race.date.compareTo(todayIso) <= 0) {
    final runM = race.run?.distanceM;
    final raced = runM != null && runM > 0
        ? runM
        : (race.distanceM ?? plan.goalDistanceM);
    final days = seasonRecoveryDays(raced);
    final untilIso = shiftIsoDate(race.date, days);
    if (untilIso.compareTo(todayIso) >= 0) {
      recovery = RecapRecovery(days: days, untilIso: untilIso);
    }
  }
  final afterRecovery = recovery == null
      ? defaultStart
      : toIsoDate(nextSunday(parseIsoDate(shiftIsoDate(recovery.untilIso, 1))));
  final startIso =
      afterRecovery.compareTo(defaultStart) > 0 ? afterRecovery : defaultStart;

  int? seed5kSec;
  final vdot = race?.vdot;
  if (race != null &&
      vdot != null &&
      race.date.compareTo(todayIso) <= 0 &&
      race.date.compareTo(shiftIsoDate(todayIso, -kRecent5kWindowDays)) >= 0) {
    final s = fiveKSecondsAtVdot(vdot);
    if (isPlausibleRecent5k(s)) seed5kSec = s;
  }

  return PlanRecap(
    sessions: RecapSessions(
      completed: completed,
      total: total,
      pct: pct,
      skipped: skipped,
      missed: missed,
    ),
    volume: volume,
    longRuns: _longRunProgression(workouts, distanceById),
    records: inWindow,
    race: race,
    next: RecapNext(recovery: recovery, startIso: startIso, seed5kSec: seed5kSec),
  );
}

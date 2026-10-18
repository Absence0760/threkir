/// Changing a plan's race date mid-plan (issue #1186, decisions § 2120): which
/// weeks to drop or repeat so the plan ends on the new race day with its taper
/// whole. `change_plan_race_date` applies the result in one transaction and
/// re-checks every choice.
///
/// Whole weeks, so every workout keeps its weekday role and stays inside the
/// week window both clients derive from start_date + 7 * week_index. An earlier
/// race drops pre-taper weeks that have not started (build first, then base,
/// then peak, the latest of each first); a later race repeats the last base or
/// build week before the peak, or before the taper once the peak has started.
/// The taper and race weeks are never dropped, and nothing that has started,
/// nothing completed and no other race moves.
///
/// Dart twin of `apps/web/src/lib/training/plan_race_date.ts`.
library;

import 'cycle_plan.dart' show daysBetweenIso;
import 'plan_bulk_ops.dart' show shiftIsoDate;
import 'race_plan_preset.dart';

const int kRaceDateMaxAddedWeeks = 52;

class RaceDatePlan {
  final String startDate;
  final String endDate;
  final String? trimmedAt;
  final String status;
  final bool isTemplate;

  const RaceDatePlan({
    required this.startDate,
    required this.endDate,
    required this.trimmedAt,
    required this.status,
    this.isTemplate = false,
  });
}

class RaceDateWeek {
  final String id;
  final int weekIndex;
  final String phase;

  const RaceDateWeek(
      {required this.id, required this.weekIndex, required this.phase});
}

class RaceDateWorkout {
  final String id;
  final String weekId;
  final String scheduledDate;
  final String kind;
  final String? racePriority;
  final String? completedRunId;
  final bool manuallyCompleted;

  const RaceDateWorkout({
    required this.id,
    required this.weekId,
    required this.scheduledDate,
    required this.kind,
    this.racePriority,
    required this.completedRunId,
    required this.manuallyCompleted,
  });

  RaceDateWorkout copyWith(
          {String? kind, String? racePriority, bool? manuallyCompleted}) =>
      RaceDateWorkout(
        id: id,
        weekId: weekId,
        scheduledDate: scheduledDate,
        kind: kind ?? this.kind,
        racePriority: racePriority ?? this.racePriority,
        completedRunId: completedRunId,
        manuallyCompleted: manuallyCompleted ?? this.manuallyCompleted,
      );
}

enum RaceDateRefusal {
  /// Not a usable date.
  invalid,

  /// Today or earlier.
  past,

  /// The race is already on that day.
  unchanged,

  /// The plan has no race still ahead to move.
  noRace,

  /// Race week has started, so no week can be added in front of it.
  raceWeekStarted,

  /// Even with every pre-taper week that has not started cut, the taper
  /// cannot end on that day. [RaceDateResult.earliestIso] says the first day
  /// it can.
  tooSoon,

  /// More than [kRaceDateMaxAddedWeeks] weeks later.
  tooFar,

  /// No base or build week to repeat.
  noBuildWeek,

  /// A week that would move or go holds another race or a completed workout.
  inTheWay,
}

class RaceDateChange {
  final String raceDateIso;

  /// Weeks added (positive) or removed (negative).
  final int weekDelta;
  final List<String> dropWeekIds;

  /// The week index the repeated weeks are inserted at, or null.
  final int? insertAt;
  final int insertCount;
  final String? repeatWeekId;

  /// The race workout that moves onto the new day, or null when the plan's
  /// race is only its end date.
  final String? raceWorkoutId;

  const RaceDateChange({
    required this.raceDateIso,
    required this.weekDelta,
    required this.dropWeekIds,
    required this.insertAt,
    required this.insertCount,
    required this.repeatWeekId,
    required this.raceWorkoutId,
  });
}

/// Web models this as a discriminated union; Dart carries the arms on one
/// small class, as [RacePlanPresetResult] does.
class RaceDateResult {
  final RaceDateChange? change;
  final RaceDateRefusal? reason;
  final String? earliestIso;

  const RaceDateResult.ok(RaceDateChange this.change)
      : reason = null,
        earliestIso = null;
  const RaceDateResult.refused(RaceDateRefusal this.reason, {this.earliestIso})
      : change = null;

  bool get ok => change != null;
}

const _taper = {'taper', 'race'};
const _late = {'peak', 'taper', 'race'};
const _dropRank = {'build': 0, 'base': 1, 'peak': 2};

bool _isDone(RaceDateWorkout w) =>
    w.completedRunId != null || w.manuallyCompleted;

/// The race day a plan can move: its end date, when the plan is the runner's
/// own active or paused plan, was not ended early, and its last week is a race
/// week. Null for a walk-run plan, a trimmed plan or a template.
String? planRaceDate(RaceDatePlan plan, List<RaceDateWeek> weeks) {
  if (plan.isTemplate || plan.trimmedAt != null) return null;
  if (plan.status != 'active' && plan.status != 'paused') return null;
  if (weeks.isEmpty) return null;
  final last = weeks.reduce((a, b) => b.weekIndex > a.weekIndex ? b : a);
  return last.phase == 'race' ? plan.endDate : null;
}

int _trailingStart(List<RaceDateWeek> sorted, Set<String> phases) {
  var start = sorted.last.weekIndex + 1;
  for (var i = sorted.length - 1; i >= 0 && phases.contains(sorted[i].phase); i--) {
    start = sorted[i].weekIndex;
  }
  return start;
}

RaceDateResult raceDateChange({
  required RaceDatePlan plan,
  required List<RaceDateWeek> weeks,
  required List<RaceDateWorkout> workouts,
  required String raceDateIso,
  required String todayIso,
}) {
  final preset = racePlanPreset(raceDateIso: raceDateIso, todayIso: todayIso);
  if (!preset.ok && preset.reason != RacePlanRefusal.tooSoon) {
    return RaceDateResult.refused(preset.reason == RacePlanRefusal.past
        ? RaceDateRefusal.past
        : RaceDateRefusal.invalid);
  }
  final current = planRaceDate(plan, weeks);
  if (current == null || current.compareTo(todayIso) < 0) {
    return const RaceDateResult.refused(RaceDateRefusal.noRace);
  }
  if (raceDateIso == current) {
    return const RaceDateResult.refused(RaceDateRefusal.unchanged);
  }

  final toRace = daysBetweenIso(plan.startDate, raceDateIso);
  final toToday = daysBetweenIso(plan.startDate, todayIso);
  if (toRace == null || toToday == null) {
    return const RaceDateResult.refused(RaceDateRefusal.invalid);
  }

  final sorted = [...weeks]..sort((a, b) => a.weekIndex - b.weekIndex);
  final last = sorted.last;
  final r = last.weekIndex;
  final c = (toToday / 7).floor();
  final k = (toRace / 7).floor() - r;

  final byWeek = <String, List<RaceDateWorkout>>{};
  for (final w in workouts) {
    byWeek.putIfAbsent(w.weekId, () => []).add(w);
  }
  List<RaceDateWorkout> of(RaceDateWeek week) => byWeek[week.id] ?? const [];
  final lastRows = of(last);
  bool isARace(RaceDateWorkout w) =>
      w.kind == 'race' &&
      (w.racePriority == null || w.racePriority == 'A') &&
      !_isDone(w);
  final aRaces = lastRows.where(isARace).toList()
    ..sort((a, b) => b.scheduledDate.compareTo(a.scheduledDate));
  final raceWo =
      aRaces.where((w) => w.scheduledDate == plan.endDate).firstOrNull ??
          aRaces.firstOrNull;
  bool blocks(RaceDateWorkout w) =>
      (w.kind == 'race' && w.id != raceWo?.id) || _isDone(w);
  bool holdsRace(RaceDateWeek week) => of(week).any((w) => w.kind == 'race');

  var dropWeekIds = <String>[];
  int? insertAt;
  String? repeatWeekId;
  var moving = <RaceDateWeek>[];

  if (k < 0) {
    final candidates = sorted
        .where((w) =>
            w.weekIndex > c &&
            !_taper.contains(w.phase) &&
            !holdsRace(w) &&
            !of(w).any(_isDone))
        .toList()
      ..sort((a, b) {
        final rank = (_dropRank[a.phase] ?? 3) - (_dropRank[b.phase] ?? 3);
        return rank != 0 ? rank : b.weekIndex - a.weekIndex;
      });
    if (candidates.length < -k) {
      final weekStart = shiftIsoDate(plan.startDate, 7 * (r - candidates.length));
      final tomorrow = shiftIsoDate(todayIso, 1);
      return RaceDateResult.refused(RaceDateRefusal.tooSoon,
          earliestIso:
              weekStart.compareTo(tomorrow) > 0 ? weekStart : tomorrow);
    }
    final drop = candidates.take(-k).toList();
    dropWeekIds = drop.map((w) => w.id).toList()..sort();
    final firstDrop =
        drop.map((w) => w.weekIndex).reduce((a, b) => a < b ? a : b);
    final dropped = dropWeekIds.toSet();
    moving = sorted
        .where((w) => w.weekIndex > firstDrop && !dropped.contains(w.id))
        .toList();
  } else if (k > 0) {
    if (k > kRaceDateMaxAddedWeeks) {
      return const RaceDateResult.refused(RaceDateRefusal.tooFar);
    }
    final lateStart = _trailingStart(sorted, _late);
    final p = lateStart > c + 1 ? lateStart : c + 1;
    if (p > r) {
      return const RaceDateResult.refused(RaceDateRefusal.raceWeekStarted);
    }
    final before = sorted
        .where((w) => w.weekIndex < p && !holdsRace(w))
        .toList()
        .reversed
        .toList();
    final source = before
            .where((w) => w.phase == 'base' || w.phase == 'build')
            .firstOrNull ??
        before.where((w) => !_taper.contains(w.phase)).firstOrNull;
    if (source == null) {
      return const RaceDateResult.refused(RaceDateRefusal.noBuildWeek);
    }
    insertAt = p;
    repeatWeekId = source.id;
    moving = sorted.where((w) => w.weekIndex >= p).toList();
  }

  if (moving.any((w) => of(w).any(blocks))) {
    return const RaceDateResult.refused(RaceDateRefusal.inTheWay);
  }

  for (final w in lastRows) {
    if (w.id == raceWo?.id) continue;
    final moved = shiftIsoDate(w.scheduledDate, 7 * k);
    final cmp = moved.compareTo(raceDateIso);
    final gone = cmp > 0 || (cmp == 0 && raceWo != null);
    if (gone && blocks(w)) {
      return const RaceDateResult.refused(RaceDateRefusal.inTheWay);
    }
  }

  return RaceDateResult.ok(RaceDateChange(
    raceDateIso: raceDateIso,
    weekDelta: k,
    dropWeekIds: dropWeekIds,
    insertAt: insertAt,
    insertCount: k > 0 ? k : 0,
    repeatWeekId: repeatWeekId,
    raceWorkoutId: raceWo?.id,
  ));
}

/// A suggested change to a coach-assigned plan, read for display (issue #1215
/// Phase 2, decisions § 2382).
///
/// A `plan_change_requests` row stores the apply_ai_plan_edits payload: a list
/// of workout changes (`id` plus the fields it changes) and a list of week
/// target changes. Both clients show it as before → after lines, with "before"
/// read from the plan rows as they are now, so the card describes what an
/// approval would write rather than what the athlete's screen showed.
///
/// Web twin: `apps/web/src/lib/training/plan_change.ts`.
library;

const List<String> planChangeStatuses = [
  'pending',
  'approved',
  'declined',
  'withdrawn',
  'overridden',
];

String? parsePlanChangeStatus(Object? raw) =>
    raw is String && planChangeStatuses.contains(raw) ? raw : null;

class PlanChangeWorkoutRow {
  const PlanChangeWorkoutRow({
    required this.id,
    required this.scheduledDate,
    required this.kind,
    required this.targetDistanceM,
    required this.targetDurationSeconds,
    required this.skipped,
  });

  final String id;
  final String scheduledDate;
  final String kind;
  final num? targetDistanceM;
  final num? targetDurationSeconds;
  final bool skipped;
}

class PlanChangeWeekRow {
  const PlanChangeWeekRow({
    required this.id,
    required this.weekIndex,
    required this.targetVolumeM,
  });

  final String id;
  final int weekIndex;
  final num? targetVolumeM;
}

class PlanChangeWorkoutState {
  const PlanChangeWorkoutState({
    required this.scheduledDate,
    required this.kind,
    required this.distanceM,
    required this.durationS,
    required this.skipped,
  });

  final String scheduledDate;
  final String kind;
  final num? distanceM;
  final num? durationS;
  final bool skipped;

  @override
  bool operator ==(Object other) =>
      other is PlanChangeWorkoutState &&
      other.scheduledDate == scheduledDate &&
      other.kind == kind &&
      other.distanceM == distanceM &&
      other.durationS == durationS &&
      other.skipped == skipped;

  @override
  int get hashCode =>
      Object.hash(scheduledDate, kind, distanceM, durationS, skipped);
}

class PlanChangeWorkoutLine {
  const PlanChangeWorkoutLine({
    required this.workoutId,
    required this.before,
    required this.after,
  });

  final String workoutId;
  final PlanChangeWorkoutState before;
  final PlanChangeWorkoutState after;
}

class PlanChangeWeekLine {
  const PlanChangeWeekLine({
    required this.weekId,
    required this.weekIndex,
    required this.beforeM,
    required this.afterM,
  });

  final String weekId;
  final int weekIndex;
  final num? beforeM;
  final num? afterM;
}

class PlanChangeLines {
  const PlanChangeLines({
    required this.workouts,
    required this.weeks,
    required this.unreadable,
  });

  final List<PlanChangeWorkoutLine> workouts;
  final List<PlanChangeWeekLine> weeks;

  /// Changes whose row the viewer can no longer read (deleted, or the link
  /// ended): counted, never guessed at.
  final int unreadable;
}

/// The well-formed changes of a stored list: objects with a string id.
List<Map<String, dynamic>> parseChangeList(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final c in raw)
      if (c is Map && c['id'] is String) Map<String, dynamic>.from(c),
  ];
}

({List<String> workoutIds, List<String> weekIds}) planChangeIds(
  Object? workouts,
  Object? weeks,
) =>
    (
      workoutIds: [for (final c in parseChangeList(workouts)) c['id'] as String],
      weekIds: [for (final c in parseChangeList(weeks)) c['id'] as String],
    );

num? _numberOrNull(Object? v, num? fallback) {
  if (v == null) return null;
  return v is num && v.isFinite ? v : fallback;
}

PlanChangeLines planChangeLines(
  Object? workouts,
  Object? weeks,
  List<PlanChangeWorkoutRow> workoutRows,
  List<PlanChangeWeekRow> weekRows,
) {
  final byWorkout = {for (final r in workoutRows) r.id: r};
  final byWeek = {for (final r in weekRows) r.id: r};
  var unreadable = 0;

  final workoutLines = <PlanChangeWorkoutLine>[];
  for (final c in parseChangeList(workouts)) {
    final id = c['id'] as String;
    final row = byWorkout[id];
    if (row == null) {
      unreadable++;
      continue;
    }
    final before = PlanChangeWorkoutState(
      scheduledDate: row.scheduledDate,
      kind: row.kind,
      distanceM: row.targetDistanceM,
      durationS: row.targetDurationSeconds,
      skipped: row.skipped,
    );
    final date = c['scheduled_date'];
    final kind = c['kind'];
    final after = PlanChangeWorkoutState(
      scheduledDate: date is String ? date : before.scheduledDate,
      kind: kind is String ? kind : before.kind,
      distanceM: c.containsKey('target_distance_m')
          ? _numberOrNull(c['target_distance_m'], before.distanceM)
          : before.distanceM,
      durationS: c.containsKey('target_duration_seconds')
          ? _numberOrNull(c['target_duration_seconds'], before.durationS)
          : before.durationS,
      skipped: c['skip'] == true || before.skipped,
    );
    workoutLines.add(
      PlanChangeWorkoutLine(workoutId: id, before: before, after: after),
    );
  }
  workoutLines.sort((a, b) {
    final byDay = a.before.scheduledDate.compareTo(b.before.scheduledDate);
    return byDay != 0 ? byDay : a.workoutId.compareTo(b.workoutId);
  });

  final weekLines = <PlanChangeWeekLine>[];
  for (final c in parseChangeList(weeks)) {
    final id = c['id'] as String;
    final row = byWeek[id];
    if (row == null) {
      unreadable++;
      continue;
    }
    weekLines.add(
      PlanChangeWeekLine(
        weekId: id,
        weekIndex: row.weekIndex,
        beforeM: row.targetVolumeM,
        afterM: _numberOrNull(c['target_volume_m'], row.targetVolumeM),
      ),
    );
  }
  weekLines.sort((a, b) => a.weekIndex.compareTo(b.weekIndex));

  return PlanChangeLines(
    workouts: workoutLines,
    weeks: weekLines,
    unreadable: unreadable,
  );
}

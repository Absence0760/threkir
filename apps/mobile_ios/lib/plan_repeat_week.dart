/// Running weeks of a plan again from next week, and pushing every later week
/// back by as many whole weeks. "Too hard? Repeat this week" runs one week
/// again (this week, or the week that just finished); the break offer
/// (`plan_break.dart`) runs the latest N weeks again. Both share [rerunFrame]
/// and [rerunPlacement], as `repeat_plan_week` and
/// `reschedule_plan_after_break` share `private.repeat_plan_weeks`, which
/// applies the change in one transaction and re-checks every choice.
///
/// Copies go in at the current week + 1, each workout on its weekday. A plan
/// that ends on a race keeps its race day: as many pre-taper weeks that have
/// not started are dropped instead (build first, then base, then peak, the
/// latest of each first), as `change_plan_race_date` drops them. A plan
/// without a race ends that many weeks later. The taper and race weeks never
/// run again, and nothing done and no other race moves.
///
/// Dart twin of `apps/web/src/lib/training/plan_repeat_week.ts`.
library;

import 'cycle_plan.dart' show daysBetweenIso;
import 'plan_bulk_ops.dart' show shiftIsoDate;
import 'plan_race_date.dart';

enum RepeatWeekRefusal {
  /// Not an active plan of the runner's that is under way.
  notActive,

  /// Not this week or last week, or a taper or race week.
  notRepeatable,

  /// There is no week after this one to push back.
  lastWeek,

  /// A race plan with no pre-taper week left that could make room.
  noRoom,

  /// A week that would move holds another race or a completed workout.
  inTheWay,
}

class RepeatWeekChange {
  final String weekId;

  /// The week index the copy goes in at: the current week + 1.
  final int copyIndex;

  /// The first day of the copy's week.
  final String copyStartIso;
  final String? dropWeekId;

  /// The plan's end date afterwards.
  final String endIso;

  /// The race day the plan keeps, or null for a plan without one.
  final String? raceDateIso;

  const RepeatWeekChange({
    required this.weekId,
    required this.copyIndex,
    required this.copyStartIso,
    required this.dropWeekId,
    required this.endIso,
    required this.raceDateIso,
  });
}

/// Web models this as a discriminated union; Dart carries the arms on one
/// small class, as [RaceDateResult] does.
class RepeatWeekResult {
  final RepeatWeekChange? change;
  final RepeatWeekRefusal? reason;

  const RepeatWeekResult.ok(RepeatWeekChange this.change) : reason = null;
  const RepeatWeekResult.refused(RepeatWeekRefusal this.reason) : change = null;

  bool get ok => change != null;
}

class RerunFrame {
  final int current;
  final List<RaceDateWeek> sorted;
  final Map<String, List<RaceDateWorkout>> byWeek;

  /// The race day the plan keeps, or null for a plan without one.
  final String? raceDate;

  /// The weeks a race plan may drop, in the order it drops them.
  final List<RaceDateWeek> drops;

  const RerunFrame({
    required this.current,
    required this.sorted,
    required this.byWeek,
    required this.raceDate,
    required this.drops,
  });
}

class RerunPlacement {
  final List<RaceDateWeek> drops;
  final String? endIso;

  /// [RepeatWeekRefusal.noRoom] or [RepeatWeekRefusal.inTheWay].
  final RepeatWeekRefusal? reason;

  const RerunPlacement.ok(this.drops, String this.endIso) : reason = null;
  const RerunPlacement.refused(RepeatWeekRefusal this.reason)
      : drops = const [],
        endIso = null;

  bool get ok => reason == null;
}

const Set<String> kRerunTaperPhases = {'taper', 'race'};
const _dropRank = {'build': 0, 'base': 1, 'peak': 2};

bool _holdsSomething(RaceDateWorkout w) =>
    w.kind == 'race' || w.completedRunId != null || w.manuallyCompleted;

/// The plan as a rerun sees it, or null when it is not an active plan that is
/// under way with a week after the current one.
RerunFrame? rerunFrame(RaceDatePlan plan, List<RaceDateWeek> weeks,
    List<RaceDateWorkout> workouts, String todayIso) {
  if (plan.isTemplate || plan.trimmedAt != null || plan.status != 'active') {
    return null;
  }
  if (weeks.isEmpty || todayIso.compareTo(plan.endDate) > 0) return null;
  final toToday = daysBetweenIso(plan.startDate, todayIso);
  if (toToday == null || toToday < 0) return null;
  final current = (toToday / 7).floor();
  final sorted = [...weeks]..sort((a, b) => a.weekIndex - b.weekIndex);
  if (sorted.last.weekIndex <= current) return null;

  final byWeek = <String, List<RaceDateWorkout>>{};
  for (final w in workouts) {
    (byWeek[w.weekId] ??= []).add(w);
  }
  final raceDate = planRaceDate(plan, weeks);
  final drops = raceDate == null
      ? <RaceDateWeek>[]
      : (sorted
          .where((w) =>
              w.weekIndex > current &&
              !kRerunTaperPhases.contains(w.phase) &&
              !(byWeek[w.id] ?? const []).any(_holdsSomething))
          .toList()
        ..sort((a, b) {
          final byRank = (_dropRank[a.phase] ?? 3) - (_dropRank[b.phase] ?? 3);
          return byRank != 0 ? byRank : b.weekIndex - a.weekIndex;
        }));
  return RerunFrame(
    current: current,
    sorted: sorted,
    byWeek: byWeek,
    raceDate: raceDate,
    drops: drops,
  );
}

/// Where [k] copies would leave the rest of the plan: the weeks a race plan
/// drops and the end date afterwards, or why it cannot.
RerunPlacement rerunPlacement(RerunFrame frame, RaceDatePlan plan, int k) {
  if (frame.raceDate != null && k > frame.drops.length) {
    return const RerunPlacement.refused(RepeatWeekRefusal.noRoom);
  }
  final drops =
      frame.raceDate != null ? frame.drops.sublist(0, k) : <RaceDateWeek>[];
  final dropped = drops.map((w) => w.id).toSet();
  for (final w in frame.sorted) {
    if (w.weekIndex <= frame.current || dropped.contains(w.id)) continue;
    final below = drops.where((d) => d.weekIndex < w.weekIndex).length;
    if (k - below == 0) continue;
    if ((frame.byWeek[w.id] ?? const []).any(_holdsSomething)) {
      return const RerunPlacement.refused(RepeatWeekRefusal.inTheWay);
    }
  }
  return RerunPlacement.ok(
    drops,
    frame.raceDate != null ? plan.endDate : shiftIsoDate(plan.endDate, 7 * k),
  );
}

RepeatWeekResult repeatWeekChange({
  required RaceDatePlan plan,
  required List<RaceDateWeek> weeks,
  required List<RaceDateWorkout> workouts,
  required String weekId,
  required String todayIso,
}) {
  if (plan.isTemplate ||
      plan.trimmedAt != null ||
      plan.status != 'active' ||
      weeks.isEmpty) {
    return const RepeatWeekResult.refused(RepeatWeekRefusal.notActive);
  }
  final toToday = daysBetweenIso(plan.startDate, todayIso);
  if (toToday == null || toToday < 0 || todayIso.compareTo(plan.endDate) > 0) {
    return const RepeatWeekResult.refused(RepeatWeekRefusal.notActive);
  }
  final current = (toToday / 7).floor();
  RaceDateWeek? week;
  for (final w in weeks) {
    if (w.id == weekId) week = w;
  }
  if (week == null ||
      week.weekIndex > current ||
      week.weekIndex < current - 1 ||
      kRerunTaperPhases.contains(week.phase)) {
    return const RepeatWeekResult.refused(RepeatWeekRefusal.notRepeatable);
  }
  final frame = rerunFrame(plan, weeks, workouts, todayIso);
  if (frame == null) {
    return const RepeatWeekResult.refused(RepeatWeekRefusal.lastWeek);
  }
  final placed = rerunPlacement(frame, plan, 1);
  if (!placed.ok) return RepeatWeekResult.refused(placed.reason!);
  return RepeatWeekResult.ok(RepeatWeekChange(
    weekId: weekId,
    copyIndex: current + 1,
    copyStartIso: shiftIsoDate(plan.startDate, 7 * (current + 1)),
    dropWeekId: placed.drops.isEmpty ? null : placed.drops.first.id,
    endIso: placed.endIso!,
    raceDateIso: frame.raceDate,
  ));
}

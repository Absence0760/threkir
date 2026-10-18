/// A break of a week or more inside an active plan: whether the runner is on
/// one, and what re-running the missed weeks would change.
/// `reschedule_plan_after_break` applies a change in one transaction and
/// re-checks every choice.
///
/// A break is [kBreakMinDays] or more of the runner's local days, up to
/// yesterday, with no run of any kind and no plan workout done. A run today
/// does not end it, so the offer is still there on the day the runner comes
/// back.
///
/// The change runs the latest `weeks` weeks up to the current one again, from
/// next week, and everything after them moves back by that many whole weeks.
/// A plan that ends on a race keeps its race day: the same number of pre-taper
/// weeks that have not started are dropped (build first, then base, then peak,
/// the latest of each first), as `change_plan_race_date` drops them. The
/// taper, anything that has started and anything done never move.
library;

import 'cycle_plan.dart' show daysBetweenIso;
import 'plan_bulk_ops.dart' show shiftIsoDate;
import 'plan_race_date.dart';

const int kBreakMinDays = 7;
const int kBreakMaxWeeks = 52;

class PlanBreak {
  /// The first day of the break.
  final String fromIso;

  /// Days without a run or a done workout, today not counted.
  final int days;

  /// The race day the plan keeps, or null for a plan without one.
  final String? raceDateIso;

  /// The most weeks a change can run again; at least 1.
  final int maxWeeks;

  const PlanBreak({
    required this.fromIso,
    required this.days,
    required this.raceDateIso,
    required this.maxWeeks,
  });
}

class BreakChange {
  final int weeks;

  /// The weeks run again, oldest first; copies go in at the current week + 1.
  final List<String> repeatWeekIds;
  final List<String> dropWeekIds;
  final String endIso;

  const BreakChange({
    required this.weeks,
    required this.repeatWeekIds,
    required this.dropWeekIds,
    required this.endIso,
  });
}

const _taper = {'taper', 'race'};
const _dropRank = {'build': 0, 'base': 1, 'peak': 2};

bool _isDone(RaceDateWorkout w) =>
    w.completedRunId != null || w.manuallyCompleted;

class _Shape {
  final String from;
  final int days;
  final int current;
  final String? raceDate;
  final List<RaceDateWeek> sources;
  final List<RaceDateWeek> drops;
  final List<RaceDateWeek> sorted;
  final Map<String, List<RaceDateWorkout>> byWeek;

  const _Shape(this.from, this.days, this.current, this.raceDate, this.sources,
      this.drops, this.sorted, this.byWeek);
}

_Shape? _shape(RaceDatePlan plan, List<RaceDateWeek> weeks,
    List<RaceDateWorkout> workouts, List<String> runDatesIso, String todayIso) {
  if (plan.isTemplate || plan.trimmedAt != null || plan.status != 'active') {
    return null;
  }
  if (weeks.isEmpty || todayIso.compareTo(plan.endDate) > 0) return null;
  final toToday = daysBetweenIso(plan.startDate, todayIso);
  if (toToday == null || toToday < 0) return null;
  final current = (toToday / 7).floor();
  final sorted = [...weeks]..sort((a, b) => a.weekIndex - b.weekIndex);
  if (sorted.last.weekIndex <= current) return null;

  String? last;
  for (final d in runDatesIso) {
    if (d.compareTo(todayIso) < 0 && (last == null || d.compareTo(last) > 0)) {
      last = d;
    }
  }
  for (final w in workouts) {
    if (_isDone(w) &&
        w.scheduledDate.compareTo(todayIso) < 0 &&
        (last == null || w.scheduledDate.compareTo(last) > 0)) {
      last = w.scheduledDate;
    }
  }
  final afterLast = last == null ? plan.startDate : shiftIsoDate(last, 1);
  final from =
      afterLast.compareTo(plan.startDate) > 0 ? afterLast : plan.startDate;
  final days = daysBetweenIso(from, todayIso);
  if (days == null || days < kBreakMinDays) return null;
  if (!workouts.any((w) =>
      w.kind != 'rest' &&
      w.scheduledDate.compareTo(from) >= 0 &&
      w.scheduledDate.compareTo(todayIso) < 0)) {
    return null;
  }

  final byWeek = <String, List<RaceDateWorkout>>{};
  for (final w in workouts) {
    (byWeek[w.weekId] ??= []).add(w);
  }
  List<RaceDateWorkout> of(RaceDateWeek week) => byWeek[week.id] ?? const [];

  final sources = <RaceDateWeek>[];
  for (final w in sorted.reversed) {
    if (w.weekIndex > current) continue;
    if (_taper.contains(w.phase)) break;
    sources.add(w);
  }
  final raceDate = planRaceDate(plan, weeks);
  final drops = raceDate == null
      ? <RaceDateWeek>[]
      : (sorted
          .where((w) =>
              w.weekIndex > current &&
              !_taper.contains(w.phase) &&
              !of(w).any((x) => x.kind == 'race' || _isDone(x)))
          .toList()
        ..sort((a, b) {
          final byRank = (_dropRank[a.phase] ?? 3) - (_dropRank[b.phase] ?? 3);
          return byRank != 0 ? byRank : b.weekIndex - a.weekIndex;
        }));
  return _Shape(from, days, current, raceDate, sources, drops, sorted, byWeek);
}

BreakChange? _changeFor(_Shape s, RaceDatePlan plan, int k) {
  if (k < 1 || k > kBreakMaxWeeks || k > s.sources.length) return null;
  if (s.raceDate != null && k > s.drops.length) return null;
  final drop = s.raceDate != null ? s.drops.sublist(0, k) : <RaceDateWeek>[];
  final dropped = drop.map((w) => w.id).toSet();
  for (final w in s.sorted) {
    if (w.weekIndex <= s.current || dropped.contains(w.id)) continue;
    final below = drop.where((d) => d.weekIndex < w.weekIndex).length;
    if (k - below == 0) continue;
    if ((s.byWeek[w.id] ?? const []).any((x) => x.kind == 'race' || _isDone(x))) {
      return null;
    }
  }
  return BreakChange(
    weeks: k,
    repeatWeekIds: s.sources.sublist(0, k).reversed.map((w) => w.id).toList(),
    dropWeekIds: drop.map((w) => w.id).toList()..sort(),
    endIso: s.raceDate != null ? plan.endDate : shiftIsoDate(plan.endDate, 7 * k),
  );
}

/// The break the runner is on, or null when there is none to offer anything
/// for: not an active plan of their own, the plan has not started or has no
/// week after this one, fewer than [kBreakMinDays] quiet days, no planned
/// workout fell in them, or no change can keep the taper and the race day.
PlanBreak? detectPlanBreak({
  required RaceDatePlan plan,
  required List<RaceDateWeek> weeks,
  required List<RaceDateWorkout> workouts,
  required List<String> runDatesIso,
  required String todayIso,
}) {
  final s = _shape(plan, weeks, workouts, runDatesIso, todayIso);
  if (s == null) return null;
  final cap = [(s.days / 7).floor(), kBreakMaxWeeks].reduce((a, b) => a < b ? a : b);
  var maxWeeks = 0;
  while (maxWeeks < cap && _changeFor(s, plan, maxWeeks + 1) != null) {
    maxWeeks++;
  }
  if (maxWeeks < 1) return null;
  return PlanBreak(
      fromIso: s.from, days: s.days, raceDateIso: s.raceDate, maxWeeks: maxWeeks);
}

/// What running the latest [weeksToRepeat] weeks again would change, or null
/// when there is no break or [weeksToRepeat] is outside 1..maxWeeks.
BreakChange? planBreakChange({
  required RaceDatePlan plan,
  required List<RaceDateWeek> weeks,
  required List<RaceDateWorkout> workouts,
  required List<String> runDatesIso,
  required String todayIso,
  required int weeksToRepeat,
}) {
  final found = detectPlanBreak(
      plan: plan,
      weeks: weeks,
      workouts: workouts,
      runDatesIso: runDatesIso,
      todayIso: todayIso);
  if (found == null || weeksToRepeat > found.maxWeeks) return null;
  final s = _shape(plan, weeks, workouts, runDatesIso, todayIso);
  return s == null ? null : _changeFor(s, plan, weeksToRepeat);
}

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
/// taper, anything that has started and anything done never move. The weeks
/// and drops come from `plan_repeat_week.dart`, which "Repeat this week"
/// shares.
library;

import 'cycle_plan.dart' show daysBetweenIso;
import 'plan_bulk_ops.dart' show shiftIsoDate;
import 'plan_race_date.dart';
import 'plan_repeat_week.dart';

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

bool _isDone(RaceDateWorkout w) =>
    w.completedRunId != null || w.manuallyCompleted;

class _Shape {
  final String from;
  final int days;
  final RerunFrame frame;
  final List<RaceDateWeek> sources;

  const _Shape(this.from, this.days, this.frame, this.sources);
}

_Shape? _shape(RaceDatePlan plan, List<RaceDateWeek> weeks,
    List<RaceDateWorkout> workouts, List<String> runDatesIso, String todayIso) {
  final frame = rerunFrame(plan, weeks, workouts, todayIso);
  if (frame == null) return null;

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

  final sources = <RaceDateWeek>[];
  for (final w in frame.sorted.reversed) {
    if (w.weekIndex > frame.current) continue;
    if (kRerunTaperPhases.contains(w.phase)) break;
    sources.add(w);
  }
  return _Shape(from, days, frame, sources);
}

BreakChange? _changeFor(_Shape s, RaceDatePlan plan, int k) {
  if (k < 1 || k > kBreakMaxWeeks || k > s.sources.length) return null;
  final placed = rerunPlacement(s.frame, plan, k);
  if (!placed.ok) return null;
  return BreakChange(
    weeks: k,
    repeatWeekIds: s.sources.sublist(0, k).reversed.map((w) => w.id).toList(),
    dropWeekIds: placed.drops.map((w) => w.id).toList()..sort(),
    endIso: placed.endIso!,
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
      fromIso: s.from, days: s.days, raceDateIso: s.frame.raceDate, maxWeeks: maxWeeks);
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

/// Whether `user_settings.prefs.plan_break_dismissed` already answers this
/// break: the same plan and the same first day. A later break, or one in
/// another plan, is offered again; anything unreadable is not an answer.
bool isBreakDismissed(Object? pref, String planId, String fromIso) {
  if (pref is! Map) return false;
  return pref['plan_id'] == planId && pref['from'] == fromIso;
}

/// Whether the break offer is on screen: a break to offer that the runner has
/// not answered. While it is, a host shows neither the missed-workout prompt
/// nor the plan nudge card, and a make-up deep link only opens the plan: those
/// judge the missed weeks one workout or one week at a time, while the break
/// offer re-runs them whole.
bool breakOfferShowing(PlanBreak? found, Object? dismissedPref, String planId) =>
    found != null && !isBreakDismissed(dismissedPref, planId, found.fromIso);

/// The days a break covered, for a judge that must not read them as missed
/// training: the break on now, from its first day to today, or else the last
/// one the runner answered in this plan (`plan_break_dismissed` with its
/// `until`). Null when there is neither.
({String fromIso, String untilIso})? breakWindow(
    PlanBreak? found, Object? dismissedPref, String planId, String todayIso) {
  if (found != null) return (fromIso: found.fromIso, untilIso: todayIso);
  if (dismissedPref is! Map) return null;
  final from = dismissedPref['from'];
  final until = dismissedPref['until'];
  if (dismissedPref['plan_id'] != planId || from is! String || until is! String) {
    return null;
  }
  return (fromIso: from, untilIso: until);
}

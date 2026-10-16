/// Which of a runner's active training plans is "current", and which is
/// queued next.
///
/// A runner may hold several `status = 'active'` plans as long as their
/// inclusive `[start_date, end_date]` windows do not overlap (the
/// `training_plans_active_no_overlap` exclusion constraint), so a marathon
/// block ending Nov 15 can have an ultra block starting Nov 16 queued behind
/// it. Dates are ISO `yyyy-mm-dd` strings, which order lexically the same as
/// they do chronologically, so no time zone enters the comparison.
///
/// Dart twin of `apps/web/src/lib/training/plan_current.ts` — keep the
/// selection rules, tie-breaks, inclusive boundaries, and test counts in
/// lockstep.
library;

class CurrentPlanPick<T> {
  /// The plan whose window covers today; else the one that ended most
  /// recently; else null.
  final T? current;

  /// The plan with the earliest start after today. Never [current], which
  /// always starts on or before today.
  final T? upcoming;

  const CurrentPlanPick({required this.current, required this.upcoming});
}

CurrentPlanPick<T> pickCurrentPlan<T>(
  List<T> activePlans,
  String todayIso, {
  required String Function(T plan) start,
  required String Function(T plan) end,
}) {
  T? covering;
  T? latestEnded;
  for (final p in activePlans) {
    final s = start(p);
    final e = end(p);
    if (s.compareTo(todayIso) <= 0 && e.compareTo(todayIso) >= 0) {
      if (covering == null || s.compareTo(start(covering)) > 0) {
        covering = p;
      }
    } else if (e.compareTo(todayIso) < 0) {
      if (latestEnded == null || e.compareTo(end(latestEnded)) > 0) {
        latestEnded = p;
      }
    }
  }
  final current = covering ?? latestEnded;

  T? upcoming;
  for (final p in activePlans) {
    final s = start(p);
    if (s.compareTo(todayIso) <= 0) continue;
    if (upcoming == null || s.compareTo(start(upcoming)) < 0) {
      upcoming = p;
    }
  }
  return CurrentPlanPick(current: current, upcoming: upcoming);
}

/// The plans whose inclusive window shares at least one day with
/// `[startIso, endIso]`. Two windows that share only a boundary day overlap;
/// a window starting the day after another ends does not.
List<T> overlappingPlans<T>(
  List<T> plans,
  String startIso,
  String endIso, {
  required String Function(T plan) start,
  required String Function(T plan) end,
}) =>
    [
      for (final p in plans)
        if (start(p).compareTo(endIso) <= 0 && end(p).compareTo(startIso) >= 0)
          p,
    ];

/// Which of an athlete's plans a coach's assignment must clear (decisions
/// § 2008): `assign_plan_to_athlete` refuses a window that shares a day with
/// any of the athlete's active plans, and accepts any other. The coaching
/// screen reads every active plan the athlete holds and names the ones still
/// ahead, so the coach can pick dates before the server refuses.
///
/// Dates are ISO `yyyy-mm-dd` strings. Dart twin of
/// `apps/web/src/lib/training/plan_assign.ts` — keep `assignBlockers`,
/// `firstStartAfter`, `assignCollision` and the test counts in lockstep.
library;

import 'plan_current.dart';
import 'plan_overlap.dart';

/// The athlete's active plans that still hold dates from [todayIso] on, in
/// start order. A plan that has already ended blocks nothing.
List<T> assignBlockers<T>(
  List<T> activePlans,
  String todayIso, {
  required String Function(T plan) start,
  required String Function(T plan) end,
}) =>
    [
      for (final p in activePlans)
        if (end(p).compareTo(todayIso) >= 0) p,
    ]..sort((a, b) => start(a).compareTo(start(b)));

/// The first start date after every blocker, or today when none is ahead.
String firstStartAfter<T>(
  List<T> blockers,
  String todayIso, {
  required String Function(T plan) end,
}) {
  String? lastEnd;
  for (final p in blockers) {
    if (lastEnd == null || end(p).compareTo(lastEnd) > 0) lastEnd = end(p);
  }
  if (lastEnd == null || lastEnd.compareTo(todayIso) < 0) return todayIso;
  final d = DateTime.utc(int.parse(lastEnd.substring(0, 4)),
      int.parse(lastEnd.substring(5, 7)), int.parse(lastEnd.substring(8, 10)) + 1);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${d.year.toString().padLeft(4, '0')}-${two(d.month)}-${two(d.day)}';
}

/// The blocker an assignment of [source] from [startIso] runs into — the one
/// that ends last, so "start after it ends" clears them all — or null.
T? assignCollision<T, S>(
  List<T> blockers,
  S source,
  String startIso, {
  required String Function(T plan) start,
  required String Function(T plan) end,
  required String Function(S plan) sourceStart,
  required String Function(S plan) sourceEnd,
}) {
  final endIso = clonedPlanEndIso(source, startIso,
      start: sourceStart, end: sourceEnd);
  T? hit;
  for (final p in overlappingPlans(blockers, startIso, endIso,
      start: start, end: end)) {
    if (hit == null || end(p).compareTo(end(hit)) > 0) hit = p;
  }
  return hit;
}

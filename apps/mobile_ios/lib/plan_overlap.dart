/// What a new plan may do to the active plans its window overlaps.
///
/// Dates are ISO `yyyy-mm-dd` strings, which order lexically the same as
/// they do chronologically, so no time zone enters the comparison.
///
/// Dart twin of `apps/web/src/lib/training/plan_overlap.ts` — keep
/// `canTrimOverlap` and `clonedPlanEndIso`, their boundaries, and the test
/// counts in lockstep.
library;

/// Whether "End it early" (the `trim` overlap choice) can resolve
/// [overlapping] for a plan starting [newStartIso]: only when every
/// overlapped plan starts before the new one, since a plan starting on or
/// after it would be left with no days (the RPC refuses that trim too).
bool canTrimOverlap<T>(
  List<T> overlapping,
  String newStartIso, {
  required String Function(T plan) start,
}) =>
    overlapping.isNotEmpty &&
    overlapping.every((p) => start(p).compareTo(newStartIso) < 0);

/// The end date a clone of [template] takes when it starts on [startIso]:
/// the clone RPCs shift every date by the same whole-day offset.
String clonedPlanEndIso<T>(
  T template,
  String startIso, {
  required String Function(T plan) start,
  required String Function(T plan) end,
}) {
  final span = _epochDay(end(template)) - _epochDay(start(template));
  final d = DateTime.fromMillisecondsSinceEpoch(
      (_epochDay(startIso) + span) * 86400000,
      isUtc: true);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${d.year.toString().padLeft(4, '0')}-${two(d.month)}-${two(d.day)}';
}

int _epochDay(String iso) =>
    DateTime.utc(int.parse(iso.substring(0, 4)), int.parse(iso.substring(5, 7)),
                int.parse(iso.substring(8, 10)))
            .millisecondsSinceEpoch ~/
        86400000;

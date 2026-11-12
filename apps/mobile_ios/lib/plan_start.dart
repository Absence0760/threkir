/// Start-date alignment for the plan wizard. `generatePlan` hard-anchors day
/// 0 of the start week to the Sunday long run — every day role in
/// `_generateWeek` is an OFFSET from the start date, not a real weekday — so a
/// plan that starts on a Wednesday puts the long run midweek and the rest day
/// on Thursday, whatever the generator's own comments say.
///
/// The beginner walk-run plan is the one exemption. Its sessions sit at offsets
/// 0/2/4 with rest between and no long run, so no day role is tied to a
/// weekday and nothing shifts when it starts midweek. A walk-run plan may
/// start today, and defaults to tomorrow.
///
/// Dart twin of `apps/web/src/lib/training/plan_start.ts` — keep the algorithm,
/// edge cases, outputs, and test counts in lockstep. The web twin works in ISO
/// `yyyy-mm-dd` because its input is an `<input type="date">` value; the phone
/// picker hands over a `DateTime`, so this side takes one. That input type is
/// the only difference.
library;

/// Snap a date forward to the upcoming Sunday — a no-op when it already is
/// one. Stepped through the year/month/day constructor rather than by adding
/// a fixed 24-hour `Duration`, so a span crossing a DST transition still
/// lands on local midnight.
DateTime nextSunday(DateTime d) {
  final off = (DateTime.sunday - d.weekday) % 7;
  return DateTime(d.year, d.month, d.day + off);
}

/// True when a date falls on a Sunday (local time).
bool isSunday(DateTime d) => d.weekday == DateTime.sunday;

/// Whether a plan of this shape may start on [d]. Every date is allowed for a
/// walk-run plan; any other plan needs a Sunday.
bool planStartAllowed(DateTime d, {required bool walkRun}) =>
    walkRun || isSunday(d);

/// The date a picked start lands on: unchanged for a walk-run plan, snapped
/// forward to the upcoming Sunday for any other.
DateTime alignPlanStart(DateTime d, {required bool walkRun}) =>
    walkRun ? DateTime(d.year, d.month, d.day) : nextSunday(d);

/// The wizard's default start. A walk-run plan starts tomorrow, which leaves
/// today to get ready without making the runner wait. Any other plan starts on
/// the Sunday at least a week out, so the first long run has a week's notice.
DateTime defaultPlanStart(DateTime today, {required bool walkRun}) => walkRun
    ? DateTime(today.year, today.month, today.day + 1)
    : nextSunday(DateTime(today.year, today.month, today.day + 7));

/// Which meal slot a log at this hour belongs to, derived rather than guessed.
///
/// This lived in `widgets/nutrition_log_sheet.dart` as a hard-coded
/// `'breakfast'`, so the composer filed a 7 p.m. dinner under breakfast unless
/// the user noticed the dropdown. Pure and mobile-only: web's
/// `/nutrition/log` has no such derivation today, so there is no twin to keep
/// in lockstep — closing that is web's to do first ([decisions § 24]).
library;


/// The meal slot a log stamped at [at] most likely belongs to.
///
/// The boundaries are the ones the day's own eating pattern gives: the small
/// hours are a snack rather than an early breakfast (nobody sits down to
/// breakfast at 02:00, and a misfiled one distorts the morning's totals), and
/// the late evening is a snack rather than a second dinner. A wrong guess
/// costs one tap on the slot dropdown; no guess at all cost that tap every
/// time.
String mealSlotForTime(DateTime at) {
  final hour = at.toLocal().hour;
  if (hour < 5) return 'snack';
  if (hour < 11) return 'breakfast';
  if (hour < 15) return 'lunch';
  if (hour < 21) return 'dinner';
  return 'snack';
}

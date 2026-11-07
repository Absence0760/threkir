/// How long one run can last, and the entry rules for a typed duration.
/// Shared with `apps/web/src/lib/runs/run_duration.ts`: keep the two in
/// lockstep — constants, algorithm, edge cases, and test counts.
///
/// Nothing bounded a manual duration at any layer, so a runner who typed
/// "12333" into the Hours box saved a 2 km run lasting 12,333 hours and every
/// weekly total, recap and challenge that summed it read the same absurd
/// number (issue #1300 § 5, decisions § 2359). It lives in core_models rather
/// than the app because `api_client`'s batch push reads the bound too.
library;

/// Ten days. The longest single efforts this product records are multi-day
/// ultras — the Moab 240's cutoff is 112 h, the longest plausible push about
/// five days — so ten days refuses no real activity and refuses every typo
/// that lands an hours figure in the thousands. `runs_duration_s_max_check`
/// on the server holds the same literal.
const int kMaxRunDurationS = 864000;

/// 1 km/h. A typed duration this slow for its distance is almost certainly a
/// figure in the wrong box, so the form asks before saving rather than
/// refusing: the slowest legitimate whole-activity pace is a steep alpine hike
/// (Naismith: about 600 m of climbing an hour), still above 1.4 km/h over the
/// ground, and a 240-mile ultra finishing at its 112 h cutoff averages 3.4 km/h.
const int kSlowPaceConfirmSecPerKm = 3600;

/// Input widths. Three hour digits hold 240 h, the whole bound; two are the
/// most 0–59 ever needs.
const int kHoursMaxDigits = 3;
const int kMinutesSecondsMaxDigits = 2;

enum ManualDurationError {
  invalid,
  minutesOutOfRange,
  secondsOutOfRange,
  zero,
  tooLong,
}

/// Either [seconds] (valid) or [error], never both.
class ManualDurationResult {
  final int? seconds;
  final ManualDurationError? error;

  const ManualDurationResult.ok(int this.seconds) : error = null;
  const ManualDurationResult.failed(ManualDurationError this.error)
      : seconds = null;

  bool get ok => seconds != null;

  @override
  bool operator ==(Object other) =>
      other is ManualDurationResult &&
      other.seconds == seconds &&
      other.error == error;

  @override
  int get hashCode => Object.hash(seconds, error);

  @override
  String toString() => ok
      ? 'ManualDurationResult.ok($seconds)'
      : 'ManualDurationResult.failed($error)';
}

final RegExp _digits = RegExp(r'^\d*$');

int? _part(String raw) {
  final t = raw.trim();
  if (!_digits.hasMatch(t)) return null;
  return t.isEmpty ? 0 : int.parse(t);
}

/// Grade the three boxes of a typed duration. An empty box reads as 0; any
/// character other than a digit is `invalid`, so a sign or a decimal point can
/// never be read as something else. Minutes and seconds are clock fields, 0–59.
ManualDurationResult validateManualDuration(
  String hours,
  String minutes,
  String seconds,
) {
  final h = _part(hours);
  final m = _part(minutes);
  final s = _part(seconds);
  if (h == null || m == null || s == null) {
    return const ManualDurationResult.failed(ManualDurationError.invalid);
  }
  if (m > 59) {
    return const ManualDurationResult.failed(
        ManualDurationError.minutesOutOfRange);
  }
  if (s > 59) {
    return const ManualDurationResult.failed(
        ManualDurationError.secondsOutOfRange);
  }
  final total = h * 3600 + m * 60 + s;
  if (total <= 0) {
    return const ManualDurationResult.failed(ManualDurationError.zero);
  }
  if (total > kMaxRunDurationS) {
    return const ManualDurationResult.failed(ManualDurationError.tooLong);
  }
  return ManualDurationResult.ok(total);
}

/// The read-side bound: a stored duration a total may sum. A row outside it
/// predates the CHECK (or reached the table before it was validated) and
/// contributes nothing to a duration aggregate rather than swamping it.
bool isPlausibleRunDuration(num durationS) =>
    durationS.isFinite && durationS >= 0 && durationS <= kMaxRunDurationS;

/// Whether a typed duration is slower than [kSlowPaceConfirmSecPerKm] over
/// its distance. False with no distance — there is no pace to judge.
bool isImplausiblySlow(num durationS, num distanceM) {
  if (!(distanceM > 0) || !(durationS > 0)) return false;
  return durationS / (distanceM / 1000) > kSlowPaceConfirmSecPerKm;
}

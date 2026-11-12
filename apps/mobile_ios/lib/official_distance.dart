/// A route's official (certified) distance against its traced length, issue
/// #1291. A course traced on street centre lines measures long, so when the
/// owner records the race's own distance every surface shows that figure and
/// distance along the line is scaled by official / measured, putting km 42
/// where the race's sign stands.
///
/// Dart twin of `apps/web/src/lib/routes/official_distance.ts` — keep both in
/// lockstep. Pure functions, no Flutter / Supabase deps.
library;

/// The tighter bound the edit form and the race-link prefill apply; the
/// column's CHECK holds only the hard range below, because `distance_m` moves
/// whenever the owner redraws the route (migration 20271108000010).
const double officialDistanceMaxDeviation = 0.1;

/// The column CHECK's ceiling, 1,000 km.
const double officialDistanceMaxM = 1000000;

bool _positive(double? v) => v != null && v.isFinite && v > 0;

/// The distance a route is shown as: the official one when set, the measured
/// one otherwise.
double routeDisplayDistanceM(double measuredM, double? officialM) =>
    _positive(officialM) ? officialM! : measuredM;

/// Official metres per metre of drawn line. Multiply a distance measured along
/// the line by this to get the distance the race would call it; divide an
/// official distance by it to find where on the line it falls. 1 when either
/// figure is missing, so a route with no official distance is unchanged.
double courseDistanceScale(double lineLengthM, double? officialM) =>
    _positive(lineLengthM) && _positive(officialM)
        ? officialM! / lineLengthM
        : 1;

enum OfficialDistanceVerdict { ok, outOfRange, tooFar }

/// Whether [officialM] may be saved on a route measuring [measuredM]: positive,
/// within the column's ceiling, and within 10% of the measured distance.
OfficialDistanceVerdict officialDistanceVerdict(
  double measuredM,
  double officialM,
) {
  if (!_positive(officialM) || officialM > officialDistanceMaxM) {
    return OfficialDistanceVerdict.outOfRange;
  }
  if (!_positive(measuredM)) return OfficialDistanceVerdict.ok;
  return (officialM - measuredM).abs() <=
          measuredM * officialDistanceMaxDeviation
      ? OfficialDistanceVerdict.ok
      : OfficialDistanceVerdict.tooFar;
}

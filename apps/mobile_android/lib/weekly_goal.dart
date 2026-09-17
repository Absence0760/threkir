import 'package:core_models/core_models.dart' show DistanceUnit, kMetresPerMile;

/// The weekly distance goal, typed in the runner's own unit. Shared with the
/// web twin (apps/web/src/lib/settings/weekly_goal.ts); keep the two in
/// lockstep: algorithm, edge cases, outputs, and test counts must match.
///
/// `weekly_mileage_goal_m` is stored in metres, which is not what a person
/// types: nobody thinks of their week as `50000`. The field asks in km or mi
/// and converts at the boundary, the entry/exit split `challenge_goal` keeps
/// for a typed challenge distance.

const String kWeeklyGoalKey = 'weekly_mileage_goal_m';

/// The range a typed goal must fall in, in the unit it is typed in.
const double kWeeklyGoalMin = 0.1;
const double kWeeklyGoalMax = 500;

double _metresPerUnit(DistanceUnit unit) =>
    unit == DistanceUnit.mi ? kMetresPerMile : 1000;

/// A stored goal as the field shows it: in [unit], to one decimal place.
/// Null for an absent, non-numeric or non-positive stored value.
double? weeklyGoalToInput(Object? metres, DistanceUnit unit) {
  if (metres is! num || !metres.isFinite || metres <= 0) return null;
  return (metres / _metresPerUnit(unit) * 10).round() / 10;
}

/// Whether a typed goal is one the field accepts. Null (an empty field) is not
/// a goal; it clears one, and the caller handles it before asking.
bool isUsableWeeklyGoalInput(double? typed) =>
    typed != null &&
    typed.isFinite &&
    typed >= kWeeklyGoalMin &&
    typed <= kWeeklyGoalMax;

/// The metres to store for a typed goal, or null to clear it. A non-positive
/// goal clears too, though the field refuses one before it gets here.
///
/// When the typed value is exactly what the field shows for the stored goal,
/// the stored metres come back unchanged: the display rounds to one decimal,
/// so converting it back would move a goal nobody edited (50000 m shows as
/// 31.1 mi, and 31.1 mi is 50051 m).
num? weeklyGoalFromInput(
  double? typed,
  DistanceUnit unit,
  Object? storedMetres,
) {
  if (typed == null || !typed.isFinite || typed <= 0) return null;
  final shown = weeklyGoalToInput(storedMetres, unit);
  if (shown != null && shown == typed) return storedMetres as num;
  return (typed * _metresPerUnit(unit)).round();
}

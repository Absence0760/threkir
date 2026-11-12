import 'package:core_models/core_models.dart' show UserProfileRow;

import 'health_consent.dart';
import 'nutrition_targets.dart' show ageFromDob;
import 'training.dart' show TrainingGender;

/// The runner facts the plan generator calibrates on: gender (the § 76 pace
/// calibration), age (the § 93 masters recovery calibration) and the
/// `extra_recovery` setting that asks for that recovery calibration at any
/// age. Every surface that builds a plan for the signed-in runner — the
/// wizard and its starters, the plans list's starters, the season planner —
/// reads them through `TrainingService.fetchPlanCalibration`, so none of them
/// can quietly skip one. Web twin: `apps/web/src/lib/training/plan_calibration.ts`.
class PlanCalibration {
  const PlanCalibration({
    required this.gender,
    required this.age,
    required this.dobState,
    required this.extraRecovery,
  });

  /// Nothing read yet: the standard schedule, and no date-of-birth hint.
  static const unknown = PlanCalibration(
    gender: null,
    age: null,
    dobState: null,
    extraRecovery: false,
  );

  final TrainingGender gender;
  final int? age;

  /// Null when the profile could not be read, so a caller hides the "add
  /// your date of birth" hint rather than tell a runner who has one that it
  /// is missing.
  final HealthUseDobState? dobState;
  final bool extraRecovery;
}

/// Grade the two reads. [profileRead] is false when the `get_my_profile()`
/// read failed (distinct from a null row); [extraRecoverySetting] is the
/// effective `extra_recovery` bag value, null when unset or when the bag
/// has not loaded. Only a literal `true` turns it on.
PlanCalibration planCalibrationFrom({
  required UserProfileRow? profile,
  required bool profileRead,
  required Object? extraRecoverySetting,
  required int nowMs,
}) {
  final g = profileRead ? profile?.gender : null;
  return PlanCalibration(
    gender: g == 'male' || g == 'female' || g == 'prefer_not_to_say' ? g : null,
    age: profileRead ? ageFromDob(healthUseDob(profile), nowMs) : null,
    dobState: profileRead ? healthUseDobState(profile) : null,
    extraRecovery: extraRecoverySetting == true,
  );
}

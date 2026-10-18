import 'package:core_models/core_models.dart' show DistanceUnit;

import 'plan_nudges.dart' show overrunDigits;
import 'preferences.dart' show activeDistanceUnit;
import 'training.dart' show fmtKm;

/// How far a workout ran past its target, for "Done · +3 km": whole units
/// unless a tenth says something. Web twin: `fmtOverrun` in units.svelte.ts.
String fmtOverrun(double metres) {
  final inUnits = activeDistanceUnit == DistanceUnit.mi
      ? metres / 1609.344
      : metres / 1000;
  return fmtKm(metres, overrunDigits(inUnits));
}

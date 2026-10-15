import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'env_flag.dart';

/// The dart-define / dotenv key the gate reads. Web spells the same flag
/// `PUBLIC_WEIGHT_FLUID_ENABLED` (`apps/web/src/lib/nutrition/weight_fluid_flag.ts`);
/// mobile drops the web-only `PUBLIC_` prefix.
const String kWeightFluidEnvKey = 'WEIGHT_FLUID_ENABLED';

/// Pure parse of the weight-based fluid deploy flag, delegating to the one
/// canonical [isTruthyFlagValue] (decisions § 709).
bool weightFluidEnabled(String? raw) => isTruthyFlagValue(raw);

/// The weight-based fluid gate as `RoadbookScreen` reads it — the mobile twin
/// of web's `nutrition/weight_fluid_flag.ts` (decisions § 1976).
///
/// Fluid planning is a new Art 9 use of body weight, so CISO + counsel review
/// it against the health-data consent copy before it reaches real users
/// (decisions § 150). Off, the screen reads no body weight at all, never shows
/// the toggle, and keeps the flat rate. The read is guarded because
/// `dotenv.env` throws until something has loaded it; an unreadable dotenv
/// reads off.
bool get weightFluidGate {
  try {
    return weightFluidEnabled(dotenv.env[kWeightFluidEnvKey]);
  } catch (_) {
    return false;
  }
}

import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'env_flag.dart';

/// The dart-define / dotenv key the gate reads. Web spells the same flag
/// `PUBLIC_CYCLE_PLANS_ENABLED` (`apps/web/src/lib/training/cycle_plan_flag.ts`);
/// mobile drops the web-only `PUBLIC_` prefix.
const String kCyclePlansEnvKey = 'CYCLE_PLANS_ENABLED';

/// Pure parse of the cycle-plans deploy flag, delegating to the one canonical
/// [isTruthyFlagValue] (decisions § 709).
bool cyclePlansEnabled(String? raw) => isTruthyFlagValue(raw);

/// The cycle / pregnancy-aware plan adjustment gate — the mobile twin of
/// web's `training/cycle_plan_flag.ts` (decisions § 231).
///
/// The adjustment reads GDPR Art 9 reproductive-health settings, so it stays
/// off until owner + CISO + counsel sign it off (decisions § 150). Off, plan
/// detail offers no cycle or pregnancy adjustment and reads none of those
/// settings. The read is guarded because `dotenv.env` throws until something
/// has loaded it; an unreadable dotenv reads off.
bool get cyclePlansGate {
  try {
    return cyclePlansEnabled(dotenv.env[kCyclePlansEnvKey]);
  } catch (_) {
    return false;
  }
}

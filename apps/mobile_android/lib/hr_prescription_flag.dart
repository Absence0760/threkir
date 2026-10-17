import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'env_flag.dart';

/// The dart-define / dotenv key the gate reads. Web spells the same flag
/// `PUBLIC_HR_PRESCRIPTION_ENABLED`
/// (`apps/web/src/lib/training/hr_prescription_flag.ts`); mobile drops the
/// web-only `PUBLIC_` prefix.
const String kHrPrescriptionEnvKey = 'HR_PRESCRIPTION_ENABLED';

/// Pure parse of the heart-rate prescription deploy flag, delegating to the
/// one canonical [isTruthyFlagValue] (decisions § 709).
bool hrPrescriptionEnabled(String? raw) => isTruthyFlagValue(raw);

/// The heart-rate prescription gate — the mobile twin of web's
/// `training/hr_prescription_flag.ts` (decisions § 2087).
///
/// Three Art 9 surfaces sit behind it: the bpm target on a planned workout,
/// the "heart rate is medication-affected" setting with its low-confidence
/// label on the training-load chart, and the easy-run HR-drift flag on the
/// coach roster. CISO + counsel review them against the health-data consent
/// copy before they reach real users (decisions § 150). Off, none of the three
/// renders and nothing writes a bpm target or the setting. The read is guarded
/// because `dotenv.env` throws until something has loaded it; an unreadable
/// dotenv reads off.
bool get hrPrescriptionGate {
  try {
    return hrPrescriptionEnabled(dotenv.env[kHrPrescriptionEnvKey]);
  } catch (_) {
    return false;
  }
}

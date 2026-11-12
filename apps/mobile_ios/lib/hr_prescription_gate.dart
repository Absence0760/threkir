import 'package:flutter/foundation.dart';

/// The heart-rate prescription gate, read from the server — the mobile twin
/// of web's `training/hr_prescription_gate.ts` (decisions § 2092, § 2108).
///
/// Three Art 9 surfaces sit behind it: the bpm target on a planned workout,
/// the "heart rate is medication-affected" setting with its low-confidence
/// label on the training-load chart, and the easy-run HR-drift flag on the
/// coach roster. CISO + counsel review them against the health-data consent
/// copy before they reach real users (decisions § 150).
///
/// The gate is the `hr_prescription` row in `private.feature_flags`, which the
/// database enforces on every write and on the roster read. The app asks the
/// same row (`ApiClient.hrPrescriptionEnabled`) rather than reading a build
/// flag of its own, so the surfaces can never be on while the server refuses
/// what they write. Off until the first read succeeds, and off again on any
/// failed read.
final ValueNotifier<bool> hrPrescriptionGateValue = ValueNotifier<bool>(false);

/// The gate as last read from the server; false before the first read.
bool get hrPrescriptionGate => hrPrescriptionGateValue.value;

/// Re-reads the gate. [read] is `ApiClient.hrPrescriptionEnabled`, which
/// already reads a failure as off; a throw is read the same way.
Future<void> refreshHrPrescriptionGate(Future<bool> Function() read) async {
  try {
    hrPrescriptionGateValue.value = await read();
  } catch (e) {
    debugPrint('hr prescription gate read failed: $e');
    hrPrescriptionGateValue.value = false;
  }
}

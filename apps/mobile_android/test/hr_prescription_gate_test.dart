// The heart-rate prescription gate is the server's row, not a build flag
// (decisions § 2108): off until a read says otherwise, and off again on any
// failed read. Web pins its half from source in hr_prescription_gate.test.ts.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../lib/hr_prescription_gate.dart';

void main() {
  setUp(() => hrPrescriptionGateValue.value = false);

  test('the gate is off until the server says otherwise', () {
    expect(hrPrescriptionGate, isFalse);
  });

  test('a read that returns true opens it, and one that returns false shuts it', () async {
    await refreshHrPrescriptionGate(() async => true);
    expect(hrPrescriptionGate, isTrue);
    await refreshHrPrescriptionGate(() async => false);
    expect(hrPrescriptionGate, isFalse);
  });

  test('a failed read shuts an open gate', () async {
    await refreshHrPrescriptionGate(() async => true);
    await refreshHrPrescriptionGate(() async => throw StateError('offline'));
    expect(hrPrescriptionGate, isFalse);
  });

  test('no build flag can open it: nothing in lib reads an HR_PRESCRIPTION env key', () {
    final readers = [
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>())
        if (f.path.endsWith('.dart') && f.readAsStringSync().contains('HR_PRESCRIPTION')) f.path,
    ];
    expect(readers, isEmpty);
  });
}

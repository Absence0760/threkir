// The heart-rate prescription gate, driven end to end. Dart mirror of web's
// `training/hr_prescription_flag.test.ts`, which had no counterpart here.
//
// Three Art 9 surfaces sit behind it (the bpm target, the medication-affected
// setting, the roster HR-drift flag), so the property that matters is that
// every state short of an explicit affirmative reads off (decisions § 150).

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/hr_prescription_flag.dart';

void main() {
  setUpAll(() => TestWidgetsFlutterBinding.ensureInitialized());
  tearDownAll(() => dotenv.clean());

  test('the key matches web without its PUBLIC_ prefix', () {
    expect(kHrPrescriptionEnvKey, 'HR_PRESCRIPTION_ENABLED');
  });

  group('hrPrescriptionEnabled', () {
    test('accepts the shared affirmative set', () {
      for (final v in const ['1', 'true', 'yes', 'on', 'YES', ' on ']) {
        expect(hrPrescriptionEnabled(v), isTrue, reason: '"$v" should enable');
      }
    });

    test('fails closed on unset, empty, negatives and junk', () {
      for (final v in const [null, '', '0', 'false', 'off', 'enabled', 'y']) {
        expect(hrPrescriptionEnabled(v), isFalse,
            reason: '"${v ?? '<null>'}" must stay off');
      }
    });
  });

  group('hrPrescriptionGate', () {
    test('an uninitialised dotenv reads off rather than throwing', () {
      dotenv.clean();
      expect(dotenv.isInitialized, isFalse,
          reason: 'the precondition this test exists for must hold');
      expect(hrPrescriptionGate, isFalse);
    });

    test('unset is off, an affirmative is on, junk is off', () {
      dotenv.clean();
      dotenv.loadFromString(isOptional: true);
      expect(hrPrescriptionGate, isFalse,
          reason: 'an unset sign-off gate must fail closed');

      dotenv.env[kHrPrescriptionEnvKey] = 'yes';
      expect(hrPrescriptionGate, isTrue);

      for (final junk in const ['enabled', '0', 'false', '']) {
        dotenv.env[kHrPrescriptionEnvKey] = junk;
        expect(hrPrescriptionGate, isFalse,
            reason: '"$junk" must never open an Art 9 surface');
      }
    });
  });
}

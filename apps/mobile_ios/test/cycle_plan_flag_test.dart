// The cycle / pregnancy plan-adjustment gate, driven end to end. Dart mirror
// of web's `training/cycle_plan_flag.ts`. The adjustment reads GDPR Art 9
// reproductive-health settings, so every state short of an explicit
// affirmative must read off (decisions § 150, § 231).

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/cycle_plan_flag.dart';

void main() {
  setUpAll(() => TestWidgetsFlutterBinding.ensureInitialized());
  tearDownAll(() => dotenv.clean());

  test('the key matches web without its PUBLIC_ prefix', () {
    expect(kCyclePlansEnvKey, 'CYCLE_PLANS_ENABLED');
  });

  group('cyclePlansEnabled', () {
    test('accepts the shared affirmative set', () {
      for (final v in const ['1', 'true', 'yes', 'on', 'YES', ' on ']) {
        expect(cyclePlansEnabled(v), isTrue, reason: '"$v" should enable');
      }
    });

    test('fails closed on unset, empty, negatives and junk', () {
      for (final v in const [null, '', '0', 'false', 'off', 'enabled', 'y']) {
        expect(cyclePlansEnabled(v), isFalse,
            reason: '"${v ?? '<null>'}" must stay off');
      }
    });
  });

  group('cyclePlansGate', () {
    test('an uninitialised dotenv reads off rather than throwing', () {
      dotenv.clean();
      expect(dotenv.isInitialized, isFalse,
          reason: 'the precondition this test exists for must hold');
      expect(cyclePlansGate, isFalse);
    });

    test('unset is off, an affirmative is on, junk is off', () {
      dotenv.clean();
      dotenv.loadFromString(isOptional: true);
      expect(cyclePlansGate, isFalse,
          reason: 'an unset sign-off gate must fail closed');

      dotenv.env[kCyclePlansEnvKey] = 'yes';
      expect(cyclePlansGate, isTrue);

      for (final junk in const ['enabled', '0', 'false', '']) {
        dotenv.env[kCyclePlansEnvKey] = junk;
        expect(cyclePlansGate, isFalse,
            reason: '"$junk" must never open an Art 9 surface');
      }
    });
  });
}

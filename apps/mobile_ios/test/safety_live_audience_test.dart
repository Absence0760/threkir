import 'package:flutter_test/flutter_test.dart';
import '../lib/safety_live_audience.dart';

void main() {
  group('autoLiveShareAudience', () {
    test('gate open: the automatic share is never public', () {
      expect(autoLiveShareAudience(safetyAudienceEnabled: true),
          LiveShareAudience.safetyContacts);
    });
    test('gate closed: the explicit opt-in keeps its public share', () {
      expect(autoLiveShareAudience(safetyAudienceEnabled: false),
          LiveShareAudience.public);
    });
  });

  group('safetyNetArmed', () {
    test('an overdue window at or above the scan floor arms it', () {
      expect(safetyNetArmed(overdueMinutes: 30), isTrue);
      expect(safetyNetArmed(overdueMinutes: 10), isTrue);
    });
    test('below the floor, absent or malformed does not', () {
      expect(safetyNetArmed(overdueMinutes: 5), isFalse);
      expect(safetyNetArmed(), isFalse);
      expect(safetyNetArmed(overdueMinutes: '30'), isFalse);
      expect(safetyNetArmed(overdueMinutes: double.nan), isFalse);
    });
    test('the off-route alert arms it on its own', () {
      expect(safetyNetArmed(offRouteAlerts: true), isTrue);
      expect(safetyNetArmed(offRouteAlerts: 'true'), isFalse);
    });
  });

  group('effectiveAutoLiveShare', () {
    test('an explicit choice wins in both directions', () {
      expect(
          effectiveAutoLiveShare(
              explicitPref: false,
              safetyAudienceEnabled: true,
              safetyNetArmed: true),
          isFalse);
      expect(
          effectiveAutoLiveShare(
              explicitPref: true,
              safetyAudienceEnabled: false,
              safetyNetArmed: false),
          isTrue);
    });
    test('unset defaults on only for the safety audience with an armed net', () {
      expect(
          effectiveAutoLiveShare(
              explicitPref: null,
              safetyAudienceEnabled: true,
              safetyNetArmed: true),
          isTrue);
    });
    test('unset never defaults on into a public share', () {
      expect(
          effectiveAutoLiveShare(
              explicitPref: null,
              safetyAudienceEnabled: false,
              safetyNetArmed: true),
          isFalse);
    });
    test('unset stays off when nothing would watch the stub', () {
      expect(
          effectiveAutoLiveShare(
              explicitPref: null,
              safetyAudienceEnabled: true,
              safetyNetArmed: false),
          isFalse);
    });
  });
}

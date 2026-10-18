import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/health_consent.dart';
import '../lib/plan_calibration.dart';

final _now = DateTime.utc(2026, 10, 18, 12).millisecondsSinceEpoch;

UserProfileRow _row({String? gender, DateTime? dob, DateTime? consentAt}) =>
    UserProfileRow(
      profilePrivate: false,
      id: 'u1',
      shadowHidden: false,
      gender: gender,
      dateOfBirth: dob,
      healthDataConsentAt: consentAt,
    );

void main() {
  test(
      'planCalibrationFrom: a consented date of birth gives the age and a '
      'usable state', () {
    final c = planCalibrationFrom(
      profile: _row(
        gender: 'female',
        dob: DateTime.utc(1970, 3, 2),
        consentAt: DateTime.utc(2026, 1, 1),
      ),
      profileRead: true,
      extraRecoverySetting: null,
      nowMs: _now,
    );
    expect(c.gender, 'female');
    expect(c.age, 56);
    expect(c.dobState, HealthUseDobState.usable);
    expect(c.extraRecovery, isFalse);
  });

  test(
      'planCalibrationFrom: no date of birth reads as absent, a withheld '
      'consent as consentWithheld', () {
    expect(
      planCalibrationFrom(
        profile: _row(),
        profileRead: true,
        extraRecoverySetting: null,
        nowMs: _now,
      ).dobState,
      HealthUseDobState.absent,
    );
    final withheld = planCalibrationFrom(
      profile: _row(dob: DateTime.utc(1970, 3, 2)),
      profileRead: true,
      extraRecoverySetting: null,
      nowMs: _now,
    );
    expect(withheld.dobState, HealthUseDobState.consentWithheld);
    expect(withheld.age, isNull);
  });

  test(
      'planCalibrationFrom: a failed profile read hides the date-of-birth '
      'state rather than call it absent', () {
    final c = planCalibrationFrom(
      profile: null,
      profileRead: false,
      extraRecoverySetting: true,
      nowMs: _now,
    );
    expect(c.gender, isNull);
    expect(c.age, isNull);
    expect(c.dobState, isNull);
    expect(c.extraRecovery, isTrue);
  });

  test('planCalibrationFrom: only a literal true turns extra recovery on', () {
    bool on(Object? v) => planCalibrationFrom(
          profile: null,
          profileRead: true,
          extraRecoverySetting: v,
          nowMs: _now,
        ).extraRecovery;
    expect(on('true'), isFalse);
    expect(on(false), isFalse);
    expect(on(null), isFalse);
    expect(on(true), isTrue);
  });
}

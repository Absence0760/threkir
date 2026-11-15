import 'package:flutter_test/flutter_test.dart';

import '../lib/backup.dart';

/// Decisions § 2542: the database refuses a settings-bag weight without
/// health-data consent, and that one key used to fail the whole restored bag.
/// Mirrors the consent cases in
/// `apps/web/src/lib/backup/restore_orchestrator.test.ts`.
void main() {
  const archived = <String, dynamic>{
    'preferred_unit': 'km',
    'body_weight_kg': 70,
    'hr_medication_affected': true,
    'cycle_length_days': 28,
  };

  test('into an account without consent the gated values are left out', () {
    expect(restorablePrefs(archived, consented: false),
        {'preferred_unit': 'km'});
  });

  test('with consent the whole bag restores', () {
    expect(restorablePrefs(archived, consented: true), archived);
  });

  test('a bag of only gated values restores as empty without consent', () {
    expect(restorablePrefs({'body_weight_kg': 70}, consented: false), isEmpty);
  });
}

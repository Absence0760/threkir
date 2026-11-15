import 'package:flutter_test/flutter_test.dart';

import '../lib/backup.dart';

/// Decisions § 2542: the database refuses a settings-bag weight without
/// health-data consent, and that one key used to fail the whole restored bag;
/// and consent is never restored from an archive. Mirrors the consent cases in
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

  test('an archived consent stamp and the server-owned columns are never '
      'written, so the profile row restores', () {
    final out = restorableProfile({
      'display_name': 'Ada',
      'date_of_birth': '1990-01-01',
      'health_data_consent_at': null,
      'coach_consent_at': '2026-01-01T00:00:00Z',
      'ai_disclosure_version': 1,
      'age_confirmed_at': null,
      'terms_accepted_at': null,
      'billing_issue_at': null,
      'tier_updated_event_ts': 1,
      'shadow_hidden': false,
      'subscription_tier': 'pro',
      'subscription_at': '2026-01-01T00:00:00Z',
      'parkrun_number': 'A1',
      'handle': 'ada',
    }, consented: true);
    expect(out, {'display_name': 'Ada', 'date_of_birth': '1990-01-01'});
  });

  test('height and gender restore only with health-data consent', () {
    const row = <String, dynamic>{
      'display_name': 'Ada',
      'height_cm': 170,
      'gender': 'female',
    };
    expect(restorableProfile(row, consented: false), {'display_name': 'Ada'});
    expect(restorableProfile(row, consented: true), row);
  });
}

import 'package:api_client/api_client.dart';
import 'package:test/test.dart';

/// The wizard's name step is prefilled with the sign-in provider's name
/// (decisions § 2363), so clearing it has to reach the row as null; leaving
/// the column out would keep a name the person removed.
void main() {
  final now = DateTime.utc(2026, 11, 7, 9);

  Map<String, dynamic> build(String? name) => ApiClient.onboardingProfileUpdate(
        displayName: name,
        preferredUnit: 'km',
        healthDataConsent: false,
        now: now,
      );

  test('a typed name is written trimmed', () {
    expect(build('  Ana Souza ')['display_name'], 'Ana Souza');
  });

  test('a cleared name is written as null', () {
    final update = build('   ');
    expect(update.containsKey('display_name'), isTrue);
    expect(update['display_name'], isNull);
  });

  test('a null name leaves the column alone', () {
    expect(build(null).containsKey('display_name'), isFalse);
  });

  test('the stamp and unit are always written', () {
    final update = build(null);
    expect(update['preferred_unit'], 'km');
    expect(update['onboarded_at'], now.toIso8601String());
  });
}

import 'package:flutter_test/flutter_test.dart';

import '../lib/disclosure.dart';
import '../lib/onboarding.dart';

/// Mirror of web `apps/web/src/lib/settings/disclosure.test.ts` — same cases,
/// same count.
void main() {
  group('disclosure level', () {
    test('disclosureLevelKey is the universal-prefs bag key the override '
        'lives in', () {
      expect(disclosureLevelKey, 'disclosure_level');
    });

    test('disclosureLevels is the three levels, ordered least to most', () {
      // The index is the rank, so the order is load-bearing, not cosmetic.
      expect(disclosureLevels, ['simple', 'standard', 'full']);
    });

    test('a fresh account lands on the floor its stated goal puts under it',
        () {
      // Zero runs, so the history floor is `simple` and the goal alone decides.
      expect(disclosureLevel('general_fitness', 0), 'simple');
      expect(disclosureLevel('weight_loss', 0), 'simple');
      expect(disclosureLevel('5k', 0), 'simple');
      expect(disclosureLevel('10k', 0), 'standard');
      expect(disclosureLevel('half_marathon', 0), 'standard');
      expect(disclosureLevel('marathon', 0), 'full');
      // And every goal the wizard can write resolves to a real level.
      for (final goal in primaryGoalValues) {
        expect(isDisclosureLevel(disclosureLevel(goal, 0)), isTrue,
            reason: goal);
      }
    });

    test('history alone raises the level at each threshold', () {
      expect(disclosureLevel('5k', disclosureStandardRuns - 1), 'simple');
      expect(disclosureLevel('5k', disclosureStandardRuns), 'standard');
      expect(disclosureLevel('5k', disclosureFullRuns - 1), 'standard');
      expect(disclosureLevel('5k', disclosureFullRuns), 'full');
      expect(disclosureLevel('5k', 4000), 'full');
    });

    test('the higher of the two floors wins, in both directions', () {
      // Goal above history.
      expect(disclosureLevel('marathon', 0), 'full');
      expect(disclosureLevel('10k', 0), 'standard');
      // History above goal.
      expect(disclosureLevel('general_fitness', disclosureFullRuns), 'full');
      // Neither above the other.
      expect(disclosureLevel('10k', disclosureStandardRuns), 'standard');
      // A big history never drags a high goal back DOWN.
      expect(disclosureLevel('marathon', 1), 'full');
    });

    test('an unset or unknown goal leaves the history floor to decide alone',
        () {
      for (final goal in [null, '', 'ultra', '10K', 'primaryGoalValues']) {
        expect(disclosureLevel(goal, 0), 'simple', reason: '$goal');
        expect(disclosureLevel(goal, disclosureStandardRuns), 'standard',
            reason: '$goal');
        expect(disclosureLevel(goal, disclosureFullRuns), 'full',
            reason: '$goal');
      }
    });

    test('a run count that is not a whole positive number reads as zero', () {
      // A count comes off an aggregate read that can degrade; it must not mint
      // a level out of a negative or a NaN.
      for (final runs in [-1, -4000, double.nan, double.negativeInfinity]) {
        expect(disclosureLevel('5k', runs), 'simple', reason: '$runs');
      }
      // A fraction floors rather than rounds up over a threshold.
      expect(disclosureLevel('5k', disclosureStandardRuns - 0.5), 'simple');
      expect(disclosureLevel('5k', double.infinity), 'simple');
    });

    test('isDisclosureLevel accepts exactly the three levels', () {
      for (final level in disclosureLevels) {
        expect(isDisclosureLevel(level), isTrue, reason: level);
      }
      for (final other in [
        null,
        '',
        'SIMPLE',
        'basic',
        0,
        2,
        true,
        <String, String>{},
        ['full'],
      ]) {
        expect(isDisclosureLevel(other), isFalse, reason: '$other');
      }
    });

    test('a stored level is what the surface renders at, whatever the '
        'derivation says', () {
      // The override is the whole reason hiding anything is safe.
      expect(resolveDisclosureLevel('simple', 'marathon', 4000), 'simple');
      expect(resolveDisclosureLevel('full', 'general_fitness', 0), 'full');
      expect(resolveDisclosureLevel('standard', null, 0), 'standard');
    });

    test('any value that is not a level falls through to the derivation', () {
      for (final stored in [
        null,
        '',
        'basics',
        'SIMPLE',
        1,
        false,
        <String, String>{},
      ]) {
        expect(resolveDisclosureLevel(stored, 'marathon', 0), 'full',
            reason: '$stored');
        expect(resolveDisclosureLevel(stored, 'general_fitness', 0), 'simple',
            reason: '$stored');
      }
    });
  });
}

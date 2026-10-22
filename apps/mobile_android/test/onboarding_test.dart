import 'package:api_client/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/onboarding.dart';
import '../lib/training.dart';

/// Pure-contract twin of web `apps/web/src/lib/settings/onboarding.test.ts`.
/// Keeps the mobile setup-wizard enum + step count in lockstep with web.
void main() {
  group('onboarding contract', () {
    test('primaryGoalKey is the universal-prefs bag key the wizard writes', () {
      expect(primaryGoalKey, 'primary_goal');
      // And it's the SAME constant the SettingsKeys registry exposes, so a
      // rename can't silently split the writer from the reader.
      expect(primaryGoalKey, SettingsKeys.primaryGoal);
    });

    test('primaryGoalValues covers the fixed six-value enum, in order', () {
      expect(primaryGoalValues, [
        'general_fitness',
        'weight_loss',
        '5k',
        '10k',
        'half_marathon',
        'marathon',
      ]);
    });

    test('primaryGoalValues includes the four distance goals + two non-distance',
        () {
      for (final v in ['5k', '10k', 'half_marathon', 'marathon']) {
        expect(primaryGoalValues.contains(v), isTrue, reason: 'missing $v');
      }
      expect(primaryGoalValues.contains('general_fitness'), isTrue);
      expect(primaryGoalValues.contains('weight_loss'), isTrue);
      expect(primaryGoalValues.length, 6);
    });

    test('onboardingTotalSteps matches web (9)', () {
      expect(onboardingTotalSteps, 9);
      // The constant is written out (a list length is not a constant
      // expression), so pin it against the list it describes.
      expect(setupWizardSteps.length, onboardingTotalSteps);
    });

    test('setupWizardSteps are web\'s ONBOARDING_STEPS ids, in order', () {
      expect(setupWizardSteps, [
        'name',
        'units',
        'goal',
        'about',
        'run-privacy',
        'notifications',
        'track',
        'import',
        'done',
      ]);
    });

    test('visibleSetupWizardSteps drops run-privacy once the launch flow '
        'already asked, and nothing else', () {
      final asked = visibleSetupWizardSteps(privacyAlreadyChosen: true);
      expect(asked.contains('run-privacy'), isFalse);
      expect(asked.length, onboardingTotalSteps - 1);
      expect(asked, setupWizardSteps.where((s) => s != 'run-privacy'));
      // Order is preserved — the wizard indexes this list.
      expect(asked.first, 'name');
      expect(asked.last, 'done');
    });

    test('visibleSetupWizardSteps walks every step when privacy is unanswered',
        () {
      final steps = visibleSetupWizardSteps(privacyAlreadyChosen: false);
      expect(steps, setupWizardSteps);
    });

    test('the track and import steps sit just before done, in that order',
        () {
      for (final asked in [true, false]) {
        final steps = visibleSetupWizardSteps(privacyAlreadyChosen: asked);
        expect(steps.where((s) => s == setupWizardTrackStep), hasLength(1));
        expect(steps.where((s) => s == setupWizardImportStep), hasLength(1));
        expect(steps[steps.length - 3], setupWizardTrackStep);
        expect(steps[steps.length - 2], setupWizardImportStep);
        expect(steps.last, 'done');
      }
    });

    test('the import step offers the device\'s own health platform only', () {
      final ios = setupWizardImportSources(isIOS: true, parkrunAvailable: true);
      expect(ios, ['healthkit', 'strava', 'parkrun']);
      expect(ios.contains('health_connect'), isFalse);

      final android =
          setupWizardImportSources(isIOS: false, parkrunAvailable: true);
      expect(android, ['health_connect', 'strava', 'parkrun']);
      expect(android.contains('healthkit'), isFalse);
    });

    test('the import step hides parkrun until its probe says yes', () {
      for (final isIOS in [true, false]) {
        final sources =
            setupWizardImportSources(isIOS: isIOS, parkrunAvailable: false);
        expect(sources.contains('parkrun'), isFalse);
        expect(sources, hasLength(2));
      }
    });

    test('the import step never offers a web-only source', () {
      // Garmin's export upload is a web importer; a phone reaches Garmin
      // through the health platform instead.
      for (final isIOS in [true, false]) {
        expect(
          setupWizardImportSources(isIOS: isIOS, parkrunAvailable: true)
              .contains('garmin'),
          isFalse,
        );
      }
    });

    test('planPresetForGoal maps distance goals 1:1 and seeds beginners into '
        'walk-run 5K', () {
      expect(planPresetForGoal('10k').goalEvent, GoalEvent.distance10k);
      expect(planPresetForGoal('10k').beginnerWalkRun, isFalse);
      expect(planPresetForGoal('half_marathon').goalEvent, GoalEvent.distanceHalf);
      expect(planPresetForGoal('marathon').goalEvent, GoalEvent.distanceFull);
      for (final v in ['5k', 'general_fitness', 'weight_loss']) {
        expect(planPresetForGoal(v).goalEvent, GoalEvent.distance5k,
            reason: '$v should seed the 5K');
        expect(planPresetForGoal(v).beginnerWalkRun, isTrue,
            reason: '$v should tick the walk-run toggle');
      }
    });

    test('ApiClient.dateOnly emits a zone-free YYYY-MM-DD calendar day', () {
      // A DOB is a calendar day, not an instant — the wizard must not let
      // a user east/west of UTC roll a day. Pad single digits.
      expect(ApiClient.dateOnly(DateTime(2001, 2, 3)), '2001-02-03');
      expect(ApiClient.dateOnly(DateTime(1990, 11, 25)), '1990-11-25');
      // A late-evening local instant keeps its local calendar day (no UTC
      // conversion that would advance to the next date).
      expect(ApiClient.dateOnly(DateTime(2001, 2, 3, 23, 30)), '2001-02-03');
    });
  });
}

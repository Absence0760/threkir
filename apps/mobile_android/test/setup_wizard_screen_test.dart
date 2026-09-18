import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/onboarding.dart';
import '../lib/preferences.dart';
import '../lib/screens/setup_wizard_screen.dart';
import '../lib/settings_sync.dart';

/// Records the two onboarding writes so the flow can be asserted without a
/// live Supabase. Every other ApiClient method is left to the base class.
class _FakeApi extends ApiClient {
  bool markOnboardedCalled = false;
  bool completeOnboardingCalled = false;
  String? completedDisplayName;
  String? completedUnit;
  bool? completedConsent;
  String? completedGender;
  DateTime? completedDob;

  /// Simulates zero connectivity — both stamp writes throw, like the
  /// real client does when the server is unreachable (issue #246).
  bool failWrites = false;

  @override
  String? get userId => 'u1';

  @override
  Future<void> markOnboarded() async {
    if (failWrites) throw Exception('network unreachable');
    markOnboardedCalled = true;
  }

  @override
  Future<void> completeOnboarding({
    String? displayName,
    required String preferredUnit,
    DateTime? dateOfBirth,
    String? gender,
    required bool healthDataConsent,
  }) async {
    if (failWrites) throw Exception('network unreachable');
    completeOnboardingCalled = true;
    completedDisplayName = displayName;
    completedUnit = preferredUnit;
    completedDob = dateOfBirth;
    completedGender = gender;
    completedConsent = healthDataConsent;
  }
}

Future<Preferences> _prefs() async {
  SharedPreferences.setMockInitialValues({});
  final p = Preferences();
  await p.init();
  return p;
}

Future<void> _pump(
  WidgetTester tester,
  _FakeApi api,
  Preferences prefs, {
  Locale? locale,
  String? initialPreferredUnit,
  SettingsSyncService? settingsSync,
}) async {
  // Host under a Navigator with a base route so the wizard's pop-on-finish
  // has somewhere to land (it's pushed as a fullscreen route in the app).
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SetupWizardScreen(
                    apiClient: api,
                    preferences: prefs,
                    settingsSync: settingsSync,
                    initialPreferredUnit: initialPreferredUnit,
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

/// Tap the wizard's single forward button. Its label is Continue on a step
/// that has an answer and Skip on one that doesn't, so a test walking the
/// wizard can't hard-code either.
Future<void> _forward(WidgetTester tester, AppLocalizations l10n) async {
  final skip = find.widgetWithText(FilledButton, l10n.setupSkipStep);
  await tester
      .tap(skip.evaluate().isEmpty ? find.text(l10n.setupContinue) : skip);
  await tester.pumpAndSettle();
}

/// The number of forward taps between the first step and the last, for the
/// step list a signed-out-at-launch fixture produces.
int _forwardTaps(Preferences prefs) =>
    visibleSetupWizardSteps(privacyAlreadyChosen: prefs.onboarded).length - 1;

void main() {
  group('SetupWizardScreen', () {
    testWidgets('renders the first step + a Skip header action', (tester) async {
      final api = _FakeApi();
      await _pump(tester, api, await _prefs());
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(find.text(l10n.setupNameTitle), findsOneWidget);
      expect(find.text(l10n.setupSkip), findsOneWidget);
    });

    testWidgets('Skip header stamps onboarded_at only (markOnboarded)',
        (tester) async {
      final api = _FakeApi();
      await _pump(tester, api, await _prefs());
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      await tester.tap(find.text(l10n.setupSkip));
      await tester.pumpAndSettle();
      expect(api.markOnboardedCalled, isTrue);
      expect(api.completeOnboardingCalled, isFalse);
    });

    testWidgets('Continue advances through every step to Open dashboard',
        (tester) async {
      final api = _FakeApi();
      await _pump(tester, api, await _prefs());
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      // Walk all steps via Continue; the final step shows Open dashboard.
      for (var i = 0; i < onboardingTotalSteps - 1; i++) {
        await _forward(tester, l10n);
      }
      expect(find.text(l10n.setupOpenDashboard), findsOneWidget);
    });

    testWidgets(
        'final step with a goal offers one primary CTA, not two competing buttons',
        (tester) async {
      // Reason (#261): the goal-keyed "Create my training plan" CTA and the
      // nav "Open dashboard" were both FilledButtons, and the hint told the
      // runner to "tap Open dashboard" — two competing primaries + a mismatched
      // hint. The CTA must be the single primary; Open dashboard demotes to a
      // secondary outlined action and the hint names the primary.
      final api = _FakeApi();
      await _pump(tester, api, await _prefs());
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      // Advance to the goal step (index 2) and pick a goal.
      await _forward(tester, l10n);
      await _forward(tester, l10n);
      await tester.ensureVisible(find.text(l10n.setupGoal5k));
      await tester.pump();
      await tester.tap(find.text(l10n.setupGoal5k));
      await tester.pump();
      // Advance to the final step.
      for (var i = 2; i < onboardingTotalSteps - 1; i++) {
        await _forward(tester, l10n);
      }
      expect(find.widgetWithText(FilledButton, l10n.setupCreatePlanCta),
          findsOneWidget);
      expect(find.widgetWithText(FilledButton, l10n.setupOpenDashboard),
          findsNothing);
      expect(find.widgetWithText(OutlinedButton, l10n.setupOpenDashboard),
          findsOneWidget);
      expect(find.text(l10n.setupDoneHintGoal), findsOneWidget);
    });

    testWidgets('Finish persists the answers via completeOnboarding',
        (tester) async {
      final api = _FakeApi();
      await _pump(tester, api, await _prefs());
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));

      // Step 1: name.
      await tester.enterText(find.byType(TextField).first, 'Alex Runner');
      await _forward(tester, l10n);
      // Step 2: pick miles.
      await tester.tap(find.text(l10n.setupUnitMi));
      await tester.pump();
      await _forward(tester, l10n);
      // Remaining steps: just advance.
      for (var i = 2; i < onboardingTotalSteps - 1; i++) {
        await _forward(tester, l10n);
      }
      // Final step: Open dashboard. Settle the success toast's timer +
      // the pop animation so no timer outlives the disposed tree.
      await tester.tap(find.text(l10n.setupOpenDashboard));
      await tester.pumpAndSettle(const Duration(seconds: 4));

      expect(api.completeOnboardingCalled, isTrue);
      expect(api.completedDisplayName, 'Alex Runner');
      expect(api.completedUnit, 'mi');
      // No DOB / gender chosen → consent stays false (Art 9 not granted).
      expect(api.completedConsent, isFalse);
    });

    testWidgets(
        'health-consent checkbox only appears after a demographic is entered',
        (tester) async {
      final api = _FakeApi();
      await _pump(tester, api, await _prefs());
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      // Advance to the About-you step (step index 3).
      for (var i = 0; i < 3; i++) {
        await _forward(tester, l10n);
      }
      // No demographic chosen yet → no consent checkbox.
      expect(find.byType(CheckboxListTile), findsNothing);
      // Choose a gender → the Art 9 consent checkbox surfaces.
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.setupGenderFemale).last);
      await tester.pumpAndSettle();
      expect(find.byType(CheckboxListTile), findsOneWidget);
    });

    testWidgets('DOB picker opens in year-selection mode', (tester) async {
      // Reason (#222): a birth year sits decades back, so the picker must
      // open on the year grid — the day-grid default forces paging month
      // by month (or spotting the tap-the-header affordance) to reach it.
      final api = _FakeApi();
      await _pump(tester, api, await _prefs());
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      for (var i = 0; i < 3; i++) {
        await _forward(tester, l10n);
      }
      await tester.ensureVisible(find.text(l10n.setupDobPlaceholder));
      await tester.pump();
      await tester.tap(find.text(l10n.setupDobPlaceholder));
      await tester.pumpAndSettle();
      expect(find.byType(YearPicker), findsOneWidget);
    });

    group('run privacy is asked once, at launch (not twice)', () {
      Future<Preferences> onboardedPrefs(String privacy) async {
        SharedPreferences.setMockInitialValues({});
        final p = Preferences();
        await p.init();
        await p.setOnboarded(true);
        await p.setPrivacyDefault(privacy);
        return p;
      }

      testWidgets('the wizard drops its privacy step when the launch flow '
          'already asked', (tester) async {
        final api = _FakeApi();
        final prefs = await onboardedPrefs('public');
        await _pump(tester, api, prefs);
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));

        // One dot fewer than the full wizard, and the privacy step is never
        // reached on the way to the end.
        expect(_forwardTaps(prefs), onboardingTotalSteps - 2);
        for (var i = 0; i < _forwardTaps(prefs); i++) {
          expect(find.text(l10n.setupPrivacyTitle), findsNothing);
          await _forward(tester, l10n);
        }
        expect(find.text(l10n.setupPrivacyTitle), findsNothing);
        expect(find.text(l10n.setupOpenDashboard), findsOneWidget);
      });

      testWidgets('Finish writes the answer given at launch, not a '
          'hard-coded private', (tester) async {
        final api = _FakeApi();
        final fake = _FakeSettingsService();
        final prefs = await onboardedPrefs('public');
        final sync = SettingsSyncService(
          preferences: prefs,
          serviceLoader: () async => fake,
        );
        await _pump(tester, api, prefs, settingsSync: sync);
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));

        for (var i = 0; i < _forwardTaps(prefs); i++) {
          await _forward(tester, l10n);
        }
        await tester.tap(find.text(l10n.setupOpenDashboard));
        await tester.pumpAndSettle(const Duration(seconds: 4));

        expect(fake.universalWrites.single[SettingsKeys.privacyDefault],
            'public');
        expect(prefs.privacyDefault, 'public');
      });

      testWidgets('a wizard reached without the launch flow still asks',
          (tester) async {
        // Signed in on a device whose local onboarding never ran — the
        // wizard is then the only place the question gets asked.
        final api = _FakeApi();
        final prefs = await _prefs();
        await _pump(tester, api, prefs);
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        for (var i = 0; i < 4; i++) {
          await _forward(tester, l10n);
        }
        expect(find.text(l10n.setupPrivacyTitle), findsOneWidget);
      });
    });

    group('one forward button, labelled for what it does', () {
      testWidgets('an unanswered optional step offers Skip, and only Skip',
          (tester) async {
        final api = _FakeApi();
        await _pump(tester, api, await _prefs());
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));

        // Step 0 (name) starts empty.
        expect(find.widgetWithText(FilledButton, l10n.setupSkipStep),
            findsOneWidget);
        expect(find.text(l10n.setupContinue), findsNothing);

        await tester.enterText(find.byType(TextField).first, 'Alex');
        await tester.pump();
        expect(find.widgetWithText(FilledButton, l10n.setupContinue),
            findsOneWidget);
        expect(find.text(l10n.setupSkipStep), findsNothing);
      });

      testWidgets('a pre-answered step only ever offers Continue',
          (tester) async {
        // Units is seeded from the locale, so there is nothing to skip.
        final api = _FakeApi();
        await _pump(tester, api, await _prefs());
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        await _forward(tester, l10n);
        expect(find.text(l10n.setupUnitsTitle), findsOneWidget);
        expect(find.widgetWithText(FilledButton, l10n.setupContinue),
            findsOneWidget);
        expect(find.text(l10n.setupSkipStep), findsNothing);
      });

      testWidgets('the goal step flips to Continue once a goal is picked',
          (tester) async {
        final api = _FakeApi();
        await _pump(tester, api, await _prefs());
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        await _forward(tester, l10n);
        await _forward(tester, l10n);
        expect(find.text(l10n.setupSkipStep), findsOneWidget);
        await tester.ensureVisible(find.text(l10n.setupGoal5k));
        await tester.pump();
        await tester.tap(find.text(l10n.setupGoal5k));
        await tester.pump();
        expect(find.widgetWithText(FilledButton, l10n.setupContinue),
            findsOneWidget);
      });
    });

    group('the notification level is a choice, not a default', () {
      // The privacy key stopped writing an unchosen default when the launch
      // flow's answer started seeding it; the notification key two lines
      // below it in the same bag did not. Seeded 'important', an untouched
      // step wrote that into the bag as though it had been picked AND
      // reported itself answered, so the one forward button read Continue
      // over a question nobody had been asked.
      testWidgets('an untouched step offers Skip, and flips on a tap',
          (tester) async {
        final api = _FakeApi();
        await _pump(tester, api, await _prefs());
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        for (var i = 0; i < 5; i++) {
          await _forward(tester, l10n);
        }
        expect(find.text(l10n.setupNotificationsTitle), findsOneWidget);
        expect(find.widgetWithText(FilledButton, l10n.setupSkipStep),
            findsOneWidget);
        expect(find.text(l10n.setupContinue), findsNothing);

        await tester.ensureVisible(find.text(l10n.prefsPushNotifAll));
        await tester.pump();
        await tester.tap(find.text(l10n.prefsPushNotifAll));
        await tester.pump();
        expect(find.widgetWithText(FilledButton, l10n.setupContinue),
            findsOneWidget);
        expect(find.text(l10n.setupSkipStep), findsNothing);
      });

      testWidgets('walking past it leaves push_notifications unwritten',
          (tester) async {
        final api = _FakeApi();
        final fake = _FakeSettingsService();
        final prefs = await _prefs();
        final sync = SettingsSyncService(
          preferences: prefs,
          serviceLoader: () async => fake,
        );
        await _pump(tester, api, prefs, settingsSync: sync);
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        for (var i = 0; i < _forwardTaps(prefs); i++) {
          await _forward(tester, l10n);
        }
        await tester.tap(find.text(l10n.setupOpenDashboard));
        await tester.pumpAndSettle(const Duration(seconds: 7));

        expect(fake.universalWrites, hasLength(1));
        final bag = fake.universalWrites.single;
        // Unwritten, not written as 'important' — reads fall back to the
        // registered default, but nothing claims the runner chose it.
        expect(bag.containsKey(SettingsKeys.pushNotifications), isFalse);
        expect(bag[SettingsKeys.privacyDefault], isNotNull);
      });
    });

    group('the OS back gesture', () {
      testWidgets('steps back through the wizard instead of doing nothing',
          (tester) async {
        final api = _FakeApi();
        await _pump(tester, api, await _prefs());
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        await _forward(tester, l10n);
        expect(find.text(l10n.setupUnitsTitle), findsOneWidget);

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        expect(find.text(l10n.setupNameTitle), findsOneWidget);
        // Still on the wizard — the gesture never pops the route itself.
        expect(find.text('open'), findsNothing);
      });

      testWidgets('on the first step it confirms, and Stay keeps the answers',
          (tester) async {
        final api = _FakeApi();
        await _pump(tester, api, await _prefs());
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        await tester.enterText(find.byType(TextField).first, 'Alex');
        await tester.pump();

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.text(l10n.setupLeaveTitle), findsOneWidget);

        await tester.tap(find.widgetWithText(TextButton, l10n.setupLeaveStay));
        await tester.pumpAndSettle();
        expect(find.text(l10n.setupNameTitle), findsOneWidget);
        expect(api.markOnboardedCalled, isFalse);
        expect(
            tester.widget<TextField>(find.byType(TextField).first).controller!.text,
            'Alex');
      });

      testWidgets('confirming leaves the same way the header Skip does',
          (tester) async {
        final api = _FakeApi();
        await _pump(tester, api, await _prefs());
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        await tester
            .tap(find.widgetWithText(TextButton, l10n.setupLeaveConfirm));
        await tester.pumpAndSettle();

        expect(api.markOnboardedCalled, isTrue);
        expect(api.completeOnboardingCalled, isFalse);
        expect(find.text('open'), findsOneWidget);
      });
    });

    group('answers survive a process death', () {
      testWidgets('the typed name, the picked goal and the step cursor all '
          'come back', (tester) async {
        final api = _FakeApi();
        final prefs = await _prefs();
        // Mounted as `home` so the restored tree is the wizard itself —
        // the route stack is the shell's to restore, not this screen's.
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: SetupWizardScreen(apiClient: api, preferences: prefs),
          ),
        );
        await tester.pumpAndSettle();
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));

        await tester.enterText(find.byType(TextField).first, 'Alex Runner');
        await tester.pump();
        await _forward(tester, l10n);
        await _forward(tester, l10n);
        await tester.ensureVisible(find.text(l10n.setupGoal5k));
        await tester.pump();
        await tester.tap(find.text(l10n.setupGoal5k));
        await tester.pumpAndSettle();

        await tester.restartAndRestore();
        await tester.pumpAndSettle();

        expect(find.text(l10n.setupGoalTitle), findsOneWidget);
        expect(
          tester.widget<Card>(find.ancestor(
              of: find.text(l10n.setupGoal5k), matching: find.byType(Card))),
          isNotNull,
        );
        expect(find.byIcon(Icons.check_circle), findsOneWidget);
        await tester.tap(find.text(l10n.setupBack));
        await tester.pumpAndSettle();
        await tester.tap(find.text(l10n.setupBack));
        await tester.pumpAndSettle();
        expect(
            tester.widget<TextField>(find.byType(TextField).first).controller!.text,
            'Alex Runner');
      });
    });

    group('offline fail-safe exit (issue #246)', () {
      testWidgets(
          'a failing Skip reveals Finish later, which dismisses the wizard '
          'with zero connectivity', (tester) async {
        final api = _FakeApi()..failWrites = true;
        final prefs = await _prefs();
        await _pump(tester, api, prefs);
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));

        // No fail-safe exit before a save ever failed — the normal exits
        // own the happy path.
        expect(find.text(l10n.setupFinishLater), findsNothing);

        await tester.tap(find.text(l10n.setupSkip));
        // Drain the failure banner's auto-dismiss timer.
        await tester.pumpAndSettle(const Duration(seconds: 4));

        // Still trapped on the wizard (canPop is false) — but the
        // fail-safe exit is now offered.
        expect(find.text(l10n.setupPageTitle), findsOneWidget);
        expect(find.text(l10n.setupFinishLater), findsOneWidget);

        await tester.tap(find.text(l10n.setupFinishLater));
        await tester.pumpAndSettle();

        // The wizard popped without any server write, and the dismissal
        // was recorded locally so the gate defers the stamp instead of
        // re-pushing the wizard.
        expect(find.text(l10n.setupPageTitle), findsNothing);
        expect(find.text('open'), findsOneWidget);
        expect(prefs.setupWizardDismissed, isTrue);
        expect(api.markOnboardedCalled, isFalse);
      });

      testWidgets('a failing Finish reveals the same fail-safe exit',
          (tester) async {
        final api = _FakeApi()..failWrites = true;
        final prefs = await _prefs();
        await _pump(tester, api, prefs);
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));

        for (var i = 0; i < onboardingTotalSteps - 1; i++) {
          await _forward(tester, l10n);
        }
        await tester.tap(find.text(l10n.setupOpenDashboard));
        await tester.pumpAndSettle(const Duration(seconds: 4));

        expect(find.text(l10n.setupFinishLater), findsOneWidget);

        await tester.tap(find.text(l10n.setupFinishLater));
        await tester.pumpAndSettle();
        expect(find.text('open'), findsOneWidget);
        expect(prefs.setupWizardDismissed, isTrue);
      });
    });

    group('locale-derived unit default', () {
      Future<void> finish(WidgetTester tester, AppLocalizations l10n) async {
        for (var i = 0; i < onboardingTotalSteps - 1; i++) {
          await _forward(tester, l10n);
        }
        await tester.tap(find.text(l10n.setupOpenDashboard));
        await tester.pumpAndSettle(const Duration(seconds: 4));
      }

      void setDeviceLocale(WidgetTester tester, Locale locale) {
        tester.platformDispatcher.localeTestValue = locale;
        addTearDown(tester.platformDispatcher.clearLocaleTestValue);
      }

      testWidgets('en_US device locale seeds miles when no unit was chosen',
          (tester) async {
        final api = _FakeApi();
        setDeviceLocale(tester, const Locale('en', 'US'));
        await _pump(tester, api, await _prefs(), locale: const Locale('en'));
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        await finish(tester, l10n);
        expect(api.completedUnit, 'mi');
      });

      testWidgets('de_DE device locale seeds kilometres', (tester) async {
        final api = _FakeApi();
        setDeviceLocale(tester, const Locale('de', 'DE'));
        await _pump(tester, api, await _prefs(), locale: const Locale('en'));
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        await finish(tester, l10n);
        expect(api.completedUnit, 'km');
      });

      testWidgets('an explicit prior choice overrides the locale seed',
          (tester) async {
        final api = _FakeApi();
        setDeviceLocale(tester, const Locale('en', 'US'));
        await _pump(tester, api, await _prefs(),
            locale: const Locale('en'), initialPreferredUnit: 'km');
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        await finish(tester, l10n);
        expect(api.completedUnit, 'km');
      });
    });

    group('narrow-width overflow (issue #666 V7)', () {
      testWidgets(
          'nav renders at 320 logical width with the forward actions in a '
          'Wrap so long localized labels reflow instead of striping',
          (tester) async {
        tester.view.physicalSize = const Size(320, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final api = _FakeApi();
        await _pump(tester, api, await _prefs());
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));

        // Advance one step so the Back button shares the row with the
        // wrapped forward button.
        await _forward(tester, l10n);

        expect(find.text(l10n.setupBack), findsOneWidget);
        expect(
          find.ancestor(
              of: find.widgetWithText(FilledButton, l10n.setupContinue),
              matching: find.byType(Wrap)),
          findsWidgets,
        );
      });
    });

    group('preferences bag (the answers with no local mirror)', () {
      testWidgets('Finish writes the answer bag even when onSignedIn never ran',
          (tester) async {
        // Regression: SettingsSyncService.updateUniversal returned silently
        // while its service was null, so a brand-new account's units, goal,
        // privacy default and notification choice were dropped on the floor
        // — no exception for the wizard's catch, nothing in the offline
        // queue. The goal + notification keys have no local Preferences
        // mirror, so that was the only copy.
        final api = _FakeApi();
        final fake = _FakeSettingsService();
        final sync = SettingsSyncService(
          preferences: await _prefs(),
          serviceLoader: () async => fake,
        );
        await _pump(tester, api, await _prefs(), settingsSync: sync);
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));

        await _forward(tester, l10n);
        await _forward(tester, l10n);
        await tester.ensureVisible(find.text(l10n.setupGoal5k));
        await tester.pump();
        await tester.tap(find.text(l10n.setupGoal5k));
        await tester.pump();
        for (var i = 2; i < onboardingTotalSteps - 1; i++) {
          // The notification level is written only when it is chosen, so
          // answer that step on the way past it.
          if (i == 5) {
            await tester.ensureVisible(find.text(l10n.prefsPushNotifAll));
            await tester.pump();
            await tester.tap(find.text(l10n.prefsPushNotifAll));
            await tester.pump();
          }
          await _forward(tester, l10n);
        }
        await tester.tap(find.text(l10n.setupCreatePlanCta));
        await tester.pumpAndSettle(const Duration(seconds: 7));

        expect(fake.universalWrites, hasLength(1));
        final bag = fake.universalWrites.single;
        expect(bag[SettingsKeys.primaryGoal], '5k');
        expect(bag[SettingsKeys.preferredUnit], isNotNull);
        expect(bag[SettingsKeys.privacyDefault], isNotNull);
        expect(bag[SettingsKeys.pushNotifications], 'all');
      });

      testWidgets('a dropped answer bag is disclosed, not toasted as welcome',
          (tester) async {
        final api = _FakeApi();
        final sync = SettingsSyncService(
          preferences: await _prefs(),
          serviceLoader: () async => throw Exception('Not authenticated'),
        );
        await _pump(tester, api, await _prefs(), settingsSync: sync);
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));

        for (var i = 0; i < onboardingTotalSteps - 1; i++) {
          await _forward(tester, l10n);
        }
        await tester.tap(find.text(l10n.setupOpenDashboard));
        await tester.pump();
        await tester.pump();

        expect(find.text(l10n.setupWelcomeToast), findsNothing);
        final prefix = l10n.setupPrefsSaveError('§§').split('§§').first;
        expect(find.textContaining(prefix), findsOneWidget);
        await tester.pumpAndSettle(const Duration(seconds: 7));
      });
    });
  });
}

class _FakeSettingsService implements SettingsService {
  final List<Map<String, dynamic>> universalWrites = [];

  @override
  Map<String, dynamic> get universal => const <String, dynamic>{};
  @override
  Map<String, dynamic> get device => const <String, dynamic>{};
  @override
  bool get isServerHydrated => true;
  @override
  Future<void> updateUniversal(Map<String, dynamic> changes) async {
    universalWrites.add(changes);
  }

  @override
  Future<void> updateDevice(Map<String, dynamic> changes) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

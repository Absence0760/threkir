// The recovery block in the plan wizard and the `extra_recovery` switch in
// Preferences (decisions § 93). The masters recovery calibration needs a
// consented date of birth at 50+; without one the wizard says how to get it,
// and any runner can opt into the same calibration with `extra_recovery`, a
// universal setting the wizard and Preferences share. The generator
// arithmetic is unit-tested; these pin the wiring. Mirrors web
// `tests-e2e/plans/extra-recovery.spec.ts`.

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' show TrainingPlanRow, UserProfileRow;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/health_consent.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/plan_calibration.dart';
import '../lib/preferences.dart';
import '../lib/screens/plan_new_screen.dart';
import '../lib/screens/settings_preferences_screen.dart';
import '../lib/settings_destination.dart';
import '../lib/settings_sync.dart';
import '../lib/training_service.dart';

class _Training extends TrainingService {
  _Training(this.calibration, {this.saveFails = false});

  final PlanCalibration calibration;
  final bool saveFails;
  final List<bool> saved = [];

  @override
  Future<PlanCalibration> fetchPlanCalibration() async => calibration;

  @override
  Future<PlanRunHistory?> fetchPlanRunHistory() async => null;

  @override
  Future<List<TrainingPlanRow>> fetchClubTemplates(String clubId) async =>
      const [];

  @override
  Future<void> setExtraRecovery(bool on) async {
    if (saveFails) throw Exception('test: offline');
    saved.add(on);
  }
}

PlanCalibration _calibration({int? age, HealthUseDobState? dobState}) =>
    PlanCalibration(
      gender: null,
      age: age,
      dobState: dobState,
      extraRecovery: false,
    );

Future<void> _pumpWizard(WidgetTester tester, _Training training) async {
  tester.view.physicalSize = const Size(400, 12000) * 2;
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: PlanNewScreen(training: training),
    ),
  );
  await tester.pumpAndSettle();
}

String _weekKm(WidgetTester tester, int week) =>
    tester.widget<Text>(find.byKey(Key('plan-new-week-km-$week'))).data!;

SwitchListTile _wizardSwitch(WidgetTester tester) =>
    tester.widget<SwitchListTile>(find.byKey(const Key('plan-new-extra-recovery')));

class _Sync extends SettingsSyncService {
  _Sync(Preferences prefs) : super(preferences: prefs);

  final List<Map<String, dynamic>> universalWrites = [];

  @override
  bool get synced => true;

  @override
  SettingsService? get service => null;

  @override
  Future<void> updateUniversal(Map<String, dynamic> changes) async {
    universalWrites.add(changes);
    notifyListeners();
  }
}

class _Api extends ApiClient {
  @override
  Future<UserProfileRow?> fetchMyProfile() async => UserProfileRow(
        id: 'u1',
        profilePrivate: false,
        shadowHidden: false,
      );

  @override
  Future<bool> fetchMyProfilePrivate() async => false;
}

void main() {
  setUp(initializeDateFormatting);
  tearDown(() => pendingSettingsDestination.value = null);

  group('plan wizard recovery block', () {
    testWidgets(
        'a runner with no date of birth is told where to add one, and the '
        'switch reshapes the plan and saves the setting', (tester) async {
      final training =
          _Training(_calibration(dobState: HealthUseDobState.absent));
      await _pumpWizard(tester, training);

      expect(find.byKey(const Key('plan-new-dob-hint')), findsOneWidget);
      expect(find.byKey(const Key('plan-new-dob-consent-hint')), findsNothing);
      expect(_wizardSwitch(tester).value, isFalse);
      expect(_wizardSwitch(tester).onChanged, isNotNull);

      // The third week is the first a 3-week cycle eases off; a 4-week cycle
      // is still building.
      final before = _weekKm(tester, 2);
      await tester.tap(find.byKey(const Key('plan-new-extra-recovery')));
      await tester.pumpAndSettle();
      expect(_wizardSwitch(tester).value, isTrue);
      expect(training.saved, [true]);
      expect(_weekKm(tester, 2), isNot(before));

      await tester.tap(find.text('Add your date of birth'));
      expect(pendingSettingsDestination.value, SettingsDestination.preferences);
    });

    testWidgets(
        'a masters runner is told the calibration is already on, with no '
        'switch and no hint', (tester) async {
      await _pumpWizard(
        tester,
        _Training(_calibration(age: 58, dobState: HealthUseDobState.usable)),
      );
      expect(find.byKey(const Key('plan-new-recovery-masters')), findsOneWidget);
      expect(find.byKey(const Key('plan-new-extra-recovery')), findsNothing);
      expect(find.byKey(const Key('plan-new-dob-hint')), findsNothing);
    });

    testWidgets(
        'a date of birth held without health-data consent points at the '
        'consent, not at adding a date', (tester) async {
      await _pumpWizard(
        tester,
        _Training(_calibration(dobState: HealthUseDobState.consentWithheld)),
      );
      expect(find.byKey(const Key('plan-new-dob-consent-hint')), findsOneWidget);
      expect(find.byKey(const Key('plan-new-dob-hint')), findsNothing);
      expect(find.byKey(const Key('plan-new-extra-recovery')), findsOneWidget);

      await tester.tap(find.text('Review consent'));
      expect(pendingSettingsDestination.value, SettingsDestination.bodyMetrics);
    });

    testWidgets('a failed profile read shows the switch but no hint',
        (tester) async {
      await _pumpWizard(tester, _Training(PlanCalibration.unknown));
      expect(find.byKey(const Key('plan-new-extra-recovery')), findsOneWidget);
      expect(find.byKey(const Key('plan-new-dob-hint')), findsNothing);
      expect(find.byKey(const Key('plan-new-dob-consent-hint')), findsNothing);
    });

    testWidgets('a failed save puts the switch back and says so',
        (tester) async {
      await _pumpWizard(
        tester,
        _Training(_calibration(dobState: HealthUseDobState.absent),
            saveFails: true),
      );
      final before = _weekKm(tester, 2);
      await tester.tap(find.byKey(const Key('plan-new-extra-recovery')));
      await tester.pumpAndSettle();
      expect(_wizardSwitch(tester).value, isFalse);
      expect(
          find.byKey(const Key('plan-new-extra-recovery-error')), findsOneWidget);
      expect(_weekKm(tester, 2), before);
    });
  });

  testWidgets('the Preferences switch writes extra_recovery to the universal bag',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = Preferences();
    await prefs.init();
    final sync = _Sync(prefs);
    tester.view.physicalSize = const Size(400, 8000) * 2;
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SettingsPreferencesScreen(
          apiClient: _Api(),
          preferences: prefs,
          settingsSync: sync,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('prefsExtraRecovery')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    final row = tester
        .widget<SwitchListTile>(find.byKey(const Key('prefsExtraRecovery')));
    expect(row.value, isFalse);
    await tester.tap(find.byKey(const Key('prefsExtraRecovery')));
    await tester.pumpAndSettle();
    expect(sync.universalWrites, [
      {'extra_recovery': true}
    ]);
  });
}

// "My heart rate is affected by medication" on mobile Preferences (decisions
// § 2087). Art 9: the switch exists only under the deploy gate, can be turned
// on only with health-data consent on record, and asks for a measured max
// heart rate once it is on.

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' show UserProfileRow;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/preferences.dart';
import '../lib/screens/settings_preferences_screen.dart';
import '../lib/settings_sync.dart';

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
  _Api({required this.consented});
  final bool consented;

  @override
  Future<UserProfileRow?> fetchMyProfile() async => UserProfileRow(
        id: 'u1',
        profilePrivate: false,
        shadowHidden: false,
        healthDataConsentAt: consented ? DateTime.utc(2026, 1, 1) : null,
      );

  @override
  Future<bool> fetchMyProfilePrivate() async => false;
}

Future<_Sync> _pump(WidgetTester tester,
    {required bool gate, required bool consented}) async {
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
        apiClient: _Api(consented: consented),
        preferences: prefs,
        settingsSync: sync,
        hrPrescription: gate,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return sync;
}

SwitchListTile _switch(WidgetTester tester) => tester.widget<SwitchListTile>(
    find.byKey(const Key('prefsHrMedicationAffected')));

void main() {
  setUp(initializeDateFormatting);

  testWidgets('with the gate off the switch does not exist', (tester) async {
    await _pump(tester, gate: false, consented: true);
    expect(find.byKey(const Key('prefsHrMedicationAffected')), findsNothing);
  });

  testWidgets('without health-data consent the switch says why and is off',
      (tester) async {
    await _pump(tester, gate: true, consented: false);
    expect(_switch(tester).onChanged, isNull);
    expect(
        find.text('This is health data, so it needs your health-data consent '
            'first.'),
        findsOneWidget);
  });

  testWidgets('with consent the switch writes the universal key', (tester) async {
    final sync = await _pump(tester, gate: true, consented: true);
    expect(_switch(tester).onChanged, isNotNull);
    await tester.tap(find.byKey(const Key('prefsHrMedicationAffected')));
    await tester.pumpAndSettle();
    expect(sync.universalWrites, [
      {'hr_medication_affected': true}
    ]);
  });
}

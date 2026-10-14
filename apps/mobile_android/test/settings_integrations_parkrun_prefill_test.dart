import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/ble_heart_rate.dart';
import '../lib/ble_treadmill.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/preferences.dart';
import '../lib/race_service.dart';
import '../lib/screens/settings_integrations_screen.dart';

/// A runner who already saved an athlete number re-runs the import from the
/// saved profile, so the dialog has to open holding it rather than asking for
/// it again.
class _FakeApi extends ApiClient {
  final imported = <String>[];

  @override
  String? get userId => 'u1';

  @override
  Future<List<IntegrationRow>> fetchIntegrations() async => const [];

  @override
  Future<UserProfileRow?> fetchMyProfile() async =>
      const UserProfileRow(id: 'u1', parkrunNumber: 'A123456', shadowHidden: false);

  @override
  Future<void> setParkrunAthleteNumber(String? athleteNumber) async {}

  @override
  Future<ImportCompleteness> importParkrunResults(String athleteNumber) async {
    imported.add(athleteNumber);
    return const ImportCompleteness(
        imported: 3, skipped: 0, total: 3, complete: true);
  }
}

class _FakeRaceService extends RaceService {
  @override
  Future<bool> isParkrunConfigured() async => true;

  @override
  Future<bool> isProviderConfigured(String provider) async => false;
}

void main() {
  testWidgets('the parkrun import opens filled with the saved athlete number',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = Preferences();
    await prefs.init();
    final api = _FakeApi();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SettingsIntegrationsScreen(
          apiClient: api,
          heartRate: BleHeartRate(),
          treadmill: BleTreadmill(),
          preferences: prefs,
          raceService: _FakeRaceService(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    await tester.tap(find.widgetWithText(ListTile, l10n.integrationsParkrunName));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.descendant(
        of: find.byType(AlertDialog), matching: find.byType(TextField)));
    expect(field.controller!.text, 'A123456');

    await tester.tap(find.widgetWithText(FilledButton, l10n.integrationsImport));
    await tester.pumpAndSettle();

    expect(api.imported, ['A123456'],
        reason: 'the saved number imports without being retyped');
    expect(find.text(l10n.integrationsParkrunImported(3)), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });
}

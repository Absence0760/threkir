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

/// The settings screen offers a tile only for what this deployment can honour.
///
/// Every widget test runs without a loaded `.env`, so `isStravaConfigured()`
/// answers false throughout — which is exactly the shape a minimal deployment
/// has, and the one the Strava tile used to render a Connect chevron for
/// regardless, disclosing nothing until the tap opened a browser instead.
class _FakeApi extends ApiClient {
  _FakeApi(this.rows);

  final List<IntegrationRow> rows;

  @override
  String? get userId => 'u1';

  @override
  Future<List<IntegrationRow>> fetchIntegrations() async => rows;
}

class _FakeRaceService extends RaceService {
  _FakeRaceService({this.parkrun = true});

  final bool parkrun;

  @override
  Future<bool> isParkrunConfigured() async => parkrun;

  @override
  Future<bool> isProviderConfigured(String provider) async => false;
}

Future<AppLocalizations> _pump(
  WidgetTester tester, {
  List<IntegrationRow> rows = const [],
  bool parkrun = true,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = Preferences();
  await prefs.init();
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: SettingsIntegrationsScreen(
        apiClient: _FakeApi(rows),
        heartRate: BleHeartRate(),
        treadmill: BleTreadmill(),
        preferences: prefs,
        raceService: _FakeRaceService(parkrun: parkrun),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return AppLocalizations.delegate.load(const Locale('en'));
}

IntegrationRow _row(String provider) => IntegrationRow(
      id: 'i-$provider',
      userId: 'u1',
      provider: provider,
      lastSyncAt: DateTime.utc(2026, 5, 10, 8),
    );

void main() {
  testWidgets('an unconfigured Strava with no connection gets no tile',
      (tester) async {
    final l10n = await _pump(tester);
    expect(find.text(l10n.integrationsStravaName), findsNothing);
    // parkrun is the proof the screen rendered rather than failing to build.
    expect(find.text(l10n.integrationsParkrunName), findsOneWidget);
  });

  testWidgets('a connected Strava is still shown on a deployment that cannot start a new grant',
      (tester) async {
    // The env var builds the OAuth redirect, so it gates starting a NEW grant;
    // syncing one that already exists runs on the Edge Function's own
    // credentials. Hiding this tile would strand the row — no disconnect, and a
    // stored grant still rotating its token server-side.
    final l10n = await _pump(tester, rows: [_row('strava')]);
    expect(find.text(l10n.integrationsStravaName), findsOneWidget);
  });

  testWidgets('an unreachable parkrun leg gets no tile', (tester) async {
    final l10n = await _pump(tester, parkrun: false);
    expect(find.text(l10n.integrationsParkrunName), findsNothing);
  });

  testWidgets('a connected parkrun is shown even when its leg is unreachable',
      (tester) async {
    final l10n =
        await _pump(tester, rows: [_row('parkrun')], parkrun: false);
    expect(find.text(l10n.integrationsParkrunName), findsOneWidget);
  });

  testWidgets('the device-capability tiles are never gated on a deployment',
      (tester) async {
    // Heart-rate strap, treadmill and the watch relay are on-device: they need
    // no credential and no Edge Function, so they must survive a deployment
    // that configured nothing. They are the counterpart to web's bulk
    // importers — the part a minimal deployment always has.
    final l10n = await _pump(tester, parkrun: false);
    expect(find.text(l10n.watchLiveTitle), findsOneWidget);
  });

  testWidgets('every offered tile carries an info tip that explains the feature',
      (tester) async {
    final l10n = await _pump(tester);
    final label = l10n.integrationsInfoAbout(l10n.integrationsParkrunName);

    expect(find.byTooltip(label), findsOneWidget);
    expect(find.text(l10n.integrationsParkrunInfo), findsNothing);

    await tester.tap(find.byTooltip(label));
    await tester.pumpAndSettle();
    expect(find.text(l10n.integrationsParkrunInfo), findsOneWidget);

    await tester.tap(find.text(l10n.commonDismiss));
    await tester.pumpAndSettle();
    expect(find.text(l10n.integrationsParkrunInfo), findsNothing);
  });
}

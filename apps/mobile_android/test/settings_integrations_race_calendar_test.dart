import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/ble_heart_rate.dart';
import '../lib/ble_treadmill.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/preferences.dart';
import '../lib/race_provider_labels.dart';
import '../lib/race_service.dart';
import '../lib/screens/races_screen.dart';
import '../lib/screens/settings_integrations_screen.dart';

class _FakeApi extends ApiClient {
  @override
  String? get userId => 'u1';

  @override
  Future<List<IntegrationRow>> fetchIntegrations() async => const [];
}

class _FakeRaceService extends RaceService {
  final Set<String> configured;

  _FakeRaceService({this.configured = const {}});

  @override
  Future<bool> isProviderConfigured(String provider) async =>
      configured.contains(provider);

  @override
  Future<bool> isParkrunConfigured() async => configured.contains('parkrun');
}

Future<void> _pump(WidgetTester tester, {Set<String> configured = const {}}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = Preferences();
  await prefs.init();
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: SettingsIntegrationsScreen(
        apiClient: _FakeApi(),
        heartRate: BleHeartRate(),
        treadmill: BleTreadmill(),
        preferences: prefs,
        raceService: _FakeRaceService(configured: configured),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

const _allProviders = {'runsignup', 'ultrasignup', 'chronotrack'};

void main() {
  testWidgets('every configured import provider gets a tile that links to the race calendar',
      (tester) async {
    await _pump(tester, configured: _allProviders);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    final labels = raceProviderLabels(l10n);

    for (final spec in raceImportProviders) {
      final row = labels[spec.provider];
      expect(row, isNotNull,
          reason: '${spec.provider} has no name, so its tile cannot be built');
      final tile =
          tester.widget<ListTile>(find.widgetWithText(ListTile, row!.name));
      expect(tile.onTap, isNotNull, reason: '${row.name} must stay tappable');
    }
    expect(find.text(l10n.integrationsRunsignupOpen),
        findsNWidgets(raceImportProviders.length));
  });

  testWidgets('a provider whose import leg this deployment cannot run gets no tile',
      (tester) async {
    // Each tile used to render whatever its probe said, carrying the explainer
    // where its action would be, on the reasoning that the tap is a secondary
    // deep link into the calendar (decisions § 488). What the tile advertises
    // is THAT provider's import, and the calendar has its own entry point on
    // the fitness hub — so the offer had nothing behind it (§ 488 amendment).
    await _pump(tester);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    for (final row in raceProviderLabels(l10n).values) {
      expect(find.text(row.name), findsNothing, reason: row.name);
    }
    expect(find.text(l10n.integrationsRunsignupUnavailable), findsNothing);
    expect(find.text(l10n.integrationsRunsignupOpen), findsNothing);
  });

  testWidgets('every offered tile carries an info tip that explains the feature',
      (tester) async {
    // A new runner does not know what a bib number is for, let alone which
    // timing company ran their race.
    await _pump(tester, configured: _allProviders);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    expect(find.byTooltip(l10n.integrationsInfoAbout(l10n.integrationsRunsignup)),
        findsOneWidget);
    expect(find.text(l10n.integrationsRunsignupInfo), findsNothing);

    await tester.tap(
        find.byTooltip(l10n.integrationsInfoAbout(l10n.integrationsRunsignup)));
    await tester.pumpAndSettle();
    expect(find.text(l10n.integrationsRunsignupInfo), findsOneWidget);
  });

  testWidgets('tapping the RunSignUp tile opens the race calendar',
      (tester) async {
    await _pump(tester, configured: _allProviders);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await tester.tap(find.text(l10n.integrationsRunsignup));
    await tester.pumpAndSettle();
    expect(find.byType(RacesScreen), findsOneWidget);
  });

  testWidgets('tapping the UltraSignup tile opens the race calendar',
      (tester) async {
    await _pump(tester, configured: _allProviders);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await tester.tap(find.text(l10n.integrationsUltrasignup));
    await tester.pumpAndSettle();
    expect(find.byType(RacesScreen), findsOneWidget);
  });

  testWidgets('each tile answers its own probe, never a peer provider\'s',
      (tester) async {
    // UltraSignup has its own credential pair, so a provisioned RunSignUp key
    // must not put an UltraSignup tile on the screen.
    await _pump(tester, configured: const {'runsignup'});
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    expect(find.text(l10n.integrationsRunsignupConnect), findsOneWidget);
    expect(find.text(l10n.integrationsUltrasignup), findsNothing);
    expect(find.text(l10n.integrationsChronotrack), findsNothing);
  });

  testWidgets('a configured UltraSignup tile says the import leg is live',
      (tester) async {
    await _pump(tester, configured: const {'ultrasignup'});
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    expect(find.text(l10n.integrationsUltrasignupConnect), findsOneWidget);
    expect(find.text(l10n.integrationsUltrasignupUnavailable), findsNothing);
  });
}

// The Preferences offline notice is catalogue copy, and a failed settings load
// never puts the exception's own text on the screen. The service used to keep
// a hardcoded English sentence for the notice and `e.toString()` for a failed
// load in one `lastError` string the screen rendered.

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/preferences.dart';
import '../lib/screens/settings_preferences_screen.dart';
import '../lib/settings_sync.dart';
import 'pump_until.dart';

class _FakeSettingsService implements SettingsService {
  _FakeSettingsService({required this.serverHydrated});

  final bool serverHydrated;

  @override
  Map<String, dynamic> get universal => const <String, dynamic>{};
  @override
  Map<String, dynamic> get device => const <String, dynamic>{};
  @override
  bool get isServerHydrated => serverHydrated;
  @override
  T? effective<T>(String key, {T? fallback}) => fallback;
  @override
  Future<void> updateUniversal(Map<String, dynamic> changes) async {}
  @override
  Future<void> updateDevice(Map<String, dynamic> changes) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<Preferences> _prefs() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = Preferences();
  await prefs.init();
  return prefs;
}

Future<void> _pump(
  WidgetTester tester,
  Preferences prefs,
  SettingsSyncService sync,
  Locale locale,
) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: SettingsPreferencesScreen(page: PreferencesPage.display, preferences: prefs, settingsSync: sync),
    ),
  );
  // The sync settled before the pump; what is left is the locale's catalogue
  // load, and the screen is ready once its title reads in that locale.
  final title =
      (await AppLocalizations.delegate.load(locale)).prefsPageDisplay;
  await pumpUntil(tester, () => find.text(title).evaluate().isNotEmpty,
      describe: 'the preferences screen to build in $locale');
}

void main() {
  setUp(initializeDateFormatting);

  testWidgets('a cache-served load shows the localized offline notice',
      (tester) async {
    final prefs = await _prefs();
    final sync = SettingsSyncService(
      preferences: prefs,
      serviceLoader: () async => _FakeSettingsService(serverHydrated: false),
      timeZoneReader: () async => null,
    );
    await tester.runAsync(sync.onSignedIn);
    const de = Locale('de');
    await _pump(tester, prefs, sync, de);

    final l10n = await AppLocalizations.delegate.load(de);
    expect(find.text(l10n.prefsOfflineNotice), findsOneWidget);
    expect(find.byIcon(Icons.cloud_off), findsOneWidget);
  });

  testWidgets('a failed load shows no notice and none of the exception text',
      (tester) async {
    final prefs = await _prefs();
    final sync = SettingsSyncService(
      preferences: prefs,
      serviceLoader: () async =>
          throw Exception('PostgrestException(code: 42501, details: x)'),
      timeZoneReader: () async => null,
    );
    await tester.runAsync(sync.onSignedIn);
    await _pump(tester, prefs, sync, const Locale('en'));

    expect(sync.synced, isFalse);
    expect(find.byIcon(Icons.cloud_off), findsNothing);
    expect(find.textContaining('PostgrestException'), findsNothing);
  });
}

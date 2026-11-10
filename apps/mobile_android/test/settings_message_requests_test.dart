import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/preferences.dart';
import '../lib/screens/settings_preferences_screen.dart';

/// The message-requests switch (issue #1216) is `user_settings.dm_requests`,
/// a column the INSERT policy reads (migration 20271213121601), so it is read
/// and written through the api rather than the settings bag.
class _FakeApi extends ApiClient {
  _FakeApi({this.stored = true, this.failWrite = false});

  final bool stored;
  final bool failWrite;
  final List<bool> writes = [];

  @override
  String? get userId => 'u1';

  @override
  Future<UserProfileRow?> fetchMyProfile() async => null;

  @override
  Future<bool> fetchMyProfilePrivate() async => false;

  @override
  Future<bool> fetchMyDmReadReceipts() async => true;

  @override
  Future<bool> fetchMyDmRequests() async => stored;

  @override
  Future<void> setDmRequests(bool on) async {
    writes.add(on);
    if (failWrite) throw StateError('refused');
  }
}

Future<Preferences> _prefs() async {
  SharedPreferences.setMockInitialValues({});
  final p = Preferences();
  await p.init();
  return p;
}

const _switchKey = Key('prefsMessageRequests');

Future<void> _pumpAndReveal(WidgetTester tester, _FakeApi api) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: SettingsPreferencesScreen(
        apiClient: api,
        preferences: await _prefs(),
        settingsSync: null,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.byKey(_switchKey),
    250,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(find.byKey(_switchKey));
  await tester.pumpAndSettle();
}

bool _switchValue(WidgetTester tester) =>
    tester.widget<SwitchListTile>(find.byKey(_switchKey)).value;

void main() {
  setUp(initializeDateFormatting);

  testWidgets('a runner who turned requests off reads off', (tester) async {
    await _pumpAndReveal(tester, _FakeApi(stored: false));
    expect(_switchValue(tester), isFalse);
  });

  testWidgets('turning requests off writes the column', (tester) async {
    final api = _FakeApi();
    await _pumpAndReveal(tester, api);
    expect(_switchValue(tester), isTrue);

    await tester.tap(find.byKey(_switchKey));
    await tester.pumpAndSettle();

    expect(api.writes, [false]);
    expect(_switchValue(tester), isFalse);
  });

  testWidgets('a refused write rolls the switch back and says so',
      (tester) async {
    final api = _FakeApi(failWrite: true);
    await _pumpAndReveal(tester, api);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    await tester.tap(find.byKey(_switchKey));
    await tester.pump();
    await tester.pump();

    expect(api.writes, [false]);
    expect(_switchValue(tester), isTrue);
    expect(find.text(l10n.prefsMessageRequestsFailed), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
  });
}

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/preferences.dart';
import '../lib/screens/settings_preferences_screen.dart';

/// The private-profile switch (decisions § 1967) is the profile row's
/// `profile_private`, not a prefs key, so it is read and written through the
/// api rather than the settings bag.
class _FakeApi extends ApiClient {
  _FakeApi({this.storedPrivate = false, this.failReads = 0});

  final bool storedPrivate;
  int failReads;
  final List<bool> writes = [];

  @override
  String? get userId => 'u1';

  @override
  Future<UserProfileRow?> fetchMyProfile() async => null;

  @override
  Future<bool> fetchMyProfilePrivate() async {
    if (failReads > 0) {
      failReads--;
      throw Exception('network down');
    }
    return storedPrivate;
  }

  @override
  Future<void> setProfilePrivate(bool value) async => writes.add(value);

  @override
  Future<List<IncomingFollowRequest>> fetchIncomingFollowRequests() async =>
      const [];
}

Future<Preferences> _prefs() async {
  SharedPreferences.setMockInitialValues({});
  final p = Preferences();
  await p.init();
  return p;
}

const _switchKey = ValueKey('prefs-private-profile');
const _requestsKey = ValueKey('prefs-follow-requests');

Future<void> _pumpAndReveal(WidgetTester tester, _FakeApi api) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: SettingsPreferencesScreen(
        page: PreferencesPage.privacy,
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

  testWidgets('a private profile reads on, with the follow requests row',
      (tester) async {
    await _pumpAndReveal(tester, _FakeApi(storedPrivate: true));

    expect(_switchValue(tester), isTrue);
    expect(find.byKey(_requestsKey), findsOneWidget);
  });

  testWidgets(
      'turning it on writes profile_private and reveals the follow requests '
      'row', (tester) async {
    final api = _FakeApi();
    await _pumpAndReveal(tester, api);
    expect(_switchValue(tester), isFalse);
    expect(find.byKey(_requestsKey), findsNothing);

    await tester.tap(find.byKey(_switchKey));
    await tester.pumpAndSettle();

    expect(api.writes, [true]);
    expect(_switchValue(tester), isTrue);
    expect(find.byKey(_requestsKey), findsOneWidget);
  });

  testWidgets('the follow requests row opens the requests screen',
      (tester) async {
    await _pumpAndReveal(tester, _FakeApi(storedPrivate: true));

    await tester.ensureVisible(find.byKey(_requestsKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_requestsKey));
    // Not pumpAndSettle: the requests screen opens on a shimmering skeleton.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byKey(const ValueKey('follow-requests-empty')), findsOneWidget);
  });

  // Issue #1374 FS-6: a failed read left the switch OFF and interactive, so a
  // private runner on a flaky connection read their activity as public.
  testWidgets('a failed read shows a retry row, not a guessed OFF switch',
      (tester) async {
    final api = _FakeApi(storedPrivate: true, failReads: 1);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SettingsPreferencesScreen(
          page: PreferencesPage.privacy,
          apiClient: api,
          preferences: await _prefs(),
          settingsSync: null,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(
        tester.element(find.byType(SettingsPreferencesScreen)));
    final title = find.text(l10n.prefsPrivateProfile);
    await tester.scrollUntilVisible(title, 250,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();

    expect(find.byKey(_switchKey), findsNothing);
    final retryRow = find.ancestor(of: title, matching: find.byType(ListTile));
    expect(
        find.descendant(
            of: retryRow, matching: find.text(l10n.asyncSwitchLoadFailed)),
        findsOneWidget);

    await tester.tap(retryRow);
    await tester.pumpAndSettle();
    expect(_switchValue(tester), isTrue);
    expect(find.byKey(_requestsKey), findsOneWidget);
    expect(api.writes, isEmpty);
  });
}

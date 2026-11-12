// The Preferences switch that hides Grisnir writes the universal
// `show_mascot` pref, and `mascotShown()` reads it the way web does: only a
// literal `false` hides him (#1360).

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' show UserProfileRow;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/mascot.dart';
import '../lib/preferences.dart';
import '../lib/screens/settings_preferences_screen.dart';
import '../lib/settings_sync.dart';

class _Sync extends SettingsSyncService {
  _Sync(Preferences prefs, this._service) : super(preferences: prefs);

  final SettingsService? _service;
  final List<Map<String, dynamic>> universalWrites = [];

  @override
  bool get synced => true;

  @override
  SettingsService? get service => _service;

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

class _Service extends SettingsService {
  _Service(this.values) : super(deviceId: 'test-device', platform: 'android');
  final Map<String, dynamic> values;

  @override
  T? effective<T>(String key, {T? fallback}) =>
      values.containsKey(key) ? values[key] as T? : fallback;
}

void main() {
  setUp(initializeDateFormatting);
  tearDown(() => registerActiveSettingsSync(null));

  testWidgets('the Preferences switch turns Grisnir off in the universal bag',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = Preferences();
    await prefs.init();
    final sync = _Sync(prefs, null);
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
      find.byKey(const Key('prefsShowMascot')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    final row =
        tester.widget<SwitchListTile>(find.byKey(const Key('prefsShowMascot')));
    expect(row.value, isTrue, reason: 'on by default');
    await tester.tap(find.byKey(const Key('prefsShowMascot')));
    await tester.pumpAndSettle();
    expect(sync.universalWrites, [
      {'show_mascot': false}
    ]);
  });

  test('mascotShown hides him only for a literal false', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = Preferences();
    await prefs.init();
    expect(mascotShown(), isTrue, reason: 'no settings loaded yet');
    for (final (value, shown) in [
      (null, true),
      (true, true),
      ('false', true),
      (false, false),
    ]) {
      registerActiveSettingsSync(
          _Sync(prefs, _Service({'show_mascot': ?value})));
      expect(mascotShown(), shown, reason: 'show_mascot = $value');
    }
  });
}

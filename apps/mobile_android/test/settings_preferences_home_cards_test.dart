// Settings → Preferences "Home cards" (#1187, decisions § 2386): where a trend
// group hidden from Home comes back, through the universal
// `dashboard_hidden_cards` key. Web twin: the Home section of
// `/settings/display`.

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/dashboard_layout.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/preferences.dart';
import '../lib/screens/settings_preferences_screen.dart';
import '../lib/settings_sync.dart';

class _Service extends SettingsService {
  _Service(this._values) : super(deviceId: 'test-device', platform: 'android');
  final Map<String, dynamic> _values;

  @override
  T? effective<T>(String key, {T? fallback}) =>
      _values.containsKey(key) ? _values[key] as T? : fallback;
}

class _Sync extends SettingsSyncService {
  _Sync(Preferences prefs, this._service) : super(preferences: prefs);
  final SettingsService _service;
  final List<Map<String, dynamic>> pushed = [];

  List<Object?> get hiddenWrites => [
        for (final w in pushed)
          if (w.containsKey(kDashboardHiddenCardsKey))
            w[kDashboardHiddenCardsKey],
      ];

  @override
  bool get synced => true;

  @override
  SettingsService? get service => _service;

  @override
  Future<void> updateUniversal(Map<String, dynamic> values) async {
    pushed.add(values);
  }
}

const _tileKey = Key('prefsHomeCards');

Future<_Sync> _open(WidgetTester tester, Map<String, dynamic> bag) async {
  final prefs = Preferences();
  await tester.runAsync(prefs.init);
  final sync = _Sync(prefs, _Service(bag));
  tester.view.physicalSize = const Size(400, 8000) * 2;
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: SettingsPreferencesScreen(preferences: prefs, settingsSync: sync),
  ));
  await tester.pumpAndSettle();
  final tile = find.byKey(_tileKey);
  await tester.scrollUntilVisible(tile, 300,
      scrollable: find.byType(Scrollable).first);
  await tester.ensureVisible(tile);
  await tester.pumpAndSettle();
  await tester.tap(tile);
  await tester.pumpAndSettle();
  return sync;
}

bool _checked(WidgetTester tester, String id) =>
    tester.widget<CheckboxListTile>(find.byKey(Key('prefsHomeCard-$id'))).value ==
    true;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('a hidden group reads unticked and ticking it brings it back',
      (tester) async {
    final sync = await _open(tester, {
      kDashboardHiddenCardsKey: ['volume', 'recent'],
    });
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(_checked(tester, 'volume'), isFalse);
    expect(_checked(tester, 'recent'), isFalse);
    expect(_checked(tester, 'fitness'), isTrue);

    await tester.tap(find.byKey(const Key('prefsHomeCard-volume')));
    await tester.pumpAndSettle();
    expect(_checked(tester, 'volume'), isTrue);
    expect(sync.hiddenWrites.last, ['recent']);
  });

  testWidgets('unticking a group hides it, in Home order', (tester) async {
    final sync = await _open(tester, {
      kDashboardHiddenCardsKey: ['recent'],
    });
    await tester.tap(find.byKey(const Key('prefsHomeCard-effort')));
    await tester.pumpAndSettle();
    expect(sync.hiddenWrites.last, ['effort', 'recent']);
  });

  testWidgets('a malformed bag shows every group', (tester) async {
    await _open(tester, {kDashboardHiddenCardsKey: 'volume'});
    for (final id in hideableDashboardCards) {
      expect(_checked(tester, id), isTrue, reason: id);
    }
  });
}

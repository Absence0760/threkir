// The park course month-close notice's mute (`notify_park_course_month`,
// issue #1343) is a universal setting on Notifications. These pin the phone
// end: the switch reads on when nothing is stored, off only for the literal
// 'off', and a tap writes the opposite to the universal bag.

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/preferences.dart';
import '../lib/screens/settings_preferences_screen.dart';
import '../lib/settings_sync.dart';
import 'worst_case_layout.dart';

class _FakeSettingsService extends SettingsService {
  _FakeSettingsService(this._values)
      : super(deviceId: 'test-device', platform: 'android');

  final Map<String, dynamic> _values;

  @override
  T? effective<T>(String key, {T? fallback}) =>
      _values.containsKey(key) ? _values[key] as T? : fallback;
}

class _FakeSettingsSync extends SettingsSyncService {
  _FakeSettingsSync(Preferences prefs, this._service)
      : super(preferences: prefs);

  final SettingsService? _service;
  final List<Map<String, dynamic>> pushed = [];

  List<Object?> get muteWrites => [
        for (final w in pushed)
          if (w.containsKey(SettingsKeys.notifyParkCourseMonth))
            w[SettingsKeys.notifyParkCourseMonth],
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

const _switch = Key('prefs-notify-park-course-month');

Future<_FakeSettingsSync> _pump(
  WidgetTester tester,
  Map<String, dynamic> bag,
) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = Preferences();
  await prefs.init();
  final sync = _FakeSettingsSync(prefs, _FakeSettingsService(bag));
  tester.view.physicalSize = const Size(400, 8000) * 2;
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: SettingsPreferencesScreen(
        page: PreferencesPage.notifications,
        preferences: prefs,
        settingsSync: sync,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(find.byKey(_switch), 300,
      scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
  return sync;
}

bool _on(WidgetTester tester) => tester
    .widget<SwitchListTile>(find.descendant(
        of: find.byKey(_switch), matching: find.byType(SwitchListTile)))
    .value;

void main() {
  worstCaseTestWidgets('the Notifications page with the Park course months '
      'switch', (tester, locale) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = Preferences();
    await prefs.init();
    final sync = _FakeSettingsSync(prefs, _FakeSettingsService(const {}));
    await tester.pumpWidget(worstCaseApp(
      locale: locale,
      home: SettingsPreferencesScreen(
        page: PreferencesPage.notifications,
        preferences: prefs,
        settingsSync: sync,
      ),
    ));
    await tester.pumpAndSettle();
    await walkScrollable(tester, primaryScrollable(), 'Notifications');
  }, layoutOnly: true);

  testWidgets('with nothing stored the switch is on, and a tap mutes it', (
    tester,
  ) async {
    final sync = await _pump(tester, <String, dynamic>{});
    expect(find.text('Park course months'), findsOneWidget);
    expect(_on(tester), isTrue);
    await tester.tap(find.byKey(_switch));
    await tester.pumpAndSettle();
    expect(sync.muteWrites, ['off']);
  });

  testWidgets('a stored off reads off, and a tap turns it back on', (
    tester,
  ) async {
    final sync = await _pump(
      tester,
      <String, dynamic>{SettingsKeys.notifyParkCourseMonth: 'off'},
    );
    expect(_on(tester), isFalse);
    await tester.tap(find.byKey(_switch));
    await tester.pumpAndSettle();
    expect(sync.muteWrites, ['on']);
  });
}

// Where the AI Coach sits in Messages is a universal setting
// (`messages_coach_row`, decisions § 2227). These pin the Preferences end:
// the tile reads the stored placement, falls back to pinned when nothing is
// stored, and a pick writes the placement's name to the universal bag.

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/preferences.dart';
import '../lib/screens/settings_preferences_screen.dart';
import '../lib/settings_sync.dart';

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

  /// Only the writes this tile owns; the screen also stamps `locale` on mount.
  List<Map<String, dynamic>> get coachRowWrites => [
        for (final w in pushed)
          if (w.containsKey(SettingsKeys.messagesCoachRow)) w,
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

Future<_FakeSettingsSync> _pumpPreferences(
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
      home: SettingsPreferencesScreen(preferences: prefs, settingsSync: sync),
    ),
  );
  await tester.pumpAndSettle();
  final tile = find.byKey(const Key('prefsCoachInMessages'));
  await tester.scrollUntilVisible(tile, 300,
      scrollable: find.byType(Scrollable).first);
  await tester.ensureVisible(tile);
  await tester.pumpAndSettle();
  return sync;
}

void main() {
  testWidgets('with nothing stored the tile reads pinned', (tester) async {
    await _pumpPreferences(tester, <String, dynamic>{});
    final tile = find.byKey(const Key('prefsCoachInMessages'));
    expect(
      find.descendant(of: tile, matching: find.text('Pinned at the top')),
      findsOneWidget,
    );
  });

  testWidgets('the tile reads the stored placement', (tester) async {
    await _pumpPreferences(
        tester, <String, dynamic>{SettingsKeys.messagesCoachRow: 'listed'});
    final tile = find.byKey(const Key('prefsCoachInMessages'));
    expect(
      find.descendant(of: tile, matching: find.text('With your conversations')),
      findsOneWidget,
    );
  });

  testWidgets('picking a placement writes its name to the universal bag',
      (tester) async {
    final sync = await _pumpPreferences(tester, <String, dynamic>{});
    await tester.tap(find.byKey(const Key('prefsCoachInMessages')));
    await tester.pumpAndSettle();
    expect(find.byType(SimpleDialog), findsOneWidget);
    await tester.tap(find.descendant(
      of: find.byType(SimpleDialog),
      matching: find.text('Hidden'),
    ));
    await tester.pumpAndSettle();
    expect(sync.coachRowWrites, [
      {SettingsKeys.messagesCoachRow: 'hidden'},
    ]);
  });

  testWidgets('dismissing the picker writes nothing', (tester) async {
    final sync = await _pumpPreferences(tester, <String, dynamic>{});
    await tester.tap(find.byKey(const Key('prefsCoachInMessages')));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.byType(SimpleDialog), findsNothing);
    expect(sync.coachRowWrites, isEmpty);
  });
}

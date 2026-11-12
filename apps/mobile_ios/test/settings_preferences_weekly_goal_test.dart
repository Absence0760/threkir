// The weekly distance goal is stored in metres and asked for in the runner's
// own unit (issue #902 § 5). These pin the editor end of `weekly_goal.dart`:
// the tile and the dialog read in km or mi, a typed goal lands in metres, and
// saving the figure the dialog already shows does not move a goal nobody
// edited.

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
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

  @override
  bool get synced => true;

  @override
  SettingsService? get service => _service;

  @override
  Future<void> updateUniversal(Map<String, dynamic> values) async {
    pushed.add(values);
  }
}

Future<_FakeSettingsSync> _openGoalDialog(
  WidgetTester tester, {
  required bool useMiles,
  required Map<String, dynamic> bag,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = Preferences();
  await prefs.init();
  await prefs.setUseMiles(useMiles);
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

  final row = find.widgetWithText(ListTile, 'Weekly distance goal');
  await tester.scrollUntilVisible(row, 300,
      scrollable: find.byType(Scrollable).first);
  await tester.ensureVisible(row);
  await tester.pumpAndSettle();
  await tester.tap(row);
  await tester.pumpAndSettle();
  expect(find.byType(AlertDialog), findsOneWidget);
  return sync;
}

void main() {
  setUp(initializeDateFormatting);

  testWidgets('a miles runner reads the stored goal in miles', (tester) async {
    await _openGoalDialog(
      tester,
      useMiles: true,
      bag: <String, dynamic>{'weekly_mileage_goal_m': 50000},
    );

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, '31.1');
    expect(find.text('mi'), findsOneWidget);
  });

  testWidgets('saving the goal the dialog shows keeps the stored metres',
      (tester) async {
    final sync = await _openGoalDialog(
      tester,
      useMiles: true,
      bag: <String, dynamic>{'weekly_mileage_goal_m': 50000},
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(sync.pushed.last, <String, dynamic>{'weekly_mileage_goal_m': 50000});
  });

  testWidgets('a goal typed in kilometres is stored in metres', (tester) async {
    final sync = await _openGoalDialog(
      tester,
      useMiles: false,
      bag: <String, dynamic>{},
    );

    await tester.enterText(find.byType(TextField), '42.2');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(sync.pushed.last, <String, dynamic>{'weekly_mileage_goal_m': 42200});
  });
}

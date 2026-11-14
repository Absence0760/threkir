// ignore_for_file: avoid_relative_lib_imports
// The heart-rate zones dialog holds five fields, stacked by FieldColumn so
// each floating label clears the field above. At 2x text on a 320 dp phone
// five fields and three actions are taller than the screen, so the dialog
// scrolls rather than pushing Save under the nav bar.

import 'package:api_client/api_client.dart' show SettingsService;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ui_kit/ui_kit.dart' show FieldColumn, ListRow;

import '../lib/preferences.dart';
import '../lib/screens/settings_preferences_screen.dart';
import '../lib/settings_sync.dart';
import 'three_button_nav_bar.dart';
import 'worst_case_layout.dart';

class _SettingsService extends SettingsService {
  _SettingsService() : super(deviceId: 'test-device', platform: 'android');

  @override
  T? effective<T>(String key, {T? fallback}) => fallback;
}

class _SettingsSync extends SettingsSyncService {
  _SettingsSync(Preferences prefs) : super(preferences: prefs);

  final _service = _SettingsService();

  @override
  bool get synced => true;

  @override
  SettingsService? get service => _service;

  @override
  Future<void> updateUniversal(Map<String, dynamic> values) async {}
}

void main() {
  setUp(initializeDateFormatting);

  worstCaseTestWidgets('Heart-rate zones dialog', (tester, locale) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = Preferences();
    await tester.runAsync(prefs.init);
    await tester.pumpWidget(worstCaseApp(
      locale: locale,
      home: SettingsPreferencesScreen(
          page: PreferencesPage.training,
          preferences: prefs,
          settingsSync: _SettingsSync(prefs)),
    ));
    await tester.pumpAndSettle();
    final l10n = l10nFor(locale);
    // The row, not the section header, which says the same in some locales.
    final row = find.widgetWithText(ListRow, l10n.prefsHrZones);
    await tester.scrollUntilVisible(row, 200,
        scrollable: find
            .byWidgetPredicate((w) =>
                w is Scrollable && w.axisDirection == AxisDirection.down)
            .last);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(FieldColumn), matching: find.byType(TextField)),
        findsNWidgets(5));
    final save = find.widgetWithText(FilledButton, l10n.prefsSave);
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    expectAboveNavBar(tester, save);
  });
}

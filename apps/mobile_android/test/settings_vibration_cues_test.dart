// Widget tests for the "Vibration cues" tile on settings_preferences_screen
// (issue #1186): on by default, toggling it flips the per-device pref, and
// it stays reachable with the voice master off — vibration is the cue
// channel for a runner who has turned the audio off.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/preferences.dart';
import '../lib/screens/settings_preferences_screen.dart';

const _title = 'Vibration cues';

Future<Preferences> _pump(
  WidgetTester tester,
  Map<String, Object> stored,
) async {
  SharedPreferences.setMockInitialValues(stored);
  final prefs = Preferences();
  await prefs.init();
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: SettingsPreferencesScreen(preferences: prefs, settingsSync: null),
    ),
  );
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.text(_title),
    250,
    scrollable: find.byType(Scrollable).first,
  );
  return prefs;
}

SwitchListTile _tile() => find
    .widgetWithText(SwitchListTile, _title)
    .evaluate()
    .single
    .widget as SwitchListTile;

void main() {
  setUp(() async {
    await initializeDateFormatting();
  });

  testWidgets('is on by default and toggles the per-device pref',
      (tester) async {
    final prefs = await _pump(tester, {});
    expect(_tile().value, isTrue);
    expect(prefs.hapticFeedback, isTrue);

    await tester.tap(find.text(_title));
    await tester.pumpAndSettle();
    expect(prefs.hapticFeedback, isFalse);

    final reloaded = Preferences();
    await reloaded.init();
    expect(reloaded.hapticFeedback, isFalse,
        reason: 'the choice must survive a relaunch');
  });

  testWidgets('stays available with the voice cues turned off',
      (tester) async {
    await _pump(tester, {'audio_cues': false});
    expect(_tile().onChanged, isNotNull);
  });

  test('sign-out puts it back on — it mirrors a per-account device bag',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = Preferences();
    await prefs.init();
    await prefs.setHapticFeedback(false);
    await prefs.resetAccountScopedPrefs();
    expect(prefs.hapticFeedback, isTrue);
  });
}

// Settings → Preferences → Default run privacy wrote the pick to the universal
// bag and nowhere else. Every reader of the value reads the LOCAL mirror —
// `Preferences.newRunsArePublic` on the phone's own run save, and the Apple
// Watch settings push the mirror's setter makes — and the mirror is only
// overlaid from the bag at sign-in, so a runner who chose "Public" kept
// saving private runs until they next signed in. The activity-type editor on
// the same screen already wrote both; this pins the privacy one to match.

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/preferences.dart';
import '../lib/screens/settings_preferences_screen.dart';
import '../lib/settings_sync.dart';

class _FakeSettingsSync extends SettingsSyncService {
  _FakeSettingsSync(Preferences prefs) : super(preferences: prefs);

  final List<Map<String, dynamic>> universalWrites = [];

  @override
  bool get synced => true;

  @override
  SettingsService? get service => null;

  @override
  Future<void> updateUniversal(Map<String, dynamic> changes) async {
    universalWrites.add(changes);
    notifyListeners();
  }
}

void main() {
  setUp(() async {
    await initializeDateFormatting();
  });

  testWidgets('picking a default privacy writes the local mirror AND the bag',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = Preferences();
    await prefs.init();
    final sync = _FakeSettingsSync(prefs);
    expect(prefs.newRunsArePublic, isFalse);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SettingsPreferencesScreen(preferences: prefs, settingsSync: sync),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Default run privacy'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Default run privacy'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(RadioListTile<String>, 'Public'));
    await tester.pumpAndSettle();

    expect(
      sync.universalWrites,
      contains(containsPair(SettingsKeys.privacyDefault, 'public')),
    );
    expect(prefs.privacyDefault, 'public');
    expect(prefs.newRunsArePublic, isTrue);
  });
}

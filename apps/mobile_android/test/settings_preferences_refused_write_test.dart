import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/preferences.dart';
import '../lib/screens/settings_preferences_screen.dart';
import '../lib/settings_sync.dart';

/// A bag write the server refuses is undone by `SettingsService` and
/// rethrown; the Preferences screen must tell the runner rather than leave a
/// change that never saved looking saved (decisions § 2542). A throw that is
/// not a refusal (no session, an unloadable bag) stays in the log.
class _FailingSettingsSync extends SettingsSyncService {
  _FailingSettingsSync(Preferences prefs, this.error) : super(preferences: prefs);

  final Object error;
  int writes = 0;

  @override
  bool get synced => true;

  @override
  Future<void> updateUniversal(Map<String, dynamic> changes) async {
    writes++;
    throw error;
  }
}

const _title = "Today's workout";
const _refused = "Couldn't save that setting.";

Future<_FailingSettingsSync> _pump(WidgetTester tester, Object error) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = Preferences();
  await prefs.init();
  final sync = _FailingSettingsSync(prefs, error);
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
  await tester.scrollUntilVisible(
    find.text(_title),
    250,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(find.widgetWithText(SwitchListTile, _title));
  await tester.pumpAndSettle();
  return sync;
}

void main() {
  setUp(() async {
    await initializeDateFormatting();
  });

  testWidgets('a refused write is reported to the runner', (tester) async {
    final sync = await _pump(
      tester,
      const PostgrestException(message: 'denied', code: '42501'),
    );
    await tester.tap(find.widgetWithText(SwitchListTile, _title));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(sync.writes, 1);
    expect(find.text(_refused), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('a failure that is not a refusal shows no banner',
      (tester) async {
    final sync = await _pump(tester, StateError('settings not loaded'));
    await tester.tap(find.widgetWithText(SwitchListTile, _title));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(sync.writes, 1);
    expect(find.text(_refused), findsNothing);
    await tester.pump(const Duration(seconds: 10));
  });
}

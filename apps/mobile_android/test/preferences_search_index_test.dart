// You's settings search finds a Preferences row without opening its page, so
// it reads `PreferencesRow`, a list beside the page builders, and a result
// opens the page landed on the row by its id (`SettingsAnchor`). These keep
// the list and the pages in step: every row a page draws carries an id from
// its page's list under its own title, and every listed id is drawn by a
// default mount or named here as gated, with the gate.

import 'package:api_client/api_client.dart' show SettingsService;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ui_kit/ui_kit.dart' show ListRow, SettingsAnchor;

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/preferences.dart';
import '../lib/screens/settings_preferences_screen.dart';
import '../lib/settings_sync.dart';
import '../lib/widgets/async_switch_tile.dart';

class _SyncedNoBag extends SettingsSyncService {
  _SyncedNoBag(Preferences prefs) : super(preferences: prefs);

  @override
  bool get synced => true;

  @override
  SettingsService? get service => null;
}

/// Rows a default mount (no API, no stores, nearby gate off, medication
/// unset) cannot show, each with what shows it.
const Map<PreferencesRow, String> _gated = {
  PreferencesRow.showGym: 'the Gym and Nutrition stores',
  PreferencesRow.showNutrition: 'the Gym and Nutrition stores',
  PreferencesRow.hrMedicationSetMaxHr: 'medication on with no max HR',
  PreferencesRow.privateProfile: 'an ApiClient',
  PreferencesRow.followRequests: 'an ApiClient and a private profile',
  PreferencesRow.discoverableNearby: 'the nearby deploy gate',
  PreferencesRow.nearbyArea: 'the nearby deploy gate and an ApiClient',
  PreferencesRow.readReceipts: 'an ApiClient',
  PreferencesRow.messageRequests: 'an ApiClient',
};

typedef _Drawn = ({
  List<SettingsAnchor> anchors,
  List<(String title, String? anchor)> rows,
});

Future<_Drawn> _drawn(WidgetTester tester, PreferencesPage page) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = Preferences();
  await prefs.init();
  tester.view.physicalSize = const Size(400, 12000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: SettingsPreferencesScreen(
        page: page,
        preferences: prefs,
        settingsSync: _SyncedNoBag(prefs),
        hrPrescription: true,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (
    anchors: tester
        .widgetList<SettingsAnchor>(
          find.byType(SettingsAnchor, skipOffstage: false),
        )
        .toList(),
    rows: [
      for (final r in tester.widgetList<ListRow>(
        find.byType(ListRow, skipOffstage: false),
      ))
        (r.title, r.anchor),
      for (final r in tester.widgetList<AsyncSwitchTile>(
        find.byType(AsyncSwitchTile, skipOffstage: false),
      ))
        (r.title, r.anchor),
    ],
  );
}

void main() {
  late AppLocalizations l10n;
  setUpAll(() async {
    await initializeDateFormatting();
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  for (final page in PreferencesPage.values) {
    testWidgets('${page.name}: every row is indexed and every id lands', (
      tester,
    ) async {
      final drawn = await _drawn(tester, page);
      final index = {for (final r in PreferencesRow.on(page)) r.name: r};
      expect(drawn.rows, isNotEmpty);
      expect(
        [
          for (final (title, anchor) in drawn.rows)
            if (anchor == null) title,
        ],
        isEmpty,
        reason:
            'a row with no anchor cannot be searched for or linked to: '
            'add it to PreferencesRow and pass anchor: PreferencesRow.x.name',
      );
      final ids = [for (final a in drawn.anchors) a.id];
      expect(
        ids.toSet(),
        hasLength(ids.length),
        reason: 'an id is drawn twice on one page',
      );
      for (final a in drawn.anchors) {
        final row = index[a.id];
        expect(
          row,
          isNotNull,
          reason: '"${a.id}" is not a ${page.name} row in PreferencesRow',
        );
        expect(
          a.label,
          preferencesRowTitle(l10n, row!),
          reason: '"${a.id}" is drawn under another row\'s title',
        );
      }
      final missing = index.values.where(
        (r) => !ids.contains(r.name) && !_gated.containsKey(r),
      );
      expect(
        missing,
        isEmpty,
        reason:
            'a listed row no mount draws: a search result for it '
            'would land nowhere. Drop it, or name its gate in _gated',
      );
    });
  }

  test('a title belongs to one row, so a result opens one place', () {
    final seen = <String, PreferencesRow>{};
    for (final r in PreferencesRow.values) {
      final t = preferencesRowTitle(l10n, r);
      expect(seen[t], isNull, reason: '"$t" is ${seen[t]} and $r');
      seen[t] = r;
    }
  });
}

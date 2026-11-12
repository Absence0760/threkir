import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_run_store.dart';
import '../lib/screens/import_screen.dart';

late Directory _runsDir;

Future<LocalRunStore> _makeStore() async {
  _runsDir = Directory.systemTemp.createTempSync('import_screen_test_');
  final store = LocalRunStore();
  await store.init(overrideDirectory: _runsDir);
  return store;
}

Future<void> _pump(WidgetTester tester, LocalRunStore runStore) async {
  // Stretch the surface vertically so every Card in the ListView is
  // built + laid out — the default 800x600 viewport puts the lower
  // cards (CSV / Backup-ZIP) just past the offstage cliff so
  // `skipOffstage: false` alone isn't enough for ancestor finders.
  await tester.binding.setSurfaceSize(const Size(800, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ImportScreen(
        apiClient: null,
        runStore: runStore,
      ),
    ),
  );
  await tester.pump();
}

void main() {
  tearDown(() {
    if (_runsDir.existsSync()) _runsDir.deleteSync(recursive: true);
  });

  group('ImportScreen', () {
    testWidgets('renders Import runs app-bar title', (tester) async {
      final store = await _makeStore();
      await _pump(tester, store);
      expect(find.text('Import runs'), findsOneWidget);
    });

    testWidgets('shows Strava import card with heading and description',
        (tester) async {
      final store = await _makeStore();
      await _pump(tester, store);
      expect(find.text('Strava'), findsOneWidget);
      expect(find.textContaining('Strava data export ZIP'), findsOneWidget);
    });

    testWidgets('shows Health Connect import card with heading', (tester) async {
      final store = await _makeStore();
      await _pump(tester, store);
      expect(find.text('Health Connect'), findsOneWidget);
    });

    test('the Settings import tile names only the importers this screen has',
        () {
      // GPX and TCX arrive inside the Strava export ZIP, or as routes from
      // the Routes tab; there is no standalone GPX/TCX run import, so the
      // tile that opens this screen must not promise one in any locale.
      for (final locale in AppLocalizations.supportedLocales) {
        final subtitle =
            lookupAppLocalizations(locale).settingsAccountImportSubtitle;
        expect(subtitle, isNot(contains('GPX')), reason: '$locale');
        expect(subtitle, isNot(contains('TCX')), reason: '$locale');
      }
    });

    testWidgets('the Health Connect card does not deny the map import it offers',
        (tester) async {
      // Health Connect hands over a workout's GPS route when it is allowed
      // to, and the card offers "Allow map import" when it holds one back,
      // so the description must not say routes can never come across.
      final store = await _makeStore();
      await _pump(tester, store);
      expect(find.textContaining('GPS map comes too'), findsOneWidget);
      expect(find.textContaining('not exposed'), findsNothing);
      expect(find.textContaining("won't have a map trace"), findsNothing);
    });

    testWidgets('Import Strava ZIP button is present and enabled', (tester) async {
      final store = await _makeStore();
      await _pump(tester, store);
      final btn = find.widgetWithText(FilledButton, 'Import Strava ZIP');
      expect(btn, findsOneWidget);
      // onPressed must be non-null when _busy == false (i.e., the button is enabled).
      final widget = tester.widget<FilledButton>(btn);
      expect(widget.onPressed, isNotNull);
    });

    testWidgets('Import from Health Connect button is present and enabled',
        (tester) async {
      final store = await _makeStore();
      await _pump(tester, store);
      final btn = find.widgetWithText(FilledButton, 'Import from Health Connect');
      expect(btn, findsOneWidget);
      final widget = tester.widget<FilledButton>(btn);
      expect(widget.onPressed, isNotNull);
    });

    testWidgets('status card is absent before any import is triggered',
        (tester) async {
      final store = await _makeStore();
      await _pump(tester, store);
      // The status card only renders when _busy == true or _status is
      // non-empty — neither holds on initial paint.
      expect(find.byIcon(Icons.check_circle), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('shows CSV import card with the no-GPS caveat',
        (tester) async {
      final store = await _makeStore();
      await _pump(tester, store);
      // CSV + backup-ZIP cards sit below the fold in the default
      // 800x600 test viewport — `skipOffstage: false` reaches into
      // the ListView's off-screen children which are built eagerly
      // (the `children:` constructor, not `.builder`).
      expect(find.text('CSV', skipOffstage: false), findsOneWidget);
      // The body copy must explicitly tell the user CSV is trackless —
      // a CSV that silently produces empty maps would surprise the
      // user the moment they tap a row.
      expect(
        find.textContaining("won't have a route line", skipOffstage: false),
        findsOneWidget,
      );
    });

    testWidgets('Import CSV button is present and enabled', (tester) async {
      final store = await _makeStore();
      await _pump(tester, store);
      final btn = find.widgetWithText(FilledButton, 'Import CSV',
          skipOffstage: false);
      expect(btn, findsOneWidget);
      expect(tester.widget<FilledButton>(btn).onPressed, isNotNull);
    });

    testWidgets('shows Full backup ZIP card with offline-first language',
        (tester) async {
      final store = await _makeStore();
      await _pump(tester, store);
      expect(find.text('Full backup ZIP', skipOffstage: false),
          findsOneWidget);
      // The card must call out that the path works signed-out — the
      // whole reason to surface it on the import screen rather than
      // leave it buried in Settings.
      expect(
        find.textContaining('without signing in', skipOffstage: false),
        findsOneWidget,
      );
    });

    testWidgets('Restore backup ZIP button is present and enabled',
        (tester) async {
      final store = await _makeStore();
      await _pump(tester, store);
      final btn = find.widgetWithText(FilledButton, 'Restore backup ZIP',
          skipOffstage: false);
      expect(btn, findsOneWidget);
      expect(tester.widget<FilledButton>(btn).onPressed, isNotNull);
    });
  });

  group('Platform-aware Health label helpers', () {
    test('healthLabelFor names HealthKit on iOS, Health Connect on Android',
        () {
      final en = lookupAppLocalizations(const Locale('en'));
      expect(healthLabelFor(en, isIOS: true), 'Apple Health');
      expect(healthLabelFor(en, isIOS: false), 'Health Connect');
    });

    test('healthLabelFor uses each vendor\'s own name in the reader\'s locale',
        () {
      // Apple and Google localize these apps' names; the label must follow
      // so the card title matches the copy under it (decisions § 2226).
      String ios(String tag) =>
          healthLabelFor(lookupAppLocalizations(Locale(tag)), isIOS: true);
      String android(String tag) =>
          healthLabelFor(lookupAppLocalizations(Locale(tag)), isIOS: false);
      expect(ios('fr'), 'Apple Santé');
      expect(ios('es'), 'Salud de Apple');
      expect(ios('ja'), 'ヘルスケア');
      expect(ios('de'), 'Apple Health');
      expect(android('fr'), 'Santé Connect');
      expect(android('es'), 'Salud conectada');
      expect(android('ja'), 'ヘルスコネクト');
      expect(android('de'), 'Health Connect');
    });

    test('the health platform names match the run-history source labels', () {
      for (final locale in AppLocalizations.supportedLocales) {
        final l10n = lookupAppLocalizations(locale);
        expect(healthLabelFor(l10n, isIOS: false),
            l10n.historySourceHealthConnect,
            reason: '$locale');
        expect(healthLabelFor(l10n, isIOS: true), l10n.historySourceHealthKit,
            reason: '$locale');
      }
    });
  });

  group('buildImportStatus (#37)', () {
    final l10n = lookupAppLocalizations(const Locale('en'));

    test('Health Connect import appends the no-route note', () {
      final s = buildImportStatus(
        savedCount: 5,
        errorCount: 0,
        label: 'Health Connect',
        noGpsNote: true,
        l10n: l10n,
      );
      expect(s, contains('Imported 5 runs from Health Connect'));
      expect(s, contains('no map'));
    });

    test('non-HC import omits the note; zero-saved omits it too', () {
      expect(
        buildImportStatus(
            savedCount: 3, errorCount: 0, label: 'Strava', l10n: l10n),
        'Imported 3 runs from Strava',
      );
      expect(
        buildImportStatus(
          savedCount: 0,
          errorCount: 0,
          label: 'Health Connect',
          noGpsNote: true,
          l10n: l10n,
        ),
        isNot(contains('no map')),
      );
    });
  });
}

// Preferences was one page of about 65 rows in ten groups (issue #1374
// finding 10); it is now web's five pages, each a `SettingsList` of pinned
// groups. These pin the shape: which groups each page holds and in what
// order, that the eyebrows still pin per group (issue #666 C13), and that
// every page fits a 320 dp phone at 2x text above a 48 dp 3-button bar.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ui_kit/ui_kit.dart' show AppTheme, SectionHeader;

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/preferences.dart';
import '../lib/screens/settings_preferences_screen.dart';
import 'three_button_nav_bar.dart' show kThreeButtonNavBar;

Future<Preferences> _prefs([Map<String, Object> seed = const {}]) async {
  SharedPreferences.setMockInitialValues(seed);
  final prefs = Preferences();
  await prefs.init();
  return prefs;
}

late AppLocalizations _en;

Future<void> _pump(
  WidgetTester tester,
  Preferences prefs, {
  required PreferencesPage page,
  Size size = const Size(400, 800),
  double textScale = 1.0,
  double navBar = 0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  tester.view.viewPadding = FakeViewPadding(bottom: navBar);
  tester.view.padding = FakeViewPadding(bottom: navBar);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: SettingsPreferencesScreen(
        page: page,
        preferences: prefs,
        settingsSync: null,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// A viewport tall enough that the whole lazily-built list is laid out, so
/// order can be read off geometry rather than off scroll position.
const _wholePage = Size(400, 8000);

/// Group eyebrows top to bottom, as laid out.
List<String> _groupLabels(WidgetTester tester) {
  final found = <(double, String)>[];
  for (final e in find.byType(SectionHeader).evaluate()) {
    final box = e.renderObject as RenderBox?;
    if (box == null || !box.attached) continue;
    found.add((
      box.localToGlobal(Offset.zero).dy,
      (e.widget as SectionHeader).label,
    ));
  }
  found.sort((a, b) => a.$1.compareTo(b.$1));
  return [for (final f in found) f.$2];
}

/// SectionHeader renders its label uppercased, so match the widget, not text.
Finder _headerNamed(String label) => find.byWidgetPredicate(
      (w) => w is SectionHeader && w.label == label,
    );

/// Rows in the list. A [SwitchListTile] builds a [ListTile], so counting the
/// latter alone counts each row exactly once.
int _rowCount() => find.byType(ListTile).evaluate().length;

void main() {
  setUpAll(() async {
    await initializeDateFormatting();
    _en = await AppLocalizations.delegate.load(const Locale('en'));
  });

  // Web's groups, in web's order, for a mount with no stores, no API and no
  // settings sync (the rows those add are pinned in their own suites).
  final expected = <PreferencesPage, List<String> Function()>{
    PreferencesPage.display: () => [
          _en.prefsGroupLanguageTheme,
          _en.prefsGroupUnits,
          _en.prefsGroupMapsPages,
          _en.prefsSectionMessages,
        ],
    PreferencesPage.recording: () => [
          _en.prefsSectionActivityRecording,
          _en.prefsGroupVoiceFeedback,
          _en.prefsVoiceCueTypesLabel,
        ],
    PreferencesPage.training: () => [
          _en.prefsGroupWeeklyGoal,
          _en.prefsGroupHeartRate,
          _en.prefsGroupPlans,
          _en.prefsSectionFueling,
          _en.prefsSectionAiCoach,
        ],
    PreferencesPage.privacy: () => [
          _en.prefsGroupYourRuns,
          _en.prefsGroupBeingFound,
          _en.prefsGroupTelemetry,
        ],
    PreferencesPage.notifications: () => [
          _en.prefsGroupEmailPush,
          _en.prefsGroupOptionalEmails,
        ],
  };

  for (final page in PreferencesPage.values) {
    testWidgets('${page.name}: titled, and web\'s groups in web\'s order',
        (tester) async {
      await _pump(tester, await _prefs(), page: page, size: _wholePage);
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text(preferencesPageTitle(_en, page)),
        ),
        findsOneWidget,
      );
      expect(_groupLabels(tester), expected[page]!());

      final headers = tester
          .widgetList<SliverPersistentHeader>(
              find.byType(SliverPersistentHeader))
          .toList();
      // Assert the population, not only the property (decisions § 534): an
      // empty header set would satisfy `every` vacuously.
      expect(headers, hasLength(expected[page]!().length));
      expect(headers.every((h) => h.pinned), isTrue);
    });

    testWidgets(
        '${page.name}: fits 320 dp at 2x text, last row above a 3-button bar',
        (tester) async {
      await _pump(
        tester,
        await _prefs(),
        page: page,
        size: const Size(320, 640),
        textScale: 2.0,
        navBar: kThreeButtonNavBar,
      );
      expect(tester.takeException(), isNull);
      // Drag to the end: the last row must come to rest above the bar, where
      // a tap reaches it rather than Back, Home or Recents.
      for (var i = 0; i < 40; i++) {
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
      final last = find.byType(ListTile).last;
      expect(tester.getRect(last).bottom,
          lessThanOrEqualTo(640 - kThreeButtonNavBar + 0.5));
    });
  }

  testWidgets('no page is the old 65-row scroll', (tester) async {
    for (final page in PreferencesPage.values) {
      await _pump(tester, await _prefs(), page: page, size: _wholePage);
      expect(_rowCount(), lessThanOrEqualTo(24), reason: page.name);
      expect(_rowCount(), greaterThan(0), reason: page.name);
    }
  });

  testWidgets('a group is still named after scrolling deep into a page',
      (tester) async {
    await _pump(tester, await _prefs(), page: PreferencesPage.recording);
    final top = tester.getTopLeft(find.byType(CustomScrollView)).dy;
    List<String> visible() => [
          for (final e in find.byType(SectionHeader).evaluate())
            if ((e.renderObject as RenderBox).localToGlobal(Offset.zero).dy >=
                top - 0.5)
              (e.widget as SectionHeader).label,
        ];
    final atTop = visible();
    expect(atTop, isNotEmpty);
    for (var i = 0; i < 6; i++) {
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
      await tester.pumpAndSettle();
    }
    final deep = visible();
    expect(deep, isNotEmpty,
        reason: 'nothing on screen names the group these rows belong to');
    expect(deep.first, isNot(atTop.first),
        reason: 'the drag did not actually leave the first group');
  });

  testWidgets('the spoken-cues eyebrow does not name the device rows',
      (tester) async {
    // Audio cues default on; the sub-group only exists then.
    await _pump(tester, await _prefs(),
        page: PreferencesPage.recording, size: _wholePage);
    final cueHeader = _headerNamed(_en.prefsVoiceCueTypesLabel);
    expect(cueHeader, findsOneWidget);
    for (final row in [
      _en.prefsKeepScreenOn,
      _en.prefsAdvancedGps,
      _en.prefsShowRawTrack,
    ]) {
      expect(
        tester.getTopLeft(find.text(row)).dy,
        lessThan(tester.getTopLeft(cueHeader).dy),
        reason: '"$row" sits under the spoken-cues label',
      );
    }
  });

  // The split-interval row's subtitle stated "1 km for running, 5 km for
  // cycling" in every locale while the default it describes actually follows
  // the distance preference — `splitIntervalMetresFor` returns 1 mi / 5 mi in
  // imperial, deliberately, so an imperial runner is told when they pass a
  // MILE (decisions § 820).
  testWidgets('the default split interval is described in the runner unit',
      (tester) async {
    await _pump(tester, await _prefs({'use_miles': true}),
        page: PreferencesPage.recording, size: _wholePage);
    expect(find.textContaining('1 mi for running'), findsOneWidget);
    expect(find.textContaining('5 mi for cycling'), findsOneWidget);
    expect(find.textContaining('for running, 5 km'), findsNothing);

    await _pump(tester, await _prefs({'use_miles': false}),
        page: PreferencesPage.recording, size: _wholePage);
    expect(find.textContaining('1 km for running'), findsOneWidget);
    expect(find.textContaining('5 km for cycling'), findsOneWidget);
  });

  testWidgets('turning audio cues off drops the voice-cue group entirely',
      (tester) async {
    await _pump(tester, await _prefs(),
        page: PreferencesPage.recording, size: _wholePage);
    final withCues = _rowCount();
    expect(_headerNamed(_en.prefsVoiceCueTypesLabel), findsOneWidget);

    await _pump(tester, await _prefs({'audio_cues': false}),
        page: PreferencesPage.recording, size: _wholePage);
    expect(_headerNamed(_en.prefsVoiceCueTypesLabel), findsNothing);
    expect(_rowCount(), lessThan(withCues));
  });

  testWidgets('the error-reports switch is on Privacy & sharing',
      (tester) async {
    final prefs = await _prefs();
    await _pump(tester, prefs,
        page: PreferencesPage.privacy, size: _wholePage);
    final row = find.byKey(const ValueKey('prefs-error-reports'));
    expect(row, findsOneWidget);
    expect(prefs.sentryOptOut, isFalse);
    await tester.tap(row);
    await tester.pump();
    expect(prefs.sentryOptOut, isTrue);
    // Let the confirmation banner's dismiss timer run out.
    await tester.pump(const Duration(seconds: 10));
  });
}

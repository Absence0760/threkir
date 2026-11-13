import 'dart:io';

import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ui_kit/ui_kit.dart' show EmptyState, PageHeader;
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_route_store.dart';
import '../lib/local_run_store.dart';
import '../lib/preferences.dart';
import '../lib/screens/period_summary_screen.dart';
import '../lib/widgets/activity_heatmap.dart';
import '../lib/widgets/this_week_strip.dart';
import 'pump_until.dart';
import 'worst_case_layout.dart';

late Directory _runsDir;

Future<({LocalRunStore runStore, LocalRouteStore routeStore, Preferences prefs})>
    _makeStores() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = Preferences();
  await prefs.init();

  _runsDir = Directory.systemTemp.createTempSync('period_summary_screen_test_');
  final runStore = LocalRunStore();
  await runStore.init(overrideDirectory: _runsDir);

  return (runStore: runStore, routeStore: LocalRouteStore(), prefs: prefs);
}

Future<void> _pump(
  WidgetTester tester, {
  required PeriodType period,
  required DateTime anchor,
  required LocalRunStore runStore,
  required LocalRouteStore routeStore,
  required Preferences prefs,
}) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: PeriodSummaryScreen(
        initialPeriod: period,
        initialAnchor: anchor,
        runStore: runStore,
        routeStore: routeStore,
        preferences: prefs,
      ),
    ),
  );
}

void main() {
  tearDown(() {
    if (_runsDir.existsSync()) _runsDir.deleteSync(recursive: true);
  });

  group('PeriodSummaryScreen — initial render', () {
    testWidgets('app-bar title is "Weekly Summary" when initialPeriod is week',
        (tester) async {
      final s = await _makeStores();
      await _pump(
        tester,
        period: PeriodType.week,
        anchor: DateTime(2026, 4, 27),
        runStore: s.runStore,
        routeStore: s.routeStore,
        prefs: s.prefs,
      );
      await tester.pump();
      expect(find.descendant(of: find.byType(PageHeader), matching: find.text('Weekly Summary')),
          findsOneWidget);
    });

    testWidgets('app-bar title is "Monthly Summary" when initialPeriod is month',
        (tester) async {
      // Reason: the title swaps based on _period — flipping to the
      // wrong label would imply the period type is wrong.
      final s = await _makeStores();
      await _pump(
        tester,
        period: PeriodType.month,
        anchor: DateTime(2026, 4, 27),
        runStore: s.runStore,
        routeStore: s.routeStore,
        prefs: s.prefs,
      );
      await tester.pump();
      expect(find.descendant(of: find.byType(PageHeader), matching: find.text('Monthly Summary')),
          findsOneWidget);
    });

    testWidgets('renders prev/next chevrons in the app bar',
        (tester) async {
      // Reason: the chevrons walk the anchor forward and back —
      // their absence would strand users on the initial period.
      final s = await _makeStores();
      await _pump(
        tester,
        period: PeriodType.week,
        anchor: DateTime(2026, 4, 27),
        runStore: s.runStore,
        routeStore: s.routeStore,
        prefs: s.prefs,
      );
      await tester.pump();
      expect(find.byIcon(Icons.chevron_left), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });

    testWidgets('shows "No runs this week" empty state', (tester) async {
      // Reason: with an empty run store the period summary should
      // surface a no-runs hint rather than render a blank scaffold.
      final s = await _makeStores();
      await _pump(
        tester,
        period: PeriodType.week,
        anchor: DateTime(2026, 4, 27),
        runStore: s.runStore,
        routeStore: s.routeStore,
        prefs: s.prefs,
      );
      await tester.pump();
      expect(find.text('No runs this week'), findsOneWidget);
      expect(find.byType(EmptyState), findsOneWidget);
      expect(find.byIcon(Icons.event_busy), findsOneWidget);
      // Unbounded host: the shared EmptyState must NOT nest its own
      // scrollable inside the screen's ListView.
      expect(
        find.descendant(
          of: find.byType(EmptyState),
          matching: find.byType(SingleChildScrollView),
        ),
        findsNothing,
      );
      // ...and the host itself still scrolls.
      expect(find.byType(ListView), findsOneWidget);
    });

    testWidgets('period-type switcher exposes merged button semantics',
        (tester) async {
      final s = await _makeStores();
      await _pump(
        tester,
        period: PeriodType.week,
        anchor: DateTime(2026, 4, 27),
        runStore: s.runStore,
        routeStore: s.routeStore,
        prefs: s.prefs,
      );
      await tester.pump();
      final semantics =
          tester.getSemantics(find.text('Tap to switch to monthly'));
      expect(semantics.hasFlag(SemanticsFlag.isButton), isTrue);
    });
  });

  // Home keeps one this-week view (the week lead); the day strip and the
  // week's climb it used to show beside it live here (decisions § 2283).
  group('PeriodSummaryScreen — what Home handed over', () {
    Future<void> seed(LocalRunStore store, DateTime at, double vert) =>
        store.save(Run(
          id: 'r-${at.millisecondsSinceEpoch}',
          startedAt: at,
          duration: const Duration(minutes: 30),
          distanceMetres: 5000,
          source: RunSource.app,
          metadata: {'elevation_m': vert},
        ));

    testWidgets('the current week shows the day strip and its climb',
        (tester) async {
      late ({LocalRunStore runStore, LocalRouteStore routeStore, Preferences prefs}) s;
      await tester.runAsync(() async {
        s = await _makeStores();
        await seed(s.runStore, DateTime.now(), 140);
      });
      await _pump(
        tester,
        period: PeriodType.week,
        anchor: DateTime.now(),
        runStore: s.runStore,
        routeStore: s.routeStore,
        prefs: s.prefs,
      );
      await pumpUntil(
        tester,
        () => find.byType(ThisWeekStrip).evaluate().isNotEmpty,
        describe: 'the day strip to render',
      );
      final vert = find.byKey(const Key('periodSummaryVert'));
      expect(vert, findsOneWidget);
      expect(
          find.descendant(
              of: vert, matching: find.text(UnitFormat.elevationValue(140, s.prefs.unit))),
          findsOneWidget);
    });

    testWidgets('the week view carries the activity heatmap as a week picker',
        (tester) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final s = await _makeStores();
      await _pump(
        tester,
        period: PeriodType.week,
        anchor: DateTime.now(),
        runStore: s.runStore,
        routeStore: s.routeStore,
        prefs: s.prefs,
      );
      await tester.pump();
      expect(find.byType(ThisWeekStrip), findsOneWidget);
      final painter = find.byKey(const Key('dashboardHeatmapPainter'));
      // The leftmost column is 19 weeks back: the summary moves there, so the
      // strip (current week only) goes and Next, disabled on this week, opens.
      IconButton next() => tester.widget<IconButton>(find.ancestor(
          of: find.byIcon(Icons.chevron_right), matching: find.byType(IconButton)));
      expect(next().onPressed, isNull);
      await tester.tapAt(tester.getTopLeft(painter) + const Offset(2, 2));
      await tester.pump();
      expect(find.byType(ThisWeekStrip), findsNothing);
      expect(next().onPressed, isNotNull);
    });

    testWidgets('the month view has no heatmap', (tester) async {
      final s = await _makeStores();
      await _pump(
        tester,
        period: PeriodType.month,
        anchor: DateTime.now(),
        runStore: s.runStore,
        routeStore: s.routeStore,
        prefs: s.prefs,
      );
      await tester.pump();
      expect(find.byType(ActivityHeatmap), findsNothing);
    });

    testWidgets('a past week has no day strip, which only draws the week '
        'holding today', (tester) async {
      final s = await _makeStores();
      await _pump(
        tester,
        period: PeriodType.week,
        anchor: DateTime.now().subtract(const Duration(days: 21)),
        runStore: s.runStore,
        routeStore: s.routeStore,
        prefs: s.prefs,
      );
      await tester.pump();
      expect(find.descendant(of: find.byType(PageHeader), matching: find.text('Weekly Summary')),
          findsOneWidget);
      expect(find.byType(ThisWeekStrip), findsNothing);
      expect(find.byKey(const Key('periodSummaryVert')), findsNothing,
          reason: 'no climb tile without any climb');
    });
  });

  // The week strip, heatmap and run cards are ListCards (issue #1374).
  worstCaseTestWidgets('Weekly summary', (tester, locale) async {
    late ({LocalRunStore runStore, LocalRouteStore routeStore, Preferences prefs}) s;
    await tester.runAsync(() async {
      s = await _makeStores();
      await s.runStore.save(Run(
        id: 'r-1',
        startedAt: DateTime.now(),
        duration: const Duration(minutes: 30),
        distanceMetres: 5000,
        source: RunSource.app,
        metadata: {'elevation_m': 140},
      ));
    });
    await tester.pumpWidget(worstCaseApp(
      locale: locale,
      home: PeriodSummaryScreen(
        initialPeriod: PeriodType.week,
        initialAnchor: DateTime.now(),
        runStore: s.runStore,
        routeStore: s.routeStore,
        preferences: s.prefs,
      ),
    ));
    // Loaded tall so the strip is built whatever the locale puts above it,
    // then walked on the phone.
    tester.view.physicalSize = const Size(320, 3000);
    await pumpUntil(
      tester,
      () => find.byType(ThisWeekStrip).evaluate().isNotEmpty,
      describe: 'the day strip to render',
    );
    tester.view.physicalSize = kWorstCasePhone;
    await tester.pump();
    await walkScrollable(tester, primaryScrollable(), 'Weekly summary');
  });
}

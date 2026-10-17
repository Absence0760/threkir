// multi_modal.md § Home, contract v1: "Today" cards, then a thin divider, then
// "Trends", and every trend card collapsible to a single-line heading. The web
// twin is `tests-e2e/dashboard/layout.spec.ts`.

import 'dart:convert';
import 'dart:io';

import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ui_kit/ui_kit.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_food_store.dart';
import '../lib/local_gym_store.dart';
import '../lib/local_route_store.dart';
import '../lib/local_run_store.dart';
import '../lib/preferences.dart';
import '../lib/screens/dashboard_screen.dart';
import '../lib/widgets/mileage_trend_card.dart';
import 'pump_until.dart';

Run _run(String id, DateTime startedAt) => Run(
      id: id,
      startedAt: startedAt,
      duration: const Duration(minutes: 25),
      distanceMetres: 5000,
      source: RunSource.app,
    );

const _kStoreKey = 'run_app.disclosure_v1:dashboard_trends:anon';

class _Harness {
  final Directory dir;
  final Preferences prefs;
  final LocalRunStore runStore;
  _Harness(this.dir, this.prefs, this.runStore);
}

Future<_Harness> _seed(WidgetTester tester) async {
  late _Harness h;
  await tester.runAsync(() async {
    final prefs = Preferences();
    await prefs.init();
    final dir = Directory.systemTemp.createTempSync('dashboard_trends_');
    final now = DateTime.now().toUtc();
    final seed = LocalRunStore();
    await seed.init(overrideDirectory: dir);
    for (var i = 0; i < 40; i++) {
      await seed.save(_run('r$i', now.subtract(Duration(days: i))));
    }
    final runStore = LocalRunStore();
    await runStore.init(overrideDirectory: dir);
    h = _Harness(dir, prefs, runStore);
  });
  return h;
}

Future<void> _pump(WidgetTester tester, _Harness h,
    {double textScale = 1, Key? key}) async {
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: DashboardScreen(
      key: key,
      runStore: h.runStore,
      routeStore: LocalRouteStore(),
      gymStore: LocalGymStore(),
      foodStore: LocalFoodStore(),
      preferences: h.prefs,
    ),
  ));
  await pumpUntil(
    tester,
    () => find.byKey(const Key('dashboardTrendsDivider')).evaluate().isNotEmpty,
    describe: 'the dashboard to mount its trend section',
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a Trends divider sits between today and the trend groups',
      (tester) async {
    tester.view.physicalSize = const Size(400, 8000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final h = await _seed(tester);
    addTearDown(() => h.dir.deleteSync(recursive: true));
    await _pump(tester, h);

    final divider = find.byKey(const Key('dashboardTrendsDivider'));
    expect(find.descendant(of: divider, matching: find.text('Trends')),
        findsOneWidget);
    expect(find.descendant(of: divider, matching: find.byType(Divider)),
        findsOneWidget,
        reason: 'a hairline, not a section header');

    double top(Finder f) => tester.getTopLeft(f).dy;
    final weekLead = find.byKey(const Key('dashboardWeekLead'));
    expect(top(weekLead), lessThan(top(divider)),
        reason: 'the week lead is a Today card');

    // Web's order, every group mounting for a runner with history and no
    // HR zones (Effort) or lifts (Recent), which hide with their only card.
    final order = ['volume', 'fitness', 'performance']
        .map((k) => find.byKey(ValueKey('dashboard-trend-$k')))
        .toList();
    for (final g in order) {
      expect(g, findsOneWidget);
    }
    expect(top(order.first), greaterThan(top(divider)));
    expect(top(order[0]), lessThan(top(order[1])));
    expect(top(order[1]), lessThan(top(order[2])));
    expect(find.byKey(const ValueKey('dashboard-trend-effort')), findsNothing);
    expect(find.byKey(const ValueKey('dashboard-trend-recent')), findsNothing);
  });

  testWidgets('a group folds to its heading and stays folded next time',
      (tester) async {
    tester.view.physicalSize = const Size(400, 8000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final h = await _seed(tester);
    addTearDown(() => h.dir.deleteSync(recursive: true));
    await _pump(tester, h);

    // Open by default: a returning runner finds every card where it was.
    expect(find.byType(MileageTrendCard), findsOneWidget);

    await tester.tap(find.text('Volume'));
    await tester.pump();
    expect(find.byType(MileageTrendCard), findsNothing,
        reason: 'the folded group hides its cards');
    expect(find.text('Volume'), findsOneWidget,
        reason: 'and keeps its one-line heading');
    expect(find.text('Fitness and form'), findsOneWidget);

    late SharedPreferences sp;
    await tester.runAsync(() async => sp = await SharedPreferences.getInstance());
    await pumpUntil(
      tester,
      () => sp.getString(_kStoreKey) != null,
      describe: 'the fold to be remembered',
    );
    expect(jsonDecode(sp.getString(_kStoreKey)!)['volume'], isFalse);

    // A fresh mount reads it back.
    await _pump(tester, h, key: UniqueKey());
    await pumpUntil(
      tester,
      () => find.byType(MileageTrendCard).evaluate().isEmpty,
      describe: 'the remembered fold to be restored',
    );

    await tester.tap(find.text('Volume'));
    await tester.pump();
    expect(find.byType(MileageTrendCard), findsOneWidget);
  });

  testWidgets('the divider and group headings hold at 2.0x text on a phone',
      (tester) async {
    tester.view.physicalSize = const Size(360, 12000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    // Collect layout errors rather than fail on the first: what this pins is
    // that none of them comes from the divider or a group heading. Cards
    // inside the groups carry their own 2.0x tests.
    final errors = <String>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (d) => errors.add(d.toString());
    addTearDown(() => FlutterError.onError = previous);

    final h = await _seed(tester);
    addTearDown(() => h.dir.deleteSync(recursive: true));
    await _pump(tester, h, textScale: 2.0);
    FlutterError.onError = previous;

    expect(find.text('Trends'), findsOneWidget);
    expect(find.text('Fitness and form'), findsOneWidget);
    expect(find.text('Personal bests and predicted race times'),
        findsOneWidget);
    final ours = errors.where((e) =>
        e.contains('disclosure_section.dart') || e.contains('_TrendsDivider'));
    expect(ours, isEmpty);
  });
}

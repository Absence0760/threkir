import 'dart:io';

import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart' hide Route;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_route_store.dart';
import '../lib/local_run_store.dart';
import '../lib/preferences.dart';
import '../lib/screens/run_detail_screen.dart';

// The Route History card ranks the runs on one route by duration. A run still
// holding the ten-day repair placeholder (864000 s, decisions § 2464) has no
// time to rank, so it is neither an attempt nor given a card of its own:
// `qualifyingAttempts` in apps/web/src/lib/routes/route_history.ts.

Run _onRoute(String id, Duration duration, int day) => Run(
      id: id,
      startedAt: DateTime.utc(2026, 4, day, 7, 30),
      duration: duration,
      distanceMetres: 5000,
      source: RunSource.app,
      routeId: 'route-1',
      metadata: const {'activity_type': 'run'},
    );

final _fast = _onRoute('fast', const Duration(minutes: 22), 10);
final _slow = _onRoute('slow', const Duration(minutes: 25), 11);
final _capped = _onRoute('capped', const Duration(seconds: 864000), 12);

Future<void> _pump(WidgetTester tester, Run run) async {
  tester.view.physicalSize = const Size(360, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final prefs = Preferences();
  await prefs.init();

  final dir = Directory.systemTemp.createTempSync('run_detail_route_history_');
  addTearDown(() => dir.deleteSync(recursive: true));
  final runStore = LocalRunStore();
  await runStore.init(overrideDirectory: dir);
  await tester
      .runAsync(() => runStore.saveManyFromRemote([_fast, _slow, _capped]));

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: RunDetailScreen(
        run: run,
        runStore: runStore,
        routeStore: LocalRouteStore(),
        preferences: prefs,
      ),
    ),
  );
  // Timed pumps only — pumpAndSettle spins LiveRunMap's pulse animation.
  await tester.pump();
  await tester.pump(Duration.zero);
}

void main() {
  testWidgets('a capped run on the route is not counted as an attempt',
      (tester) async {
    await _pump(tester, _slow);

    expect(find.text('Route History'), findsOneWidget);
    expect(find.textContaining('Attempt 2 of 2'), findsOneWidget);
  });

  testWidgets('a capped run gets no route ranking of its own', (tester) async {
    await _pump(tester, _capped);

    expect(find.text('Route History'), findsNothing);
    expect(find.textContaining('Attempt'), findsNothing);
  });
}

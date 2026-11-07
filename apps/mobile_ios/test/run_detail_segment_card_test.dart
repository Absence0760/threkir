import 'dart:io';

import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart' hide Route;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_route_store.dart';
import '../lib/local_run_store.dart';
import '../lib/preferences.dart';
import '../lib/screens/run_detail_screen.dart';
import '../lib/widgets/live_run_map.dart';
import '../lib/widgets/map_attribution.dart';
import '../lib/widgets/track_segment.dart';

/// Issue #1300 § 2: the tapped-stretch stats card was positioned over the
/// map's bottom edge, where it covered the basemap credit (§ 491) and the
/// replay button sat on top of it. It now lives under the map.
Run _run() {
  final t0 = DateTime.utc(2026, 4, 15, 7, 30);
  return Run(
    id: 'run-segment-card',
    startedAt: t0,
    duration: const Duration(minutes: 10),
    distanceMetres: 2000,
    source: RunSource.app,
    metadata: const {'activity_type': 'run'},
    track: [
      for (var i = 0; i <= 40; i++)
        Waypoint(
          lat: -37.8136 + i * 0.00045,
          lng: 144.9631,
          elevationMetres: 10.0 + i,
          timestamp: t0.add(Duration(seconds: i * 15)),
        ),
    ],
  );
}

Future<void> _pump(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({});
  final prefs = Preferences();
  await prefs.init();
  final dir = Directory.systemTemp.createTempSync('run_detail_segment_card_');
  addTearDown(() => dir.deleteSync(recursive: true));
  final runStore = LocalRunStore();
  await runStore.init(overrideDirectory: dir);

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: RunDetailScreen(
        run: _run(),
        runStore: runStore,
        routeStore: LocalRouteStore(),
        preferences: prefs,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(Duration.zero);
}

Future<void> _selectSegment(WidgetTester tester) async {
  final map = tester.widget<LiveRunMap>(find.byType(LiveRunMap));
  final segment = buildSegmentAt(map.track, 20);
  expect(segment, isNotNull);
  map.onSegmentSelect!(segment!);
  await tester.pump();
}

final _card = find.byKey(const ValueKey('run-detail-segment-card'));

void _expectCreditUncovered(WidgetTester tester) {
  final mapRect = tester.getRect(find.byType(LiveRunMap));
  final credit = tester.getRect(find.byType(MapAttribution));
  final strip = find.descendant(
      of: find.byType(MapAttribution), matching: find.byType(Text));
  expect(strip, findsWidgets, reason: 'the credit has to render to be seen');
  for (final text in strip.evaluate()) {
    final rect = tester.getRect(find.byWidget(text.widget));
    expect(mapRect.contains(rect.topLeft) && mapRect.contains(rect.bottomLeft),
        isTrue,
        reason: 'credit $rect is outside the map $mapRect');
  }
  final cardRect = tester.getRect(_card);
  expect(cardRect.overlaps(credit), isFalse,
      reason: 'the segment card $cardRect covers the credit $credit');
  expect(cardRect.top, greaterThanOrEqualTo(mapRect.bottom),
      reason: 'the segment card is drawn over the map');
  final replay = tester.getRect(find.ancestor(
      of: find.byIcon(Icons.play_arrow),
      matching: find.byType(FloatingActionButton)));
  expect(replay.overlaps(cardRect), isFalse,
      reason: 'the replay button sits on the segment card');
}

void main() {
  setUpAll(() => dotenv.loadFromString(isOptional: true));

  testWidgets('on a phone the segment card sits under the map, leaving the '
      'credit and the replay button clear', (tester) async {
    await _pump(tester, const Size(411, 900));
    expect(_card, findsNothing);
    await _selectSegment(tester);
    expect(_card, findsOneWidget);
    _expectCreditUncovered(tester);

    await tester.tap(find.descendant(of: _card, matching: find.byIcon(Icons.close)));
    await tester.pump();
    expect(_card, findsNothing);
  });

  testWidgets('on an expanded layout the card sits under the map pane',
      (tester) async {
    await _pump(tester, const Size(1200, 900));
    await _selectSegment(tester);
    expect(_card, findsOneWidget);
    _expectCreditUncovered(tester);
  });
}

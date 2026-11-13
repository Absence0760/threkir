// ignore_for_file: avoid_relative_lib_imports
import 'dart:io';

import 'package:core_models/core_models.dart' as cm;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/local_route_store.dart';
import '../lib/local_run_store.dart';
import '../lib/preferences.dart';
import '../lib/screens/period_summary_screen.dart';
import '../lib/widgets/finisher_certificate_card.dart';
import '../lib/widgets/route_share_card.dart';
import '../lib/widgets/share_canvas.dart';
import 'worst_case_layout.dart';

/// Issue #1374 TO-3: three share images were captured at the preview's size
/// and the OS text scale, so the PNG shipped truncated (a month's "12h 34m"
/// as "12h…") or cropped (the certificate's last lines) on a phone. Each is a
/// [ShareCanvas] now: laid out at a fixed size with text scaling off, scaled
/// into the preview, and exported at a fixed width.
int _pngWidth(List<int> png) =>
    (png[16] << 24) | (png[17] << 16) | (png[18] << 8) | png[19];

void main() {
  setUpAll(() => dotenv.loadFromString(isOptional: true));

  testWidgets('the canvas is laid out at its size with text scaling off, '
      'and exports at a fixed width whatever the preview', (tester) async {
    final key = GlobalKey();
    late TextScaler seen;
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
        child: Center(
          child: SizedBox(
            width: 200,
            child: ShareCanvas(
              canvasSize: const Size(480, 360),
              captureKey: key,
              child: Builder(builder: (context) {
                seen = MediaQuery.textScalerOf(context);
                return const ColoredBox(color: Colors.white);
              }),
            ),
          ),
        ),
      ),
    ));
    expect(seen, TextScaler.noScaling,
        reason: 'the reader\'s text size is not part of the picture');
    expect(key.currentContext!.size, const Size(480, 360));
    final png = await tester.runAsync(
        () => captureShareCanvas(key, canvasSize: const Size(480, 360)));
    expect(_pngWidth(png!), 1080);
  });

  worstCaseTestWidgets('The finisher certificate share', (tester, locale) async {
    final key = GlobalKey();
    await tester.pumpWidget(worstCaseApp(
      locale: locale,
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(32),
          child: ShareCanvas(
            canvasSize: kFinisherCertificateCanvas,
            captureKey: key,
            child: FinisherCertificateCard(
              eventTitle: 'Richmond Riverside Half Marathon and 10K',
              finisherName: 'Alexandra Bartholomew-Nguyen',
              durationS: 3 * 3600 + 25 * 60 + 8,
              distanceM: 21097,
              rank: 123,
              date: DateTime(2026, 6, 12),
              clubName: 'Richmond Run Club',
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    expect(key.currentContext!.size, kFinisherCertificateCanvas);
  });

  worstCaseTestWidgets('The route share', (tester, locale) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = Preferences();
    await prefs.init();
    final key = GlobalKey();
    await tester.pumpWidget(worstCaseApp(
      locale: locale,
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(32),
          child: ShareCanvas(
            canvasSize: kRouteShareCanvas,
            captureKey: key,
            child: RouteShareCard(
              route: cm.Route(
                id: 'r1',
                userId: 'u1',
                name: 'Philadelphia Marathon full course, Art Museum to Manayunk',
                distanceMetres: 42195,
                elevationGainMetres: 260,
                waypoints: const [
                  cm.Waypoint(lat: 39.96, lng: -75.18),
                  cm.Waypoint(lat: 39.97, lng: -75.19),
                ],
              ),
              preferences: prefs,
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    expect(key.currentContext!.size, kRouteShareCanvas);
    // The map's tile fetches have no network here.
    expectNoLayoutOverflow(tester, 'route share');
  }, layoutOnly: true);

  worstCaseTestWidgets('The period summary share', (tester, locale) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = Preferences();
    await prefs.init();
    final dir = Directory.systemTemp.createTempSync('period_share_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final runStore = LocalRunStore();
    await runStore.init(overrideDirectory: dir);
    final now = DateTime.now();
    await tester.runAsync(() async {
      for (var i = 0; i < 20; i++) {
        await runStore.save(cm.Run(
          id: 'r$i',
          startedAt: DateTime(now.year, now.month, 1, 7).add(Duration(hours: i)),
          duration: const Duration(minutes: 45),
          distanceMetres: 10000,
          source: cm.RunSource.app,
        ));
      }
    });
    await tester.pumpWidget(worstCaseApp(
      locale: locale,
      home: PeriodSummaryScreen(
        initialPeriod: PeriodType.month,
        initialAnchor: now,
        runStore: runStore,
        routeStore: LocalRouteStore(),
        preferences: prefs,
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expectNoOverflow(tester, 'period summary');
    await tester.tap(find.byIcon(Icons.share_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(ShareCanvas), findsOneWidget);
  });
}

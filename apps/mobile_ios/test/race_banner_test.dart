import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import '../lib/course_gates.dart' show SessionStartMode;
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/race_controller.dart';
import '../lib/social_service.dart';
import '../lib/widgets/race_banner.dart';

/// The idle run screen's race banner (#1306): a scheduled GO's countdown and
/// its voice marks on the server clock, the Self-timed attempt switch, and
/// the distance to the frozen start line.

Position _fix(double lat, double lng) => Position(
      latitude: lat,
      longitude: lng,
      timestamp: DateTime.utc(2026, 11, 8),
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

Future<void> _pump(
  WidgetTester tester, {
  required ActiveRace race,
  required RaceController controller,
  required DateTime Function() now,
  void Function(int)? onCue,
  Stream<Position> Function()? fixes,
}) async {
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: RaceBanner(
        race: race,
        controller: controller,
        now: now,
        onCountdownCue: onCue,
        positionFixes: fixes ?? () => const Stream<Position>.empty(),
      ),
    ),
  ));
}

void main() {
  final t0 = DateTime.utc(2026, 11, 8, 9, 0, 0);

  testWidgets('a scheduled race counts down on the server clock and speaks the marks', (tester) async {
    var clock = t0;
    final cues = <int>[];
    final controller = RaceController(SocialService());
    // The device runs 2 s behind the server.
    controller.clockOffset.addSample(
      sentAt: t0,
      receivedAt: t0,
      serverAt: t0.add(const Duration(seconds: 2)),
    );
    final race = ActiveRace(
      eventId: 'sch',
      instanceStart: t0,
      status: 'armed',
      startedAt: null,
      eventTitle: 'Saturday 5K',
      startMode: SessionStartMode.scheduled,
      scheduledStartAt: t0.add(const Duration(seconds: 14)),
      windowClosesAt: t0.add(const Duration(hours: 1)),
    );
    await _pump(tester, race: race, controller: controller, now: () => clock, onCue: cues.add);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('Saturday 5K starts in 0:12'), findsOneWidget,
        reason: '14 s to GO, less the 2 s the device is behind');

    for (var s = 1; s <= 12; s++) {
      clock = t0.add(Duration(seconds: s));
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(cues, [10, 5, 3, 2, 1]);
    // At the instant the banner turns live by itself.
    expect(find.text('Race LIVE'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a self-timed window offers the explicit attempt switch', (tester) async {
    final controller = RaceController(SocialService());
    final race = ActiveRace(
      eventId: 'tt',
      instanceStart: t0,
      status: 'running',
      startedAt: t0,
      eventTitle: 'Park trial',
      startMode: SessionStartMode.selfTimed,
      windowOpensAt: t0,
      windowClosesAt: DateTime.now().toUtc().add(const Duration(days: 1)),
    );
    controller.setActiveForTest(race);
    await _pump(tester, race: race, controller: controller, now: DateTime.now);
    await tester.pump();
    expect(find.text('Self-timed'), findsOneWidget);
    expect(find.byKey(const ValueKey('race-attempt')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('race-attempt')));
    await tester.pump();
    expect(controller.attemptArmed, isTrue);
    expect(find.byKey(const ValueKey('race-attempt-cancel')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('race-attempt-cancel')));
    await tester.pump();
    expect(controller.attemptArmed, isFalse);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('the distance to the start line comes from the runner position', (tester) async {
    final controller = RaceController(SocialService());
    final race = ActiveRace(
      eventId: 'tt',
      instanceStart: t0,
      status: 'running',
      startedAt: t0,
      eventTitle: 'Park trial',
      startMode: SessionStartMode.selfTimed,
      windowOpensAt: t0,
      windowClosesAt: DateTime.now().toUtc().add(const Duration(days: 1)),
      startLineLat: 51.5,
      startLineLng: -0.1,
    );
    final fixes = StreamController<Position>.broadcast();
    await _pump(tester, race: race, controller: controller, now: DateTime.now, fixes: () => fixes.stream);
    expect(find.byKey(const ValueKey('race-banner-to-start')), findsNothing,
        reason: 'no fix yet, no distance line');
    // About 111 m north of the line.
    fixes.add(_fix(51.501, -0.1));
    await tester.pump();
    expect(find.byKey(const ValueKey('race-banner-to-start')), findsOneWidget);
    expect(find.textContaining('to the start line'), findsOneWidget);
    await fixes.close();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Host GO armed still waits for GO', (tester) async {
    final controller = RaceController(SocialService());
    final race = ActiveRace(
      eventId: 'h',
      instanceStart: t0,
      status: 'armed',
      startedAt: null,
      eventTitle: 'Club 10K',
    );
    await _pump(tester, race: race, controller: controller, now: DateTime.now);
    expect(find.text('Race armed'), findsOneWidget);
    expect(find.textContaining('waiting for GO'), findsOneWidget);
    expect(find.byKey(const ValueKey('race-attempt')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}

import 'dart:io';
import 'dart:math' as math;

import 'package:core_models/core_models.dart' show Waypoint;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:run_recorder/run_recorder.dart' show RunSnapshot;

import '../lib/gate_crossing.dart';
import '../lib/line_calibration.dart';
import '../lib/screens/line_calibration_screen.dart';

/// The debug-only calibration screen (#1304 § 6): unreachable in a release
/// build, and what it shares holds error figures, never a position.

const _lat0 = 47.123456;
const _lng0 = 8.654321;
const _mPerDegLat = 6371008.8 * math.pi / 180;
final _mPerDegLng = _mPerDegLat * math.cos(_lat0 * math.pi / 180);
final _t0 = DateTime(2026, 11, 10, 7, 0, 0);

GateFix _fix(double eastM, int ms) => GateFix(
      lat: _lat0,
      lng: _lng0 + eastM / _mPerDegLng,
      tMs: _t0.millisecondsSinceEpoch + ms.toDouble(),
      coveredM: eastM + 100,
    );

Future<void> _pump(WidgetTester tester, Widget child) async {
  // Tall enough that the whole form is built: a ListView builds lazily.
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: child));
}

void main() {
  group('a release build', () {
    testWidgets('has no Settings entry', (tester) async {
      await _pump(
        tester,
        Scaffold(
          body: LineCalibrationEntry(onOpen: () {}, available: false),
        ),
      );
      expect(find.byKey(const ValueKey('line-calibration-entry')), findsNothing);
      expect(find.byType(ListTile), findsNothing);
    });

    testWidgets('renders nothing of the screen', (tester) async {
      await _pump(tester, const LineCalibrationScreen(available: false));
      expect(find.byType(Scaffold), findsNothing);
      expect(find.byKey(const ValueKey('line-calibration-start')), findsNothing);
    });

    test('is the configuration the tools key off', () {
      expect(kLineCalibrationAvailable, kDebugMode);
      expect(const LineCalibrationEntry(onOpen: _noop).available, kDebugMode);
      expect(const LineCalibrationScreen().available, kDebugMode);
    });

    test('reaches the tools from nowhere outside a kDebugMode branch', () {
      // A release build compiles kDebugMode to false, so a reference inside
      // `if (kDebugMode)` is dropped. Any other one would ship the tools.
      final own = {
        'lib/line_calibration.dart',
        'lib/screens/line_calibration_screen.dart',
      };
      final refs = <String>[];
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        if (own.contains(f.path)) continue;
        final lines = f.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final l = lines[i];
          if (!l.contains('LineCalibration')) continue;
          if (l.trimLeft().startsWith('import ')) continue;
          refs.add('${f.path}:${i + 1}');
          final window = lines.sublist(math.max(0, i - 3), i + 1).join('\n');
          expect(window, contains('if (kDebugMode)'),
              reason: '${f.path}:${i + 1} reaches the calibration tools '
                  'outside a kDebugMode branch');
        }
      }
      expect(refs, isNotEmpty,
          reason: 'the Settings entry and the run screen capture exist');
    });
  });

  testWidgets('a session scores a capture and shares figures only',
      (tester) async {
    final capture = LineCalibrationCapture();
    String? shared;
    await _pump(
      tester,
      LineCalibrationScreen(
        available: true,
        capture: capture,
        sampleServerClock: () async {
          // The device runs 1.5 s behind; one round trip of 40 ms.
          final sent = DateTime.now();
          final received = sent.add(const Duration(milliseconds: 40));
          return (
            sentAt: sent,
            receivedAt: received,
            serverAt: sent.add(const Duration(milliseconds: 1520)),
          );
        },
        shareCsv: (csv) async => shared = csv,
      ),
    );
    await tester.tap(find.byKey(const ValueKey('line-calibration-start')));
    await tester.pump();
    expect(capture.active, isTrue);

    // What the run screen would have offered: a pass east at 4 m/s, over
    // the line at device 07:00:10.000, server 07:00:11.500.
    capture.clear();
    capture.start();
    for (var k = -5; k <= 5; k++) {
      final f = _fix(4.0 * (k * 1000 - 500) / 1000, 10000 + k * 1000 - 500);
      capture.offer(
        RunSnapshot(
          elapsed: Duration.zero,
          distanceMetres: f.coveredM,
          currentPosition: Waypoint(lat: f.lat, lng: f.lng),
          positionFixedAt:
              DateTime.fromMillisecondsSinceEpoch(f.tMs.round()),
        ),
        fresh: true,
        paused: false,
      );
    }
    await tester.tap(find.byKey(const ValueKey('line-calibration-stop')));
    await tester.pump();
    expect(find.text('Idle: 11 fixes held'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Line centre latitude'),
        '$_lat0');
    await tester.enterText(
        find.widgetWithText(TextField, 'Line centre longitude'), '$_lng0');
    await tester.enterText(
        find.widgetWithText(TextField, 'Bearing of travel, deg'), '90');
    await tester.tap(find.byKey(const ValueKey('line-calibration-measure')));
    await tester.pump();
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('line-calibration-offset')))
            .controller!
            .text,
        '1500');
    await tester.enterText(
        find.byKey(const ValueKey('line-calibration-instants')), '07:00:11.200');
    await tester.ensureVisible(find.byKey(const ValueKey('line-calibration-score')));
    await tester.tap(find.byKey(const ValueKey('line-calibration-score')));
    await tester.pump();
    expect(find.byKey(const ValueKey('line-calibration-problem')), findsNothing);
    expect(
        find.textContaining(
            '1 of 1 matched, 0 missed, 0 false, 0 near; median 300 ms'),
        findsOneWidget);
    expect(find.textContaining('offset ±20 ms'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const ValueKey('line-calibration-share')));
    await tester.tap(find.byKey(const ValueKey('line-calibration-share')));
    await tester.pump();
    expect(shared, isNotNull);
    expect(shared, contains('summary,90,run,phone_hand,'));
    expect(shared!.trim().split('\n').last, endsWith(',300,300,300,40'),
        reason: 'the offset round trip rides the summary');
    for (final leak in ['47.12', '8.65', '07:00', '2026']) {
      expect(shared, isNot(contains(leak)), reason: '$leak left the device');
    }
  });

  testWidgets('a capture cannot be scored without its line', (tester) async {
    await _pump(
      tester,
      LineCalibrationScreen(available: true, capture: LineCalibrationCapture()),
    );
    await tester.ensureVisible(find.byKey(const ValueKey('line-calibration-score')));
    await tester.tap(find.byKey(const ValueKey('line-calibration-score')));
    await tester.pump();
    expect(find.byKey(const ValueKey('line-calibration-problem')), findsOneWidget);
    expect(find.byKey(const ValueKey('line-calibration-share')), findsNothing);
  });
}

void _noop() {}

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/course_gates.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/widgets/course_lines_map.dart';
import '../lib/widgets/race_preflight_dialog.dart';

// #1305: the course map draws a course's start and finish timing lines, and
// the race director's Arm preflight asks on a warning and blocks on an error.

const _start = CourseGate(
  lat: 51.5,
  lng: -0.1,
  bearingDeg: 0,
  halfWidthM: 15,
  source: GateSource.derived,
);
const _finish = CourseGate(
  lat: 51.501,
  lng: -0.1,
  bearingDeg: 0,
  halfWidthM: 20,
  source: GateSource.organiser,
);

Widget _app(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );

/// The tile layer's load and retry timers outlive the frame; unmount the map
/// and let them run out so the test ends with none pending.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 5));
}

List<Polyline> _polylines(WidgetTester tester, String key) =>
    tester.widget<PolylineLayer>(find.byKey(ValueKey(key))).polylines;

void main() {
  setUpAll(() => dotenv.loadFromString(isOptional: true));

  group('CourseLinesMap', () {
    testWidgets('draws the start line and the finish line with its arrow',
        (tester) async {
      await tester.pumpWidget(_app(
          const CourseLinesMap(start: _start, finish: _finish)));
      await tester.pump();

      final start = _polylines(tester, 'course-gate-start');
      final finish = _polylines(tester, 'course-gate-finish');
      // Casing + colour for the line, the arrow shaft and the arrowhead.
      expect(start, hasLength(6));
      expect(finish, hasLength(6));

      // The line's two ends straddle the centre, 15 m either side (west and
      // east for a northbound line).
      final (left, right) = gateLineEnds(_start);
      expect(start[3].points.first.longitude, left.lng);
      expect(start[3].points.last.longitude, right.lng);
      expect(left.lng, lessThan(_start.lng));
      expect(right.lng, greaterThan(_start.lng));

      // The finish arrow runs from the centre to the tip ahead of it.
      final shaft = finish[4].points;
      expect(shaft.first.latitude, _finish.lat);
      expect(shaft.last.latitude, gateArrowTip(_finish).lat);
      expect(shaft.last.latitude, greaterThan(_finish.lat));

      expect(start[3].color, isNot(finish[3].color));
      await _unmount(tester);
    });

    testWidgets('draws only the line a course has', (tester) async {
      await tester.pumpWidget(
          _app(const CourseLinesMap(start: null, finish: _finish)));
      await tester.pump();
      expect(find.byKey(const ValueKey('course-gate-start')), findsNothing);
      expect(find.byKey(const ValueKey('course-gate-finish')), findsOneWidget);
      await _unmount(tester);
    });

    testWidgets('a course with no line shows no map', (tester) async {
      await tester
          .pumpWidget(_app(const CourseLinesMap(start: null, finish: null)));
      await tester.pump();
      expect(find.byType(FlutterMap), findsNothing);
    });
  });

  group('confirmRacePreflight', () {
    Future<bool?> run(WidgetTester tester, List<PreflightIssue> issues,
        {String? tap}) async {
      bool? result;
      await tester.pumpWidget(_app(Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            result = await confirmRacePreflight(
                context, issues, (id) => id == 'c1' ? '5K' : '10K');
          },
          child: const Text('arm'),
        ),
      )));
      await tester.tap(find.text('arm'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      if (tap != null) {
        await tester.tap(find.byKey(Key(tap)));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
      }
      return result;
    }

    testWidgets('no issues arms without asking', (tester) async {
      final result = await run(tester, const []);
      expect(find.byKey(const Key('race-preflight-dialog')), findsNothing);
      expect(result, isTrue);
    });

    const warnings = [
      PreflightIssue(
          courseId: 'c1',
          code: PreflightCode.noFinish,
          severity: PreflightSeverity.warning),
      PreflightIssue(
          courseId: 'c2',
          code: PreflightCode.selfCross,
          severity: PreflightSeverity.warning),
    ];

    testWidgets('a warning lists each course and Arm anyway proceeds',
        (tester) async {
      await run(tester, warnings);
      expect(find.byKey(const Key('race-preflight-dialog')), findsOneWidget);
      expect(find.textContaining('5K: no finish line'), findsOneWidget);
      expect(find.textContaining('10K: the route crosses its own finish line'),
          findsOneWidget);
      await tester.tap(find.byKey(const Key('race-preflight-arm')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('race-preflight-dialog')), findsNothing);
    });

    testWidgets('Arm anyway returns true', (tester) async {
      expect(await run(tester, warnings, tap: 'race-preflight-arm'), isTrue);
    });

    testWidgets('Cancel does not arm', (tester) async {
      expect(await run(tester, warnings, tap: 'race-preflight-cancel'), isFalse);
    });

    const blocking = [
      PreflightIssue(
          courseId: 'c1',
          code: PreflightCode.noStart,
          severity: PreflightSeverity.error),
      PreflightIssue(
          courseId: 'c2',
          code: PreflightCode.gateFarFromRoute,
          severity: PreflightSeverity.warning,
          which: GateWhich.finish),
    ];

    testWidgets('an error blocks with no way to arm', (tester) async {
      await run(tester, blocking);
      expect(find.text("This race can't be armed yet"), findsOneWidget);
      expect(find.textContaining('5K: no start line'), findsOneWidget);
      expect(find.byKey(const Key('race-preflight-arm')), findsNothing);
    });

    testWidgets('closing the blocking dialog does not arm', (tester) async {
      expect(await run(tester, blocking, tap: 'race-preflight-ok'), isFalse);
    });

    test('every issue code reads as its own sentence', () {
      final l10n = lookupAppLocalizations(const Locale('en'));
      final texts = {
        for (final i in const [
          PreflightIssue(
              courseId: 'x',
              code: PreflightCode.noFinish,
              severity: PreflightSeverity.warning),
          PreflightIssue(
              courseId: 'x',
              code: PreflightCode.noStart,
              severity: PreflightSeverity.error),
          PreflightIssue(
              courseId: 'x',
              code: PreflightCode.selfCross,
              severity: PreflightSeverity.warning),
          PreflightIssue(
              courseId: 'x',
              code: PreflightCode.gateFarFromRoute,
              severity: PreflightSeverity.warning,
              which: GateWhich.start),
          PreflightIssue(
              courseId: 'x',
              code: PreflightCode.gateFarFromRoute,
              severity: PreflightSeverity.warning,
              which: GateWhich.finish),
        ])
          preflightIssueText(l10n, i, 'Loop'),
      };
      expect(texts, hasLength(5));
      expect(texts.every((t) => t.startsWith('Loop')), isTrue);
    });
  });
}

import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/park_courses_screen.dart';
import '../lib/widgets/run_park_course_attempts.dart';

ParkCourseAttempt _attempt(
  ParkCourseAttemptOutcome outcome, {
  int progressM = 2100,
  int courseM = 5000,
  int? missedCheckpoint,
  int checkpointCount = 4,
}) => ParkCourseAttempt(
  parkCourseId: 'course-${outcome.name}',
  courseName: 'Beaver Lake Trail',
  parkName: 'Pocahontas State Park',
  region: 'US-VA',
  parkSlug: 'pocahontas',
  courseSlug: 'beaver-lake-trail',
  outcome: outcome,
  progressM: progressM,
  courseM: courseM,
  missedCheckpoint: missedCheckpoint,
  checkpointCount: checkpointCount,
);

class _FakeApi extends ApiClient {
  _FakeApi({
    this.viewerId = 'owner-1',
    this.attempts = const [],
    this.fail = false,
    this.gate,
    this.resolves = false,
  });

  final String? viewerId;
  final List<ParkCourseAttempt> attempts;
  final bool fail;
  final Completer<void>? gate;
  final bool resolves;
  int reads = 0;
  final opened = <String>[];

  @override
  String? get userId => viewerId;

  @override
  Future<List<ParkCourseAttempt>> fetchParkCourseAttempts(String runId) async {
    reads++;
    if (gate != null) await gate!.future;
    if (fail) throw Exception('offline');
    return attempts;
  }

  @override
  Future<({ParkListing park, ParkCourseListing course})?>
  fetchParkCourseBySlugs(String parkSlug, String courseSlug) async {
    opened.add('$parkSlug/$courseSlug');
    if (!resolves) return null;
    final created = DateTime.parse('2027-01-01T00:00:00Z');
    return (
      park: ParkListing(
        park: ParkRow(
          id: 'p1',
          slug: parkSlug,
          name: 'Pocahontas State Park',
          kind: 'park',
          agency: 'state',
          regionCode: 'US-VA',
          countryCode: 'US',
          timezone: 'America/New_York',
          isActive: true,
          createdAt: created,
        ),
        season: 2027,
        month: 6,
      ),
      course: ParkCourseListing(
        course: ParkCourseRow(
          id: 'c1',
          parkId: 'p1',
          globalSegmentId: 's1',
          slug: courseSlug,
          courseShape: 'loop',
          status: 'open',
          geometrySource: 'osm',
          checkpoints: const [],
          createdAt: created,
        ),
        segment: GlobalSegmentRow(
          id: 's1',
          name: 'Beaver Lake Trail',
          waypoints: const [],
          distanceM: 3595,
          surface: 'trail',
          isActive: true,
          createdAt: created,
        ),
      ),
    );
  }
}

Future<void> _pump(
  WidgetTester tester,
  ApiClient api, {
  DistanceUnit unit = DistanceUnit.km,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: RunParkCourseAttempts(api: api, runId: 'run-1', unit: unit),
      ),
    ),
  );
  await tester.pump();
}

const _barLabel = 'How far along the course you got';

/// The screen reader's value on the progress bar node named [_barLabel].
String _barValue(WidgetTester tester) => tester
    .getSemantics(find.bySemanticsLabel(_barLabel))
    .getSemanticsData()
    .value;

void main() {
  testWidgets(
    'a run that stopped short says how far it got and where to finish',
    (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        _FakeApi(attempts: [_attempt(ParkCourseAttemptOutcome.stoppedShort)]),
      );
      expect(find.byKey(const Key('run-park-course-attempts')), findsOneWidget);
      expect(
        find.text(
          'Beaver Lake Trail: no time. You ran 2.10 km of 5.00 km. '
          'Run the whole course to get a time.',
        ),
        findsOneWidget,
      );
      expect(find.text('2.10 km of 5.00 km'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Park courses with no time'),
        findsOneWidget,
      );
      expect(_barValue(tester), '2.10 km of 5.00 km');
      handle.dispose();
    },
  );

  testWidgets('the distances follow the runner\'s unit', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(
      tester,
      _FakeApi(
        attempts: [
          _attempt(
            ParkCourseAttemptOutcome.stoppedShort,
            progressM: 1609,
            courseM: 4828,
          ),
        ],
      ),
      unit: DistanceUnit.mi,
    );
    expect(find.text('1.00 mi of 3.00 mi'), findsOneWidget);
    expect(find.textContaining('km'), findsNothing);
    expect(_barValue(tester), '1.00 mi of 3.00 mi');
    handle.dispose();
  });

  testWidgets('a missed checkpoint names which one, out of how many', (
    tester,
  ) async {
    await _pump(
      tester,
      _FakeApi(
        attempts: [
          _attempt(
            ParkCourseAttemptOutcome.skippedCheckpoint,
            missedCheckpoint: 2,
            checkpointCount: 5,
          ),
        ],
      ),
    );
    expect(
      find.text(
        'Beaver Lake Trail: no time. You missed checkpoint 2 of 5. '
        'Stay on the course line to pass every one.',
      ),
      findsOneWidget,
    );
    expect(find.text('2.10 km of 5.00 km'), findsOneWidget);
  });

  testWidgets('running off the course and running it backwards each say so', (
    tester,
  ) async {
    await _pump(
      tester,
      _FakeApi(
        attempts: [
          _attempt(ParkCourseAttemptOutcome.offCourse, progressM: 5000),
          _attempt(ParkCourseAttemptOutcome.wrongDirection, progressM: 0),
        ],
      ),
    );
    expect(
      find.text(
        'Beaver Lake Trail: no time. You ran too far off the course. '
        'Stay on the course line.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Beaver Lake Trail: no time. You ran it the wrong way round. '
        'Follow the arrows on the course map.',
      ),
      findsOneWidget,
    );
    expect(find.text('5.00 km of 5.00 km'), findsOneWidget);
    expect(find.text('0.00 km of 5.00 km'), findsOneWidget);
  });

  testWidgets('a card opens its course', (tester) async {
    final api = _FakeApi(
      attempts: [_attempt(ParkCourseAttemptOutcome.stoppedShort)],
      resolves: true,
    );
    await _pump(tester, api);
    await tester.tap(
      find.byKey(const Key('run-park-course-attempt-course-stoppedShort')),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
    expect(api.opened, ['pocahontas/beaver-lake-trail']);
    final screen = tester.widget<ParkCourseScreen>(
      find.byType(ParkCourseScreen),
    );
    expect(screen.course.course.slug, 'beaver-lake-trail');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('a course that can no longer be opened says so', (tester) async {
    final api = _FakeApi(
      attempts: [_attempt(ParkCourseAttemptOutcome.offCourse)],
    );
    await _pump(tester, api);
    await tester.tap(
      find.byKey(const Key('run-park-course-attempt-course-offCourse')),
    );
    await tester.pump();
    expect(find.text("Couldn't open this course."), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('nothing shows while loading or for a run with no attempt', (
    tester,
  ) async {
    final gate = Completer<void>();
    await _pump(tester, _FakeApi(gate: gate));
    expect(find.byKey(const Key('run-park-course-attempts')), findsNothing);
    gate.complete();
    await tester.pump();
    expect(find.byKey(const Key('run-park-course-attempts')), findsNothing);
  });

  testWidgets('a signed-out viewer is never asked for', (tester) async {
    final api = _FakeApi(
      viewerId: null,
      attempts: [_attempt(ParkCourseAttemptOutcome.stoppedShort)],
    );
    await _pump(tester, api);
    expect(api.reads, 0);
    expect(find.byKey(const Key('run-park-course-attempts')), findsNothing);
  });

  testWidgets('a failed read leaves the section out and shows no error', (
    tester,
  ) async {
    final api = _FakeApi(
      fail: true,
      attempts: [_attempt(ParkCourseAttemptOutcome.stoppedShort)],
    );
    await _pump(tester, api);
    expect(api.reads, 1);
    expect(find.byKey(const Key('run-park-course-attempts')), findsNothing);
    expect(find.byType(TextButton), findsNothing);
  });

  test('the bar fraction is clamped to the course', () {
    expect(
      parkCourseAttemptFraction(
        _attempt(ParkCourseAttemptOutcome.stoppedShort, progressM: 2500),
      ),
      0.5,
    );
    expect(
      parkCourseAttemptFraction(
        _attempt(ParkCourseAttemptOutcome.offCourse, progressM: 6000),
      ),
      1.0,
    );
  });
}

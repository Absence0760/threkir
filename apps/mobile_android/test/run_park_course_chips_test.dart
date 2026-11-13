import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/park_courses_screen.dart';
import '../lib/widgets/run_park_course_chips.dart';

Map<String, dynamic> _row(String name, int? rank, {int? monthRank}) => {
      'effort_id': 'effort-$name',
      'global_segment_id': 'seg-$name',
      'course_name': name,
      'course_slug': 'beaver-lake-trail',
      'park_name': 'Pocahontas State Park',
      'park_slug': 'pocahontas',
      'region_code': 'US-VA',
      'time_seconds': 1452,
      'started_at': '2027-05-01T12:00:00Z',
      'season': 2027,
      'season_rank': rank,
      'month': 5,
      'month_rank': monthRank ?? rank,
    };

class _FakeApi extends ApiClient {
  _FakeApi({this.viewerId = 'owner-1', this.rows = const [], this.failures = 0, this.gate});

  final String? viewerId;
  final List<Map<String, dynamic>> rows;
  final Completer<void>? gate;
  int failures;
  int reads = 0;
  final opened = <String>[];

  @override
  String? get userId => viewerId;

  @override
  Future<List<Map<String, dynamic>>> fetchRunParkCourseTimes(String runId) async {
    reads++;
    if (gate != null) await gate!.future;
    if (failures > 0) {
      failures--;
      throw Exception('offline');
    }
    return rows;
  }

  @override
  Future<({ParkListing park, ParkCourseListing course})?> fetchParkCourseBySlugs(
      String parkSlug, String courseSlug) async {
    opened.add('$parkSlug/$courseSlug');
    return null;
  }
}

/// Resolves the course, so the chip pushes the course screen.
class _OpeningApi extends _FakeApi {
  _OpeningApi({super.rows});

  @override
  Future<({ParkListing park, ParkCourseListing course})?> fetchParkCourseBySlugs(
      String parkSlug, String courseSlug) async {
    final created = DateTime.parse('2027-01-01T00:00:00Z');
    return (
      park: ParkListing(
        park: ParkRow(
          id: 'p1',
          slug: parkSlug,
          name: 'Pocahontas State Park',
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

Future<void> _pump(WidgetTester tester, ApiClient api) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: RunParkCourseChips(api: api, runId: 'run-1')),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('a placed course shows its name, time, month and season places', (tester) async {
    await _pump(tester, _FakeApi(rows: [_row('Beaver Lake Trail', 3, monthRank: 2)]));
    expect(find.byKey(const Key('run-park-courses')), findsOneWidget);
    expect(find.text('Beaver Lake Trail · 24:12 · #2 in May, #3 in 2027'), findsOneWidget);
    expect(find.bySemanticsLabel('Park courses on this run'), findsOneWidget);
  });

  testWidgets('a month place without a season place shows the month alone', (tester) async {
    await _pump(tester, _FakeApi(rows: [_row('Beaver Lake Trail', null, monthRank: 14)]));
    expect(find.text('Beaver Lake Trail · 24:12 · #14 in May'), findsOneWidget);
  });

  testWidgets('an unranked course shows no place', (tester) async {
    await _pump(tester, _FakeApi(rows: [_row('Swift Creek 5K', null)]));
    expect(find.text('Swift Creek 5K · 24:12'), findsOneWidget);
    expect(find.textContaining('#'), findsNothing);
  });

  testWidgets('nothing shows while loading or for a run with no course', (tester) async {
    final gate = Completer<void>();
    final api = _FakeApi(rows: const [], gate: gate);
    await _pump(tester, api);
    expect(find.byType(ActionChip), findsNothing);
    expect(find.byKey(const Key('run-park-courses-error')), findsNothing);
    gate.complete();
    await tester.pump();
    expect(find.byKey(const Key('run-park-courses')), findsNothing);
    expect(find.byKey(const Key('run-park-courses-error')), findsNothing);
  });

  testWidgets('a signed-out viewer is never asked for', (tester) async {
    final api = _FakeApi(viewerId: null, rows: [_row('Beaver Lake Trail', 1)]);
    await _pump(tester, api);
    expect(api.reads, 0);
    expect(find.byType(ActionChip), findsNothing);
  });

  testWidgets('a failed read is a quiet line, and Retry loads the chips', (tester) async {
    final api = _FakeApi(rows: [_row('Beaver Lake Trail', 1)], failures: 1);
    await _pump(tester, api);
    expect(find.text("Couldn't load your park course times."), findsOneWidget);
    expect(find.byType(ActionChip), findsNothing);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(api.reads, 2);
    expect(find.text('Beaver Lake Trail · 24:12 · #1 in May, #1 in 2027'), findsOneWidget);
    expect(find.byKey(const Key('run-park-courses-error')), findsNothing);
  });

  testWidgets('a chip opens its course on the effort\'s month', (tester) async {
    final api = _OpeningApi(rows: [_row('Beaver Lake Trail', 3, monthRank: 2)]);
    await _pump(tester, api);
    await tester.tap(find.byType(ActionChip));
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
    final screen = tester.widget<ParkCourseScreen>(find.byType(ParkCourseScreen));
    expect(screen.initialPeriod?.season, 2027);
    expect(screen.initialPeriod?.month, 5);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('a course that can no longer be opened says so', (tester) async {
    final api = _FakeApi(rows: [_row('Beaver Lake Trail', 1)]);
    await _pump(tester, api);
    await tester.tap(find.byType(ActionChip));
    await tester.pump();
    expect(api.opened, ['pocahontas/beaver-lake-trail']);
    expect(find.text("Couldn't open this course."), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });
}

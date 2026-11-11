import 'dart:convert';
import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FunctionException;
import 'package:ui_kit/ui_kit.dart' show EmptyState;

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/park_courses_screen.dart';
import '../lib/widgets/elevation_chart.dart';
import '../lib/widgets/park_course_map.dart';
import 'supabase_test_init.dart';

ParkListing _park({
  required String id,
  required String name,
  String region = 'US-VA',
  String agency = 'state',
  String? websiteUrl,
}) => ParkListing(
  park: ParkRow(
    id: id,
    slug: name.toLowerCase().replaceAll(' ', '-'),
    name: name,
    agency: agency,
    regionCode: region,
    countryCode: 'US',
    timezone: 'America/New_York',
    websiteUrl: websiteUrl,
    isActive: true,
    createdAt: DateTime.parse('2026-01-01T00:00:00Z'),
  ),
  season: 2026,
);

/// A loop north out of the park and back to where it began, with an
/// elevation on every point.
List<Map<String, dynamic>> _loop({double ele = 100}) => [
  for (var i = 0; i <= 12; i++)
    {
      'lat': 37.0 + (i < 6 ? i : 12 - i) * 0.002,
      'lng': -77.0 + (i < 6 || i == 12 ? 0 : 0.002),
      'ele': ele + i,
    },
];

ParkCourseListing _course({
  String id = 'c1',
  String name = 'Lake Loop',
  String parkId = 'p1',
  String status = 'open',
  String shape = 'loop',
  double distanceM = 1100,
  int? laps,
  String? attribution,
  String? routeId,
  String? description,
  Object checkpoints = const [],
  List<Map<String, dynamic>>? waypoints,
  Object? routeGuide,
  DateTime? routeGuideCheckedAt,
  String? sharedUse,
}) => ParkCourseListing(
  course: ParkCourseRow(
    id: id,
    parkId: parkId,
    globalSegmentId: 's-$id',
    routeId: routeId,
    slug: name.toLowerCase().replaceAll(' ', '-'),
    courseShape: shape,
    status: status,
    geometrySource: 'osm',
    checkpoints: checkpoints,
    laps: laps,
    attribution: attribution,
    routeGuide: routeGuide,
    routeGuideCheckedAt: routeGuideCheckedAt,
    sharedUse: sharedUse,
    createdAt: DateTime.parse('2026-01-01T00:00:00Z'),
  ),
  segment: GlobalSegmentRow(
    id: 's-$id',
    name: name,
    description: description,
    waypoints: waypoints ?? _loop(),
    distanceM: distanceM,
    elevationM: 45,
    surface: 'trail',
    isActive: true,
    createdAt: DateTime.parse('2026-01-01T00:00:00Z'),
  ),
);

GlobalSegmentLeaderboardEntry _fast(
  String userId,
  String name,
  int rank,
  double t,
) => GlobalSegmentLeaderboardEntry(
  effort: GlobalSegmentEffortRow(
    id: 'e-$userId',
    globalSegmentId: 's-c1',
    runId: 'r-$userId',
    userId: userId,
    timeSeconds: t,
    startedAt: DateTime.parse('2026-02-01T00:00:00Z'),
    createdAt: DateTime.parse('2026-02-01T00:00:00Z'),
    matchedBy: 'zone',
  ),
  athlete: PublicProfile(id: userId, displayName: name),
  rank: rank,
);

class _ParksApi extends ApiClient {
  _ParksApi({
    this.parks = const [],
    List<ParkCourseListing>? courses,
    this.viewer = 'viewer-1',
    this.failParks = false,
    this.failAllCourses = false,
    this.failRecords = false,
    this.records = const {},
    this.emptyBoards = false,
    this.emptyThisSeasonOnly = false,
    this.seasonBoard,
  }) : courses = courses ?? [_course()];

  final List<ParkListing> parks;
  final List<ParkCourseListing> courses;
  final String? viewer;
  final bool failParks;
  final bool failAllCourses;
  final bool failRecords;
  final Map<String, ParkCourseRecord> records;
  final bool emptyBoards;
  final bool emptyThisSeasonOnly;

  /// This season's fastest board, in place of the default two rows.
  final List<GlobalSegmentLeaderboardEntry>? seasonBoard;
  final List<int?> leaderboardSeasons = [];
  final List<int?> completionSeasons = [];
  final List<Map<String, Object?>> reports = [];
  FunctionException? reportRefusal;

  @override
  String? get userId => viewer;

  @override
  Future<List<ParkListing>> fetchParks() async {
    if (failParks) throw StateError('parks network down');
    return parks;
  }

  @override
  Future<List<ParkCourseListing>> fetchParkCourses(String parkId) async =>
      courses;

  @override
  Future<List<ParkCourseListing>> fetchAllParkCourses() async {
    if (failAllCourses) throw StateError('courses network down');
    return courses;
  }

  @override
  Future<void> submitParkCourseReport({
    required String courseId,
    required String reason,
    required String notes,
    String? contactEmail,
  }) async {
    final refusal = reportRefusal;
    if (refusal != null) throw refusal;
    reports.add({
      'courseId': courseId,
      'reason': reason,
      'notes': notes,
      'contactEmail': contactEmail,
    });
  }

  @override
  Future<Map<String, ParkCourseRecord>> fetchParkCourseRecords() async {
    if (failRecords) throw StateError('records network down');
    return records;
  }

  @override
  Future<List<GlobalSegmentLeaderboardEntry>> fetchGlobalSegmentLeaderboard(
    String segmentId, {
    String? gender,
    String? ageBand,
    String? clubId,
    int? season,
    int limit = 50,
  }) async {
    leaderboardSeasons.add(season);
    if (emptyBoards || (emptyThisSeasonOnly && season != null)) return [];
    final planted = seasonBoard;
    if (planted != null && season != null) return planted;
    return season == null
        ? [_fast('viewer-1', 'Me', 1, 400), _fast('u2', 'Bea', 2, 410)]
        : [_fast('u2', 'Bea', 1, 410), _fast('viewer-1', 'Me', 2, 430)];
  }

  @override
  Future<List<GlobalSegmentCompletionsEntry>> fetchGlobalSegmentCompletions(
    String segmentId, {
    int? season,
    int limit = 50,
  }) async {
    completionSeasons.add(season);
    if (emptyBoards) return [];
    return [
      GlobalSegmentCompletionsEntry(
        athlete: const PublicProfile(id: 'viewer-1', displayName: 'Me'),
        completions: 3,
        lastCompletedAt: DateTime.parse('2026-03-01T00:00:00Z'),
        rank: 1,
      ),
    ];
  }
}

Widget _host(Widget child, {double textScale = 1}) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, inner) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      textScaler: TextScaler.linear(textScale),
    ),
    child: inner!,
  ),
  home: child,
);

bool _supabaseReady = false;

Future<void> _ensureEnvironment() async {
  if (_supabaseReady) return;
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  dotenv.loadFromString(envString: '', isOptional: true);
  dotenv.env.clear();
  await initializeTestSupabase();
  _supabaseReady = true;
}

/// The fake reads resolve as microtasks; a few frames build what they bring.
/// No pumpAndSettle: the maps' tile layers keep timers alive.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump();
  }
}

/// The tile layers' load and retry timers outlive the frame; unmount the maps
/// and let them run out so the test ends with none pending.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 5));
}

/// Credits outside the course map: the basemap's own credit sits on the map,
/// and the course page must add exactly one line of its own.
int _creditsOffMap(WidgetTester tester, String needle) {
  final all = find.textContaining(needle).evaluate().length;
  final onMap = find
      .descendant(
        of: find.byType(ParkCourseMap),
        matching: find.textContaining(needle),
      )
      .evaluate()
      .length;
  return all - onMap;
}

Finder _inCard(String courseId, Finder f) =>
    find.descendant(of: find.byKey(ValueKey('park-course-$courseId')), matching: f);

void main() {
  setUpAll(_ensureEnvironment);

  // Tall enough that the course page's boards, below the map, are built.
  void tallView(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  void phoneView(WidgetTester tester) {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  final pocahontasCourses = [
    _course(id: 'beaver', name: 'Beaver Lake Trail', distanceM: 4000),
    _course(id: 'k10', name: '10K', distanceM: 10000, laps: 2),
    _course(id: 'k50', name: '50K', distanceM: 50000),
    _course(id: 'k5', name: '5K', distanceM: 5000),
    _course(id: 'half', name: 'Half marathon', distanceM: 21100),
    _course(id: 'full', name: 'Marathon', distanceM: 42200),
    _course(
      id: 'shut',
      name: 'Aaa Closed',
      distanceM: 1000,
      status: 'closed',
    ),
  ];

  group('ParksScreen', () {
    testWidgets('groups parks under their region, each a card with its '
        'courses, count and distance range', (tester) async {
      final api = _ParksApi(
        parks: [
          _park(id: 'p1', name: 'Pocahontas State Park'),
          _park(id: 'p2', name: 'Umstead State Park', region: 'US-NC'),
        ],
        courses: [
          _course(id: 'a', distanceM: 5000),
          _course(id: 'b', distanceM: 21100),
        ],
      );
      await tester.pumpWidget(_host(ParksScreen(api: api)));
      await _settle(tester);
      expect(find.text('Virginia'), findsOneWidget);
      expect(find.text('North Carolina'), findsOneWidget);
      expect(find.text('Pocahontas State Park'), findsOneWidget);
      expect(find.text('State park'), findsNWidgets(2));
      expect(find.byKey(const Key('parks-intro')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('parks-park-summary-p1')),
        findsOneWidget,
      );
      expect(find.text('2 courses · 5–21.1 km'), findsOneWidget);
      // Umstead has no courses in the fixture, so no summary and no map.
      expect(
        find.byKey(const ValueKey('parks-park-summary-p2')),
        findsNothing,
      );
      expect(find.byType(ParkOverviewMap), findsOneWidget);
      await _unmount(tester);
    });

    testWidgets('a failed course read still lists the parks', (tester) async {
      await tester.pumpWidget(
        _host(
          ParksScreen(
            api: _ParksApi(
              parks: [_park(id: 'p1', name: 'Pocahontas State Park')],
              failAllCourses: true,
            ),
          ),
        ),
      );
      await _settle(tester);
      expect(find.text('Pocahontas State Park'), findsOneWidget);
      expect(find.byType(ParkOverviewMap), findsNothing);
      expect(
        find.byKey(const ValueKey('parks-park-summary-p1')),
        findsNothing,
      );
    });

    testWidgets('says so when there are no parks', (tester) async {
      await tester.pumpWidget(_host(ParksScreen(api: _ParksApi())));
      await _settle(tester);
      expect(find.byKey(const Key('parks-empty')), findsOneWidget);
      expect(find.byType(EmptyState), findsOneWidget);
    });

    testWidgets('surfaces a failed read with a retry', (tester) async {
      await tester.pumpWidget(
        _host(ParksScreen(api: _ParksApi(failParks: true))),
      );
      await _settle(tester);
      expect(find.text("Couldn't load park courses."), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });
  });

  group('ParkScreen', () {
    testWidgets('lists courses shortest first with readable distances, the '
        'laps chip and no Loop label', (tester) async {
      tallView(tester);
      await tester.pumpWidget(
        _host(
          ParkScreen(
            api: _ParksApi(courses: pocahontasCourses),
            listing: _park(
              id: 'p1',
              name: 'Pocahontas State Park',
              websiteUrl: 'https://www.dcr.virginia.gov/state-parks/pocahontas',
            ),
          ),
        ),
      );
      await _settle(tester);
      final order = [
        'Beaver Lake Trail',
        '5K',
        '10K',
        'Half marathon',
        'Marathon',
        '50K',
        'Aaa Closed',
      ];
      final ys = [for (final n in order) tester.getTopLeft(find.text(n)).dy];
      for (var i = 1; i < ys.length; i++) {
        expect(ys[i], greaterThan(ys[i - 1]), reason: order[i]);
      }
      expect(find.text('5 km'), findsOneWidget);
      expect(find.text('21.1 km'), findsOneWidget);
      expect(find.text('42.2 km'), findsOneWidget);
      expect(find.text('50 km'), findsOneWidget);
      expect(find.textContaining('.00 km'), findsNothing);
      expect(find.text('Loop'), findsNothing);
      expect(
        find.byKey(const ValueKey('park-course-laps-k10')),
        findsOneWidget,
      );
      expect(_inCard('k10', find.text('2 laps')), findsOneWidget);
      expect(find.text('2 laps'), findsOneWidget);
      expect(_inCard('shut', find.text('Closed')), findsOneWidget);
      expect(find.text('7 courses'), findsOneWidget);
      expect(find.byKey(const Key('park-overview-map')), findsOneWidget);
      // The website is its own control, not run into the agency label.
      expect(find.byKey(const Key('park-website')), findsOneWidget);
      expect(find.text('Virginia · State park'), findsOneWidget);
      expect(find.byKey(const Key('park-not-affiliated')), findsOneWidget);
      await _unmount(tester);
    });

    testWidgets('shows each course\'s season record', (tester) async {
      tallView(tester);
      await tester.pumpWidget(
        _host(
          ParkScreen(
            api: _ParksApi(
              courses: [_course(id: 'a'), _course(id: 'b', name: 'Bluff')],
              records: const {
                'a': ParkCourseRecord(
                  season: 2026,
                  timeSeconds: 1500,
                  displayName: 'Bea',
                ),
              },
            ),
            listing: _park(id: 'p1', name: 'Pocahontas State Park'),
          ),
        ),
      );
      await _settle(tester);
      expect(
        _inCard('a', find.text('Fastest in 2026: 25:00 by Bea')),
        findsOneWidget,
      );
      expect(
        _inCard('b', find.textContaining('No time yet this season')),
        findsOneWidget,
      );
      await _unmount(tester);
    });

    testWidgets('a failed record read leaves the course list standing', (
      tester,
    ) async {
      tallView(tester);
      await tester.pumpWidget(
        _host(
          ParkScreen(
            api: _ParksApi(failRecords: true),
            listing: _park(id: 'p1', name: 'Pocahontas State Park'),
          ),
        ),
      );
      await _settle(tester);
      expect(find.text('Lake Loop'), findsOneWidget);
      expect(find.byKey(const Key('park-records-failed')), findsOneWidget);
      expect(find.textContaining('record:'), findsNothing);
      await _unmount(tester);
    });

    testWidgets('a signed-out reader gets the courses without records', (
      tester,
    ) async {
      tallView(tester);
      await tester.pumpWidget(
        _host(
          ParkScreen(
            api: _ParksApi(viewer: null),
            listing: _park(id: 'p1', name: 'Pocahontas State Park'),
          ),
        ),
      );
      await _settle(tester);
      expect(find.text('Lake Loop'), findsOneWidget);
      expect(find.byKey(const Key('park-records-failed')), findsNothing);
      expect(find.textContaining('this season'), findsNothing);
      await _unmount(tester);
    });

    testWidgets('fits a 360x640 phone at 2x text', (tester) async {
      phoneView(tester);
      await tester.pumpWidget(
        _host(
          ParkScreen(
            api: _ParksApi(courses: pocahontasCourses),
            listing: _park(
              id: 'p1',
              name: 'Pocahontas State Park',
              websiteUrl: 'https://example.org/park',
            ),
          ),
          textScale: 2,
        ),
      );
      await _settle(tester);
      expect(tester.takeException(), isNull);
      await _unmount(tester);
    });
  });

  group('ParkCourseScreen', () {
    testWidgets(
      'a course an organised group shares gets the give-way note, naming no one',
      (tester) async {
        tallView(tester);
        await tester.pumpWidget(
          _host(
            ParkCourseScreen(
              api: _ParksApi(),
              listing: _park(id: 'p1', name: 'Deep Run Park'),
              course: _course(
                name: 'Deep Run Park, 5 km',
                distanceM: 5000,
                sharedUse: 'saturday_morning_group',
              ),
            ),
          ),
        );
        await _settle(tester);
        final notices = find.byKey(const Key('park-course-notices'));
        final note = find.descendant(
          of: notices,
          matching: find.byKey(const Key('park-course-shared-use')),
        );
        expect(note, findsOneWidget);
        expect(
          find.descendant(
            of: note,
            matching: find.text(
              'Organised groups use these paths on Saturday mornings. '
              'Give way, and avoid timing an effort through them.',
            ),
          ),
          findsOneWidget,
        );
        expect(
          find.text(
            'Times here are Threkir times on these paths. '
            'They are not results of any event held on them.',
          ),
          findsOneWidget,
        );
        final y = (String k) => tester.getTopLeft(find.byKey(Key(k))).dy;
        expect(y('park-course-safety'), lessThan(y('park-course-shared-use')));
        expect(y('park-course-shared-use'), lessThan(y('park-course-times')));
        await _unmount(tester);
      },
    );

    testWidgets(
      'loads this season first, then all time, then completions',
      (tester) async {
        tallView(tester);
        final api = _ParksApi();
        await tester.pumpWidget(
          _host(
            ParkCourseScreen(
              api: api,
              listing: _park(id: 'p1', name: 'Pocahontas State Park'),
              course: _course(),
            ),
          ),
        );
        await _settle(tester);
        expect(api.leaderboardSeasons, [2026]);
        expect(find.byKey(const Key('park-course-notices')), findsOneWidget);
        expect(find.byKey(const Key('park-course-safety')), findsOneWidget);
        expect(
          find.byKey(const Key('park-course-not-affiliated')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('park-course-long')), findsNothing);
        expect(find.byKey(const Key('park-course-share-gpx')), findsOneWidget);
        expect(find.byKey(const Key('park-course-help')), findsOneWidget);
        expect(find.byKey(const Key('park-board-controls')), findsOneWidget);
        expect(find.text('This year (2026)'), findsOneWidget);
        expect(find.text('Bea'), findsOneWidget);

        await tester.tap(find.text('All time'));
        await _settle(tester);
        expect(api.leaderboardSeasons, [2026, null]);

        await tester.tap(find.text('Most completions'));
        await _settle(tester);
        expect(api.completionSeasons, [null]);
        expect(find.text('3 days'), findsOneWidget);
        await _unmount(tester);
      },
    );

    testWidgets(
        'a board row shows the time the server gave a real Beaver Lake run', (
      tester,
    ) async {
      tallView(tester);
      // The effort segment-match writes for the clean Beaver Lake run of
      // fixtures/park_course_runs.json (issue #1342 step 5c); the board RPC
      // hands its time back in whole seconds.
      final fixture = jsonDecode(
        File('../../fixtures/park_course_runs.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final clean = (fixture['cases'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((c) => c['key'] == 'beaver_clean');
      final matched = (clean['matched'] as Map<String, dynamic>)[
          'beaver-lake-trail'] as Map<String, dynamic>;
      final seconds = (matched['time_seconds'] as num).roundToDouble();
      final api = _ParksApi(
        seasonBoard: [_fast('u9', 'Beaver Runner', 1, seconds)],
      );
      await tester.pumpWidget(
        _host(
          ParkCourseScreen(
            api: api,
            listing: _park(id: 'p1', name: 'Pocahontas State Park'),
            course: _course(
              id: 'beaver',
              name: 'Beaver Lake Trail',
              distanceM: 3595,
            ),
          ),
        ),
      );
      await _settle(tester);
      expect(api.leaderboardSeasons, [2026]);
      expect(find.text('Beaver Runner'), findsOneWidget);
      final whole = seconds.toInt();
      final shown = '${whole ~/ 60}:${(whole % 60).toString().padLeft(2, '0')}';
      expect(find.text(shown), findsOneWidget);
      await _unmount(tester);
    });

    testWidgets('the safety notice leads the one notices block', (
      tester,
    ) async {
      tallView(tester);
      await tester.pumpWidget(
        _host(
          ParkCourseScreen(
            api: _ParksApi(),
            listing: _park(id: 'p1', name: 'Pocahontas State Park'),
            course: _course(distanceM: 21100),
          ),
        ),
      );
      await _settle(tester);
      final notices = find.byKey(const Key('park-course-notices'));
      for (final k in [
        'park-course-safety',
        'park-course-long',
        'park-course-times',
        'park-course-not-affiliated',
      ]) {
        expect(
          find.descendant(of: notices, matching: find.byKey(Key(k))),
          findsOneWidget,
          reason: k,
        );
      }
      final y = (String k) => tester.getTopLeft(find.byKey(Key(k))).dy;
      expect(y('park-course-safety'), lessThan(y('park-course-long')));
      expect(y('park-course-long'), lessThan(y('park-course-times')));
      expect(
        y('park-course-times'),
        lessThan(y('park-course-not-affiliated')),
      );
      expect(find.byKey(const Key('park-course-shared-use')), findsNothing);
      expect(
        find.textContaining(
          'Start early enough to finish before the park closes.',
        ),
        findsOneWidget,
      );
      expect(find.text('21.1 km'), findsOneWidget);
      await _unmount(tester);
    });

    testWidgets('the route guide sits above the notices under its draft note', (
      tester,
    ) async {
      tallView(tester);
      await tester.pumpWidget(
        _host(
          ParkCourseScreen(
            api: _ParksApi(),
            listing: _park(id: 'p1', name: 'Pocahontas State Park'),
            course: _course(
              routeGuide: {
                'version': 1,
                'lang': 'en',
                'getting_there': 'Park by the boathouse.',
                'steps': [
                  {'kind': 'start', 'at_m': 0, 'name': 'Lake Trail'},
                  {
                    'kind': 'junction',
                    'at_m': 400,
                    'turn': 'left',
                    'name': 'Ridge Trail',
                  },
                  {'kind': 'finish', 'at_m': 1990},
                ],
              },
            ),
          ),
        ),
      );
      await _settle(tester);
      final guide = find.byKey(const Key('park-course-guide'));
      expect(guide, findsOneWidget);
      expect(find.text('Route guide'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('park-course-guide-pending')),
          matching: find.text(
            'Drafted from map data, not yet checked on the ground.',
          ),
        ),
        findsOneWidget,
      );
      expect(find.text('Park by the boathouse.'), findsOneWidget);
      final steps = find.byKey(const Key('park-course-guide-steps'));
      expect(
        find.descendant(of: steps, matching: find.text('Start on Lake Trail.')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: steps,
          matching: find.textContaining('turn left onto Ridge Trail.'),
        ),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(guide).dy,
        lessThan(
          tester.getTopLeft(find.byKey(const Key('park-course-notices'))).dy,
        ),
      );
      await _unmount(tester);
    });

    testWidgets('a guide checked on the ground says when, not the draft note', (
      tester,
    ) async {
      tallView(tester);
      await tester.pumpWidget(
        _host(
          ParkCourseScreen(
            api: _ParksApi(),
            listing: _park(id: 'p1', name: 'Pocahontas State Park'),
            course: _course(
              routeGuide: {
                'version': 1,
                'lang': 'en',
                'steps': [
                  {'kind': 'start', 'at_m': 0, 'way': 'path'},
                  {'kind': 'finish', 'at_m': 1100},
                ],
              },
              routeGuideCheckedAt: DateTime(2026, 12, 1),
            ),
          ),
        ),
      );
      await _settle(tester);
      expect(find.byKey(const Key('park-course-guide-pending')), findsNothing);
      expect(
        find.text('Checked on the ground on Dec 1, 2026.'),
        findsOneWidget,
      );
      await _unmount(tester);
    });

    testWidgets('no route guide, or an unreadable one, shows no guide section', (
      tester,
    ) async {
      tallView(tester);
      for (final raw in <Object?>[
        null,
        {'version': 1, 'lang': 'en', 'steps': []},
      ]) {
        await tester.pumpWidget(
          _host(
            ParkCourseScreen(
              api: _ParksApi(),
              listing: _park(id: 'p1', name: 'Pocahontas State Park'),
              course: _course(routeGuide: raw),
            ),
          ),
        );
        await _settle(tester);
        expect(find.byKey(const Key('park-course-guide')), findsNothing);
        expect(find.byKey(const Key('park-course-notices')), findsOneWidget);
        await _unmount(tester);
      }
    });

    testWidgets('the map carries a legend for every mark it draws', (
      tester,
    ) async {
      tallView(tester);
      await tester.pumpWidget(
        _host(
          ParkCourseScreen(
            api: _ParksApi(),
            listing: _park(id: 'p1', name: 'Pocahontas State Park'),
            course: _course(
              checkpoints: const [
                {'lat': 37.004, 'lng': -77.0},
                {'lat': 37.008, 'lng': -77.0},
              ],
            ),
          ),
        ),
      );
      await _settle(tester);
      expect(find.byKey(const Key('park-course-map')), findsOneWidget);
      expect(find.byKey(const Key('park-course-legend')), findsOneWidget);
      // The fixture loop starts and finishes in one place.
      expect(
        find.byKey(const Key('park-course-legend-start-finish')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('park-course-legend-start')), findsNothing);
      expect(
        find.byKey(const Key('park-course-legend-checkpoints')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('park-course-legend-direction')),
        findsOneWidget,
      );
      expect(find.text('Checkpoint: your run must pass it'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('Course map with 2 checkpoints')),
        findsOneWidget,
      );
      expect(find.byType(ElevationChart), findsOneWidget);
      expect(find.text('Elevation profile'), findsOneWidget);
      await _unmount(tester);
    });

    testWidgets('a point-to-point course names its start and its finish', (
      tester,
    ) async {
      tallView(tester);
      await tester.pumpWidget(
        _host(
          ParkCourseScreen(
            api: _ParksApi(),
            listing: _park(id: 'p1', name: 'Pocahontas State Park'),
            course: _course(
              shape: 'point_to_point',
              waypoints: [
                for (var i = 0; i < 6; i++)
                  {'lat': 37.0 + i * 0.002, 'lng': -77.0},
              ],
            ),
          ),
        ),
      );
      await _settle(tester);
      expect(find.byKey(const Key('park-course-legend-start')), findsOneWidget);
      expect(
        find.byKey(const Key('park-course-legend-finish')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('park-course-legend-checkpoints')), findsNothing);
      expect(find.text('Point to point'), findsOneWidget);
      // No elevation on these points, so no profile.
      expect(find.byType(ElevationChart), findsNothing);
      await _unmount(tester);
    });

    testWidgets('one credit line, from the attribution column', (
      tester,
    ) async {
      tallView(tester);
      const credit = '© OpenStreetMap contributors (ODbL); elevation: USGS 3DEP';
      await tester.pumpWidget(
        _host(
          ParkCourseScreen(
            api: _ParksApi(),
            listing: _park(id: 'p1', name: 'Pocahontas State Park'),
            course: _course(
              attribution: credit,
              description: 'Run it clockwise.',
            ),
          ),
        ),
      );
      await _settle(tester);
      expect(find.text(credit), findsOneWidget);
      expect(_creditsOffMap(tester, 'OpenStreetMap'), 1);
      expect(find.text('Run it clockwise.'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('park-course-attribution'))).data,
        credit,
      );
      await _unmount(tester);
    });

    testWidgets('the credit falls back to the geometry source label', (
      tester,
    ) async {
      tallView(tester);
      await tester.pumpWidget(
        _host(
          ParkCourseScreen(
            api: _ParksApi(),
            listing: _park(id: 'p1', name: 'Pocahontas State Park'),
            course: _course(),
          ),
        ),
      );
      await _settle(tester);
      expect(
        tester.widget<Text>(find.byKey(const Key('park-course-attribution'))).data,
        'Course line © OpenStreetMap contributors',
      );
      expect(_creditsOffMap(tester, 'OpenStreetMap'), 1);
      await _unmount(tester);
    });

    testWidgets('Navigate is the one filled action when the course has a '
        'route, with GPX beside it', (tester) async {
      tallView(tester);
      await tester.pumpWidget(
        _host(
          ParkCourseScreen(
            api: _ParksApi(),
            listing: _park(id: 'p1', name: 'Pocahontas State Park'),
            course: _course(routeId: 'route-1'),
          ),
        ),
      );
      await _settle(tester);
      expect(
        find.descendant(
          of: find.byKey(const Key('park-course-navigate')),
          matching: find.text('Navigate this course'),
        ),
        findsOneWidget,
      );
      expect(find.byWidgetPredicate((w) => w is FilledButton), findsOneWidget);
      expect(
        find.ancestor(
          of: find.text('Share GPX'),
          matching: find.byWidgetPredicate((w) => w is OutlinedButton),
        ),
        findsOneWidget,
      );
      await _unmount(tester);
    });

    testWidgets('an empty board is an invitation, with its filters hidden', (
      tester,
    ) async {
      tallView(tester);
      final api = _ParksApi(emptyBoards: true);
      await tester.pumpWidget(
        _host(
          ParkCourseScreen(
            api: api,
            listing: _park(id: 'p1', name: 'Pocahontas State Park'),
            course: _course(),
          ),
        ),
      );
      await _settle(tester);
      expect(find.byKey(const Key('park-board-invitation')), findsOneWidget);
      expect(find.text('No times yet. Yours could be the first.'), findsOneWidget);
      expect(find.byKey(const Key('park-board-controls')), findsNothing);
      expect(find.byKey(const Key('park-board-kind')), findsNothing);
      expect(find.byKey(const Key('park-board-season')), findsNothing);
      expect(find.text('Compare with a friend'), findsNothing);
      expect(find.text('All genders'), findsNothing);
      // The all-time completions board is what said nobody has run it.
      expect(api.completionSeasons, [null]);
      await _unmount(tester);
    });

    testWidgets('an empty season with older times keeps the filters', (
      tester,
    ) async {
      tallView(tester);
      await tester.pumpWidget(
        _host(
          ParkCourseScreen(
            api: _ParksApi(emptyThisSeasonOnly: true),
            listing: _park(id: 'p1', name: 'Pocahontas State Park'),
            course: _course(),
          ),
        ),
      );
      await _settle(tester);
      expect(find.byKey(const Key('park-board-invitation')), findsNothing);
      expect(find.byKey(const Key('park-board-controls')), findsOneWidget);
      expect(
        find.textContaining('No times on this board yet'),
        findsOneWidget,
      );
      await _unmount(tester);
    });

    testWidgets('shows the closed banner on a closed course', (tester) async {
      tallView(tester);
      await tester.pumpWidget(
        _host(
          ParkCourseScreen(
            api: _ParksApi(),
            listing: _park(id: 'p1', name: 'Pocahontas State Park'),
            course: _course(status: 'closed', routeId: 'route-1'),
          ),
        ),
      );
      await _settle(tester);
      expect(find.byKey(const Key('park-course-closed')), findsOneWidget);
      // A closed course offers nothing to follow, the GPX included.
      expect(find.byKey(const Key('park-course-share-gpx')), findsNothing);
      expect(find.byKey(const Key('park-course-navigate')), findsNothing);
      expect(find.byKey(const Key('park-course-safety')), findsOneWidget);
      await _unmount(tester);
    });

    testWidgets('asks a signed-out reader to sign in for boards', (
      tester,
    ) async {
      tallView(tester);
      final api = _ParksApi(viewer: null);
      await tester.pumpWidget(
        _host(
          ParkCourseScreen(
            api: api,
            listing: _park(id: 'p1', name: 'Pocahontas State Park'),
            course: _course(),
          ),
        ),
      );
      await _settle(tester);
      expect(api.leaderboardSeasons, isEmpty);
      expect(find.text("Sign in to see this course's boards."), findsOneWidget);
      await _unmount(tester);
    });

    testWidgets('fits a 360x640 phone at 2x text', (tester) async {
      phoneView(tester);
      await tester.pumpWidget(
        _host(
          ParkCourseScreen(
            api: _ParksApi(),
            listing: _park(id: 'p1', name: 'Pocahontas State Park'),
            course: _course(
              laps: 2,
              routeId: 'route-1',
              distanceM: 21100,
              checkpoints: const [
                {'lat': 37.004, 'lng': -77.0},
              ],
            ),
          ),
          textScale: 2,
        ),
      );
      await _settle(tester);
      expect(tester.takeException(), isNull);
      await _unmount(tester);
    });
  });

  group('report a problem with this course', () {
    Future<void> openSheet(WidgetTester tester, _ParksApi api) async {
      tester.view.physicalSize = const Size(800, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _host(
          ParkCourseScreen(
            api: api,
            listing: _park(id: 'p1', name: 'Pocahontas State Park'),
            course: _course(routeId: 'route-1'),
          ),
        ),
      );
      await _settle(tester);
      final entry = find.byKey(const Key('park-course-report'));
      await tester.ensureVisible(entry);
      await tester.tap(entry);
      await _settle(tester);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('park-course-report-sheet')), findsOneWidget);
    }

    testWidgets('sits at the foot of the page, after the boards, not beside Navigate', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _host(
          ParkCourseScreen(
            api: _ParksApi(),
            listing: _park(id: 'p1', name: 'Pocahontas State Park'),
            course: _course(routeId: 'route-1'),
          ),
        ),
      );
      await _settle(tester);
      final report = tester.getTopLeft(find.byKey(const Key('park-course-report')));
      final navigate = tester.getTopLeft(find.byKey(const Key('park-course-navigate')));
      final boards = tester.getTopLeft(find.byKey(const Key('park-board-controls')));
      expect(report.dy, greaterThan(boards.dy));
      expect(report.dy, greaterThan(navigate.dy));
      expect(find.text('Report a problem with this course'), findsOneWidget);
      await _unmount(tester);
    });

    testWidgets('files a land-manager request with its note and email', (
      tester,
    ) async {
      final api = _ParksApi();
      await openSheet(tester, api);
      final submit = find.byKey(const Key('park-course-report-submit'));
      expect(tester.widget<FilledButton>(submit).onPressed, isNull);

      await tester.tap(
        find.byKey(const Key('park-course-report-reason-land_manager_request')),
      );
      await tester.enterText(
        find.byKey(const Key('park-course-report-notes')),
        'Please take this course down for restoration.',
      );
      await tester.enterText(
        find.byKey(const Key('park-course-report-email')),
        'not an email',
      );
      await tester.pump();
      expect(find.text("That email address doesn't look right."), findsOneWidget);
      expect(tester.widget<FilledButton>(submit).onPressed, isNull);

      await tester.enterText(
        find.byKey(const Key('park-course-report-email')),
        'ranger@park.example',
      );
      await tester.pump();
      await tester.tap(submit);
      await _settle(tester);
      await tester.pump(const Duration(milliseconds: 400));

      expect(api.reports, [
        {
          'courseId': 'c1',
          'reason': 'land_manager_request',
          'notes': 'Please take this course down for restoration.',
          'contactEmail': 'ranger@park.example',
        },
      ]);
      expect(find.byKey(const Key('park-course-report-sheet')), findsNothing);
      await _unmount(tester);
    });

    testWidgets('a rights-holder request is not sent without an address', (
      tester,
    ) async {
      final api = _ParksApi();
      await openSheet(tester, api);
      final submit = find.byKey(const Key('park-course-report-submit'));
      final reason =
          find.byKey(const Key('park-course-report-reason-rights_holder_request'));
      await tester.ensureVisible(reason);
      await tester.tap(reason);
      await tester.enterText(
        find.byKey(const Key('park-course-report-notes')),
        'This course description uses our event name.',
      );
      await tester.pump();
      expect(
        find.textContaining(
          'We acknowledge your request within two business days.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Needed for a rights-holder request so we can answer it. '
          'We delete it 30 days after we resolve the request.',
        ),
        findsOneWidget,
      );
      expect(tester.widget<FilledButton>(submit).onPressed, isNull);

      await tester.enterText(
        find.byKey(const Key('park-course-report-email')),
        'legal@brand.example',
      );
      await tester.pump();
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await _settle(tester);
      await tester.pump(const Duration(milliseconds: 400));

      expect(api.reports, [
        {
          'courseId': 'c1',
          'reason': 'rights_holder_request',
          'notes': 'This course description uses our event name.',
          'contactEmail': 'legal@brand.example',
        },
      ]);
      await _unmount(tester);
    });

    testWidgets('the function refusing a request with no address is worded', (
      tester,
    ) async {
      final api = _ParksApi()
        ..reportRefusal = const FunctionException(
          status: 400,
          details: {'error': 'email_required'},
        );
      await openSheet(tester, api);
      await tester.enterText(
        find.byKey(const Key('park-course-report-notes')),
        'A tree is down.',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('park-course-report-submit')));
      await _settle(tester);
      expect(
        find.text(
          'A rights-holder request needs an email address so we can answer it.',
        ),
        findsOneWidget,
      );
      await _unmount(tester);
    });

    testWidgets('a refusal is worded in the sheet and nothing is filed', (
      tester,
    ) async {
      final api = _ParksApi()
        ..reportRefusal = const FunctionException(
          status: 409,
          details: {'error': 'already_reported'},
        );
      await openSheet(tester, api);
      await tester.enterText(
        find.byKey(const Key('park-course-report-notes')),
        'A tree is down.',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('park-course-report-submit')));
      await _settle(tester);
      expect(
        find.text(
          "You've already reported this course, and that report is still open.",
        ),
        findsOneWidget,
      );
      expect(api.reports, isEmpty);
      expect(find.byKey(const Key('park-course-report-sheet')), findsOneWidget);
      await _unmount(tester);
    });
  });
}

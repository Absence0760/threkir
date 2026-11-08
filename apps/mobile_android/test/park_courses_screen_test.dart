import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/park_courses_screen.dart';
import 'supabase_test_init.dart';

ParkListing _park({
  required String id,
  required String name,
  String region = 'US-VA',
  String agency = 'state',
}) => ParkListing(
  park: ParkRow(
    id: id,
    slug: name.toLowerCase().replaceAll(' ', '-'),
    name: name,
    agency: agency,
    regionCode: region,
    countryCode: 'US',
    timezone: 'America/New_York',
    isActive: true,
    createdAt: DateTime.parse('2026-01-01T00:00:00Z'),
  ),
  season: 2026,
);

ParkCourseListing _course({String status = 'open'}) => ParkCourseListing(
  course: ParkCourseRow(
    id: 'c1',
    parkId: 'p1',
    globalSegmentId: 's1',
    slug: 'lake-loop',
    courseShape: 'loop',
    status: status,
    geometrySource: 'osm',
    checkpoints: const [],
    createdAt: DateTime.parse('2026-01-01T00:00:00Z'),
  ),
  segment: GlobalSegmentRow(
    id: 's1',
    name: 'Lake Loop',
    waypoints: const [
      {'lat': 37.0, 'lng': -77.0},
      {'lat': 37.01, 'lng': -77.0},
    ],
    distanceM: 1100,
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
    globalSegmentId: 's1',
    runId: 'r-$userId',
    userId: userId,
    timeSeconds: t,
    startedAt: DateTime.parse('2026-02-01T00:00:00Z'),
    createdAt: DateTime.parse('2026-02-01T00:00:00Z'),
  ),
  athlete: PublicProfile(id: userId, displayName: name),
  rank: rank,
);

class _ParksApi extends ApiClient {
  _ParksApi({
    this.parks = const [],
    this.viewer = 'viewer-1',
    this.failParks = false,
  });

  final List<ParkListing> parks;
  final String? viewer;
  final bool failParks;
  final List<int?> leaderboardSeasons = [];
  final List<int?> completionSeasons = [];

  @override
  String? get userId => viewer;

  @override
  Future<List<ParkListing>> fetchParks() async {
    if (failParks) throw StateError('parks network down');
    return parks;
  }

  @override
  Future<List<ParkCourseListing>> fetchParkCourses(String parkId) async => [
    _course(),
  ];

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

Widget _host(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
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

void main() {
  setUpAll(_ensureEnvironment);

  // Tall enough that the course page's boards, below the map, are built.
  void tallView(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('ParksScreen groups parks under their region name', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        ParksScreen(
          api: _ParksApi(
            parks: [
              _park(id: 'p1', name: 'Pocahontas State Park'),
              _park(id: 'p2', name: 'Umstead State Park', region: 'US-NC'),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Virginia'), findsOneWidget);
    expect(find.text('North Carolina'), findsOneWidget);
    expect(find.text('Pocahontas State Park'), findsOneWidget);
    expect(find.text('State park'), findsNWidgets(2));
  });

  testWidgets('ParksScreen says so when there are no parks', (tester) async {
    await tester.pumpWidget(_host(ParksScreen(api: _ParksApi())));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('parks-empty')), findsOneWidget);
  });

  testWidgets('ParksScreen surfaces a failed read with a retry', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(ParksScreen(api: _ParksApi(failParks: true))),
    );
    await tester.pumpAndSettle();
    expect(find.text("Couldn't load park courses."), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('ParkScreen lists the park courses', (tester) async {
    await tester.pumpWidget(
      _host(
        ParkScreen(
          api: _ParksApi(),
          listing: _park(id: 'p1', name: 'Pocahontas State Park'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Lake Loop'), findsOneWidget);
  });

  testWidgets(
    'ParkCourseScreen loads this season first, then all time, then completions',
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
      await tester.pumpAndSettle();
      expect(api.leaderboardSeasons, [2026]);
      expect(find.byKey(const Key('park-course-safety')), findsOneWidget);
      expect(find.byKey(const Key('park-course-attribution')), findsOneWidget);
      expect(find.byKey(const Key('park-course-share-gpx')), findsOneWidget);
      expect(find.text('This year (2026)'), findsOneWidget);
      expect(find.text('Bea'), findsOneWidget);

      await tester.tap(find.text('All time'));
      await tester.pumpAndSettle();
      expect(api.leaderboardSeasons, [2026, null]);

      await tester.tap(find.text('Most completions'));
      await tester.pumpAndSettle();
      expect(api.completionSeasons, [null]);
      expect(find.text('3 days'), findsOneWidget);
    },
  );

  testWidgets('ParkCourseScreen shows the closed banner on a closed course', (
    tester,
  ) async {
    tallView(tester);
    await tester.pumpWidget(
      _host(
        ParkCourseScreen(
          api: _ParksApi(),
          listing: _park(id: 'p1', name: 'Pocahontas State Park'),
          course: _course(status: 'closed'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('park-course-closed')), findsOneWidget);
    // A closed course offers nothing to follow, the GPX included.
    expect(find.byKey(const Key('park-course-share-gpx')), findsNothing);
    expect(find.byKey(const Key('park-course-safety')), findsOneWidget);
  });

  testWidgets(
    'ParkCourseScreen asks a signed-out reader to sign in for boards',
    (tester) async {
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
      await tester.pumpAndSettle();
      expect(api.leaderboardSeasons, isEmpty);
      expect(find.text("Sign in to see this course's boards."), findsOneWidget);
    },
  );
}

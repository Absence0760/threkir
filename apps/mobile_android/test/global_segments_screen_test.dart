import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import 'package:ui_kit/ui_kit.dart' show EmptyState;

import '../lib/fitness_surface_requests.dart';
import '../lib/screens/global_segments_screen.dart';
import '../lib/screens/park_courses_screen.dart';
import '../lib/screens/races_screen.dart';
import '../lib/routes_views.dart';
import 'supabase_test_init.dart';
import 'worst_case_layout.dart';

GlobalSegmentRow _segment({
  required String id,
  required String name,
  String surface = 'road',
  String? region,
  double distanceM = 1200,
  double? elevationM = 12,
  String? description,
  List<Map<String, dynamic>> waypoints = const [],
}) =>
    GlobalSegmentRow(
      id: id,
      name: name,
      description: description,
      waypoints: waypoints,
      distanceM: distanceM,
      elevationM: elevationM,
      surface: surface,
      region: region,
      isActive: true,
      createdAt: DateTime.parse('2026-01-01T00:00:00Z'),
    );

final _catalogue = [
  _segment(
    id: 'a',
    name: 'Champs-Élysées Sprint',
    region: 'Paris, FR',
    distanceM: 2135,
    elevationM: 0,
  ),
  _segment(
    id: 'b',
    name: 'Harlem Hill',
    region: 'New York, US',
    surface: 'trail',
    distanceM: 857,
    elevationM: 18,
  ),
];

class _CatalogueApi extends ApiClient {
  _CatalogueApi(
    this.segments, {
    this.viewer = 'viewer-1',
    this.credit,
    this.parkCourse = false,
  });

  final List<GlobalSegmentRow> segments;
  final String? viewer;

  /// The park course credit (`park_courses.attribution`) every segment
  /// reads as; null for a segment no park course is built on.
  final String? credit;

  /// The park course every segment is built on, carrying [credit]; null for
  /// none.
  final bool parkCourse;

  @override
  Future<({ParkListing park, ParkCourseListing course})?>
      fetchParkCourseForSegment(String segmentId) async {
    if (!parkCourse && credit == null) return null;
    final segment = segments.firstWhere((s) => s.id == segmentId);
    final created = DateTime.parse('2026-01-01T00:00:00Z');
    return (
      park: ParkListing(
        park: ParkRow(
          id: 'p1',
          slug: 'beaver-lake',
          name: 'Beaver Lake Park',
          agency: 'state',
          regionCode: 'US-VA',
          countryCode: 'US',
          timezone: 'America/New_York',
          isActive: true,
          createdAt: created,
        ),
        season: 2026,
      ),
      course: ParkCourseListing(
        course: ParkCourseRow(
          id: 'c1',
          parkId: 'p1',
          globalSegmentId: segmentId,
          slug: 'loop',
          courseShape: 'loop',
          status: 'open',
          geometrySource: 'osm',
          checkpoints: const [],
          attribution: credit,
          createdAt: created,
        ),
        segment: segment,
      ),
    );
  }

  @override
  String? get userId => viewer;

  @override
  Future<List<GlobalSegmentRow>> fetchGlobalSegments({
    int limit = kGlobalSegmentCatalogueLimit,
  }) async =>
      segments;

  @override
  Future<GlobalSegmentRow?> fetchGlobalSegment(String id) async =>
      segments.where((s) => s.id == id).firstOrNull;

  @override
  Future<List<GlobalSegmentLeaderboardEntry>> fetchGlobalSegmentLeaderboard(
    String segmentId, {
    String? gender,
    String? ageBand,
    String? clubId,
    int? season,
    int limit = 50,
  }) async =>
      const [];
}

class _NoParksApi extends _CatalogueApi {
  _NoParksApi() : super(const []);

  @override
  Future<List<ParkListing>> fetchParks() async => const [];
}

class _ThrowingCatalogueApi extends ApiClient {
  @override
  String? get userId => 'viewer-1';

  @override
  Future<List<GlobalSegmentRow>> fetchGlobalSegments({
    int limit = kGlobalSegmentCatalogueLimit,
  }) async =>
      throw StateError('catalogue network down');
}

class _BoardApi extends _CatalogueApi {
  _BoardApi(super.segments, this.board);

  final List<GlobalSegmentLeaderboardEntry> board;

  @override
  Future<List<GlobalSegmentLeaderboardEntry>> fetchGlobalSegmentLeaderboard(
    String segmentId, {
    String? gender,
    String? ageBand,
    String? clubId,
    int? season,
    int limit = 50,
  }) async =>
      board;
}

class _ZoneNoteApi extends _CatalogueApi {
  _ZoneNoteApi(super.segments, {required this.hasZone});

  final bool hasZone;
  int asked = 0;

  @override
  Future<bool> globalSegmentHasZoneEfforts(String segmentId) async {
    asked++;
    return hasZone;
  }
}

GlobalSegmentRow _gatedSegment(String id) => GlobalSegmentRow(
      id: id,
      name: 'Harlem Hill',
      waypoints: const [],
      distanceM: 857,
      surface: 'road',
      isActive: true,
      createdAt: DateTime.parse('2026-01-01T00:00:00Z'),
      startGateLat: 40.79,
      startGateLng: -73.95,
      startGateBearingDeg: 0,
      startGateHalfWidthM: 15,
      startGateSource: 'derived',
      endGateLat: 40.8,
      endGateLng: -73.95,
      endGateBearingDeg: 0,
      endGateHalfWidthM: 15,
      endGateSource: 'derived',
    );

const _oldMatchNote = 'Some older efforts were measured the old way, by '
    'passing near the start and finish rather than crossing the lines. Each is '
    're-measured the next time its runner opens the run.';

class _ThrowingBoardApi extends _CatalogueApi {
  _ThrowingBoardApi(super.segments);

  @override
  Future<List<GlobalSegmentLeaderboardEntry>> fetchGlobalSegmentLeaderboard(
    String segmentId, {
    String? gender,
    String? ageBand,
    String? clubId,
    int? season,
    int limit = 50,
  }) async =>
      throw StateError('leaderboard network down');
}

GlobalSegmentLeaderboardEntry _entry(String userId, String name, int rank) =>
    GlobalSegmentLeaderboardEntry(
      effort: GlobalSegmentEffortRow(
        id: 'e-$userId',
        globalSegmentId: 'a',
        runId: 'r-$userId',
        userId: userId,
        timeSeconds: 300.0 + rank,
        startedAt: DateTime.parse('2026-02-01T00:00:00Z'),
        createdAt: DateTime.parse('2026-02-01T00:00:00Z'),
        matchedBy: 'zone',
      ),
      athlete: PublicProfile(id: userId, displayName: name),
      rank: rank,
    );

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

  group('GlobalSegmentsScreen — browse', () {
    worstCaseTestWidgets('the segment cards', (tester, locale) async {
      await tester.pumpWidget(worstCaseApp(
        locale: locale,
        home: GlobalSegmentsScreen(api: _CatalogueApi(_catalogue)),
      ));
      await tester.pump();
      await tester.pump();
      await walkScrollable(tester, primaryScrollable(), 'Segments');
    });

    worstCaseTestWidgets('the park course link', (tester, locale) async {
      final api = _CatalogueApi(
        [_segment(id: 'a', name: 'Beaver Lake Trail')],
        parkCourse: true,
      );
      await tester.pumpWidget(worstCaseApp(
        locale: locale,
        home: GlobalSegmentDetailScreen(api: api, segmentId: 'a'),
      ));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      await walkScrollable(tester, primaryScrollable(), 'Segment detail');
    });

    testWidgets('renders one card per catalogue segment with its region',
        (tester) async {
      await tester.pumpWidget(_host(GlobalSegmentsScreen(api: _CatalogueApi(_catalogue))));
      await tester.pumpAndSettle();
      expect(find.text('Champs-Élysées Sprint'), findsOneWidget);
      expect(find.text('Harlem Hill'), findsOneWidget);
      expect(find.text('Paris, FR'), findsOneWidget);
      expect(find.text('2 segments'), findsOneWidget);
    });

    testWidgets('an accent-free query still reaches an accented name',
        (tester) async {
      await tester.pumpWidget(_host(GlobalSegmentsScreen(api: _CatalogueApi(_catalogue))));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'champs-elysees');
      await tester.pumpAndSettle();
      expect(find.text('Champs-Élysées Sprint'), findsOneWidget);
      expect(find.text('Harlem Hill'), findsNothing);
      expect(find.text('1 segment'), findsOneWidget);
    });

    testWidgets('a query that matches nothing says so rather than showing zero',
        (tester) async {
      await tester.pumpWidget(_host(GlobalSegmentsScreen(api: _CatalogueApi(_catalogue))));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'nowhere at all');
      await tester.pumpAndSettle();
      expect(
        find.text('No segments match these filters — try widening them.'),
        findsOneWidget,
      );
      expect(find.text('0 segments'), findsNothing);
      expect(find.byType(EmptyState), findsOneWidget);
    });

    testWidgets('resetting from the no-match state clears the search field too',
        (tester) async {
      await tester.pumpWidget(_host(GlobalSegmentsScreen(api: _CatalogueApi(_catalogue))));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'nowhere at all');
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
          of: find.byType(EmptyState), matching: find.text('Reset')));
      await tester.pumpAndSettle();
      expect(find.byType(EmptyState), findsNothing);
      expect(find.text('2 segments'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
          isEmpty);
    });

    testWidgets('the surface filter narrows to that surface only',
        (tester) async {
      await tester.pumpWidget(_host(GlobalSegmentsScreen(api: _CatalogueApi(_catalogue))));
      await tester.pumpAndSettle();
      // Surface waits in the Filters sheet, and shows as a removable chip.
      await tester.tap(find.byTooltip('Filters'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Trail'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(InputChip, 'Trail'), findsOneWidget);
      expect(find.text('Harlem Hill'), findsOneWidget);
      expect(find.text('Champs-Élysées Sprint'), findsNothing);
    });

    testWidgets('a failed catalogue load offers a retry, not an empty state',
        (tester) async {
      await tester.pumpWidget(_host(GlobalSegmentsScreen(api: _ThrowingCatalogueApi())));
      await tester.pumpAndSettle();
      expect(
        find.text('Couldn’t load the segment catalogue.'),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);
      expect(
        find.text('No famous segments in the catalogue yet.'),
        findsNothing,
      );
    });

    testWidgets('an empty catalogue renders the shared empty state',
        (tester) async {
      await tester.pumpWidget(_host(GlobalSegmentsScreen(api: _NoParksApi())));
      await tester.pumpAndSettle();
      final empty = find.byType(EmptyState);
      expect(empty, findsOneWidget);
      expect(
        find.descendant(
            of: empty,
            matching: find.text('No famous segments in the catalogue yet.')),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsNothing);
    });

    // Under the Routes tab (issue #1374, decisions § 2490) the catalogue is
    // Explore → Segments: the tab hands it the Mine · Explore row and the
    // Routes · Segments chips, which sit above the list, and stay when the
    // catalogue is empty so the runner can still switch back.
    RoutesExploreChrome chrome() => RoutesExploreChrome(
          viewBar: const SizedBox(key: Key('test-view-bar'), height: 40),
          chips: [
            FilterChip(
              key: const Key('test-chip-segments'),
              label: const Text('Segments'),
              selected: true,
              onSelected: (_) {},
            ),
          ],
        );

    testWidgets('a chrome puts the view row and its chips above the list',
        (tester) async {
      await tester.pumpWidget(_host(GlobalSegmentsScreen(
          api: _CatalogueApi(_catalogue), chrome: chrome())));
      await tester.pumpAndSettle();
      final viewBar = find.byKey(const Key('test-view-bar'));
      final chip = find.byKey(const Key('test-chip-segments'));
      final card = find.text('Champs-Élysées Sprint');
      expect(viewBar, findsOneWidget);
      expect(chip, findsOneWidget);
      expect(card, findsOneWidget);
      expect(tester.getTopLeft(viewBar).dy,
          lessThan(tester.getTopLeft(chip).dy));
      expect(tester.getTopLeft(chip).dy, lessThan(tester.getTopLeft(card).dy));
    });

    testWidgets('an empty catalogue keeps the view row and its chips',
        (tester) async {
      await tester.pumpWidget(
          _host(GlobalSegmentsScreen(api: _NoParksApi(), chrome: chrome())));
      await tester.pumpAndSettle();
      expect(find.byType(EmptyState), findsOneWidget);
      expect(find.byKey(const Key('test-view-bar')), findsOneWidget);
      expect(find.byKey(const Key('test-chip-segments')), findsOneWidget);
    });

    // Park courses live in Races & courses (decisions § 2480). With no shell
    // to ask, the action opens that screen on its Courses view.
    testWidgets('the empty catalogue points to the Courses view of Races & '
        'courses', (tester) async {
      await tester.pumpWidget(_host(GlobalSegmentsScreen(api: _NoParksApi())));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
          of: find.byType(EmptyState), matching: find.text('Park courses')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(ParksScreen), findsNothing);
      expect(tester.widget<RacesScreen>(find.byType(RacesScreen)).initialShow,
          RacesShow.courses);
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Courses'))
            .selected,
        isTrue,
      );
    });

    testWidgets('with a shell listening, Park courses asks it for Races & '
        'courses on Courses and pushes nothing', (tester) async {
      final drained = <FitnessSurfaceRequest?>[];
      void shell() => drained.add(fitnessSurfaceRequests.take());
      fitnessSurfaceRequests.addListener(shell);
      addTearDown(() => fitnessSurfaceRequests.removeListener(shell));
      await tester.pumpWidget(_host(GlobalSegmentsScreen(api: _NoParksApi())));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('segments-parks-link')));
      await tester.pumpAndSettle();
      expect(drained, [
        (tab: FitnessTab.races, racesShow: RacesShow.courses, routesShow: null),
      ]);
      expect(find.byType(RacesScreen), findsNothing);
    });

    testWidgets('a signed-out viewer still browses the world-readable catalogue',
        (tester) async {
      await tester.pumpWidget(
        _host(GlobalSegmentsScreen(api: _CatalogueApi(_catalogue, viewer: null))),
      );
      await tester.pumpAndSettle();
      expect(find.text('Harlem Hill'), findsOneWidget);
    });

    testWidgets('tapping a card opens that segment', (tester) async {
      await tester.pumpWidget(_host(GlobalSegmentsScreen(api: _CatalogueApi(_catalogue))));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Harlem Hill'));
      await tester.pumpAndSettle();
      expect(find.byType(GlobalSegmentDetailScreen), findsOneWidget);
      expect(find.text('Elevation gain'), findsOneWidget);
    });
  });

  group('GlobalSegmentDetailScreen', () {
    testWidgets('renders the segment stats and description', (tester) async {
      final api = _CatalogueApi([
        _segment(
          id: 'a',
          name: 'Harlem Hill',
          region: 'New York, US',
          distanceM: 857,
          elevationM: 18,
          description: 'The classic north-end climb.',
        ),
      ]);
      await tester.pumpWidget(
        _host(GlobalSegmentDetailScreen(api: api, segmentId: 'a')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Harlem Hill'), findsOneWidget);
      expect(find.text('The classic north-end climb.'), findsOneWidget);
      expect(find.byKey(const Key('help-how-this-works')), findsOneWidget);
      expect(find.text('Distance'), findsOneWidget);
      expect(find.text('Elevation gain'), findsOneWidget);
      expect(find.text('Road'), findsOneWidget);
    });

    testWidgets(
        'a park course segment shows its credit once, beside a description '
        'that no longer carries it', (tester) async {
      final api = _CatalogueApi(
        [_segment(id: 'a', name: 'Beaver Lake Trail', description: 'Run it clockwise.')],
        credit: '© OpenStreetMap contributors (ODbL); elevation: USGS 3DEP',
      );
      await tester.pumpWidget(
        _host(GlobalSegmentDetailScreen(api: api, segmentId: 'a')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Run it clockwise.'), findsOneWidget);
      expect(
        find.text('© OpenStreetMap contributors (ODbL); elevation: USGS 3DEP'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('segment-course-credit')), findsOneWidget);
    });

    testWidgets('a park course segment links to its course page',
        (tester) async {
      final api = _CatalogueApi(
        [_segment(id: 'a', name: 'Beaver Lake Trail')],
        parkCourse: true,
      );
      await tester.pumpWidget(
        _host(GlobalSegmentDetailScreen(api: api, segmentId: 'a')),
      );
      await tester.pumpAndSettle();
      final link = find.byKey(const Key('segment-park-course-link'));
      expect(
          find.descendant(
              of: link, matching: find.text('Park course at Beaver Lake Park')),
          findsOneWidget);
      expect(find.byKey(const Key('segment-course-credit')), findsNothing);
      await tester.ensureVisible(link);
      await tester.tap(link);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(ParkCourseScreen), findsOneWidget);
    });

    testWidgets('a segment no park course is built on shows no credit',
        (tester) async {
      final api = _CatalogueApi([_segment(id: 'a', name: 'Harlem Hill')]);
      await tester.pumpWidget(
        _host(GlobalSegmentDetailScreen(api: api, segmentId: 'a')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('segment-course-credit')), findsNothing);
      expect(find.byKey(const Key('segment-park-course-link')), findsNothing);
    });

    testWidgets('a segment with geometry lays its preview out in a bounded box',
        (tester) async {
      final api = _CatalogueApi([
        _segment(
          id: 'a',
          name: 'Harlem Hill',
          waypoints: const [
            {'lat': 40.7963, 'lng': -73.9582},
            {'lat': 40.7988, 'lng': -73.9575},
          ],
        ),
      ]);
      await tester.pumpWidget(
        _host(GlobalSegmentDetailScreen(api: api, segmentId: 'a')),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(AspectRatio), findsOneWidget);
    });

    testWidgets('an unknown or retired segment renders the not-found state',
        (tester) async {
      await tester.pumpWidget(
        _host(GlobalSegmentDetailScreen(api: _CatalogueApi(const []), segmentId: 'gone')),
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(
            of: find.byType(EmptyState),
            matching: find.text('Segment not found')),
        findsOneWidget,
      );
      expect(find.text('Leaderboard'), findsNothing);
    });

    testWidgets('the leaderboard marks the crown holder and the viewer',
        (tester) async {
      final api = _BoardApi(
        [_segment(id: 'a', name: 'Harlem Hill')],
        [_entry('other-1', 'Rival', 1), _entry('viewer-1', 'Me', 2)],
      );
      await tester.pumpWidget(
        _host(GlobalSegmentDetailScreen(api: api, segmentId: 'a')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Rival'), findsOneWidget);
      expect(find.text('Me'), findsOneWidget);
      expect(find.text('You'), findsOneWidget);
      expect(find.text('#2'), findsOneWidget);
      expect(find.byIcon(Icons.emoji_events), findsOneWidget);
    });

    testWidgets('the viewer holding rank 1 sees the crown banner',
        (tester) async {
      final api = _BoardApi(
        [_segment(id: 'a', name: 'Harlem Hill')],
        [_entry('viewer-1', 'Me', 1)],
      );
      await tester.pumpWidget(
        _host(GlobalSegmentDetailScreen(api: api, segmentId: 'a')),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('You hold this crown — Fastest overall.'),
        findsOneWidget,
      );
    });

    testWidgets('a failed leaderboard offers a retry, not "No efforts yet"',
        (tester) async {
      final api = _ThrowingBoardApi([_segment(id: 'a', name: 'Harlem Hill')]);
      await tester.pumpWidget(
        _host(GlobalSegmentDetailScreen(api: api, segmentId: 'a')),
      );
      await tester.pumpAndSettle();
      expect(find.text("Couldn't load the leaderboard"), findsOneWidget);
      expect(
        find.text('No efforts yet — be the first to run this segment.'),
        findsNothing,
      );
    });

    testWidgets(
        'a signed-out viewer is asked to sign in rather than shown a doomed retry',
        (tester) async {
      final api = _CatalogueApi(
        [_segment(id: 'a', name: 'Harlem Hill')],
        viewer: null,
      );
      await tester.pumpWidget(
        _host(GlobalSegmentDetailScreen(api: api, segmentId: 'a')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Leaderboard'), findsOneWidget);
      expect(find.text("Couldn't load the leaderboard"), findsNothing);
      expect(find.text('Loading…'), findsNothing);
    });

    testWidgets(
        'a segment timed by its lines with old circle efforts shows the note '
        '(issue #1308)', (tester) async {
      final api = _ZoneNoteApi([_gatedSegment('a')], hasZone: true);
      await tester.pumpWidget(
        _host(GlobalSegmentDetailScreen(api: api, segmentId: 'a')),
      );
      await tester.pumpAndSettle();
      expect(find.text(_oldMatchNote), findsOneWidget);
    });

    testWidgets(
        'no note when every effort is a line match, or the segment has no '
        'lines (and then nothing is asked)', (tester) async {
      final gated = _ZoneNoteApi([_gatedSegment('a')], hasZone: false);
      await tester.pumpWidget(
        _host(GlobalSegmentDetailScreen(api: gated, segmentId: 'a')),
      );
      await tester.pumpAndSettle();
      expect(find.text(_oldMatchNote), findsNothing);

      final plain = _ZoneNoteApi([_segment(id: 'b', name: 'Plain')],
          hasZone: true);
      await tester.pumpWidget(
        _host(GlobalSegmentDetailScreen(api: plain, segmentId: 'b')),
      );
      await tester.pumpAndSettle();
      expect(find.text(_oldMatchNote), findsNothing);
      expect(plain.asked, 0);
    });
  });
}

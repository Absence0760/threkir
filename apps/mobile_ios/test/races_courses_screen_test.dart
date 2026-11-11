import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' show Position;
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/geocoding.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/race_service.dart';
import '../lib/screens/park_courses_screen.dart';
import '../lib/screens/races_screen.dart';
import '../lib/training.dart' show toIsoDate;
import '../lib/widgets/run_any_time_section.dart';
import 'pump_until.dart';
import 'supabase_test_init.dart';

/// Races & courses (issue #1352): the race calendar and the park courses
/// that can be run any day, as two sections that load and fail on their own.

class _Races extends RaceService {
  final List<RaceListingView> results;
  final bool fail;

  _Races({this.results = const [], this.fail = false});

  @override
  Future<List<RaceListingView>> searchRaceListings({
    String? query,
    String? distance,
    String? from,
    String? to,
    String? nearPlace,
    String? mapTilerKey,
    Future<GeocodedPlace?> Function(String)? geocoder,
    int limit = 60,
    bool newestFirst = false,
  }) async {
    if (fail) throw StateError('race search down');
    return results;
  }
}

RaceListingView _race(String id, String name) => RaceListingView(
      id: id,
      provider: 'manual',
      providerRaceId: null,
      name: name,
      raceDate: toIsoDate(DateTime.now().add(const Duration(days: 90))),
      distanceM: 10000,
      locationLabel: 'Richmond, VA',
      entryUrl: 'https://example.com/register',
      resultsUrl: null,
      isVerified: true,
      distanceMAway: null,
      organiserIsOfficial: false,
    );

final _created = DateTime.parse('2026-01-01T00:00:00Z');

ParkListing _park(String id, String name) => ParkListing(
      park: ParkRow(
        id: id,
        slug: name.toLowerCase().replaceAll(' ', '-'),
        name: name,
        agency: 'state',
        regionCode: 'US-VA',
        countryCode: 'US',
        timezone: 'America/New_York',
        isActive: true,
        createdAt: _created,
      ),
      season: 2026,
    );

ParkCourseListing _course(
  String id,
  String parkId,
  String name, {
  double distanceM = 5000,
  int? laps,
  required double lat,
}) =>
    ParkCourseListing(
      course: ParkCourseRow(
        id: id,
        parkId: parkId,
        globalSegmentId: 's-$id',
        slug: id,
        courseShape: 'loop',
        status: 'open',
        geometrySource: 'osm',
        checkpoints: const [],
        laps: laps,
        createdAt: _created,
      ),
      segment: GlobalSegmentRow(
        id: 's-$id',
        name: name,
        waypoints: [
          {'lat': lat, 'lng': -77.5},
          {'lat': lat + 0.01, 'lng': -77.5},
        ],
        distanceM: distanceM,
        surface: 'trail',
        isActive: true,
        createdAt: _created,
      ),
    );

class _ParksApi extends ApiClient {
  _ParksApi({
    this.viewer = 'viewer-1',
    this.failCourses = false,
    this.failRecords = false,
  });

  final String? viewer;
  final bool failCourses;
  final bool failRecords;
  int recordCalls = 0;

  @override
  String? get userId => viewer;

  @override
  Future<List<ParkListing>> fetchParks() async {
    if (failCourses) throw StateError('parks down');
    return [_park('p1', 'Pocahontas'), _park('p2', 'Swift Creek')];
  }

  @override
  Future<List<ParkCourseListing>> fetchAllParkCourses() async {
    if (failCourses) throw StateError('courses down');
    return [
      _course('far', 'p1', 'Far Loop', lat: 38.5),
      _course('near', 'p2', 'Near Loop', distanceM: 10000, laps: 2, lat: 37.51),
      // A course whose park the reader cannot see is not listed.
      _course('hidden', 'p-gone', 'Hidden Loop', lat: 37.5),
    ];
  }

  @override
  Future<Map<String, ParkCourseRecord>> fetchParkCourseRecords() async {
    recordCalls++;
    if (failRecords) throw StateError('records down');
    return const {
      'far': ParkCourseRecord(season: 2026, timeSeconds: 1500, displayName: 'Bea'),
      'near': ParkCourseRecord(season: 2026, timeSeconds: 2700),
    };
  }
}

Widget _app(Widget home) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
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

Position _at(double lat, double lng) => Position(
      latitude: lat,
      longitude: lng,
      timestamp: DateTime.now(),
      accuracy: 10,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

void main() {
  setUpAll(_ensureEnvironment);

  void tallView(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Finder anyTime(Finder f) =>
      find.descendant(of: find.byKey(const Key('races-any-time')), matching: f);

  Future<void> coursesListed(WidgetTester tester) => pumpUntil(
        tester,
        () => find.text('Far Loop').evaluate().isNotEmpty,
        describe: 'the park courses to list',
      );

  testWidgets('shows Upcoming races and Run any time, each with its content',
      (tester) async {
    tallView(tester);
    await tester.pumpWidget(_app(RacesScreen(
      service: _Races(results: [_race('r1', 'Richmond 10K')]),
      api: _ParksApi(),
    )));
    await coursesListed(tester);
    expect(
        find.descendant(
            of: find.byType(AppBar), matching: find.text('Races & courses')),
        findsOneWidget);
    expect(find.text('Upcoming races'), findsOneWidget);
    expect(find.text('Run any time'), findsOneWidget);
    expect(find.text('Richmond 10K'), findsOneWidget);
    expect(anyTime(find.text('Near Loop')), findsOneWidget);
    expect(anyTime(find.text('Hidden Loop')), findsNothing);
    expect(anyTime(find.text('Fastest in 2026: 25:00 by Bea')), findsOneWidget);
    expect(anyTime(find.text('Fastest in 2026: 45:00')), findsOneWidget);
    // A course distance reads as its name (#1352): no "10.00 km", and no
    // "Loop" on a loop.
    expect(anyTime(find.textContaining('10 km')), findsOneWidget);
    expect(anyTime(find.textContaining('10.00')), findsNothing);
    expect(anyTime(find.textContaining(' · Loop')), findsNothing);
    expect(find.byKey(const ValueKey('races-any-time-laps-near')), findsOneWidget);
    expect(find.byKey(const ValueKey('races-any-time-laps-far')), findsNothing);
    expect(anyTime(find.text('2 laps')), findsOneWidget);
    // Upcoming races leads, as on web.
    expect(tester.getTopLeft(find.text('Upcoming races')).dy,
        lessThan(tester.getTopLeft(find.text('Run any time')).dy));
  });

  testWidgets('a failed race search leaves the courses listed', (tester) async {
    tallView(tester);
    await tester.pumpWidget(_app(RacesScreen(
      service: _Races(fail: true),
      api: _ParksApi(),
    )));
    await coursesListed(tester);
    expect(
        find.text("Couldn't load races. Check your connection and try again."),
        findsOneWidget);
    expect(find.byKey(const Key('races-any-time-error')), findsNothing);
    expect(anyTime(find.text('Far Loop')), findsOneWidget);
  });

  testWidgets('a failed course read leaves the races listed, with a retry',
      (tester) async {
    tallView(tester);
    await tester.pumpWidget(_app(RacesScreen(
      service: _Races(results: [_race('r1', 'Richmond 10K')]),
      api: _ParksApi(failCourses: true),
    )));
    await pumpUntil(
      tester,
      () => find.byKey(const Key('races-any-time-error')).evaluate().isNotEmpty,
      describe: 'the course failure to show',
    );
    expect(find.text('Richmond 10K'), findsOneWidget);
    expect(
        anyTime(find.text("Couldn't load park courses.")), findsOneWidget);
    expect(
        anyTime(find.widgetWithText(OutlinedButton, 'Retry')), findsOneWidget);
    // The full index stays reachable whatever the section's read did.
    expect(find.byKey(const Key('races-any-time-all')), findsOneWidget);
  });

  testWidgets('failed records leave the courses listed, without a record line',
      (tester) async {
    tallView(tester);
    await tester.pumpWidget(_app(RacesScreen(
      service: _Races(),
      api: _ParksApi(failRecords: true),
    )));
    await coursesListed(tester);
    await pumpUntil(
      tester,
      () => find
          .byKey(const Key('races-any-time-records-failed'))
          .evaluate()
          .isNotEmpty,
      describe: 'the records failure to show',
    );
    expect(anyTime(find.text('Near Loop')), findsOneWidget);
    expect(anyTime(find.textContaining('record:')), findsNothing);
  });

  testWidgets('signed out, the courses list with no record read at all',
      (tester) async {
    tallView(tester);
    final api = _ParksApi(viewer: null);
    await tester.pumpWidget(_app(RacesScreen(service: _Races(), api: api)));
    await coursesListed(tester);
    expect(api.recordCalls, 0);
    expect(anyTime(find.textContaining('record')), findsNothing);
    expect(find.byKey(const Key('races-any-time-records-failed')),
        findsNothing);
  });

  testWidgets('without a client the races stand alone', (tester) async {
    await tester.pumpWidget(_app(RacesScreen(
      service: _Races(results: [_race('r1', 'Richmond 10K')]),
    )));
    await pumpUntil(
      tester,
      () => find.text('Richmond 10K').evaluate().isNotEmpty,
      describe: 'the race to list',
    );
    expect(find.byKey(const Key('races-any-time')), findsNothing);
  });

  group('RunAnyTimeSection', () {
    Widget section(_ParksApi api, {Stream<Position> Function()? positions}) =>
        _app(Scaffold(
          body: SingleChildScrollView(
            child: RunAnyTimeSection(api: api, positions: positions),
          ),
        ));

    testWidgets('without a fix, a stable order: region, park, distance',
        (tester) async {
      tallView(tester);
      await tester.pumpWidget(
          section(_ParksApi(), positions: () => const Stream.empty()));
      await coursesListed(tester);
      expect(tester.getTopLeft(find.text('Far Loop')).dy,
          lessThan(tester.getTopLeft(find.text('Near Loop')).dy),
          reason: 'Pocahontas sorts before Swift Creek');
      expect(find.textContaining(' away'), findsNothing);
    });

    testWidgets('with a fix, the nearest course first, with how far it is',
        (tester) async {
      tallView(tester);
      final fixes = StreamController<Position>();
      addTearDown(fixes.close);
      await tester.pumpWidget(
          section(_ParksApi(), positions: () => fixes.stream));
      await coursesListed(tester);
      fixes.add(_at(37.5, -77.5));
      await pumpUntil(
        tester,
        () => find.textContaining(' away').evaluate().isNotEmpty,
        describe: 'the fix to reorder the courses',
      );
      expect(tester.getTopLeft(find.text('Near Loop')).dy,
          lessThan(tester.getTopLeft(find.text('Far Loop')).dy));
    });

    testWidgets('a course opens its course page; the foot opens the full index',
        (tester) async {
      tallView(tester);
      await tester.pumpWidget(
          section(_ParksApi(), positions: () => const Stream.empty()));
      await coursesListed(tester);
      await tester.tap(find.text('Far Loop'));
      await pumpUntil(
        tester,
        () => find.byType(ParkCourseScreen).evaluate().isNotEmpty,
        describe: 'the course page to open',
      );
      Navigator.of(tester.element(find.byType(ParkCourseScreen))).pop();
      await pumpUntil(
        tester,
        () => find.byType(ParkCourseScreen).evaluate().isEmpty,
        describe: 'the course page to close',
      );
      await tester.tap(find.byKey(const Key('races-any-time-all')));
      await pumpUntil(
        tester,
        () => find.byType(ParksScreen).evaluate().isNotEmpty,
        describe: 'the park index to open',
      );
    });
  });
}

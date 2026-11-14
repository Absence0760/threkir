import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' show Position;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ui_kit/ui_kit.dart' show AppSearchField, FilterBar;

import '../lib/geocoding.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/race_service.dart';
import '../lib/screens/park_courses_screen.dart';
import '../lib/screens/races_screen.dart';
import '../lib/training.dart' show toIsoDate;
import '../lib/widgets/help_button.dart';
import '../lib/widgets/run_any_time_section.dart';
import 'pump_until.dart';
import 'supabase_test_init.dart';
import 'worst_case_layout.dart';

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
      month: 11,
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
    this.extraCourses = 0,
  });

  final String? viewer;
  final bool failCourses;
  final bool failRecords;
  final int extraCourses;
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
      for (var i = 0; i < extraCourses; i++)
        _course('extra-$i', 'p2', 'Extra Loop $i', lat: 37.6 + i / 100),
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

  worstCaseTestWidgets('the race and course cards', (tester, locale) async {
    await tester.pumpWidget(worstCaseApp(
      locale: locale,
      home: RacesScreen(
        service: _Races(results: [_race('r1', 'Richmond 10K')]),
        api: _ParksApi(),
      ),
    ));
    // Far Loop is below a 320 x 640 viewport, so wait for the race instead;
    // the walk builds the course cards as it scrolls past them.
    await pumpUntil(
      tester,
      () => find.text('Richmond 10K').evaluate().isNotEmpty,
      describe: 'the race to list',
    );
    await tester.pump();
    await walkScrollable(tester, primaryScrollable(), 'Races & courses');
    expect(find.text('Far Loop'), findsOneWidget);
  });

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
    // Nothing listed is nothing cut short, so no "See all".
    expect(find.byKey(const Key('races-any-time-all')), findsNothing);
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

  testWidgets(
      'the Show switch hides either section, and Courses lists every course',
      (tester) async {
    tallView(tester);
    await tester.pumpWidget(_app(RacesScreen(
      service: _Races(results: [_race('r1', 'Richmond 10K')]),
      api: _ParksApi(extraCourses: 8),
    )));
    await coursesListed(tester);
    final cards = anyTime(find.byWidgetPredicate((w) =>
        w.key is ValueKey<String> &&
        (w.key! as ValueKey<String>).value.startsWith('races-any-time-course-')));
    expect(find.text('Upcoming races'), findsOneWidget);
    expect(cards, findsNWidgets(kRunAnyTimeLimit));

    await tester.tap(find.widgetWithText(ChoiceChip, 'Courses'));
    await tester.pump();
    expect(find.text('Upcoming races'), findsNothing);
    expect(find.text('Richmond 10K'), findsNothing);
    expect(find.byKey(const Key('filter-bar-filters')), findsNothing);
    // The section is kept, not rebuilt, so every course is there at once,
    // and with every course listed there is no "See all".
    expect(cards, findsNWidgets(10));
    expect(find.byKey(const Key('races-any-time-all')), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Races'));
    await tester.pump();
    expect(find.byKey(const Key('races-any-time')), findsNothing);
    expect(find.text('Upcoming races'), findsOneWidget);
    expect(find.text('Richmond 10K'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
    await tester.pump();
    expect(find.text('Upcoming races'), findsOneWidget);
    await coursesListed(tester);
    expect(cards, findsNWidgets(kRunAnyTimeLimit));
  });

  testWidgets(
      'Courses leads with the parks, nearest course first, each opening its '
      'park; All has no park row', (tester) async {
    tallView(tester);
    await tester.pumpWidget(_app(RacesScreen(
      service: _Races(),
      api: _ParksApi(),
    )));
    await coursesListed(tester);
    expect(find.byKey(const Key('races-any-time-parks')), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Courses'));
    await tester.pump();
    final row = find.byKey(const Key('races-any-time-parks'));
    expect(row, findsOneWidget);
    expect(find.text('Parks'), findsOneWidget);
    final cards = find.descendant(of: row, matching: find.byType(ParkCard));
    expect(cards, findsNWidgets(2));
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('races-any-time-park-p2')),
            matching: find.text('Swift Creek')),
        findsOneWidget);
    // The stable order, without a fix: Pocahontas first.
    expect(tester.getTopLeft(find.byKey(const ValueKey('races-any-time-park-p1'))).dx,
        lessThan(tester.getTopLeft(find.byKey(const ValueKey('races-any-time-park-p2'))).dx));
    await tester.tap(find.descendant(
        of: find.byKey(const ValueKey('races-any-time-park-p2')),
        matching: find.text('Swift Creek')));
    await pumpUntil(
      tester,
      () => find.byType(ParkScreen).evaluate().isNotEmpty,
      describe: 'the park screen to open',
    );
    expect(
        tester.widget<ParkScreen>(find.byType(ParkScreen)).listing.park.id, 'p2');
  });

  testWidgets('a course card names its park as a link of its own',
      (tester) async {
    tallView(tester);
    await tester.pumpWidget(_app(RacesScreen(
      service: _Races(),
      api: _ParksApi(),
    )));
    await coursesListed(tester);
    final link = find.byKey(const ValueKey('races-any-time-park-link-near'));
    expect(
      tester.getSemantics(link),
      matchesSemantics(
        label: 'Swift Creek, Virginia: park page',
        isLink: true,
        hasTapAction: true,
      ),
    );
    await tester.tap(link);
    await pumpUntil(
      tester,
      () => find.byType(ParkScreen).evaluate().isNotEmpty,
      describe: 'the park screen to open',
    );
    expect(find.byType(ParkCourseScreen), findsNothing);
  });

  testWidgets('a host notifier opens the tab on the view it names',
      (tester) async {
    tallView(tester);
    final show = ValueNotifier(RacesShow.all);
    addTearDown(show.dispose);
    await tester.pumpWidget(_app(RacesScreen(
      service: _Races(results: [_race('r1', 'Richmond 10K')]),
      api: _ParksApi(),
      show: show,
    )));
    await coursesListed(tester);
    show.value = RacesShow.courses;
    await tester.pump();
    expect(find.text('Upcoming races'), findsNothing);
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Courses'))
          .selected,
      isTrue,
    );
    await tester.tap(find.widgetWithText(ChoiceChip, 'Races'));
    await tester.pump();
    expect(show.value, RacesShow.races);
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
    expect(find.widgetWithText(ChoiceChip, 'Courses'), findsNothing,
        reason: 'no client, so no courses view to switch to');
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

    testWidgets(
        'a course opens its course page; See all in the heading opens the '
        'full index', (tester) async {
      tallView(tester);
      await tester.pumpWidget(section(_ParksApi(extraCourses: 8),
          positions: () => const Stream.empty()));
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

    testWidgets('See all shows only when the list is cut short, with the count',
        (tester) async {
      tallView(tester);
      await tester.pumpWidget(
          section(_ParksApi(), positions: () => const Stream.empty()));
      await coursesListed(tester);
      expect(find.byKey(const Key('races-any-time-all')), findsNothing,
          reason: 'two courses fit under the limit of eight');

      // A new section, not the old one handed a new client.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(section(_ParksApi(extraCourses: 8),
          positions: () => const Stream.empty()));
      await pumpUntil(
        tester,
        () => find.byKey(const Key('races-any-time-all')).evaluate().isNotEmpty,
        describe: 'the cut-short list to offer See all',
      );
      final seeAll = find.byKey(const Key('races-any-time-all'));
      expect(find.descendant(of: seeAll, matching: find.text('See all 10 courses')),
          findsOneWidget);
      // In the heading row, not under the last card.
      expect(tester.getCenter(seeAll).dy,
          moreOrLessEquals(tester.getCenter(find.text('Run any time')).dy,
              epsilon: 24));
    });

    testWidgets('a course far away reads in whole, grouped kilometres',
        (tester) async {
      tallView(tester);
      final fixes = StreamController<Position>();
      addTearDown(fixes.close);
      await tester.pumpWidget(
          section(_ParksApi(), positions: () => fixes.stream));
      await coursesListed(tester);
      // About 3,900 km south of the courses: once "3901.14 km away".
      fixes.add(_at(2.5, -77.5));
      await pumpUntil(
        tester,
        () => find.textContaining(' away').evaluate().isNotEmpty,
        describe: 'the fix to measure the courses',
      );
      final lines = [
        for (final e in find.textContaining(' away').evaluate())
          (e.widget as Text).data!,
      ];
      expect(lines, isNotEmpty);
      for (final line in lines) {
        expect(line, matches(RegExp(r'\d,\d{3} km away$')), reason: line);
        expect(line, isNot(contains('.')), reason: line);
      }
    });
  });

  group('the search', () {
    Future<void> type(WidgetTester tester, String text) async {
      await tester.enterText(find.byKey(const Key('races-search')), text);
      // Past the 250 ms debounce.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
    }

    Finder courseCards() => anyTime(find.byWidgetPredicate((w) =>
        w.key is ValueKey<String> &&
        (w.key! as ValueKey<String>)
            .value
            .startsWith('races-any-time-course-')));

    testWidgets(
        'is in the FilterBar with help and the overflow on its row, in every '
        'view', (tester) async {
      tallView(tester);
      await tester.pumpWidget(_app(RacesScreen(
        service: _Races(),
        api: _ParksApi(),
      )));
      await coursesListed(tester);
      for (final view in ['All', 'Courses', 'Races']) {
        await tester.tap(find.widgetWithText(ChoiceChip, view));
        await tester.pump();
        final bar = find.byKey(const Key('races-filter-bar'));
        final search = find.descendant(
            of: bar, matching: find.byType(AppSearchField));
        expect(search, findsOneWidget, reason: view);
        final help =
            find.descendant(of: bar, matching: find.byType(HelpButton));
        final overflow = find.descendant(
            of: bar, matching: find.byKey(const Key('races-overflow')));
        expect(help, findsOneWidget, reason: view);
        expect(overflow, findsOneWidget, reason: view);
        // One row: no line holding only the two actions.
        expect(tester.getCenter(help).dy,
            moreOrLessEquals(tester.getCenter(search).dy, epsilon: 1),
            reason: view);
        expect(tester.getCenter(overflow).dy,
            moreOrLessEquals(tester.getCenter(search).dy, epsilon: 1),
            reason: view);
      }
      expect(find.byType(FilterBar), findsOneWidget);
    });

    testWidgets(
        'filters the courses by name, park and place after a pause, and '
        'keeps doing so in the Courses view', (tester) async {
      tallView(tester);
      await tester.pumpWidget(_app(RacesScreen(
        service: _Races(results: [_race('r1', 'Richmond 10K')]),
        api: _ParksApi(),
      )));
      await coursesListed(tester);
      expect(courseCards(), findsNWidgets(2));

      await tester.enterText(find.byKey(const Key('races-search')), 'far');
      await tester.pump();
      expect(courseCards(), findsNWidgets(2),
          reason: 'debounced: nothing refilters on the keystroke');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(anyTime(find.text('Far Loop')), findsOneWidget);
      expect(anyTime(find.text('Near Loop')), findsNothing);

      // By park, with an accent and in capitals.
      await type(tester, 'SWÏFT');
      expect(anyTime(find.text('Near Loop')), findsOneWidget);
      expect(anyTime(find.text('Far Loop')), findsNothing);

      // By place: both parks are in Virginia.
      await type(tester, 'virginia');
      expect(courseCards(), findsNWidgets(2));

      // Words combine across course and park.
      await type(tester, 'pocahontas loop');
      expect(courseCards(), findsOneWidget);
      expect(anyTime(find.text('Far Loop')), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Courses'));
      await tester.pump();
      expect(courseCards(), findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const Key('races-any-time-parks')),
              matching: find.byType(ParkCard)),
          findsOneWidget,
          reason: 'the park row follows the search');
      expect(
          find.descendant(
              of: find.byKey(const Key('races-search')),
              matching: find.text('Search parks and courses…')),
          findsOneWidget);
    });

    testWidgets('no match says so, and Clear search brings every course back',
        (tester) async {
      tallView(tester);
      await tester.pumpWidget(_app(RacesScreen(
        service: _Races(),
        api: _ParksApi(),
      )));
      await coursesListed(tester);
      await type(tester, 'zzz');
      final none = find.byKey(const Key('races-any-time-no-match'));
      expect(none, findsOneWidget);
      expect(find.descendant(of: none, matching: find.text('No courses match “zzz”')),
          findsOneWidget);
      await tester.tap(find.descendant(
          of: none, matching: find.widgetWithText(FilledButton, 'Clear search')));
      await tester.pump();
      expect(none, findsNothing);
      expect(courseCards(), findsNWidgets(2));
      expect(
          tester
              .widget<TextField>(find.descendant(
                  of: find.byKey(const Key('races-search')),
                  matching: find.byType(TextField)))
              .controller!
              .text,
          isEmpty);
    });

    worstCaseTestWidgets('the no-match state in the Courses view',
        (tester, locale) async {
      await tester.pumpWidget(worstCaseApp(
        locale: locale,
        home: RacesScreen(
          service: _Races(),
          api: _ParksApi(),
          initialShow: RacesShow.courses,
        ),
      ));
      await pumpUntil(
        tester,
        () => find.byKey(const Key('races-any-time-parks')).evaluate().isNotEmpty,
        describe: 'the courses to list',
      );
      await tester.enterText(
          find.byKey(const Key('races-search')), 'a long search with no match');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(find.byKey(const Key('races-any-time-no-match')), findsOneWidget);
      await walkScrollable(tester, primaryScrollable(), 'Courses, no match');
    });

    worstCaseTestWidgets('the cut-short list with See all in its heading',
        (tester, locale) async {
      await tester.pumpWidget(worstCaseApp(
        locale: locale,
        home: Scaffold(
          body: SingleChildScrollView(
            child: RunAnyTimeSection(
              api: _ParksApi(extraCourses: 8),
              positions: () => const Stream.empty(),
            ),
          ),
        ),
      ));
      await pumpUntil(
        tester,
        () => find.byKey(const Key('races-any-time-all')).evaluate().isNotEmpty,
        describe: 'See all to show',
      );
      expectNoOverflow(tester, 'Run any time heading');
    });
  });

  group('All park courses', () {
    Future<void> openIndex(WidgetTester tester, {String query = ''}) async {
      tallView(tester);
      await tester.pumpWidget(
          _app(ParksScreen(api: _ParksApi(), initialQuery: query)));
      await pumpUntil(
        tester,
        () => find
            .byKey(const ValueKey('parks-park-p1'))
            .evaluate()
            .isNotEmpty ||
            find.byKey(const Key('parks-no-match')).evaluate().isNotEmpty ||
            find.byKey(const ValueKey('parks-park-p2')).evaluate().isNotEmpty,
        describe: 'the parks to list',
      );
      // The course read decorates the cards and feeds the course-name match.
      await tester.pump();
    }

    testWidgets('finds a park by a course it holds, and says when none match',
        (tester) async {
      await openIndex(tester);
      expect(find.byKey(const ValueKey('parks-park-p1')), findsOneWidget);
      expect(find.byKey(const ValueKey('parks-park-p2')), findsOneWidget);

      await tester.enterText(find.byKey(const Key('parks-search')), 'near loop');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(find.byKey(const ValueKey('parks-park-p2')), findsOneWidget);
      expect(find.byKey(const ValueKey('parks-park-p1')), findsNothing);

      await tester.enterText(find.byKey(const Key('parks-search')), 'zzz');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      final none = find.byKey(const Key('parks-no-match'));
      expect(find.descendant(
              of: none, matching: find.text('No parks or courses match “zzz”')),
          findsOneWidget);
      await tester.tap(find.descendant(
          of: none, matching: find.widgetWithText(FilledButton, 'Clear search')));
      await tester.pump();
      expect(find.byKey(const ValueKey('parks-park-p1')), findsOneWidget);
      expect(find.byKey(const ValueKey('parks-park-p2')), findsOneWidget);
    });

    testWidgets('opens on the search See all carried', (tester) async {
      await openIndex(tester, query: 'pocahontas');
      expect(find.byKey(const ValueKey('parks-park-p1')), findsOneWidget);
      expect(find.byKey(const ValueKey('parks-park-p2')), findsNothing);
      expect(find.text('pocahontas'), findsOneWidget);
    });

    worstCaseTestWidgets('the index with its search', (tester, locale) async {
      await tester.pumpWidget(worstCaseApp(
        locale: locale,
        home: ParksScreen(api: _ParksApi(), initialQuery: 'zzz'),
      ));
      await pumpUntil(
        tester,
        () => find.byKey(const Key('parks-no-match')).evaluate().isNotEmpty,
        describe: 'the no-match state',
      );
      await walkScrollable(tester, primaryScrollable(), 'Park courses, no match');
    });
  });
}

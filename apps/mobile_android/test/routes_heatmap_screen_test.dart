// Widget tests for RoutesHeatmapScreen — the mobile mirror of the web
// route-discovery browser. The full chain (RPC → render) is exercised
// against a fake ApiClient. flutter_map's tile fetches fail under the
// test runner (HTTP 400 in widget tests) which is the same constraint
// other map-bearing widget tests deal with; we pin the chrome + the RPC
// invocation + the discovery UI, not tile-load success.

import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:core_models/core_models.dart' as cm;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/last_map_view.dart';
import '../lib/preferences.dart';
import '../lib/screens/routes_heatmap_screen.dart';
import '../lib/widgets/live_run_map.dart'
    show mapHoverLine, mapLineCasing;
import '../lib/widgets/map_attribution.dart';
import '../lib/widgets/official_badge.dart';
import 'pump_until.dart';

class _FakeApiClient extends ApiClient {
  int fetchCalls = 0;
  double? lastMinLng;
  double? lastMinLat;
  double? lastMaxLng;
  double? lastMaxLat;
  List<HeatmapPoint> nextPoints = const [];
  Object? errorToThrow;

  // Discovery support.
  int discoverCalls = 0;
  /// The routes read fails while set.
  bool failRoutes = false;
  String? lastFilter;
  List<double>? lastDistMin;
  List<cm.DiscoverableRoutePin> nextPins = const [];
  List<cm.ClubPin> nextClubs = const [];
  cm.Route? nextRouteById;

  // Upcoming race pins.
  int raceCalls = 0;
  bool? lastOfficialOnly;
  List<cm.UpcomingRacePin> nextRaces = const [];

  Set<String> parkCourseRouteIds = const {};

  @override
  Future<Set<String>> fetchParkCourseRouteIds(List<String> routeIds) async =>
      routeIds.where(parkCourseRouteIds.contains).toSet();

  @override
  Future<List<HeatmapPoint>> fetchHeatmapPoints({
    required double minLng,
    required double minLat,
    required double maxLng,
    required double maxLat,
    int maxPoints = 5000,
  }) async {
    fetchCalls++;
    lastMinLng = minLng;
    lastMinLat = minLat;
    lastMaxLng = maxLng;
    lastMaxLat = maxLat;
    if (errorToThrow != null) throw errorToThrow!;
    return nextPoints;
  }

  @override
  Future<List<cm.DiscoverableRoutePin>> fetchDiscoverableRoutesInBbox({
    required double minLng,
    required double minLat,
    required double maxLng,
    required double maxLat,
    int limit = 100,
    String filter = 'popular',
    List<double>? distMin,
    List<double?>? distMax,
  }) async {
    discoverCalls++;
    if (failRoutes) throw Exception('offline');
    lastFilter = filter;
    lastDistMin = distMin;
    lastMinLng = minLng;
    lastMinLat = minLat;
    lastMaxLng = maxLng;
    lastMaxLat = maxLat;
    return nextPins;
  }

  @override
  Future<List<cm.ClubPin>> fetchClubsInBbox({
    required double minLng,
    required double minLat,
    required double maxLng,
    required double maxLat,
    int limit = 100,
  }) async =>
      nextClubs;

  @override
  Future<List<cm.UpcomingRacePin>> fetchUpcomingRacesInBbox({
    required double minLng,
    required double minLat,
    required double maxLng,
    required double maxLat,
    int limit = 100,
    bool officialOnly = false,
  }) async {
    raceCalls++;
    lastOfficialOnly = officialOnly;
    return nextRaces;
  }

  @override
  Future<({cm.Route? route, String? ownerId})> fetchRouteById(
    String routeId,
  ) async =>
      (route: nextRouteById, ownerId: 'u');
}

Future<void> _pump(
  WidgetTester tester,
  _FakeApiClient api, {
  Locale? locale,
  Future<String> Function(Uri)? geocodingFetcher,
  Future<Position> Function()? locateFn,
  Future<Position?> Function()? backgroundLocateFn,
  void Function(BuildContext, String)? openRaceOverride,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery.withClampedTextScaling(
        minScaleFactor: textScale,
        maxScaleFactor: textScale,
        child: RoutesHeatmapScreen(
          api: api,
          geocodingFetcher: geocodingFetcher,
          locateFn: locateFn,
          backgroundLocateFn: backgroundLocateFn,
          openRaceOverride: openRaceOverride,
        ),
      ),
    ),
  );
  // Single pump — pumpAndSettle blocks on flutter_map's internal
  // animation controllers.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

cm.DiscoverableRoutePin _pin({
  String id = 'a',
  String name = 'Wash Park 5K Loop',
  bool featured = false,
  double distanceM = 5000,
  int runCount = 6,
  double lat = 39.74,
  double lng = -105.0,
  bool official = false,
  double? elevationM,
  String surface = 'road',
}) =>
    cm.DiscoverableRoutePin(
      id: id,
      name: name,
      featured: featured,
      distanceM: distanceM,
      surface: surface,
      runCount: runCount,
      lat: lat,
      lng: lng,
      official: official,
      elevationM: elevationM,
    );

Position _fakePosition({double lat = 40.7128, double lng = -74.0060}) =>
    Position(
      latitude: lat,
      longitude: lng,
      timestamp: DateTime.now(),
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

// A map that reaches the screen bottom drew its credit under the system
// navigation bar (route builder field report; same root cause here).
void simulateNavBar(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 780);
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(bottom: 48);
  tester.view.viewPadding = const FakeViewPadding(bottom: 48);
  addTearDown(tester.view.reset);
}

void expectCreditsAboveNavBar(WidgetTester tester) {
  final credits = find.descendant(
      of: find.byType(MapAttribution), matching: find.byType(Text));
  expect(credits, findsWidgets);
  for (final credit in credits.evaluate()) {
    final rect = tester.getRect(find.byWidget(credit.widget));
    expect(rect.bottom, lessThanOrEqualTo(780 - 48),
        reason: 'credit $rect is under the navigation bar');
  }
}

void main() {
  setUpAll(() {
    dotenv.loadFromString(isOptional: true);
  });

  group('RoutesHeatmapScreen', () {
    testWidgets('AppBar hosts a place-search field + a Filters button',
        (tester) async {
      final api = _FakeApiClient();
      await _pump(tester, api);
      expect(find.text('Search places…'), findsOneWidget);
      expect(find.byIcon(Icons.tune), findsOneWidget);
      expect(find.textContaining('Where people run'), findsNothing);
    });

    testWidgets('the map credit sits above the navigation bar and below the '
        'route-count pill', (tester) async {
      simulateNavBar(tester);
      final api = _FakeApiClient();
      await _pump(tester, api);
      expectCreditsAboveNavBar(tester);
      final strip = tester.getRect(find.byType(MapAttribution));
      final fab = tester.getRect(find.byType(FloatingActionButton));
      expect(strip.top, greaterThanOrEqualTo(fab.bottom));
    });

    testWidgets('shows the Locate-me FAB with my_location icon',
        (tester) async {
      final api = _FakeApiClient();
      await _pump(tester, api);
      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.byIcon(Icons.my_location), findsOneWidget);
    });

    testWidgets('tapping the Locate FAB calls locateFn + refetches',
        (tester) async {
      final api = _FakeApiClient();
      var locateCalls = 0;
      await _pump(
        tester,
        api,
        locateFn: () async {
          locateCalls++;
          return _fakePosition();
        },
      );
      await tester.pump(const Duration(milliseconds: 100));
      final initialFetches = api.discoverCalls;

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(locateCalls, 1);
      expect(api.discoverCalls, greaterThan(initialFetches),
          reason: 'Locate must schedule a refresh so discovery '
              "repopulates around the user's location.");
    });

    testWidgets('a refused Locate says the permission is off, not a raw error',
        (tester) async {
      final api = _FakeApiClient();
      await _pump(
        tester,
        api,
        locateFn: () async =>
            throw const PermissionDeniedException('Location permission denied'),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump();
      expect(find.text('Location unavailable: location permission is off'),
          findsOneWidget);
      expect(find.textContaining('PermissionDenied'), findsNothing);
      // Let the banner's dismiss timer run out.
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('search degrades silently when MapTiler is unconfigured',
        (tester) async {
      final api = _FakeApiClient();
      Future<String> stubFetcher(Uri _) async => jsonEncode({
            'features': [
              {
                'place_name': 'Tokyo, Japan',
                'center': [139.6917, 35.6895],
              },
            ],
          });
      await _pump(tester, api, geocodingFetcher: stubFetcher);
      await tester.enterText(
        find.widgetWithText(TextField, 'Search places…'),
        'Tokyo',
      );
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('Tokyo, Japan'), findsNothing,
          reason: 'searchPlaces short-circuits to empty when the '
              'MapTiler key is unset; the dropdown must not surface.');
    });

    testWidgets('typing surfaces place options from the Nominatim fallback',
        (tester) async {
      // With no MapTiler key (the protomaps-only dev default) searchPlaces
      // falls through to Nominatim, whose response is a JSON array. The
      // dropdown must surface as the user types — the production bug was a
      // missing User-Agent making Nominatim 403 into an empty list.
      final api = _FakeApiClient();
      Future<String> nominatimStub(Uri _) async => jsonEncode([
            {
              'display_name': 'London, Greater London, England',
              'lat': '51.5074',
              'lon': '-0.1276',
            },
          ]);
      await _pump(tester, api, geocodingFetcher: nominatimStub);
      await tester.enterText(
        find.widgetWithText(TextField, 'Search places…'),
        'London',
      );
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('London, Greater London, England'), findsOneWidget);
    });

    testWidgets('mounts a FlutterMap with a TileLayer + a marker layer',
        (tester) async {
      final api = _FakeApiClient();
      await _pump(tester, api);
      expect(find.byType(FlutterMap), findsOneWidget);
      expect(find.byType(TileLayer), findsAtLeastNWidgets(1));
      // Pins render in a MarkerLayer (even when empty). Heat is off by
      // default, so there is no heat CircleLayer on mount.
      expect(find.byType(MarkerLayer), findsAtLeastNWidgets(1));
    });

    testWidgets('opens centred on the user location when a fix is available',
        (tester) async {
      final api = _FakeApiClient();
      // New York City — far from the London default centre.
      await _pump(
        tester,
        api,
        backgroundLocateFn: () async => _fakePosition(
          lat: 40.7128,
          lng: -74.0060,
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(api.lastMinLng, isNotNull);
      expect(api.lastMinLng! <= -74.0060 && api.lastMaxLng! >= -74.0060, isTrue,
          reason: 'the map must open centred on the user fix, so the '
              'discovery bbox brackets NYC longitude — not London.');
      expect(api.lastMinLat! <= 40.7128 && api.lastMaxLat! >= 40.7128, isTrue,
          reason: 'and the bbox brackets NYC latitude.');
    });

    testWidgets(
        'with no location fix, widens from London + frames on the route data',
        (tester) async {
      final api = _FakeApiClient()
        // A Virginia route — far from the London default centre. The
        // discovery fetch returns it regardless of bbox (fake), so the
        // only way the bbox can bracket VA is if the map widened off
        // London when the locate gave up.
        ..nextPins = [_pin(id: 'va', lat: 37.5407, lng: -77.436)];
      await _pump(
        tester,
        api,
        // No fix available (the Brave/VPN/desktop case).
        backgroundLocateFn: () async => null,
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(api.lastMinLng, isNotNull);
      expect(api.lastMinLng! <= -77.436 && api.lastMaxLng! >= -77.436, isTrue,
          reason: 'a failed locate must widen off London so the discovery '
              'bbox brackets the Virginia routes — not strand the user on '
              'the London default whose tight bbox returns nothing.');
    });

    testWidgets(
        'with no location fix, reopens on the view it was last left on',
        (tester) async {
      // Sydney: far from London and from the (30, 0) world fallback.
      SharedPreferences.setMockInitialValues({
        kLastBrowseMapViewKey:
            jsonEncode({'lat': -33.8688, 'lng': 151.2093, 'zoom': 12.0}),
      });
      final api = _FakeApiClient()
        ..nextPins = [_pin(id: 'va', lat: 37.5407, lng: -77.436)];
      await _pump(tester, api, backgroundLocateFn: () async => null);
      await pumpUntil(
        tester,
        () =>
            api.lastMinLng != null &&
            api.lastMinLng! <= 151.2093 &&
            api.lastMaxLng! >= 151.2093,
        describe: 'a discovery fetch over the saved Sydney view',
      );
      expect(api.lastMinLat! <= -33.8688 && api.lastMaxLat! >= -33.8688,
          isTrue);
      expect(api.lastMaxLng! - api.lastMinLng!, lessThan(5),
          reason: 'the saved city-scale view, not the whole world and not '
              'a fit to routes on another continent');
    });

    testWidgets('closing the map saves the view for the next visit',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final api = _FakeApiClient();
      await _pump(
        tester,
        api,
        backgroundLocateFn: () async =>
            _fakePosition(lat: 40.7128, lng: -74.0060),
      );
      await pumpUntil(
        tester,
        () => api.lastMinLng != null && api.lastMinLng! <= -74.0060,
        describe: 'a discovery fetch over the NYC fix',
      );
      await tester.pumpWidget(const SizedBox());
      MapView? saved;
      await tester.runAsync(() async {
        saved = await loadLastBrowseMapView();
      });
      expect(saved, isNotNull);
      expect(saved!.center.latitude, closeTo(40.7128, 0.01));
      expect(saved!.center.longitude, closeTo(-74.0060, 0.01));
      expect(saved!.zoom, 14);
    });

    testWidgets('fetches discovery on mount with a valid bbox; heat is off',
        (tester) async {
      final api = _FakeApiClient();
      await _pump(tester, api);
      await tester.pump(const Duration(milliseconds: 100));
      expect(api.discoverCalls, greaterThanOrEqualTo(1));
      expect(api.lastMinLng, isNotNull);
      expect(api.lastMinLng!, lessThan(api.lastMaxLng!));
      expect(api.lastMinLat!, lessThan(api.lastMaxLat!));
      // Heat is off by default → no heat-points fetch on mount.
      expect(api.fetchCalls, 0,
          reason: 'the density heat layer is opt-in; we must not pay '
              'for heatmap points until the user enables Heat.');
    });

    testWidgets('enabling Heat fetches heat points + mounts the heat layer',
        (tester) async {
      final api = _FakeApiClient()
        ..nextPoints = const [HeatmapPoint(lat: 51.5074, lng: -0.1276)];
      await _pump(tester, api);
      await tester.pump(const Duration(milliseconds: 100));
      expect(api.fetchCalls, 0);
      expect(find.byType(CircleLayer), findsNothing);

      await tester.tap(find.byIcon(Icons.tune));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // The Heat chip sits at the bottom of the scrollable sheet.
      await tester.ensureVisible(find.text('Heat density'));
      await tester.pump();
      await tester.tap(find.text('Heat density'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(api.fetchCalls, greaterThanOrEqualTo(1),
          reason: 'toggling Heat must fetch the density points');
    });

    testWidgets('RPC error path swallows + does not crash', (tester) async {
      final api = _FakeApiClient()..errorToThrow = Exception('rpc 500');
      await _pump(tester, api);
      expect(find.text('Search places…'), findsOneWidget);
      expect(find.byType(FlutterMap), findsOneWidget);
    });
  });

  group('upcoming race pins', () {
    // No saved view from an earlier test, so the camera opens on the
    // default centre the race below sits at.
    setUp(() => SharedPreferences.setMockInitialValues({}));

    // At the map's initial centre, so the marker is on screen.
    const race = cm.UpcomingRacePin(
      id: 'race-1',
      name: 'Thames Half',
      raceDate: '2027-01-10',
      distanceM: 21097,
      locationLabel: 'London',
      lat: 51.5074,
      lng: -0.1276,
    );

    testWidgets('a race pin is on by default; its card opens the race',
        (tester) async {
      String? opened;
      final api = _FakeApiClient()..nextRaces = const [race];
      await _pump(tester, api, openRaceOverride: (_, id) => opened = id);
      await tester.pump(const Duration(milliseconds: 100));
      expect(api.raceCalls, greaterThanOrEqualTo(1));
      expect(api.lastOfficialOnly, isFalse);

      final pin = find.byKey(const ValueKey('heatmap-race-pin-race-1'));
      expect(pin, findsOneWidget);
      await tester.tap(pin);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Thames Half'), findsOneWidget);
      expect(find.text('London'), findsOneWidget);
      expect(find.textContaining('2027-01-10'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('heatmap-race-view')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(opened, 'race-1');
    });

    testWidgets('the Upcoming races chip hides the pins and stops the fetch',
        (tester) async {
      final api = _FakeApiClient()..nextRaces = const [race];
      await _pump(tester, api);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('heatmap-race-pin-race-1')),
          findsOneWidget);

      await tester.tap(find.byIcon(Icons.tune));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final chip = find.byKey(const ValueKey('heatmap-race-pins-chip'));
      await tester.ensureVisible(chip);
      await tester.pump();
      await tester.tap(chip);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final callsWhenOff = api.raceCalls;
      expect(find.byKey(const ValueKey('heatmap-race-pin-race-1')),
          findsNothing);
      // Another refetch while off asks for no races.
      await tester.tap(find.text('Featured'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(api.raceCalls, callsWhenOff);
    });

    testWidgets('the Official lens asks for official races only',
        (tester) async {
      final api = _FakeApiClient();
      await _pump(tester, api);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byIcon(Icons.tune));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Official'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(api.lastOfficialOnly, isTrue);
    });
  });

  group('discovery pins + lens', () {
    testWidgets('fetches discoverable pins on mount + lists them via the pill',
        (tester) async {
      final api = _FakeApiClient()..nextPins = [_pin()];
      await _pump(tester, api);
      await tester.pump(const Duration(milliseconds: 100));
      expect(api.discoverCalls, greaterThanOrEqualTo(1));
      expect(api.lastFilter, 'popular',
          reason: 'the default lens is popular');
      // The map is clean by default: the count shows on the pill, the
      // route name only after the pill opens the modal results list.
      expect(find.text('1 route'), findsOneWidget);
      expect(find.text('Wash Park 5K Loop'), findsNothing);

      await tester.tap(find.text('1 route'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Wash Park 5K Loop'), findsOneWidget);
    });

    // Issue #1374 FS-10: a failed fetch read as "No routes here", so the
    // runner panned and changed filters over a map that never loaded.
    testWidgets('a failed routes read says so on the pill, and a tap retries',
        (tester) async {
      final api = _FakeApiClient()
        ..failRoutes = true
        ..nextPins = [_pin()];
      final l10n = lookupAppLocalizations(const Locale('en'));
      await _pump(tester, api);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text(l10n.heatmapLoadFailed), findsOneWidget);
      expect(find.text(l10n.heatmapNoRoutesHere), findsNothing);

      api.failRoutes = false;
      final calls = api.discoverCalls;
      await tester.tap(find.byKey(const Key('heatmap-results-pill')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(api.discoverCalls, calls + 1);
      expect(find.text('1 route'), findsOneWidget);
    });

    testWidgets('a result row names the surface in the reader\'s language, '
        'not the stored token', (tester) async {
      final api = _FakeApiClient()
        ..nextPins = [_pin(surface: 'trail', runCount: 2)];
      await _pump(tester, api, locale: const Locale('fr'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.textContaining('1 '));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('Sentier'), findsOneWidget);
      expect(find.textContaining('trail'), findsNothing);
      expect(find.textContaining('2 runs'), findsNothing);
    });

    testWidgets('the Filters sheet swaps the lens + refetches',
        (tester) async {
      // No pins → no band badges, so the only "Featured" text is the
      // sheet's lens chip.
      final api = _FakeApiClient();
      await _pump(tester, api);
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byIcon(Icons.tune));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Featured'), findsOneWidget);

      await tester.tap(find.text('Featured'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(api.lastFilter, 'featured');
    });

    testWidgets('the Official lens refetches with p_filter official',
        (tester) async {
      final api = _FakeApiClient();
      await _pump(tester, api);
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byIcon(Icons.tune));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Official'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(api.lastFilter, 'official');
    });

    testWidgets('an official pin carries the Official badge in the results',
        (tester) async {
      final api = _FakeApiClient()
        ..nextPins = [
          _pin(id: 'o', name: 'Organiser Course', official: true),
          _pin(id: 'c', name: 'Community Loop', lat: 39.75),
        ];
      await _pump(tester, api);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('2 routes'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final badge = find.byType(OfficialBadge);
      expect(badge, findsOneWidget);
      expect(
        find.descendant(
          of: find.ancestor(of: badge, matching: find.byType(ListTile)),
          matching: find.text('Organiser Course'),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
        'a park course pin reads "Official Threkir course", not just "Official"',
        (tester) async {
      final api = _FakeApiClient()
        ..nextPins = [
          _pin(id: 'park', name: 'Lake Loop', official: true),
          _pin(id: 'o', name: 'Organiser Course', official: true, lat: 39.75),
        ]
        ..parkCourseRouteIds = {'park'};
      await _pump(tester, api);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('2 routes'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(OfficialBadge), findsNWidgets(2));
      expect(find.text('Official Threkir course'), findsOneWidget);
      expect(
        find.descendant(
          of: find.ancestor(
            of: find.text('Official Threkir course'),
            matching: find.byType(ListTile),
          ),
          matching: find.text('Lake Loop'),
        ),
        findsOneWidget,
      );
      expect(find.text('Official'), findsOneWidget);
    });

    testWidgets('picking a distance band threads the bounds to the RPC',
        (tester) async {
      final api = _FakeApiClient();
      await _pump(tester, api);
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byIcon(Icons.tune));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('5K'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(api.lastDistMin, [4000],
          reason: 'the 5K band lower bound must reach the RPC');
    });
  });

  group('tap-to-preview', () {
    testWidgets('tapping a route row previews its line + a View action',
        (tester) async {
      final api = _FakeApiClient()
        ..nextPins = [_pin()]
        ..nextRouteById = cm.Route(
          id: 'a',
          userId: 'u',
          name: 'Wash Park 5K Loop',
          waypoints: const [
            Waypoint(lat: 39.740, lng: -105.000),
            Waypoint(lat: 39.745, lng: -105.005),
          ],
          distanceMetres: 5000,
        );
      await _pump(tester, api);
      await tester.pump(const Duration(milliseconds: 100));

      // No route line drawn until something is selected.
      expect(find.byKey(const ValueKey('heatmap-selected-route')),
          findsNothing);

      // Open the modal results list, then tap the row.
      await tester.tap(find.text('1 route'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Wash Park 5K Loop'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // The sheet pops; the selection card + previewed route line appear.
      expect(find.text('View route'), findsOneWidget);
      expect(find.byKey(const ValueKey('heatmap-selected-route')),
          findsOneWidget);
      // The basemap-aware preview rung over the shared casing: no
      // MAPTILER_KEY in tests, so the basemap is the light OSM fallback,
      // where the old fixed cyan held under 3:1.
      final lines = tester
          .widget<PolylineLayer>(
              find.byKey(const ValueKey('heatmap-selected-route')))
          .polylines;
      expect(lines.first.color, mapLineCasing);
      expect(lines.last.color, mapHoverLine(darkBasemap: false));
    });

    testWidgets('the selection card reads elevation and runs in the reader\'s '
        'unit and language', (tester) async {
      SharedPreferences.setMockInitialValues({'use_miles': true});
      final prefs = Preferences();
      await prefs.init();
      registerActivePreferences(prefs);
      addTearDown(() async {
        SharedPreferences.setMockInitialValues({});
        final km = Preferences();
        await km.init();
        registerActivePreferences(km);
      });
      final api = _FakeApiClient()
        ..nextPins = [_pin(elevationM: 229, runCount: 1)]
        ..nextRouteById = cm.Route(
          id: 'a',
          userId: 'u',
          name: 'Wash Park 5K Loop',
          waypoints: const [
            Waypoint(lat: 39.740, lng: -105.000),
            Waypoint(lat: 39.745, lng: -105.005),
          ],
          distanceMetres: 5000,
        );
      await _pump(tester, api);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('1 route'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Wash Park 5K Loop'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('751 ft'), findsOneWidget);
      expect(find.textContaining('229 m'), findsNothing);
      expect(find.textContaining('1 run'), findsWidgets);
    });
  });

  // The keep-on-map / pin behaviour (pin a route -> its violet line persists
  // across pan + filter -> Clear removes it) is covered end-to-end by the web
  // Playwright suite (apps/web/tests-e2e/routes/heatmap-filters.spec.ts,
  // "Heatmap keep-on-map / pin"). The mobile screen is a direct mirror; a
  // widget test isn't added here because the pin controls live below the
  // collapsed DraggableScrollableSheet fold, which flutter_test can't tap
  // reliably (it matches the sheet's offstage measurement copy) — the same
  // limitation the existing sheet tests work around by tapping only the
  // top-of-list rows.

  // The map controls, the pill / selection card and the credit are
  // MapFirstPage's floating column (issue #1374, IK-10 for landscape).
  group('RoutesHeatmapScreen — insets', () {
    void setView(WidgetTester tester, Size size, FakeViewPadding bar) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.view.padding = bar;
      tester.view.viewPadding = bar;
      addTearDown(tester.view.reset);
    }

    cm.Route route() => cm.Route(
          id: 'a',
          userId: 'u',
          name: 'Wash Park 5K Loop',
          waypoints: const [
            Waypoint(lat: 39.740, lng: -105.000),
            Waypoint(lat: 39.745, lng: -105.005),
          ],
          distanceMetres: 5000,
        );

    testWidgets('320 dp, 2x text, 3-button bar: the selection card and '
        'Locate me sit above the bar, Locate above the card', (tester) async {
      setView(tester, const Size(320, 640), const FakeViewPadding(bottom: 48));
      final api = _FakeApiClient()
        ..nextPins = [_pin()]
        ..nextRouteById = route();
      await _pump(tester, api, textScale: 2);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('1 route'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Wash Park 5K Loop'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      final view = tester.getRect(find.text('View route'));
      final locate = tester.getRect(find.byType(FloatingActionButton));
      expect(view.bottom, lessThanOrEqualTo(640 - 48));
      expect(locate.bottom, lessThanOrEqualTo(view.top));
      expect(find.text('View route').hitTestable(), findsOneWidget);
    });

    testWidgets('landscape: the controls and the pill clear a side bar',
        (tester) async {
      setView(tester, const Size(780, 360), const FakeViewPadding(right: 48));
      final api = _FakeApiClient()..nextPins = [_pin()];
      await _pump(tester, api);
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      expect(tester.getRect(find.byType(FloatingActionButton)).right,
          lessThanOrEqualTo(780 - 48));
      expect(tester.getRect(find.text('1 route')).right,
          lessThanOrEqualTo(780 - 48));
    });
  });
}

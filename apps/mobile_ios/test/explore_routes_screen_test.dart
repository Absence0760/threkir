import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' as cm;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ui_kit/ui_kit.dart' show AppSearchField;
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_route_store.dart';
import '../lib/preferences.dart';
import '../lib/routes_views.dart';
import '../lib/screens/explore_routes_screen.dart';
import 'supabase_test_init.dart';

bool _supabaseReady = false;

Future<void> _ensureSupabase() async {
  if (_supabaseReady) return;
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  await initializeTestSupabase();
  _supabaseReady = true;
}

Future<({Preferences prefs, LocalRouteStore routeStore})> _makeStores() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = Preferences();
  await prefs.init();
  return (prefs: prefs, routeStore: LocalRouteStore());
}

cm.Route _route(String id, String name) => cm.Route(
      id: id,
      name: name,
      waypoints: const [],
      distanceMetres: 5000,
    );

/// A signed-in viewer with one public route in the results. A held [gate]
/// keeps a bookmark request in flight; [failWith] makes it fail.
class _BookmarkApi extends ApiClient {
  _BookmarkApi({List<cm.Route> bookmarked = const []}) : _bookmarked = bookmarked;

  final List<cm.Route> _bookmarked;
  final bookmarkCalls = <String>[];
  final unbookmarkCalls = <String>[];
  Completer<void>? gate;
  Object? failWith;

  @override
  String? get userId => 'u1';

  @override
  Future<cm.KeysetPage<cm.Route>> searchPublicRoutes({
    String? query,
    double? minDistanceM,
    double? maxDistanceM,
    String? surface,
    List<String>? tags,
    bool featuredOnly = false,
    String sort = 'newest',
    int limit = 50,
    List<Object?>? after,
  }) async =>
      after == null
          ? cm.KeysetPage([_route('r1', 'Morning loop')], null)
          : const cm.KeysetPage(<cm.Route>[], null);

  @override
  Future<List<String>> fetchPopularRouteTags({int limit = 20}) async =>
      const [];

  @override
  Future<List<cm.Route>> fetchBookmarkedRoutes({int limit = 200}) async =>
      _bookmarked;

  @override
  Future<void> bookmarkRoute(String routeId) async {
    bookmarkCalls.add(routeId);
    await gate?.future;
    if (failWith != null) throw failWith!;
  }

  @override
  Future<void> unbookmarkRoute(String routeId) async {
    unbookmarkCalls.add(routeId);
    await gate?.future;
    if (failWith != null) throw failWith!;
  }
}

Future<void> _pump(
  WidgetTester tester, {
  required Preferences prefs,
  required LocalRouteStore routeStore,
  ApiClient? api,
  Future<Position> Function()? locateFn,
  RoutesExploreChrome? chrome,
}) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ExploreRoutesScreen(
        apiClient: api,
        routeStore: routeStore,
        preferences: prefs,
        locateFn: locateFn,
        chrome: chrome,
      ),
    ),
  );
}

class _NearbyApi extends _BookmarkApi {
  final nearbyCalls = <(double, double)>[];

  @override
  Future<List<cm.Route>> nearbyPublicRoutes({
    required double lat,
    required double lng,
    double radiusM = 50000,
    int limit = 50,
  }) async {
    nearbyCalls.add((lat, lng));
    return [_route('n1', 'Riverside 10K')];
  }
}

Position _fix(double lat, double lng) => Position(
      latitude: lat,
      longitude: lng,
      timestamp: DateTime.utc(2026, 1, 1),
      accuracy: 50,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

void main() {
  setUpAll(_ensureSupabase);

  group('ExploreRoutesScreen — initial render', () {
    testWidgets('renders the Explore Routes app-bar title', (tester) async {
      final s = await _makeStores();
      await _pump(tester, prefs: s.prefs, routeStore: s.routeStore);
      await tester.pump();
      expect(find.text('Explore Routes'), findsOneWidget);
    });

    testWidgets('Featured is in the Filters sheet and shows as a removable '
        'chip once on', (tester) async {
      // Reason: Featured is the entry point into curated routes —
      // its absence would mean users can't surface non-personal
      // content from the Explore tab. It moved into the Filters sheet with
      // the bar's other filters (issue #1374), so on, it shows on the line.
      final s = await _makeStores();
      await _pump(tester, prefs: s.prefs, routeStore: s.routeStore);
      await tester.pump();
      await tester.tap(find.byKey(const Key('filter-bar-filters')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, 'Featured'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(InputChip, 'Featured'), findsOneWidget);
      expect(find.byTooltip('Remove filter: Featured'), findsOneWidget);
    });

    testWidgets('one search field, with clear, and Near me as the quick chip',
        (tester) async {
      final s = await _makeStores();
      await _pump(tester, prefs: s.prefs, routeStore: s.routeStore);
      await tester.pump();
      expect(find.byType(AppSearchField), findsOneWidget);
      expect(find.widgetWithText(FilterChip, 'Near Me'), findsOneWidget);
    });

    // Under the Routes tab (issue #1374, decisions § 2490) the tab hands this
    // body its Mine · Explore row and its Routes · Segments chips; both must
    // sit above the results, the chips leading the body's own.
    testWidgets('a chrome puts the view row and its chips above the list',
        (tester) async {
      final s = await _makeStores();
      await _pump(
        tester,
        prefs: s.prefs,
        routeStore: s.routeStore,
        api: _BookmarkApi(),
        chrome: RoutesExploreChrome(
          viewBar: const SizedBox(key: Key('test-view-bar'), height: 40),
          chips: [
            FilterChip(
              key: const Key('test-chip-routes'),
              label: const Text('Routes'),
              selected: true,
              onSelected: (_) {},
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.pump();

      final viewBar = find.byKey(const Key('test-view-bar'));
      final chip = find.byKey(const Key('test-chip-routes'));
      final nearMe = find.widgetWithText(FilterChip, 'Near Me');
      final row = find.text('Morning loop');
      expect(viewBar, findsOneWidget);
      expect(chip, findsOneWidget);
      expect(row, findsOneWidget);
      expect(tester.getTopLeft(viewBar).dy,
          lessThan(tester.getTopLeft(chip).dy));
      expect(tester.getTopLeft(chip).dy, lessThan(tester.getTopLeft(row).dy));
      expect(tester.getTopLeft(chip).dx, lessThan(tester.getTopLeft(nearMe).dx),
          reason: 'the view chips lead the body\'s own');
    });
  });

  // Saving a public route is a `saved_routes` reference that a second tap
  // removes (decisions § 30). The row used to clone the route into the local
  // store and never rebuild, so the bookmark stayed unfilled after a save.
  group('ExploreRoutesScreen — the bookmark toggle', () {
    Finder filled() => find.byIcon(Icons.bookmark);
    Finder empty() => find.byIcon(Icons.bookmark_border);

    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.pump();
    }

    testWidgets('a tap fills the bookmark at once and saves by reference',
        (tester) async {
      final s = await _makeStores();
      final api = _BookmarkApi()..gate = Completer<void>();
      await _pump(tester, prefs: s.prefs, routeStore: s.routeStore, api: api);
      await settle(tester);
      expect(empty(), findsOneWidget);

      await tester.tap(empty());
      await tester.pump();
      expect(filled(), findsOneWidget,
          reason: 'the tap must visibly land before the request returns');
      expect(api.bookmarkCalls, ['r1']);

      await tester.tap(filled());
      await tester.pump();
      expect(api.bookmarkCalls, ['r1'],
          reason: 'a tap during the request must not fire a second one');
      expect(api.unbookmarkCalls, isEmpty);

      api.gate!.complete();
      await settle(tester);
      expect(filled(), findsOneWidget);
      expect(find.text('Saved "Morning loop" to your library'), findsOneWidget);
      expect(s.routeStore.routes, isEmpty,
          reason: 'a bookmark is a reference, not a private copy');
      await tester.pump(const Duration(seconds: 8));
    });

    testWidgets('a bookmarked route shows filled, and a tap removes it',
        (tester) async {
      final s = await _makeStores();
      final api = _BookmarkApi(bookmarked: [_route('r1', 'Morning loop')]);
      await _pump(tester, prefs: s.prefs, routeStore: s.routeStore, api: api);
      await settle(tester);
      expect(filled(), findsOneWidget);
      expect(find.byTooltip('Remove from your library'), findsOneWidget);

      await tester.tap(filled());
      await settle(tester);
      expect(api.unbookmarkCalls, ['r1']);
      expect(empty(), findsOneWidget);
      expect(find.text('Removed "Morning loop" from your library'),
          findsOneWidget);
      await tester.pump(const Duration(seconds: 8));
    });

    testWidgets('a failed save puts the bookmark back and says so',
        (tester) async {
      final s = await _makeStores();
      final api = _BookmarkApi()..failWith = Exception('offline');
      await _pump(tester, prefs: s.prefs, routeStore: s.routeStore, api: api);
      await settle(tester);

      await tester.tap(empty());
      await settle(tester);
      expect(empty(), findsOneWidget,
          reason: 'the icon must not claim a save that did not happen');
      expect(find.textContaining('Bookmark failed'), findsOneWidget);
      await tester.pump(const Duration(seconds: 8));
    });

    testWidgets('a library route that only shares the name is not this one',
        (tester) async {
      final s = await _makeStores();
      // ignore: invalid_use_of_visible_for_testing_member
      s.routeStore.debugSeed([_route('mine-1', 'Morning loop')]);
      final api = _BookmarkApi();
      await _pump(tester, prefs: s.prefs, routeStore: s.routeStore, api: api);
      await settle(tester);

      expect(empty(), findsOneWidget,
          reason: 'saved-ness is by id; a name match marked unrelated routes '
              'saved and disabled their button');
      await tester.tap(empty());
      await settle(tester);
      expect(api.bookmarkCalls, ['r1']);
      await tester.pump(const Duration(seconds: 8));
    });
  });

  group('ExploreRoutesScreen — Near me', () {
    testWidgets('searches around the browse fix', (tester) async {
      final s = await _makeStores();
      final api = _NearbyApi();
      await _pump(tester,
          prefs: s.prefs,
          routeStore: s.routeStore,
          api: api,
          locateFn: () async => _fix(37.54, -77.43));
      await tester.pump();
      await tester.tap(find.text('Near Me'));
      await tester.pump();
      await tester.pump();
      expect(api.nearbyCalls, [(37.54, -77.43)]);
      expect(find.text('Riverside 10K'), findsOneWidget);
    });

    testWidgets('a refused permission says why instead of a generic failure',
        (tester) async {
      final s = await _makeStores();
      final api = _NearbyApi();
      await _pump(tester,
          prefs: s.prefs,
          routeStore: s.routeStore,
          api: api,
          locateFn: () async =>
              throw const PermissionDeniedException('denied'));
      await tester.pump();
      await tester.tap(find.text('Near Me'));
      await tester.pump();
      await tester.pump();
      expect(api.nearbyCalls, isEmpty);
      expect(
          find.text('Location permission required to find nearby routes'),
          findsOneWidget);
    });

    testWidgets('location switched off says so, not a generic failure',
        (tester) async {
      final s = await _makeStores();
      final api = _NearbyApi();
      await _pump(tester,
          prefs: s.prefs,
          routeStore: s.routeStore,
          api: api,
          locateFn: () async =>
              throw const LocationServiceDisabledException());
      await tester.pump();
      await tester.tap(find.text('Near Me'));
      await tester.pump();
      await tester.pump();
      expect(api.nearbyCalls, isEmpty);
      expect(
          find.text(
              'Location unavailable: location is turned off on this device'),
          findsOneWidget);
    });

    testWidgets('a fix that never arrives is not called a network timeout',
        (tester) async {
      final s = await _makeStores();
      final api = _NearbyApi();
      await _pump(tester,
          prefs: s.prefs,
          routeStore: s.routeStore,
          api: api,
          locateFn: () async => throw TimeoutException('no fix'));
      await tester.pump();
      await tester.tap(find.text('Near Me'));
      await tester.pump();
      await tester.pump();
      expect(api.nearbyCalls, isEmpty);
      expect(
          find.text(
              'Location unavailable: no position yet, try again in a moment'),
          findsOneWidget);
      expect(find.textContaining('Connection timed out'), findsNothing);
    });
  });

  testWidgets('a result card reads elevation in the reader\'s unit',
      (tester) async {
    SharedPreferences.setMockInitialValues({'use_miles': true});
    final prefs = Preferences();
    await prefs.init();
    await _pump(tester,
        prefs: prefs, routeStore: LocalRouteStore(), api: _ClimbApi());
    await tester.pump();
    await tester.pump();
    expect(find.text('Hill loop'), findsOneWidget);
    expect(find.text('751 ft'), findsOneWidget);
    expect(find.text('229m'), findsNothing);
  });
}

class _ClimbApi extends _BookmarkApi {
  @override
  Future<cm.KeysetPage<cm.Route>> searchPublicRoutes({
    String? query,
    double? minDistanceM,
    double? maxDistanceM,
    String? surface,
    List<String>? tags,
    bool featuredOnly = false,
    String sort = 'newest',
    int limit = 50,
    List<Object?>? after,
  }) async =>
      after == null
          ? cm.KeysetPage([
              cm.Route(
                id: 'h1',
                name: 'Hill loop',
                waypoints: const [],
                distanceMetres: 5000,
                elevationGainMetres: 229,
              ),
            ], null)
          : const cm.KeysetPage(<cm.Route>[], null);
}

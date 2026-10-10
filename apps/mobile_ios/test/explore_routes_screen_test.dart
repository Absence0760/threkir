import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' as cm;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_route_store.dart';
import '../lib/preferences.dart';
import '../lib/screens/explore_routes_screen.dart';

bool _supabaseReady = false;

Future<void> _ensureSupabase() async {
  if (_supabaseReady) return;
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  await Supabase.initialize(
    url: 'http://127.0.0.1:24321',
    anonKey: 'eyJ.local.test',
  );
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
  Future<List<cm.Route>> searchPublicRoutes({
    String? query,
    double? minDistanceM,
    double? maxDistanceM,
    String? surface,
    List<String>? tags,
    bool featuredOnly = false,
    String sort = 'newest',
    int limit = 50,
    int offset = 0,
  }) async =>
      offset == 0 ? [_route('r1', 'Morning loop')] : const [];

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
}) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ExploreRoutesScreen(
        apiClient: api,
        routeStore: routeStore,
        preferences: prefs,
      ),
    ),
  );
}

void main() {
  setUpAll(_ensureSupabase);

  group('ExploreRoutesScreen — initial render', () {
    testWidgets('renders the Explore Routes app-bar title', (tester) async {
      final s = await _makeStores();
      await _pump(tester, prefs: s.prefs, routeStore: s.routeStore);
      await tester.pump();
      expect(find.text('Explore Routes'), findsOneWidget);
    });

    testWidgets('renders the Featured filter chip', (tester) async {
      // Reason: Featured is the entry point into curated routes —
      // its absence would mean users can't surface non-personal
      // content from the Explore tab.
      final s = await _makeStores();
      await _pump(tester, prefs: s.prefs, routeStore: s.routeStore);
      await tester.pump();
      expect(find.text('Featured'), findsOneWidget);
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
}

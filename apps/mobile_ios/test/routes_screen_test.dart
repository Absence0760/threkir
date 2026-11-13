import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' as cm;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_route_store.dart';
import '../lib/preferences.dart';
import '../lib/screens/explore_routes_screen.dart';
import '../lib/screens/global_segments_screen.dart';
import '../lib/screens/routes_screen.dart';
import 'pump_until.dart';
import 'worst_case_layout.dart';

/// Signed-out fake — non-null so the api-gated discovery maps render, null
/// userId so no fetch paths fire. The Explore views' reads answer empty.
class _FakeApi extends ApiClient {
  @override
  Future<List<String>> fetchPopularRouteTags({int limit = 20}) async =>
      const [];

  @override
  Future<List<cm.GlobalSegmentRow>> fetchGlobalSegments({
    int limit = kGlobalSegmentCatalogueLimit,
  }) async =>
      const [];

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
  }) async =>
      const [];
}

/// Explore's map read fails until [up] is set, then answers empty.
class _MapDownApi extends _FakeApi {
  bool up = false;
  int calls = 0;

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
    calls++;
    if (!up) throw Exception('network');
    return const [];
  }
}

/// Signed in, owns no routes, and cannot load the routes it bookmarked.
class _BookmarksDownApi extends ApiClient {
  int bookmarkCalls = 0;

  @override
  String? get userId => 'u';

  @override
  Future<cm.KeysetPage<cm.Route>> getRoutes({
    int limit = 200,
    List<Object?>? after,
    bool starredOnly = false,
  }) async =>
      const cm.KeysetPage(<cm.Route>[], null);

  @override
  Future<List<cm.Route>> fetchBookmarkedRoutes({int limit = 200}) async {
    bookmarkCalls++;
    throw Exception('saved_routes unreachable');
  }
}

List<cm.Route> _makeRoutes(int count) {
  return [
    for (int i = 0; i < count; i++)
      cm.Route(
        id: 'route-${i.toString().padLeft(3, '0')}',
        userId: 'test-user',
        name: 'Route $i',
        waypoints: const [
          cm.Waypoint(lat: 51.5, lng: -0.12),
          cm.Waypoint(lat: 51.51, lng: -0.13),
        ],
        distanceMetres: 5000,
        elevationGainMetres: 50,
      ),
  ];
}

/// Routes named exactly as given, so a search / sort case can name them back.
List<cm.Route> _namedRoutes(List<String> names) {
  return [
    for (int i = 0; i < names.length; i++)
      cm.Route(
        id: 'route-${i.toString().padLeft(3, '0')}',
        userId: 'test-user',
        name: names[i],
        waypoints: const [
          cm.Waypoint(lat: 51.5, lng: -0.12),
          cm.Waypoint(lat: 51.51, lng: -0.13),
        ],
        distanceMetres: 5000,
        elevationGainMetres: 50,
      ),
  ];
}

Future<Preferences> _makePrefs() async {
  SharedPreferences.setMockInitialValues({});
  final p = Preferences();
  await p.init();
  return p;
}

Future<void> _pump(WidgetTester tester,
    {required Preferences prefs,
    ApiClient? api,
    LocalRouteStore? routeStore,
    ValueNotifier<RoutesShow>? show,
    RoutesShow initialShow = RoutesShow.mine,
    double textScale = 1.0}) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: RoutesScreen(
        apiClient: api,
        routeStore: routeStore ?? LocalRouteStore(),
        preferences: prefs,
        show: show,
        initialShow: initialShow,
      ),
    ),
  );
}

// The route list's own scroller. The chip lines above it are horizontal
// scrollers too, so "the first Scrollable" is not the list.
final _routeList = find.byElementPredicate(
  (e) =>
      e.widget is Scrollable &&
      (e.widget as Scrollable).axisDirection == AxisDirection.down &&
      !isNestedScrollOuter(e),
);

void main() {
  worstCaseTestWidgets('the route cards', (tester, locale) async {
    final prefs = await _makePrefs();
    // ignore: invalid_use_of_visible_for_testing_member
    final store = LocalRouteStore()
      // ignore: invalid_use_of_visible_for_testing_member
      ..debugSeed(_namedRoutes(
          ['Pocahontas State Park long loop with the lake', 'River 5k']));
    await tester.pumpWidget(worstCaseApp(
      locale: locale,
      home: RoutesScreen(routeStore: store, preferences: prefs),
    ));
    await tester.pump();
    // At 2x in some locales the page's heading and controls fill the first
    // screen; the walk scrolls them away and lays the cards out.
    await walkScrollable(tester, _routeList, 'Routes');
    expect(find.byType(Card), findsWidgets);
  });

  group('RoutesScreen — initial render', () {
    testWidgets('AppBar carries the "Routes" title', (tester) async {
      // Routes is a pushed full-screen destination (Fitness → Runs →
      // Routes), no longer a bottom-nav tab — the AppBar names it.
      final prefs = await _makePrefs();
      await _pump(tester, prefs: prefs);
      await tester.pump();
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.widgetWithText(AppBar, 'Routes'), findsOneWidget);
    });

    testWidgets('an empty My routes offers Public routes, which opens Explore',
        (tester) async {
      final prefs = await _makePrefs();
      final show = ValueNotifier(RoutesShow.mine);
      addTearDown(show.dispose);
      await _pump(tester, prefs: prefs, api: _FakeApi(), show: show);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('routes-empty-explore')));
      await tester.pump();
      expect(show.value, RoutesShow.routes);
      expect(find.byType(ExploreRoutesScreen), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing,
          reason: 'Build belongs to My routes, not to Explore');
    });

    testWidgets(
        "a failed read of Explore's map says so with Retry, not an empty map "
        '(FS-10)', (tester) async {
      final prefs = await _makePrefs();
      final api = _MapDownApi();
      await _pump(tester,
          prefs: prefs, api: api, initialShow: RoutesShow.routes);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final failed = find.byKey(const Key('explore-map-load-failed'));
      expect(failed, findsOneWidget);
      api.up = true;
      final before = api.calls;
      await tester.tap(failed);
      await tester.pump();
      expect(api.calls, greaterThan(before));
      expect(failed, findsNothing);
    });

    testWidgets(
        'Explore heads Routes with both heatmaps when an api client is wired, '
        'and has none without one', (tester) async {
      final prefs = await _makePrefs();
      await _pump(tester,
          prefs: prefs, api: _FakeApi(), initialShow: RoutesShow.routes);
      await tester.pump();
      // Community routes heatmap + the user's own run heatmap, both as
      // labelled buttons. Both labels carry their qualifier since the
      // siblings sit side by side.
      expect(find.widgetWithText(OutlinedButton, 'Routes heatmap'),
          findsOneWidget);
      expect(
          find.widgetWithText(OutlinedButton, 'Run heatmap'), findsOneWidget);

      await _pump(tester, prefs: prefs, initialShow: RoutesShow.mine);
      await tester.pump();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Explore'));
      await tester.pump();
      expect(find.widgetWithText(OutlinedButton, 'Routes heatmap'),
          findsNothing);
      expect(
          find.widgetWithText(OutlinedButton, 'Run heatmap'), findsNothing);
    });

    testWidgets('hides the cloud-sync icon when apiClient is null',
        (tester) async {
      // Reason: without a signed-in user the cloud_download icon must
      // not appear — there is nothing to sync.
      final prefs = await _makePrefs();
      await _pump(tester, prefs: prefs);
      await tester.pump();
      expect(find.byIcon(Icons.cloud_download), findsNothing);
    });

    testWidgets('renders the Import FAB with the upload icon',
        (tester) async {
      final prefs = await _makePrefs();
      await _pump(tester, prefs: prefs);
      await tester.pump();
      expect(find.byType(FloatingActionButton), findsOneWidget);
      // The empty-state hint now ALSO surfaces an "Import" label
      // inline (matching the FAB) so a first-time user can pair
      // the verbal CTA with the visual button. There are
      // therefore two "Import" texts on an empty screen — one in
      // the FAB, one in the hint row.
      expect(find.text('Import'), findsAtLeastNWidgets(1));
      expect(find.byIcon(Icons.upload_file), findsAtLeastNWidgets(1));
    });

    testWidgets('shows the empty state when there are no routes',
        (tester) async {
      // Empty-state copy now mentions BOTH the Build affordance and
      // the Import affordance so a first-time user finds both
      // FABs. The original copy said "Tap Import to add a GPX
      // or KML file" — Build wasn't surfaced at all, even though
      // it's the canonical "create from scratch" path on this
      // screen.
      final prefs = await _makePrefs();
      await _pump(tester, prefs: prefs);
      await tester.pump();
      expect(find.text('No routes yet'), findsOneWidget);
      // Match the new copy.
      expect(
        find.textContaining('Tap Build to draw a route'),
        findsOneWidget,
      );
      expect(find.textContaining('Import a GPX'), findsOneWidget);
    });
  });

  group('RoutesScreen — bookmarks', () {
    testWidgets('a failed bookmark load says so instead of vanishing silently',
        (tester) async {
      final prefs = await _makePrefs();
      final api = _BookmarksDownApi();
      await _pump(tester, prefs: prefs, api: api);
      await pumpUntil(
        tester,
        () => find
            .text('Could not load your bookmarked routes')
            .evaluate()
            .isNotEmpty,
        describe: 'the bookmarks-failed banner',
      );
      expect(api.bookmarkCalls, 1);
      // Drain the banner's auto-dismiss timer.
      await tester.pump(const Duration(seconds: 7));
    });
  });

  group('RoutesScreen — per-card row polish', () {
    // Polish iteration after the original chip-pill strip — the
    // user noted the routes cards were visibly taller than the
    // History tab's run cards. Subtitle is now a single line
    // (`distance · elevation`) matching runs' `date · duration`,
    // and the state badges moved into the trailing row + a small
    // title-prefix glyph for public routes. Tests here pin the
    // new inline shape.
    testWidgets(
      'unsynced (locally-built) routes show the cloud-upload glyph '
      'in the trailing row',
      (tester) async {
        final prefs = await _makePrefs();
        // ignore: invalid_use_of_visible_for_testing_member
        final routeStore = LocalRouteStore()
          // Seed WITHOUT marking synced — these are local-only.
          // ignore: invalid_use_of_visible_for_testing_member
          ..debugSeed(_makeRoutes(1), markSynced: false);
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: RoutesScreen(
              apiClient: null,
              routeStore: routeStore,
              preferences: prefs,
            ),
          ),
        );
        await tester.pump();
        // Inline glyph + tooltip — single-line row, no subtitle bloat.
        expect(find.byIcon(Icons.cloud_upload_outlined), findsOneWidget);
        expect(find.byTooltip('Queued to sync'), findsOneWidget);
      },
    );

    testWidgets(
      'synced routes do NOT show the cloud-upload glyph',
      (tester) async {
        final prefs = await _makePrefs();
        // ignore: invalid_use_of_visible_for_testing_member
        final routeStore = LocalRouteStore()
          // debugSeed defaults to markSynced=true.
          // ignore: invalid_use_of_visible_for_testing_member
          ..debugSeed(_makeRoutes(1));
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: RoutesScreen(
              apiClient: null,
              routeStore: routeStore,
              preferences: prefs,
            ),
          ),
        );
        await tester.pump();
        expect(find.byIcon(Icons.cloud_upload_outlined), findsNothing);
      },
    );

    testWidgets(
      'public routes show the globe glyph as a title prefix',
      (tester) async {
        final prefs = await _makePrefs();
        final publicRoute = cm.Route(
          id: 'public-route-1',
          userId: 'test-user',
          name: 'Open to all',
          waypoints: const [
            cm.Waypoint(lat: 51.5, lng: -0.12),
            cm.Waypoint(lat: 51.51, lng: -0.13),
          ],
          distanceMetres: 5000,
          elevationGainMetres: 50,
          isPublic: true,
        );
        // ignore: invalid_use_of_visible_for_testing_member
        final routeStore = LocalRouteStore()
          // ignore: invalid_use_of_visible_for_testing_member
          ..debugSeed([publicRoute]);
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: RoutesScreen(
              apiClient: null,
              routeStore: routeStore,
              preferences: prefs,
            ),
          ),
        );
        await tester.pump();
        expect(find.byIcon(Icons.public), findsOneWidget);
      },
    );

    testWidgets(
      'private routes do NOT show the globe glyph — keeps the '
      'title clean on the default-case route',
      (tester) async {
        final prefs = await _makePrefs();
        // ignore: invalid_use_of_visible_for_testing_member
        final routeStore = LocalRouteStore()
          // _makeRoutes defaults to isPublic=false.
          // ignore: invalid_use_of_visible_for_testing_member
          ..debugSeed(_makeRoutes(1));
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: RoutesScreen(
              apiClient: null,
              routeStore: routeStore,
              preferences: prefs,
            ),
          ),
        );
        await tester.pump();
        expect(find.byIcon(Icons.public), findsNothing);
      },
    );

    testWidgets(
      'route subtitle is a single line (distance · elevation) — '
      'matches the History tab card height',
      (tester) async {
        // Pre-fix the routes-card subtitle had a two-row Column
        // (distance line + Wrap badge chips below) which made the
        // card visibly taller than the History tab's run-card.
        // Both are now single-line.
        final prefs = await _makePrefs();
        // ignore: invalid_use_of_visible_for_testing_member
        final routeStore = LocalRouteStore()
          // ignore: invalid_use_of_visible_for_testing_member
          ..debugSeed(_makeRoutes(1));
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: RoutesScreen(
              apiClient: null,
              routeStore: routeStore,
              preferences: prefs,
            ),
          ),
        );
        await tester.pump();
        // 5 km / 50 m gain — pinned in `_makeRoutes`. Subtitle
        // text contains both pieces of metadata in the same Text.
        expect(
          find.textContaining('5.00\u00A0km'),
          findsOneWidget,
        );
        expect(
          find.textContaining('50\u00A0m\u00A0↑'),
          findsOneWidget,
        );
      },
    );
  });

  group('RoutesScreen pagination', () {
    test('shouldShowRoutesLoadMore — local rows beyond visibleCount', () {
      expect(
        // ignore: invalid_use_of_visible_for_testing_member
        shouldShowRoutesLoadMore(
          visibleCount: 20,
          totalCount: 25,
          remoteHasMore: false,
          apiSignedIn: false,
        ),
        isTrue,
      );
    });

    test('shouldShowRoutesLoadMore — exhausted local + signed-in cloud', () {
      expect(
        // ignore: invalid_use_of_visible_for_testing_member
        shouldShowRoutesLoadMore(
          visibleCount: 20,
          totalCount: 20,
          remoteHasMore: true,
          apiSignedIn: true,
        ),
        isTrue,
      );
    });

    test('shouldShowRoutesLoadMore — exhausted local + cloud says done', () {
      expect(
        // ignore: invalid_use_of_visible_for_testing_member
        shouldShowRoutesLoadMore(
          visibleCount: 20,
          totalCount: 20,
          remoteHasMore: false,
          apiSignedIn: true,
        ),
        isFalse,
      );
    });

    test('shouldShowRoutesLoadMore — signed out, no local extras', () {
      expect(
        // ignore: invalid_use_of_visible_for_testing_member
        shouldShowRoutesLoadMore(
          visibleCount: 20,
          totalCount: 20,
          remoteHasMore: true,
          apiSignedIn: false,
        ),
        isFalse,
      );
    });

    testWidgets('shows first page + Load more when 25 routes cached',
        (tester) async {
      final prefs = await _makePrefs();
      // ignore: invalid_use_of_visible_for_testing_member
      final routeStore = LocalRouteStore()..debugSeed(_makeRoutes(25));
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: RoutesScreen(
            apiClient: null,
            routeStore: routeStore,
            preferences: prefs,
          ),
        ),
      );
      await tester.pump();

      // First page = 20 routes; remaining 5 hidden behind the footer.
      // ListView.builder is lazy; scroll to materialise the footer.
      await tester.scrollUntilVisible(
        find.text('Load 20 more'),
        300,
        scrollable: _routeList,
      );
      expect(find.text('Load 20 more'), findsOneWidget);
    });

    testWidgets('Load more hidden when fewer routes than page size',
        (tester) async {
      final prefs = await _makePrefs();
      // ignore: invalid_use_of_visible_for_testing_member
      final routeStore = LocalRouteStore()..debugSeed(_makeRoutes(5));
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: RoutesScreen(
            apiClient: null,
            routeStore: routeStore,
            preferences: prefs,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Load 20 more'), findsNothing);
    });

    testWidgets('tapping Load more reveals the next local page',
        (tester) async {
      final prefs = await _makePrefs();
      // ignore: invalid_use_of_visible_for_testing_member
      final routeStore = LocalRouteStore()..debugSeed(_makeRoutes(25));
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: RoutesScreen(
            apiClient: null,
            routeStore: routeStore,
            preferences: prefs,
          ),
        ),
      );
      await tester.pump();

      await tester.scrollUntilVisible(
        find.text('Load 20 more'),
        300,
        scrollable: _routeList,
      );
      expect(find.text('Load 20 more'), findsOneWidget);
      // ensureVisible — the route-cards are taller after the
      // polish round (96×56 thumbnail vs the old 72×40), so the
      // load-more footer drifted a few pixels past the 600-px test
      // viewport. ensureVisible re-anchors the scroll so the tap
      // offset lands inside the renderbox.
      await tester.ensureVisible(find.text('Load 20 more'));
      await tester.pump();
      await tester.tap(find.text('Load 20 more'));
      await tester.pump();

      // 25 ≤ 40 (next page) + apiClient null → no further button.
      expect(find.text('Load 20 more'), findsNothing);
    });
  });

  group('RoutesScreen — selection mode (bulk delete)', () {
    testWidgets('the long-press hint is shown, then yields to the app bar',
        (tester) async {
      final prefs = await _makePrefs();
      // ignore: invalid_use_of_visible_for_testing_member
      final routeStore = LocalRouteStore()
        // ignore: invalid_use_of_visible_for_testing_member
        ..debugSeed(_makeRoutes(3));
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: RoutesScreen(
          apiClient: null,
          routeStore: routeStore,
          preferences: prefs,
        ),
      ));
      await tester.pump();
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));

      // A long press is the only route into multi-select, so it is announced
      // while there is something to select.
      expect(find.text(l10n.routesSelectionHint), findsOneWidget);

      await tester.longPress(find.text('Route 0'));
      await tester.pump();

      // Once selecting, the app bar carries the affordances and the hint is
      // spent — leaving it would restate a mode the user is already in.
      expect(find.text(l10n.routesSelectionHint), findsNothing);
    });

    testWidgets('no long-press hint when nothing on screen is selectable',
        (tester) async {
      final prefs = await _makePrefs();
      // ignore: invalid_use_of_visible_for_testing_member
      final routeStore = LocalRouteStore();
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: RoutesScreen(
          apiClient: null,
          routeStore: routeStore,
          preferences: prefs,
        ),
      ));
      await tester.pump();
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(find.text(l10n.routesSelectionHint), findsNothing);
    });

    testWidgets('long-press on a route enters selection mode + shows banner',
        (tester) async {
      final prefs = await _makePrefs();
      // ignore: invalid_use_of_visible_for_testing_member
      final routeStore = LocalRouteStore()
        // ignore: invalid_use_of_visible_for_testing_member
        ..debugSeed(_makeRoutes(3));
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: RoutesScreen(
          apiClient: null,
          routeStore: routeStore,
          preferences: prefs,
        ),
      ));
      await tester.pump();

      // Pre-state: no selection banner.
      expect(find.textContaining(' selected'), findsNothing);

      await tester.longPress(find.text('Route 0'));
      await tester.pump();

      expect(find.text('1 selected'), findsOneWidget);
      // Banner controls — Cancel, Select all, Delete.
      expect(find.byIcon(Icons.close), findsOneWidget);
      expect(find.byIcon(Icons.select_all), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    });

    testWidgets('tap on another route in selection mode adds to the selection',
        (tester) async {
      final prefs = await _makePrefs();
      // ignore: invalid_use_of_visible_for_testing_member
      final routeStore = LocalRouteStore()
        // ignore: invalid_use_of_visible_for_testing_member
        ..debugSeed(_makeRoutes(3));
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: RoutesScreen(
          apiClient: null,
          routeStore: routeStore,
          preferences: prefs,
        ),
      ));
      await tester.pump();

      await tester.longPress(find.text('Route 0'));
      await tester.pump();
      await tester.tap(find.text('Route 1'));
      await tester.pump();

      expect(find.text('2 selected'), findsOneWidget);
    });

    testWidgets('Cancel button exits selection mode', (tester) async {
      final prefs = await _makePrefs();
      // ignore: invalid_use_of_visible_for_testing_member
      final routeStore = LocalRouteStore()
        // ignore: invalid_use_of_visible_for_testing_member
        ..debugSeed(_makeRoutes(2));
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: RoutesScreen(
          apiClient: null,
          routeStore: routeStore,
          preferences: prefs,
        ),
      ));
      await tester.pump();

      await tester.longPress(find.text('Route 0'));
      await tester.pump();
      expect(find.text('1 selected'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();

      expect(find.textContaining(' selected'), findsNothing);
    });

    testWidgets(
        'Delete button shows a pluralised confirm dialog; Cancel keeps the rows',
        (tester) async {
      // We exercise the UI plumbing through the dialog. The actual
      // disk-write path of `routeStore.deleteMany` is covered by the
      // local_route_store_test suite; mixing the two here forces us
      // to drive the showTopBanner Timer + dialog dismiss animation
      // which the flutter_test runner can't drain cleanly with a
      // ChangeNotifier overlay + ScaffoldMessenger banner stacked on
      // top. The Cancel branch covers the UI contract; the Confirm
      // branch is exercised via the store-level deleteMany tests.
      final prefs = await _makePrefs();
      // ignore: invalid_use_of_visible_for_testing_member
      final routeStore = LocalRouteStore()
        // ignore: invalid_use_of_visible_for_testing_member
        ..debugSeed(_makeRoutes(3));
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: RoutesScreen(
          apiClient: null,
          routeStore: routeStore,
          preferences: prefs,
        ),
      ));
      await tester.pump();

      await tester.longPress(find.text('Route 0'));
      await tester.pump();
      await tester.tap(find.text('Route 1'));
      await tester.pump();
      expect(find.text('2 selected'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pump();

      // Confirm dialog title — pluralised against the selection count.
      expect(find.text('Delete 2 routes?'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Cancel keeps everything in the store and exits the dialog.
      expect(routeStore.routes, hasLength(3));
      expect(find.text('Delete 2 routes?'), findsNothing);
    });
  });

  // Field report (Android, 1080x2340 at ~1.3x OS text): "Routes heatmap" cut
  // off by the sync button, "Any distance" cut off at the screen edge, titles
  // truncated to eight characters, "229" and "m ↑" on separate lines, and two
  // extended FABs parked over the cards' star buttons.
  group('RoutesScreen — phone layout at raised text scale', () {
    const phone = Size(360, 780);
    const gutter = 16.0;

    void usePhone(WidgetTester tester, {double bottomInset = 0}) {
      tester.view.physicalSize = phone;
      tester.view.devicePixelRatio = 1.0;
      tester.view.padding = FakeViewPadding(bottom: bottomInset);
      tester.view.viewPadding = FakeViewPadding(bottom: bottomInset);
      addTearDown(tester.view.reset);
    }

    // No waypoints, so the card leads with an avatar rather than a track
    // preview that would ask the fake api for a clipped trace.
    List<cm.Route> plainRoutes(int count, {String prefix = 'Route'}) => [
          for (var i = 0; i < count; i++)
            cm.Route(
              id: 'plain-$i',
              userId: 'test-user',
              name: '$prefix $i',
              waypoints: const [],
              distanceMetres: 42617,
              elevationGainMetres: 229,
            ),
        ];

    void expectInsideScreen(WidgetTester tester, Finder chips, String what) {
      expect(chips, findsWidgets);
      for (var i = 0; i < chips.evaluate().length; i++) {
        final rect = tester.getRect(chips.at(i));
        expect(rect.left, greaterThanOrEqualTo(gutter - 0.01),
            reason: '$what #$i starts inside the gutter');
        expect(rect.right, lessThanOrEqualTo(phone.width - gutter + 0.01),
            reason: '$what #$i ends inside the gutter, not clipped');
      }
    }

    for (final scale in [1.3, 2.0]) {
      testWidgets('at ${scale}x the Explore maps all sit on screen in one row',
          (tester) async {
        usePhone(tester);
        final prefs = await _makePrefs();
        await _pump(tester,
            prefs: prefs,
            api: _FakeApi(),
            initialShow: RoutesShow.routes,
            textScale: scale);
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'no overflow stripe');

        final maps = find.descendant(
            of: find.byKey(const ValueKey('routes-discover-strip')),
            matching: find.byType(OutlinedButton));
        expect(maps, findsNWidgets(2));
        expectInsideScreen(tester, maps, 'map tile');
        final top = tester.getRect(maps.first).top;
        for (var i = 0; i < 2; i++) {
          expect(tester.getRect(maps.at(i)).top, top,
              reason: 'map tile #$i shares the first row');
          expect(tester.getSize(maps.at(i)).height,
              greaterThanOrEqualTo(kMinInteractiveDimension));
        }
        final strip =
            tester.getRect(find.byKey(const ValueKey('routes-discover-strip')));
        expect(strip.height, lessThan(3 * kMinInteractiveDimension),
            reason: 'the strip is one row of tiles, even at ${scale}x');
        expect(
            find.byWidgetPredicate(
                (w) => w is Semantics && w.properties.label == 'Discover'),
            findsOneWidget,
            reason: 'the strip is still named for assistive tech');
      });

      testWidgets('at ${scale}x the view and Explore chips sit on screen',
          (tester) async {
        usePhone(tester);
        final prefs = await _makePrefs();
        await _pump(tester,
            prefs: prefs,
            api: _FakeApi(),
            initialShow: RoutesShow.routes,
            textScale: scale);
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'no overflow stripe');
        // The test font draws every glyph a full em wide, about twice
        // Roboto's average, so at 2x it overstates the chips past the
        // screen; the line scrolls there, which the chip-line test covers.
        if (scale < 2) {
          expectInsideScreen(
              tester,
              find.descendant(
                  of: find.byKey(const ValueKey('routes-view-bar')),
                  matching: find.byType(ChoiceChip)),
              'view chip');
        }
        for (final label in ['Routes', 'Segments']) {
          final chip = find.widgetWithText(ChoiceChip, label);
          expect(chip, findsOneWidget);
          expect(tester.getRect(chip).left, greaterThanOrEqualTo(0));
        }
      });

      testWidgets('at ${scale}x Filters and the Starred chip sit on screen',
          (tester) async {
        usePhone(tester);
        final prefs = await _makePrefs();
        // ignore: invalid_use_of_visible_for_testing_member
        final store = LocalRouteStore()..debugSeed(plainRoutes(3));
        await _pump(tester, prefs: prefs, routeStore: store, textScale: scale);
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'no overflow stripe');

        // Filters beside the search, Starred on the chip line.
        final strip = find.byKey(const ValueKey('routes-filter-bar'));
        final controls = find.descendant(
          of: strip,
          matching: find.byWidgetPredicate(
              (w) => w is FilterChip || w is IconButton),
        );
        expect(controls, findsNWidgets(2));
        expectInsideScreen(tester, controls, 'filter control');
        for (var i = 0; i < 2; i++) {
          expect(tester.getSize(controls.at(i)).height,
              greaterThanOrEqualTo(kMinInteractiveDimension),
              reason: 'filter control #$i keeps a 48 dp tap target');
        }
      });

      testWidgets(
          'at ${scale}x the last route scrolls clear of the FABs and the '
          'navigation bar', (tester) async {
        const navBar = 48.0;
        usePhone(tester, bottomInset: navBar);
        final prefs = await _makePrefs();
        // ignore: invalid_use_of_visible_for_testing_member
        final store = LocalRouteStore()..debugSeed(plainRoutes(12));
        await _pump(tester,
            prefs: prefs, api: _FakeApi(), routeStore: store, textScale: scale);
        await tester.pump();

        // A builder list only estimates its extent until the tail is laid
        // out, so jump to the end until the end stops moving.
        final list = tester.state<ScrollableState>(_routeList).position;
        for (var i = 0; i < 10 && list.pixels != list.maxScrollExtent; i++) {
          list.jumpTo(list.maxScrollExtent);
          await tester.pump();
        }
        expect(list.pixels, list.maxScrollExtent);
        final last = find.byType(Card).last;
        final lastBottom = tester.getRect(last).bottom;
        final fab = find.byType(FloatingActionButton);
        expect(fab, findsOneWidget);
        expect(lastBottom, lessThanOrEqualTo(tester.getRect(fab).top),
            reason: 'the Build FAB must not cover the last card');
        expect(lastBottom, lessThanOrEqualTo(phone.height - navBar));
      });
    }

    testWidgets('at 1.3x a route title gets two lines, not one',
        (tester) async {
      usePhone(tester);
      final prefs = await _makePrefs();
      // The test font is Ahem, a square per glyph, so this is about the width
        // the field report saw: eight characters a line at 1.3x.
        const name = 'Pocahontas St';
      // ignore: invalid_use_of_visible_for_testing_member
      final store = LocalRouteStore()
        // ignore: invalid_use_of_visible_for_testing_member
        ..debugSeed([
          cm.Route(
            id: 'long',
            userId: 'test-user',
            name: name,
            waypoints: const [],
            distanceMetres: 42617,
            elevationGainMetres: 229,
          ),
        ]);
      await _pump(tester, prefs: prefs, routeStore: store, textScale: 1.3);
      await tester.pump();
      expect(tester.takeException(), isNull);
      final title = tester.renderObject<RenderParagraph>(find.text(name));
      expect(title.didExceedMaxLines, isFalse,
          reason: 'a 13-character name fits on two lines at 1.3x');
      expect(find.byIcon(Icons.chevron_right), findsNothing,
          reason: 'the whole card is the tap target; the chevron only cost '
              'the title width');
    });

    testWidgets('Build is the one FAB; Import sits in the control row',
        (tester) async {
      usePhone(tester);
      final prefs = await _makePrefs();
      await _pump(tester, prefs: prefs, api: _FakeApi(), textScale: 1.3);
      await tester.pump();
      expect(find.byType(FloatingActionButton), findsOneWidget,
          reason: 'a second FAB stacked above Build covered the star and '
              'title of every card that scrolled under the pair');
      expect(find.widgetWithText(FloatingActionButton, 'Build'),
          findsOneWidget);
      expect(find.byTooltip('Import'), findsOneWidget);
      expect(
          find.descendant(
              of: find.byType(AppBar), matching: find.byTooltip('Import')),
          findsNothing,
          reason: 'a tab body\'s actions live in its control row, hosted or '
              'pushed');
    });
  });

  // Owner decision 1 on issue #1374: Routes is My routes · Explore, and the
  // segment catalogue is Explore's Segments chip rather than a Fitness tab.
  group('RoutesScreen — My routes · Explore', () {
    testWidgets('the view row switches views and Explore keeps its chip',
        (tester) async {
      final prefs = await _makePrefs();
      final show = ValueNotifier(RoutesShow.mine);
      addTearDown(show.dispose);
      await _pump(tester, prefs: prefs, api: _FakeApi(), show: show);
      await tester.pump();
      expect(find.widgetWithText(FloatingActionButton, 'Build'),
          findsOneWidget);
      expect(find.byType(GlobalSegmentsScreen), findsNothing,
          reason: 'Explore is built the first time it is shown');

      await tester.tap(find.widgetWithText(ChoiceChip, 'Explore'));
      await tester.pump();
      expect(show.value, RoutesShow.routes);
      expect(find.byType(ExploreRoutesScreen), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Segments'));
      await tester.pump();
      expect(show.value, RoutesShow.segments);
      expect(find.byType(GlobalSegmentsScreen), findsOneWidget);
      expect(find.byType(ExploreRoutesScreen), findsNothing,
          reason: 'one Explore view on screen at a time');

      await tester.tap(find.widgetWithText(ChoiceChip, 'Mine'));
      // Past the Scaffold's FAB entrance, which draws the old and new FAB.
      await tester.pump(const Duration(seconds: 1));
      expect(show.value, RoutesShow.mine);
      expect(find.widgetWithText(FloatingActionButton, 'Build'),
          findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Explore'));
      await tester.pump();
      expect(show.value, RoutesShow.segments,
          reason: 'Explore reopens on the chip it was left on');
    });

    // Each view is its own body in an IndexedStack (decisions § 2490), so a
    // round trip through Explore must not reset what the runner typed or
    // chose in a view they left.
    testWidgets('Mine to Explore to Segments and back keeps each view\'s '
        'search text and filters', (tester) async {
      final prefs = await _makePrefs();
      final show = ValueNotifier(RoutesShow.mine);
      addTearDown(show.dispose);
      // ignore: invalid_use_of_visible_for_testing_member
      final routeStore = LocalRouteStore()
        ..debugSeed(_namedRoutes(['Zürich Lakeside', 'Riverside Way']));
      await _pump(tester,
          prefs: prefs, api: _FakeApi(), routeStore: routeStore, show: show);
      await tester.pump();

      await tester.tap(find.byTooltip('Filters'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('A–Z').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'zurich');
      await tester.pump();
      expect(find.byTooltip('Remove filter: A–Z'), findsOneWidget);
      expect(find.text('Riverside Way'), findsNothing);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Explore'));
      await tester.pump();
      expect(show.value, RoutesShow.routes);
      await tester.enterText(
          find.descendant(
              of: find.byType(ExploreRoutesScreen),
              matching: find.byType(TextField)),
          'harbour');
      await tester.pump();

      await tester.tap(find.widgetWithText(ChoiceChip, 'Segments'));
      await tester.pump();
      expect(show.value, RoutesShow.segments);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Routes'));
      await tester.pump();
      expect(show.value, RoutesShow.routes);
      expect(
          tester
              .widget<TextField>(find.descendant(
                  of: find.byType(ExploreRoutesScreen),
                  matching: find.byType(TextField)))
              .controller!
              .text,
          'harbour',
          reason: 'Explore\'s search survives a trip to Segments');

      await tester.tap(find.widgetWithText(ChoiceChip, 'Mine'));
      await tester.pump(const Duration(seconds: 1));
      expect(show.value, RoutesShow.mine);
      expect(
          tester.widget<TextField>(find.byType(TextField).first).controller!.text,
          'zurich');
      expect(find.byTooltip('Remove filter: A–Z'), findsOneWidget,
          reason: 'Mine\'s filters survive the round trip');
      expect(find.text('Zürich Lakeside'), findsOneWidget);
      expect(find.text('Riverside Way'), findsNothing);
    });

    testWidgets('a host notifier opens Explore on Segments with nothing pushed',
        (tester) async {
      final prefs = await _makePrefs();
      final show = ValueNotifier(RoutesShow.mine);
      addTearDown(show.dispose);
      await _pump(tester, prefs: prefs, api: _FakeApi(), show: show);
      await tester.pump();
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      show.value = RoutesShow.segments;
      await tester.pump();
      expect(find.byType(GlobalSegmentsScreen), findsOneWidget);
      expect(
          tester
              .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Segments'))
              .selected,
          isTrue);
      expect(navigator.canPop(), isFalse, reason: 'selected, not pushed');
    });
  });

  group('routeStatsLine', () {
    final route = cm.Route(
      id: 'r',
      userId: 'u',
      name: 'n',
      waypoints: const [],
      distanceMetres: 42617,
      elevationGainMetres: 229,
    );

    test('never leaves a breaking space between a figure and its unit', () {
      for (final unit in cm.DistanceUnit.values) {
        final pieces = routeStatsLine(route, unit).split('  •  ');
        expect(pieces, hasLength(2));
        for (final p in pieces) {
          expect(p.contains(' '), isFalse, reason: '"$p" could wrap mid-figure');
        }
      }
    });

    test('a route\'s official distance replaces the traced one', () {
      final raced = cm.Route(
        id: 'r',
        userId: 'u',
        name: 'n',
        waypoints: const [],
        distanceMetres: 42617,
        elevationGainMetres: 229,
        officialDistanceMetres: 42200,
      );
      expect(routeStatsLine(raced, cm.DistanceUnit.km).split('  •  ').first,
          '42.20\u00A0km');
    });

    test('reads elevation in the reader unit', () {
      expect(routeStatsLine(route, cm.DistanceUnit.km),
          '42.62 km  •  229 m ↑');
      expect(routeStatsLine(route, cm.DistanceUnit.mi),
          '26.48 mi  •  751 ft ↑');
    });
  });

  group('RoutesScreen — OS text scaling (issue #666 V12)', () {
    testWidgets(
        'the filter chip rail takes its height from the chips, not a literal '
        '40 px lane', (tester) async {
      final prefs = await _makePrefs();
      // The filter header is the first row of the populated list — the
      // zero-routes empty state renders instead of it.
      // ignore: invalid_use_of_visible_for_testing_member
      final store = LocalRouteStore()..debugSeed(_makeRoutes(1));

      await _pump(tester, prefs: prefs, routeStore: store);
      await tester.pump();
      final chip = find.byType(FilterChip).first;
      final small = tester.getSize(chip).height;
      // A Material chip's own tap target is 48; the old 40 px lane squeezed it.
      expect(small, greaterThanOrEqualTo(48));

      await _pump(tester, prefs: prefs, routeStore: store, textScale: 2.0);
      await tester.pump();
      // Pre-fix the chip measured exactly 40.0 here while needing 58, so its
      // label was cropped inside the rail.
      expect(tester.getSize(chip).height, greaterThan(small));
    });
  });

  // ── Search + sort fold (decisions § 1337) ─────────────────────────────
  //
  // Both used to run through `toLowerCase()`, whose answer differs between
  // this runtime and a browser's at 466 code points, and the `az` sort
  // additionally compared code units where web collated — two orderings that
  // disagree about 31.75 % of all pairs of Unicode letters. Both now go
  // through `catalogue_browse`'s generated fold, so the phone and the web
  // answer the same question the same way.
  group('RoutesScreen — search and sort fold', () {
    testWidgets('typing an unaccented query finds the accented route',
        (tester) async {
      final prefs = await _makePrefs();
      // ignore: invalid_use_of_visible_for_testing_member
      final routeStore = LocalRouteStore()
        ..debugSeed(_namedRoutes(['İstanbul Loop', 'Riverside Way']));
      await _pump(tester, prefs: prefs, routeStore: routeStore);
      await tester.pump();

      await tester.enterText(find.byType(TextField).first, 'istanbul');
      await tester.pump();

      // A browser's `toLowerCase` renders İ as i + a combining dot, so
      // `istanbul` did NOT match there while it did here. Folding makes the
      // two agree — and the assertion holds on either runtime.
      expect(find.text('İstanbul Loop'), findsOneWidget);
      expect(find.text('Riverside Way'), findsNothing);
    });

    testWidgets('the query folds accents, so zurich reaches Zürich',
        (tester) async {
      final prefs = await _makePrefs();
      // ignore: invalid_use_of_visible_for_testing_member
      final routeStore = LocalRouteStore()
        ..debugSeed(_namedRoutes(['Zürich Lakeside', 'Riverside Way']));
      await _pump(tester, prefs: prefs, routeStore: routeStore);
      await tester.pump();

      await tester.enterText(find.byType(TextField).first, 'zurich');
      await tester.pump();

      expect(find.text('Zürich Lakeside'), findsOneWidget);
      expect(find.text('Riverside Way'), findsNothing);
    });

    testWidgets('A–Z orders on the folded name, not on raw code units',
        (tester) async {
      final prefs = await _makePrefs();
      // ignore: invalid_use_of_visible_for_testing_member
      final routeStore = LocalRouteStore()
        ..debugSeed(_namedRoutes(
            ['Zaragoza Loop', 'Åre Trail', 'Riverside Way']));
      await _pump(tester, prefs: prefs, routeStore: routeStore);
      await tester.pump();

      // Sort lives in the Filters sheet.
      await tester.tap(find.byTooltip('Filters'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('A–Z').last);
      await tester.pump();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      double y(String name) => tester.getTopLeft(find.text(name)).dy;
      // Folded: "are trail" < "riverside way" < "zaragoza loop". A raw
      // code-unit order would put Å (U+00C5) after Z (U+005A) and end the
      // list with Åre — which is what this side used to do.
      expect(y('Åre Trail'), lessThan(y('Riverside Way')));
      expect(y('Riverside Way'), lessThan(y('Zaragoza Loop')));
    });
  });

}

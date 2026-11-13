import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' as cm;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/preferences.dart';
import '../lib/screens/public_route_screen.dart';
import '../lib/widgets/loading_skeletons.dart';
import 'pump_until.dart';
import 'supabase_test_init.dart';
import 'worst_case_layout.dart';

bool _supabaseReady = false;

Future<void> _ensureSupabase() async {
  if (_supabaseReady) return;
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  await initializeTestSupabase();
  _supabaseReady = true;
}

Future<void> _pump(WidgetTester tester) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: PublicRouteScreen(api: ApiClient(), routeId: 'fake-route-id'),
    ),
  );
}

void main() {
  setUpAll(_ensureSupabase);

  worstCaseTestWidgets('Public route', (tester, locale) async {
    await tester.pumpWidget(worstCaseApp(
      locale: locale,
      home: PublicRouteScreen(
        api: _OwnerApi(
          name: 'Philadelphia Marathon full course, Art Museum to Manayunk '
              'and back',
        ),
        routeId: 'r1',
      ),
    ));
    await pumpUntil(
        tester, () => find.byType(MapDetailSkeleton).evaluate().isEmpty,
        describe: 'the route to load');
    await walkScrollable(tester, primaryScrollable(), 'Public route');
    await _drain(tester);
  }, layoutOnly: true);

  group('publicRouteStartTarget', () {
    test('starts against the clipped waypoints, not the source trace', () {
      final source = cm.Route(
        id: 'r1',
        userId: 'owner',
        name: 'River Loop',
        // The source route would carry the owner's full (unclipped) trace.
        waypoints: [
          cm.Waypoint(lat: 0, lng: 0),
          cm.Waypoint(lat: 0, lng: 0.001),
          cm.Waypoint(lat: 0, lng: 0.002),
          cm.Waypoint(lat: 0, lng: 0.003),
          cm.Waypoint(lat: 0, lng: 0.004),
        ],
        distanceMetres: 5000,
        elevationGainMetres: 40,
        isPublic: true,
      );
      // What the non-owner viewer is allowed to see (privacy-clipped).
      final clipped = [
        cm.Waypoint(lat: 0, lng: 0.001),
        cm.Waypoint(lat: 0, lng: 0.002),
        cm.Waypoint(lat: 0, lng: 0.003),
      ];
      final target = publicRouteStartTarget(source, clipped);
      expect(target.waypoints, clipped);
      expect(target.waypoints.length, 3);
      expect(target.id, 'r1');
      expect(target.name, 'River Loop');
      expect(target.distanceMetres, 5000);
      expect(target.isPublic, isTrue);
    });
  });

  group('PublicRouteScreen — initial render', () {
    testWidgets('renders the Route fallback title before the route loads',
        (tester) async {
      // Reason: until _route fills in, the title falls back to the
      // literal string "Route".
      await _pump(tester);
      expect(find.text('Route'), findsOneWidget);
    });

    testWidgets('first frame shows the full-body loader', (tester) async {
      await _pump(tester);
      expect(find.byType(MapDetailSkeleton), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pump(const Duration(milliseconds: 400));
    });
  });

  testWidgets('the elevation stat reads in the reader\'s unit',
      (tester) async {
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
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: PublicRouteScreen(api: _OwnerApi(), routeId: 'r1'),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('751'), findsOneWidget);
    expect(find.text('ft'), findsOneWidget);
    expect(find.text('229'), findsNothing);
    // Drain the screen's request timeouts.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
  });

  group('PublicRouteScreen — matches route detail', () {
    testWidgets('a long name is shown in full under the map, and the bar '
        'repeats it only once that heading scrolls away', (tester) async {
      const name = 'Philadelphia Marathon full course, Art Museum to '
          'Manayunk and back';
      await _pumpLoaded(tester, _OwnerApi(name: name),
          size: const Size(360, 780));
      // The bar named the page while it loaded; the heading's arrival hides
      // it on the next frame.
      await tester.pump();

      final inBody = find.descendant(
          of: find.byType(ListView), matching: find.text(name));
      final inBar =
          find.descendant(of: find.byType(AppBar), matching: find.text(name));
      expect(inBody, findsOneWidget);
      expect(tester.renderObject<RenderParagraph>(inBody).didExceedMaxLines,
          isFalse,
          reason: 'the body heading wraps rather than truncating');
      double barOpacity() => tester
          .widget<AnimatedOpacity>(find.ancestor(
              of: inBar, matching: find.byType(AnimatedOpacity)))
          .opacity;
      expect(barOpacity(), 0,
          reason: 'no second, truncated copy while the heading is on screen');

      // Scrolled directly: a drag over the map would pan the map instead.
      tester
          .state<ScrollableState>(find
              .descendant(
                  of: find.byType(ListView), matching: find.byType(Scrollable))
              .first)
          .position
          .jumpTo(700);
      await pumpUntil(tester, () => barOpacity() == 1,
          describe: 'the bar to name the route once its heading is gone');
      await _drain(tester);
    });

    testWidgets('a route with no line does not headline "0 Waypoints"',
        (tester) async {
      await _pumpLoaded(tester, _OwnerApi(waypoints: const []));
      expect(find.text('Distance'), findsOneWidget);
      expect(find.text('Waypoints'), findsNothing);
      await _drain(tester);
    });

    testWidgets('a route with a line counts its waypoints', (tester) async {
      await _pumpLoaded(tester, _OwnerApi());
      expect(find.text('Waypoints'), findsOneWidget);
      await _drain(tester);
    });

    testWidgets('Start run wears the theme\'s start colour, not success green',
        (tester) async {
      await _pumpLoaded(tester, _OwnerApi());
      final fab = tester.widget<FloatingActionButton>(
          find.widgetWithText(FloatingActionButton, 'Start run'));
      expect(fab.backgroundColor, isNull,
          reason: 'the FAB theme (Home\'s Start) supplies the colour');
      expect(fab.foregroundColor, isNull);
      await _drain(tester);
    });
  });
}

Future<void> _pumpLoaded(WidgetTester tester, _OwnerApi api,
    {Size size = const Size(800, 3000)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: PublicRouteScreen(api: api, routeId: 'r1'),
    ),
  );
  await pumpUntil(
      tester, () => find.byType(MapDetailSkeleton).evaluate().isEmpty,
      describe: 'the route to load');
}

// Drain the screen's request timeouts.
Future<void> _drain(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 30));
}

class _OwnerApi extends ApiClient {
  _OwnerApi({
    this.name = 'Hill Loop',
    this.waypoints = const [
      cm.Waypoint(lat: 0, lng: 0),
      cm.Waypoint(lat: 0, lng: 0.01),
    ],
  });

  final String name;
  final List<cm.Waypoint> waypoints;

  @override
  String? get userId => 'owner';

  @override
  Future<({cm.Route? route, String? ownerId})> fetchRouteById(
    String routeId,
  ) async =>
      (
        route: cm.Route(
          id: routeId,
          userId: 'owner',
          name: name,
          waypoints: waypoints,
          distanceMetres: 5000,
          elevationGainMetres: 229,
        ),
        ownerId: 'owner',
      );
}

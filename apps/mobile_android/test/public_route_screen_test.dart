import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' as cm;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/preferences.dart';
import '../lib/screens/public_route_screen.dart';
import '../lib/widgets/loading_skeletons.dart';

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
}

class _OwnerApi extends ApiClient {
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
          name: 'Hill Loop',
          waypoints: [
            cm.Waypoint(lat: 0, lng: 0),
            cm.Waypoint(lat: 0, lng: 0.01),
          ],
          distanceMetres: 5000,
          elevationGainMetres: 229,
        ),
        ownerId: 'owner',
      );
}

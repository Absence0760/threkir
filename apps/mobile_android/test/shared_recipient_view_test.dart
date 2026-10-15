import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' as cm;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/public_route_screen.dart';
import '../lib/screens/public_run_screen.dart';
import '../lib/widgets/live_run_map.dart';
import '../lib/widgets/shared_with_you_chip.dart';

/// The phone's recipient view of a run or route shared through an audience
/// (decisions § 1874): it opens through the shared view, shows the clipped
/// track only, offers no owner control, and with the server gate closed (the
/// shared view returns nothing) shows nothing new.

const _clipped = [
  cm.Waypoint(lat: 51.50, lng: -0.10),
  cm.Waypoint(lat: 51.51, lng: -0.11),
];

class _RunApi extends ApiClient {
  _RunApi({this.publicRun, this.sharedRun, this.viewer = 'viewer-1'});

  final cm.RunRow? publicRun;
  final cm.RunRow? sharedRun;
  final String? viewer;
  int sharedReads = 0;
  final List<String> rawTrackReads = [];
  final List<String> clippedTrackReads = [];

  @override
  String? get userId => viewer;

  @override
  Future<cm.RunRow?> fetchPublicRunById(String runId) async => publicRun;

  @override
  Future<cm.RunRow?> fetchSharedRunById(String runId) async {
    sharedReads++;
    return sharedRun;
  }

  @override
  Future<cm.UserProfileRow?> fetchPublicProfile(String userId) async =>
      cm.UserProfileRow(profilePrivate: false, id: userId, displayName: 'Owner', shadowHidden: false);

  @override
  Future<List<cm.Waypoint>> fetchTrackByPath(String path) async {
    rawTrackReads.add(path);
    return const [cm.Waypoint(lat: 0, lng: 0), cm.Waypoint(lat: 0, lng: 1)];
  }

  @override
  Future<List<cm.Waypoint>> fetchClippedTrackForRun(String runId) async {
    clippedTrackReads.add(runId);
    return _clipped;
  }

  @override
  Future<Map<String, ({int kudosCount, bool viewerHasKudos, int commentCount})>>
      fetchEngagementSummaries(List<String> runIds) async => {};

  @override
  Future<List<cm.RunCommentWithAuthor>> fetchRunCommentsWithAuthors(
    String runId, {
    int limit = 200,
  }) async =>
      const [];

  @override
  Future<cm.ProfileSummary?> fetchProfileSummary(String userId) async => null;

  @override
  Future<List<cm.RunPhotoRow>> fetchRunPhotos(
    String runId, {
    int limit = 50,
  }) async =>
      const [];

  @override
  Future<List<cm.GearRow>> fetchRunGear(String runId) async => const [];

  @override
  Future<List<cm.SegmentEffortWithSegment>> fetchEffortsForRunWithSegments(
    String runId,
  ) async =>
      const [];

  @override
  Future<List<cm.GlobalSegmentEffortWithSegment>> fetchGlobalEffortsForRun(
    String runId,
  ) async =>
      const [];
}

class _RouteApi extends ApiClient {
  _RouteApi({required this.route});

  final cm.Route? route;
  final List<String> clipReads = [];

  @override
  String? get userId => 'viewer-1';

  @override
  Future<({cm.Route? route, String? ownerId})> fetchRouteById(
    String routeId,
  ) async =>
      (route: route, ownerId: route?.userId);

  @override
  Future<List<cm.Waypoint>> clipRouteForViewer(String routeId) async {
    clipReads.add(routeId);
    return _clipped;
  }

  @override
  Future<bool> isRouteBookmarked(String routeId) async => false;

  @override
  Future<List<cm.SegmentRow>> fetchSegmentsForRoute(
    String routeId, {
    int limit = 100,
  }) async =>
      const [];

  @override
  Future<List<cm.RoutePhotoRow>> fetchRoutePhotos(
    String routeId, {
    int limit = 50,
  }) async =>
      const [];

  @override
  Future<List<cm.RouteConditionRow>> fetchRouteConditions(
          String routeId) async =>
      const [];
}

cm.RunRow _runRow({bool isPublic = false}) => cm.RunRow(safetyAudience: false, 
      id: 'run-1',
      userId: 'owner-1',
      startedAt: DateTime(2026, 10, 1, 7),
      durationS: 1800,
      distanceM: 5000,
      source: 'app',
      activityType: 'run',
      isDnf: false,
      isPublic: isPublic,
      followersOnly: false,
    );

cm.Route _route({bool isPublic = false, String? clubId}) => cm.Route(
      id: 'route-1',
      userId: 'owner-1',
      name: 'River loop',
      // What fetchRouteById hands a non-owner is already clipped; the screen
      // clips again and renders only what clip_route_for_viewer returned.
      waypoints: _clipped,
      distanceMetres: 8000,
      elevationGainMetres: 40,
      isPublic: isPublic,
      clubId: clubId,
    );

bool _supabaseReady = false;

Future<void> _ensureSupabase() async {
  if (_supabaseReady) return;
  TestWidgetsFlutterBinding.ensureInitialized();
  dotenv.loadFromString(isOptional: true);
  SharedPreferences.setMockInitialValues({});
  await Supabase.initialize(
    url: 'http://127.0.0.1:24321',
    anonKey: 'eyJ.local.test',
  );
  _supabaseReady = true;
}

Future<void> _pump(WidgetTester tester, Widget screen) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: screen,
    ),
  );
  // The fakes resolve in microtasks; timed pumps instead of pumpAndSettle,
  // which hangs on LiveRunMap's animations.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUpAll(_ensureSupabase);

  group('PublicRunScreen as a share recipient', () {
    testWidgets('opens a run shared with the viewer, clipped, marked shared',
        (tester) async {
      final api = _RunApi(sharedRun: _runRow());
      await _pump(tester, PublicRunScreen(api: api, runId: 'run-1'));

      expect(tester.takeException(), isNull);
      expect(api.sharedReads, 1);
      expect(find.byType(SharedWithYouChip), findsOneWidget);
      expect(find.text('Shared with you'), findsOneWidget);
      expect(api.clippedTrackReads, ['run-1']);
      expect(api.rawTrackReads, isEmpty,
          reason: 'a recipient must never read the raw track');
      final map = tester.widget<LiveRunMap>(find.byType(LiveRunMap));
      expect(map.track, _clipped);
    });

    testWidgets('offers no owner control on a shared run', (tester) async {
      final api = _RunApi(sharedRun: _runRow());
      await _pump(tester, PublicRunScreen(api: api, runId: 'run-1'));

      expect(find.text('Who can see this'), findsNothing);
      expect(find.text('Share link'), findsNothing);
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
      expect(find.byIcon(Icons.delete_outline), findsNothing);
      expect(find.byTooltip('Report run'), findsOneWidget);
    });

    testWidgets('a public run is not marked shared', (tester) async {
      final api = _RunApi(publicRun: _runRow(isPublic: true));
      await _pump(tester, PublicRunScreen(api: api, runId: 'run-1'));

      expect(api.sharedReads, 0);
      expect(find.byType(SharedWithYouChip), findsNothing);
    });

    testWidgets('with the gate closed nothing new appears', (tester) async {
      // The server's audience_sharing gate closed: shared_runs admits nobody.
      final api = _RunApi();
      await _pump(tester, PublicRunScreen(api: api, runId: 'run-1'));

      expect(find.byType(SharedWithYouChip), findsNothing);
      expect(find.byType(LiveRunMap), findsNothing);
      expect(api.clippedTrackReads, isEmpty);
      expect(api.rawTrackReads, isEmpty);
    });

    testWidgets('a signed-out viewer never asks for a shared run',
        (tester) async {
      final api = _RunApi(sharedRun: _runRow(), viewer: null);
      await _pump(tester, PublicRunScreen(api: api, runId: 'run-1'));

      expect(api.sharedReads, 0);
      expect(find.byType(SharedWithYouChip), findsNothing);
    });
  });

  group('PublicRouteScreen as a share recipient', () {
    testWidgets('opens a route shared with the viewer, clipped, marked shared',
        (tester) async {
      final api = _RouteApi(route: _route());
      await _pump(tester, PublicRouteScreen(api: api, routeId: 'route-1'));

      expect(tester.takeException(), isNull);
      expect(find.byType(SharedWithYouChip), findsOneWidget);
      expect(api.clipReads, ['route-1']);
      final map = tester.widget<LiveRunMap>(find.byType(LiveRunMap));
      expect(map.plannedRoute, _clipped);
    });

    testWidgets('offers no owner control on a shared route', (tester) async {
      final api = _RouteApi(route: _route());
      await _pump(tester, PublicRouteScreen(api: api, routeId: 'route-1'));

      expect(find.text('Who can see this'), findsNothing);
      expect(find.text('Share link'), findsNothing);
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
      expect(find.byIcon(Icons.delete_outline), findsNothing);
    });

    testWidgets('a public route is not marked shared', (tester) async {
      final api = _RouteApi(route: _route(isPublic: true));
      await _pump(tester, PublicRouteScreen(api: api, routeId: 'route-1'));

      expect(find.byType(SharedWithYouChip), findsNothing);
    });

    testWidgets('a club route read as a member is not marked shared',
        (tester) async {
      final api = _RouteApi(route: _route(clubId: 'club-1'));
      await _pump(tester, PublicRouteScreen(api: api, routeId: 'route-1'));

      expect(find.byType(SharedWithYouChip), findsNothing);
    });

    testWidgets('with the gate closed nothing new appears', (tester) async {
      final api = _RouteApi(route: null);
      await _pump(tester, PublicRouteScreen(api: api, routeId: 'route-1'));

      expect(find.byType(SharedWithYouChip), findsNothing);
      expect(find.byType(LiveRunMap), findsNothing);
      expect(api.clipReads, isEmpty);
    });
  });
}

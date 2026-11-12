import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' as cm;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_route_store.dart';
import '../lib/preferences.dart';
import '../lib/screens/route_detail_screen.dart';
import 'pump_until.dart';

cm.Route _route() => cm.Route(
  id: 'r1',
  userId: 'owner',
  name: 'Old import',
  waypoints: const [],
  distanceMetres: 5000,
  elevationGainMetres: 40,
  isPublic: true,
);

/// Serves a fixed delete impact and records delete calls. [impactThrows] and
/// [deleteError] drive the failure paths.
class _DeleteApi extends ApiClient {
  _DeleteApi({this.impactThrows = false, this.deleteError});

  final bool impactThrows;
  final Object? deleteError;
  int deleteCalls = 0;

  @override
  String? get userId => 'owner';

  @override
  Future<RouteDeleteImpact> fetchRouteDeleteImpact(String routeId) async {
    if (impactThrows) throw StateError('impact down');
    return const RouteDeleteImpact(
      raceListings: 1,
      savedByOthers: 2,
      photos: 3,
    );
  }

  @override
  Future<void> deleteRoute(String routeId) async {
    deleteCalls++;
    final e = deleteError;
    if (e != null) throw e;
  }

  @override
  Future<List<cm.RouteReviewRow>> getRouteReviews(String routeId) async => [];
}

final _navKey = GlobalKey<NavigatorState>();

Future<LocalRouteStore> _pump(WidgetTester tester, ApiClient api) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = Preferences();
  await prefs.init();
  final dir = (await tester.runAsync(
    () => Directory.systemTemp.createTemp('route_delete_test'),
  ))!;
  addTearDown(() => dir.deleteSync(recursive: true));
  final store = LocalRouteStore()..debugSeed([_route()], dir: dir);

  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: _navKey,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: Text('routes list')),
    ),
  );
  _navKey.currentState!.push(
    MaterialPageRoute<void>(
      builder: (_) => RouteDetailScreen(
        route: _route(),
        routeStore: store,
        preferences: prefs,
        apiClient: api,
        isOwner: true,
      ),
    ),
  );
  // Timed pumps — pumpAndSettle spins LiveRunMap's pulse animation.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  return store;
}

Future<void> _openDelete(WidgetTester tester) async {
  await tester.tap(find.byTooltip('More'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.tap(find.text('Delete route'));
  await tester.pump();
  await pumpUntil(
    tester,
    () => find.byType(AlertDialog).evaluate().isNotEmpty,
    describe: 'the delete confirm to open',
  );
}

Finder _inDialog(String text) => find.descendant(
  of: find.byType(AlertDialog),
  matching: find.textContaining(text),
);

void main() {
  setUpAll(() => dotenv.loadFromString(isOptional: true));

  group('routeDeleteConfirmLines', () {
    final l10n = lookupAppLocalizations(const Locale('en'));

    test('a private route nothing references says only that it is final', () {
      expect(
        routeDeleteConfirmLines(
          l10n,
          const RouteDeleteImpact(),
          isPublic: false,
        ),
        [l10n.routeDetailDeleteBody],
      );
    });

    test("other people's dependents come before the owner's own content", () {
      const all = RouteDeleteImpact(
        savedByOthers: 3,
        reviewsByOthers: 4,
        conditionsByOthers: 5,
        segmentsByOthers: 6,
        segmentEffortsByOthers: 7,
        shares: 8,
        raceListings: 1,
        events: 2,
        linkedRuns: 9,
        photos: 10,
        markers: 11,
      );
      expect(routeDeleteConfirmLines(l10n, all, isPublic: true), [
        l10n.routeDetailDeleteBody,
        l10n.routeDetailDeleteImpactPublic,
        l10n.routeDetailDeleteImpactRaceListings(1),
        l10n.routeDetailDeleteImpactEvents(2),
        l10n.routeDetailDeleteImpactSaved(3),
        l10n.routeDetailDeleteImpactShares(8),
        l10n.routeDetailDeleteImpactSegments(6),
        l10n.routeDetailDeleteImpactEfforts(7),
        l10n.routeDetailDeleteImpactReviews(4),
        l10n.routeDetailDeleteImpactConditions(5),
        l10n.routeDetailDeleteImpactRuns(9),
        l10n.routeDetailDeleteImpactPhotos(10),
        l10n.routeDetailDeleteImpactMarkers(11),
      ]);
    });

    test(
      'an unknown count says so instead of implying nothing depends on it',
      () {
        expect(routeDeleteConfirmLines(l10n, null, isPublic: false), [
          l10n.routeDetailDeleteBody,
          l10n.routeDetailDeleteImpactUnknown,
        ]);
      },
    );
  });

  group('route detail delete (issue #1286)', () {
    testWidgets(
      'the confirm names what depends on the route; cancel sends nothing',
      (tester) async {
        final api = _DeleteApi();
        await _pump(tester, api);
        await _openDelete(tester);

        expect(_inDialog('It is public'), findsOneWidget);
        expect(
          _inDialog('1 race listing uses it as its course'),
          findsOneWidget,
        );
        expect(_inDialog('2 other runners have saved it.'), findsOneWidget);
        expect(_inDialog('Its 3 photos will be deleted.'), findsOneWidget);

        await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(AlertDialog), findsNothing);
        expect(api.deleteCalls, 0);
      },
    );

    testWidgets('confirming deletes once, drops the local copy and goes back', (
      tester,
    ) async {
      final api = _DeleteApi();
      final store = await _pump(tester, api);
      await _openDelete(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pump();
      await pumpUntil(
        tester,
        () => !_navKey.currentState!.canPop(),
        describe: 'the screen to pop back to the list',
      );
      expect(api.deleteCalls, 1);
      expect(store.routes.where((r) => r.id == 'r1'), isEmpty);
    });

    testWidgets('a failed count still opens the confirm and says so', (
      tester,
    ) async {
      await _pump(tester, _DeleteApi(impactThrows: true));
      await _openDelete(tester);

      expect(
        _inDialog("We couldn't check what else uses this route."),
        findsOneWidget,
      );
      expect(_inDialog('other runners have saved it'), findsNothing);
    });

    testWidgets(
      'a refused delete says only the owner can, and keeps the route',
      (tester) async {
        final api = _DeleteApi(
          deleteError: const RouteDeleteRefusedException('r1'),
        );
        final store = await _pump(tester, api);
        await _openDelete(tester);

        await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
        await tester.pump();
        await pumpUntil(
          tester,
          () => find
              .text("Only the route's owner can delete it.")
              .evaluate()
              .isNotEmpty,
          describe: 'the refusal banner',
        );
        expect(api.deleteCalls, 1);
        expect(store.routes.where((r) => r.id == 'r1'), hasLength(1));
        expect(find.text('Old import'), findsWidgets);
        // showTopBanner parks a dismiss timer; let it run out.
        await tester.pump(const Duration(seconds: 10));
      },
    );
  });
}

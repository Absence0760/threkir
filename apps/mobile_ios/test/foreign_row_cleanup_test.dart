import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/foreign_row_cleanup.dart';
import '../lib/local_route_store.dart';
import '../lib/local_run_store.dart';
import '../lib/preferences.dart';
import '../lib/sync_service.dart';

const _me = 'me';
const _clubMate = 'club-mate';
const _athlete = 'athlete';

/// The server as the reconcile sees it: what the caller owns, what they
/// bookmarked, and who holds each row RLS lets them read.
class _ServerApi extends ApiClient {
  String? session = _me;
  Set<String> ownedRuns = {};
  Set<String> ownedRoutes = {};
  Set<String> savedRoutes = {};
  Map<String, String> runOwners = {};
  Map<String, String> routeOwners = {};
  bool failOwnedRead = false;
  int ownedReads = 0;
  final List<String> pushedRoutes = [];

  @override
  String? get userId => session;

  @override
  Future<Set<String>> fetchOwnedRunIds() async {
    ownedReads++;
    if (failOwnedRead) throw Exception('network down');
    return ownedRuns;
  }

  @override
  Future<Set<String>> fetchOwnedRouteIds() async {
    ownedReads++;
    if (failOwnedRead) throw Exception('network down');
    return ownedRoutes;
  }

  @override
  Future<Set<String>> fetchSavedRouteIds() async => savedRoutes;

  @override
  Future<Map<String, String>> fetchRunOwners(Iterable<String> ids) async => {
        for (final id in ids)
          if (runOwners.containsKey(id)) id: runOwners[id]!,
      };

  @override
  Future<Map<String, String>> fetchRouteOwners(Iterable<String> ids) async => {
        for (final id in ids)
          if (routeOwners.containsKey(id)) id: routeOwners[id]!,
      };

  @override
  Future<void> saveRoute(Route route) async {
    // The owner-only `routes` write policy.
    final owner = routeOwners[route.id];
    if (owner != null && owner != _me) {
      throw Exception('new row violates row-level security policy');
    }
    pushedRoutes.add(route.id);
  }
}

Run _run(String id) => Run(
      id: id,
      startedAt: DateTime.utc(2026, 4, 10, 8),
      duration: const Duration(minutes: 25),
      distanceMetres: 5000,
      track: const [],
      source: RunSource.app,
    );

Route _route(String id, {String userId = _me, bool starred = false}) => Route(
      id: id,
      userId: userId,
      name: 'Loop $id',
      waypoints: const [
        Waypoint(lat: 47.37, lng: 8.54),
        Waypoint(lat: 47.371, lng: 8.541),
      ],
      distanceMetres: 5000,
      isPublic: false,
      isStarred: starred,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('planForeignRows', () {
    test('keeps an owned row, synced or not', () {
      final plan = planForeignRows(
        userId: _me,
        syncedIds: {'a'},
        unsyncedIds: {'b'},
        ownedIds: {'a', 'b'},
        serverOwners: {'b': _me},
      );
      expect(plan.isEmpty, isTrue);
    });

    test('drops a synced row the owned set lacks', () {
      final plan = planForeignRows(
        userId: _me,
        syncedIds: {'mine', 'club'},
        unsyncedIds: const {},
        ownedIds: {'mine'},
      );
      expect(plan.drop, {'club'});
      expect(plan.unqueue, isEmpty);
    });

    test('keeps a synced foreign row the caller bookmarked or pinned', () {
      final plan = planForeignRows(
        userId: _me,
        syncedIds: {'bookmarked'},
        unsyncedIds: const {},
        ownedIds: const {},
        keepIds: {'bookmarked'},
      );
      expect(plan.isEmpty, isTrue);
    });

    test('never drops an unsynced row for being absent from the server', () {
      // A run recorded offline is absent from every server read; absence is
      // not evidence that it is someone else's.
      final plan = planForeignRows(
        userId: _me,
        syncedIds: const {},
        unsyncedIds: {'offline-run'},
        ownedIds: const {},
      );
      expect(plan.isEmpty, isTrue);
    });

    test('drops an unsynced row the server holds under another owner', () {
      final plan = planForeignRows(
        userId: _me,
        syncedIds: const {},
        unsyncedIds: {'starred-club-route'},
        ownedIds: const {},
        serverOwners: {'starred-club-route': _clubMate},
      );
      expect(plan.drop, {'starred-club-route'});
    });

    test('keeps a kept unsynced foreign row but drops its dead push', () {
      final plan = planForeignRows(
        userId: _me,
        syncedIds: const {},
        unsyncedIds: {'pinned'},
        ownedIds: const {},
        serverOwners: {'pinned': _clubMate},
        keepIds: {'pinned'},
      );
      expect(plan.drop, isEmpty);
      expect(plan.unqueue, {'pinned'});
    });

    test('a failed owned read plans nothing', () {
      final plan = planForeignRows(
        userId: _me,
        syncedIds: {'a', 'b'},
        unsyncedIds: {'c'},
        ownedIds: null,
        serverOwners: {'c': _clubMate},
      );
      expect(plan.isEmpty, isTrue);
    });

    test('no account plans nothing', () {
      final plan = planForeignRows(
        userId: '',
        syncedIds: {'a'},
        unsyncedIds: const {},
        ownedIds: const {},
      );
      expect(plan.isEmpty, isTrue);
    });
  });

  group('ForeignRowCleanup', () {
    late Directory runDir;
    late Directory routeDir;
    late LocalRunStore runs;
    late LocalRouteStore routes;
    late Preferences prefs;
    late _ServerApi api;

    setUp(() async {
      runDir = Directory.systemTemp.createTempSync('foreign_rows_runs_');
      routeDir = Directory.systemTemp.createTempSync('foreign_rows_routes_');
      SharedPreferences.setMockInitialValues({});
      prefs = Preferences();
      await prefs.init();
      api = _ServerApi();
      runs = LocalRunStore()..currentUserIdProvider = () => api.userId;
      await runs.init(overrideDirectory: runDir);
      routes = LocalRouteStore()..currentUserIdProvider = () => api.userId;
      await routes.init(overrideDirectory: routeDir);
    });

    tearDown(() {
      for (final d in [runDir, routeDir]) {
        if (d.existsSync()) d.deleteSync(recursive: true);
      }
    });

    ForeignRowCleanup cleanup() =>
        ForeignRowCleanup(preferences: prefs, runStore: runs, routeStore: routes);

    Future<void> seedPreFixDevice() async {
      // What an older build's readers left behind: owned and foreign rows
      // pulled side by side, all marked synced.
      await runs.saveManyFromRemote([_run('my-run'), _run('athlete-run')]);
      await runs.save(_run('offline-run'));
      await routes.saveBatch([
        _route('my-route'),
        _route('club-route', userId: _clubMate),
        _route('pinned-club-route', userId: _clubMate),
        _route('bookmarked-route', userId: _clubMate),
      ]);
      await routes.pinOffline('pinned-club-route');
      await routes.save(_route('built-offline'));
      api
        ..ownedRuns = {'my-run'}
        ..runOwners = {'my-run': _me, 'athlete-run': _athlete}
        ..ownedRoutes = {'my-route'}
        ..savedRoutes = {'bookmarked-route'}
        ..routeOwners = {
          'my-route': _me,
          'club-route': _clubMate,
          'pinned-club-route': _clubMate,
          'bookmarked-route': _clubMate,
        };
    }

    test('drops foreign synced rows and keeps owned, kept and unsynced ones',
        () async {
      await seedPreFixDevice();

      expect(await cleanup().runOnce(api), isTrue);

      expect(runs.summaries.map((s) => s.id).toSet(),
          {'my-run', 'offline-run'});
      expect(runs.unsyncedRuns.map((r) => r.id), ['offline-run']);
      expect(routes.routes.map((r) => r.id).toSet(), {
        'my-route',
        'pinned-club-route',
        'bookmarked-route',
        'built-offline',
      });
      expect(routes.unsyncedRoutes.map((r) => r.id), ['built-offline']);
      expect(prefs.foreignRowCleanupDone(_me), isTrue);

      // The deletes are durable, not just in memory.
      final reloaded = LocalRouteStore();
      await reloaded.init(overrideDirectory: routeDir);
      expect(reloaded.routes.map((r) => r.id), isNot(contains('club-route')));
    });

    test('a starred club route stops being pushed on every sync', () async {
      await routes.saveBatch([_route('club-route', userId: _clubMate)]);
      // Starring it queued a push the owner-only write policy refuses.
      await routes.save(_route('club-route', userId: _clubMate, starred: true));
      api.routeOwners = {'club-route': _clubMate};
      final sync = SyncService(
        apiClient: api,
        runStore: runs,
        routeStore: routes,
        foreignRowCleanup: cleanup(),
      );

      await sync.debugTrySync('manual');

      expect(routes.routes, isEmpty);
      expect(api.pushedRoutes, isEmpty);
      expect(sync.debugBackoffState().failures, 0,
          reason: 'the refused push used to fail every cycle');
    });

    test('a failed read deletes nothing and is not marked done', () async {
      await seedPreFixDevice();
      api.failOwnedRead = true;

      expect(await cleanup().runOnce(api), isFalse);

      expect(runs.summaries, hasLength(3));
      expect(routes.routes, hasLength(5));
      expect(prefs.foreignRowCleanupDone(_me), isFalse);
    });

    test('a failure retries on the next launch, not on every sync', () async {
      await seedPreFixDevice();
      api.failOwnedRead = true;
      final thisLaunch = cleanup();
      await thisLaunch.runOnce(api);
      final readsAfterFirst = api.ownedReads;

      expect(await thisLaunch.runOnce(api), isFalse);
      expect(api.ownedReads, readsAfterFirst);

      api.failOwnedRead = false;
      expect(await cleanup().runOnce(api), isTrue);
      expect(routes.routes.map((r) => r.id), isNot(contains('club-route')));
    });

    test('the marker stops a second run for the same account', () async {
      await seedPreFixDevice();
      await cleanup().runOnce(api);
      final reads = api.ownedReads;
      // A club route that arrives after the reconcile is not its business.
      await routes.saveBatch([_route('late-club-route', userId: _clubMate)]);

      expect(await cleanup().runOnce(api), isTrue);

      expect(api.ownedReads, reads);
      expect(routes.routes.map((r) => r.id), contains('late-club-route'));
    });

    test('the marker is per account', () async {
      await prefs.markForeignRowCleanupDone('someone-else');
      expect(prefs.foreignRowCleanupDone(_me), isFalse);
      await cleanup().runOnce(api);
      expect(prefs.foreignRowCleanupDone(_me), isTrue);
    });

    test('signed out, it reads nothing and marks nothing', () async {
      await seedPreFixDevice();
      api.session = null;

      expect(await cleanup().runOnce(api), isFalse);

      expect(api.ownedReads, 0);
      expect(prefs.foreignRowCleanupDone(_me), isFalse);
      // Signed out, the stores hide the account's tagged rows; sign back in
      // to see that none of them went.
      api.session = _me;
      expect(runs.summaries, hasLength(3));
      expect(routes.routes, hasLength(5));
    });
  });
}

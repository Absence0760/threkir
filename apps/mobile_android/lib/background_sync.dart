import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:workmanager/workmanager.dart';

import 'foreign_row_cleanup.dart';
import 'local_route_store.dart';
import 'local_run_store.dart';
import 'preferences.dart';
import 'sync_service.dart'
    show
        drainPendingDeletes,
        drainPendingRouteDeletes,
        drainUnsyncedRoutes,
        filterRunsForCurrentUser;

const backgroundSyncTaskName = 'com.threkir.backgroundSync';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      await dotenv.load(fileName: '.env.development');

      final supabaseUrl = dotenv.env['SUPABASE_URL'];
      final anonKey = dotenv.env['SUPABASE_ANON_KEY'];
      if (supabaseUrl == null ||
          supabaseUrl.isEmpty ||
          anonKey == null ||
          anonKey.isEmpty) {
        return true;
      }

      await ApiClient.initialize(url: supabaseUrl, anonKey: anonKey);
      final api = ApiClient();
      if (api.userId == null) return true;

      final store = LocalRunStore();
      await store.init();
      final routeStore = LocalRouteStore();
      await routeStore.init();
      final prefs = Preferences();
      await prefs.init();
      await runBackgroundSyncCycle(
        api,
        store,
        routeStore,
        foreignRowCleanup: ForeignRowCleanup(
          preferences: prefs,
          runStore: store,
          routeStore: routeStore,
        ),
      );
    } catch (e) {
      debugPrint('Background sync error: $e');
    }
    return true;
  });
}

/// Drain the local queues to the cloud from the WorkManager callback:
/// unsynced runs, pending remote-deletes, unsynced routes, and pending
/// route remote-deletes — the same four queues the foreground
/// [SyncService] drains every cycle. Extracted from [callbackDispatcher]
/// so it can be unit-tested without the WorkManager + dotenv + Supabase
/// bootstrap.
///
/// The delete + route drains reuse the shared [drainPendingDeletes] /
/// [drainUnsyncedRoutes] / [drainPendingRouteDeletes] free functions so
/// the background path can't drift from the foreground one. Each queue
/// is wrapped in its own try/catch (layered resilience) so a failure
/// draining one queue doesn't abort the others.
///
/// **Always** routes the run queue through [filterRunsForCurrentUser]
/// so the background path honours the same owner-tag guard the
/// foreground [SyncService] does. Without this, on a shared device,
/// User A's unsynced runs would get pushed under User B's account the
/// next time WorkManager fires while B is signed in — every row would
/// land under the wrong user and RLS would silently accept them (the
/// row embeds the caller's `user_id`, not the run's tagged owner).
///
/// [foreignRowCleanup] runs first, as it does at the head of a foreground
/// cycle: until it has, a club route or athlete run an older build stored as
/// owned is pushed here and refused on every wake (decisions § 1929).
Future<void> runBackgroundSyncCycle(
  ApiClient api,
  LocalRunStore store,
  LocalRouteStore routeStore, {
  ForeignRowCleanup? foreignRowCleanup,
}) async {
  if (foreignRowCleanup != null) {
    try {
      await foreignRowCleanup.runOnce(api);
    } catch (e) {
      debugPrint('Background sync foreign-row reconcile failed: $e');
    }
  }
  final allUnsynced = store.unsyncedRuns;
  final unsyncedForOwner = filterRunsForCurrentUser(allUnsynced, api.userId);
  final skippedForeignOwner = allUnsynced.length - unsyncedForOwner.length;
  if (skippedForeignOwner > 0) {
    debugPrint(
      'Background sync: skipping $skippedForeignOwner runs owned by a '
      'different user (signed in as ${api.userId})',
    );
  }
  // Never push a run that's queued for deletion, even if it was never
  // synced — otherwise the push recreates the row the user just asked
  // to delete before the drain below removes it. See issue #675.
  final pendingDeleteIds = store.pendingRemoteDeletesForUser(api.userId);
  final unsynced = unsyncedForOwner
      .where((r) => !pendingDeleteIds.contains(r.id))
      .toList();
  if (unsynced.isNotEmpty) {
    try {
      final outcome = await api.saveRunsBatch(unsynced);
      // Park before marking: a run left in neither set drains again next cycle,
      // which is the right default, but a blocked one re-sends bytes the bucket
      // has already refused (decisions § 1070).
      if (outcome.blocked.isNotEmpty) await store.markBlocked(outcome.blocked);
      final failed = outcome.failedIds;
      await store.markManySynced(
        unsynced.where((r) => !failed.contains(r.id)),
      );
      debugPrint(
        'Background sync: pushed ${unsynced.length - failed.length} '
        '(${outcome.retryable.length} deferred, '
        '${outcome.blocked.length} parked)',
      );
    } catch (e) {
      debugPrint('Background sync batch failed: $e');
    }
  }
  try {
    await drainPendingDeletes(api, store);
  } catch (e) {
    debugPrint('Background sync delete drain failed: $e');
  }
  try {
    await drainUnsyncedRoutes(api, routeStore);
  } catch (e) {
    debugPrint('Background sync route drain failed: $e');
  }
  try {
    await drainPendingRouteDeletes(api, routeStore);
  } catch (e) {
    debugPrint('Background sync route delete drain failed: $e');
  }
}

/// Arm the background drain. Neither platform promises the task ever runs —
/// the foreground [SyncService] stays the primary drain and this is purely
/// opportunistic.
///
/// iOS and Android take different task types because iOS gates each type on
/// a matching `UIBackgroundModes` entry. A BGAppRefreshTask (what
/// `registerPeriodicTask` submits on iOS) needs the `fetch` capability and
/// gets ~30 s; draining a weekend of unsynced runs means uploading several
/// gzipped GPS tracks, which overruns that and ignores the network
/// constraint BGAppRefreshTaskRequest has no field for. A BGProcessingTask
/// gets minutes, honours [Constraints.networkType] via
/// `requiresNetworkConnectivity`, and runs while the device is idle — which
/// is what a fully deferrable queue drain wants. It is also the capability
/// the app already declares, so this needs no extra `UIBackgroundModes`
/// entry. iOS delivers it at most once per submission, so it is re-armed on
/// each launch; Android's periodic job re-fires on its own.
void registerBackgroundSync() {
  Workmanager().initialize(callbackDispatcher);
  final registered = Platform.isIOS
      ? Workmanager().registerProcessingTask(
          backgroundSyncTaskName,
          backgroundSyncTaskName,
          constraints: Constraints(networkType: NetworkType.connected),
        )
      : Workmanager().registerPeriodicTask(
          backgroundSyncTaskName,
          backgroundSyncTaskName,
          constraints: Constraints(networkType: NetworkType.connected),
          frequency: const Duration(hours: 1),
          existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
        );
  registered.catchError((Object e) {
    debugPrint('Background sync registration failed: $e');
  });
}

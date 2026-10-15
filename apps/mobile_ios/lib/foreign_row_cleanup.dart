import 'package:api_client/api_client.dart';
import 'package:flutter/foundation.dart';

import 'local_route_store.dart';
import 'local_run_store.dart';
import 'preferences.dart';

/// What the foreign-row reconcile does to one local store.
@immutable
class ForeignRowPlan {
  const ForeignRowPlan({
    this.drop = const <String>{},
    this.unqueue = const <String>{},
  });

  /// Rows to delete from the device.
  final Set<String> drop;

  /// Rows to keep whose pending push is dropped: the server holds them under
  /// another owner, so the push is refused on every sync, but the caller has
  /// a reason of their own to keep the copy (a bookmark, an offline pin).
  final Set<String> unqueue;

  bool get isEmpty => drop.isEmpty && unqueue.isEmpty;
}

/// Which local rows are someone else's, decided from what the server says the
/// caller owns (decisions § 1929).
///
/// Before § 1928 mobile `getRoutes` / `getRuns` leaned on RLS alone, so a club
/// member's device stored other members' club routes and a coach's device
/// stored athletes' runs, both stamped with the active account's owner tag.
/// Nothing on the row tells them apart locally, so the server decides:
///
/// * A **synced** row is dropped when [ownedIds] lacks it and [keepIds] (the
///   caller's bookmarks and offline pins) does too. A synced row has reached
///   the server, so if it were the caller's the owned walk would hold it.
/// * An **unsynced** row is never dropped for being absent — absent is exactly
///   what a run recorded offline looks like. It goes only on positive
///   evidence: [serverOwners] names a different owner for it. Then its push
///   can never land; the row is dropped, or kept with the push dropped when
///   [keepIds] holds it.
/// * A null [ownedIds] is a read that did not complete, and plans nothing:
///   with no owned set every synced row would read as foreign.
ForeignRowPlan planForeignRows({
  required String userId,
  required Set<String> syncedIds,
  required Set<String> unsyncedIds,
  required Set<String>? ownedIds,
  Map<String, String> serverOwners = const <String, String>{},
  Set<String> keepIds = const <String>{},
}) {
  if (userId.isEmpty || ownedIds == null) return const ForeignRowPlan();
  final drop = <String>{};
  final unqueue = <String>{};
  for (final id in syncedIds) {
    if (ownedIds.contains(id) || keepIds.contains(id)) continue;
    drop.add(id);
  }
  for (final id in unsyncedIds) {
    if (ownedIds.contains(id)) continue;
    final owner = serverOwners[id];
    if (owner == null || owner == userId) continue;
    (keepIds.contains(id) ? unqueue : drop).add(id);
  }
  return ForeignRowPlan(drop: drop, unqueue: unqueue);
}

/// Runs [planForeignRows] against the device's run and route stores once per
/// signed-in account, then records that it did.
///
/// An auxiliary effect of the sync cycle: every failure is caught and logged
/// here, nothing is marked done until both stores reconciled, and a failed
/// attempt is retried on the next launch rather than on every sync trigger.
class ForeignRowCleanup {
  ForeignRowCleanup({
    required this.preferences,
    required this.runStore,
    this.routeStore,
  });

  final Preferences preferences;
  final LocalRunStore runStore;
  final LocalRouteStore? routeStore;

  final Set<String> _attempted = <String>{};

  /// True once the reconcile has completed for the signed-in account, now or
  /// on an earlier launch. Every reconcile and marker failure is caught here;
  /// only reading the marker from an uninitialised [preferences] throws.
  Future<bool> runOnce(ApiClient api) async {
    final userId = api.userId;
    if (userId == null || userId.isEmpty) return false;
    if (preferences.foreignRowCleanupDone(userId)) return true;
    if (!_attempted.add(userId)) return false;

    var ok = true;
    try {
      await _reconcileRuns(api, userId);
    } catch (e) {
      ok = false;
      debugPrint('ForeignRowCleanup: run store reconcile failed: $e');
    }
    final routes = routeStore;
    if (routes != null) {
      try {
        await _reconcileRoutes(api, routes, userId);
      } catch (e) {
        ok = false;
        debugPrint('ForeignRowCleanup: route store reconcile failed: $e');
      }
    }
    if (!ok) return false;
    try {
      await preferences.markForeignRowCleanupDone(userId);
    } catch (e) {
      debugPrint('ForeignRowCleanup: marker write failed: $e');
      return false;
    }
    return true;
  }

  // The sync state is snapshotted BEFORE the owned walk: a row synced by then
  // is on the server for the whole walk, so an owned one is in the set. A row
  // that syncs during the walk is not a candidate at all.
  Future<void> _reconcileRuns(ApiClient api, String userId) async {
    final synced = <String>{};
    final unsynced = <String>{};
    for (final s in runStore.summaries) {
      (runStore.isSynced(s.id) ? synced : unsynced).add(s.id);
    }
    if (synced.isEmpty && unsynced.isEmpty) return;
    final owned = await api.fetchOwnedRunIds();
    final owners = unsynced.isEmpty
        ? const <String, String>{}
        : await api.fetchRunOwners(unsynced);
    _requireSameSession(api, userId);
    final plan = planForeignRows(
      userId: userId,
      syncedIds: synced,
      unsyncedIds: unsynced,
      ownedIds: owned,
      serverOwners: owners,
    );
    // A row whose sync state moved since the snapshot is left for the owner
    // to deal with: a synced row edited meanwhile is now unsynced work.
    final drop = {
      for (final id in plan.drop)
        if (runStore.isSynced(id) == synced.contains(id)) id,
    };
    if (drop.isEmpty) return;
    debugPrint('ForeignRowCleanup: dropping ${drop.length} foreign runs');
    await runStore.deleteMany(drop);
  }

  Future<void> _reconcileRoutes(
    ApiClient api,
    LocalRouteStore routes,
    String userId,
  ) async {
    final synced = <String>{};
    final unsynced = <String>{};
    for (final r in routes.routes) {
      (routes.isSynced(r.id) ? synced : unsynced).add(r.id);
    }
    if (synced.isEmpty && unsynced.isEmpty) return;
    final owned = await api.fetchOwnedRouteIds();
    final saved = await api.fetchSavedRouteIds();
    final owners = unsynced.isEmpty
        ? const <String, String>{}
        : await api.fetchRouteOwners(unsynced);
    _requireSameSession(api, userId);
    final plan = planForeignRows(
      userId: userId,
      syncedIds: synced,
      unsyncedIds: unsynced,
      ownedIds: owned,
      serverOwners: owners,
      keepIds: {...saved, ...routes.offlinePinnedIds},
    );
    final drop = {
      for (final id in plan.drop)
        if (routes.isSynced(id) == synced.contains(id) &&
            !routes.isOfflinePinned(id))
          id,
    };
    if (drop.isNotEmpty) {
      debugPrint('ForeignRowCleanup: dropping ${drop.length} foreign routes');
      await routes.deleteMany(drop);
    }
    if (plan.unqueue.isNotEmpty) {
      await routes.markManyRoutesSynced(plan.unqueue);
    }
  }

  static void _requireSameSession(ApiClient api, String userId) {
    if (api.userId != userId) {
      throw StateError('the session changed during the reconcile');
    }
  }
}

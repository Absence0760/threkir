import 'dart:async';
import 'dart:convert';

import 'package:core_models/core_models.dart' show Route, Waypoint;
import 'package:flutter/foundation.dart'
    show
        TargetPlatform,
        VoidCallback,
        debugPrint,
        defaultTargetPlatform,
        visibleForTesting;
import 'package:flutter/services.dart';

import 'local_route_store.dart';
import 'watch_route_visibility.dart';
import 'route_simplify.dart' show simplifyToBudget;

/// Positions one Apple Watch route push may carry. Must match
/// `ArmedRoute.maxPoints` in `apps/watch_ios/WatchApp/ArmedRoute.swift` and
/// `WatchIngestBridge.maxRoutePoints` in
/// `apps/mobile_ios/ios/Runner/WatchIngestBridge.swift`, both of which drop
/// an over-cap payload whole.
///
/// 512 positions is ~8 KB of coordinate data, comfortably inside the
/// `WCSession` user-info ceiling, and keeps the watch's per-fix projection
/// (linear in the point count, run once per GPS sample) negligible. It is
/// deliberately looser than the custom watch's 256-point `CRS1` cap, which is
/// a flash-capacity limit this device does not have.
const int kMaxAppleWatchRoutePoints = 512;

/// Routes one starred-list push may offer the watch picker. Must match
/// `SavedRoutes.maxRoutes` in `apps/watch_ios/WatchApp/ArmedRoute.swift` and
/// `WatchIngestBridge.maxSavedRoutes`; `scripts/check_shared_constants.mjs`
/// reads all three, so lifting the cap is one deliberate change on three
/// rails rather than three doc comments claiming each other's number
/// (decisions.md § 787).
///
/// Twelve routes of 128 positions is ~29 KB against `WCSession`'s
/// 65,536-byte user-info ceiling, and it is as far as a runner will usefully
/// thumb on a 1.9-inch screen. Both figures are computed, not measured.
const int kMaxAppleWatchSavedRoutes = 12;

/// Positions one route in that LIST may carry — a quarter of
/// [kMaxAppleWatchRoutePoints], because twelve of them ride in one payload
/// where an armed route rides alone. Must match
/// `SavedRoutes.maxPointsPerRoute` on the watch and
/// `WatchIngestBridge.maxSavedRoutePoints` on the phone.
///
/// A denser route is thinned to fit by the same priority Douglas-Peucker pass
/// the single push uses, so it keeps its shape and both its endpoints. At 128
/// positions a 10 km route holds a vertex every ~78 m, which leaves the
/// watch's 40 m off-route threshold alone: `RouteNavigator` projects
/// perpendicular to a segment rather than snapping to a vertex.
const int kMaxAppleWatchSavedRoutePoints = 128;

/// Why a saved route cannot be sent to the Apple Watch.
enum AppleWatchRouteRefusal {
  /// Fewer than two positions — there is no line to follow, and both the
  /// phone bridge and the watch decoder refuse such a payload.
  tooFewPoints,
}

/// A route shaped for the Apple Watch push: the positions the payload will
/// carry, how many the route started with, or the reason it cannot be sent.
///
/// [points] and [refusal] are exclusive. A caller that gets [points] has a
/// route to push; a caller that gets a [refusal] has something to tell the
/// runner, never a silently shortened route.
class AppleWatchRouteResult {
  final List<Waypoint>? points;

  /// Positions on the route before any thinning — the denominator behind
  /// "thinned N of M points to fit".
  final int sourcePointCount;
  final AppleWatchRouteRefusal? refusal;

  const AppleWatchRouteResult({
    required this.points,
    required this.sourcePointCount,
  }) : refusal = null;

  const AppleWatchRouteResult.refused(this.refusal, this.sourcePointCount)
      : points = null;

  bool get simplified => points != null && points!.length < sourcePointCount;
}

/// Shape a saved route's polyline into the positions an Apple Watch push
/// carries.
///
/// A denser route is thinned by priority Douglas–Peucker (`simplifyToBudget`),
/// never cut at the cap: a polyline that stopped at position 512 would hand
/// the watch a line ending mid-route, and `RouteNavigator` would then report
/// the runner off route against geometry the route does not have and announce
/// the finish early. Both endpoints survive the thinning by construction.
AppleWatchRouteResult appleWatchRouteFromWaypoints(List<Waypoint> waypoints) {
  if (waypoints.length < 2) {
    return AppleWatchRouteResult.refused(
      AppleWatchRouteRefusal.tooFewPoints,
      waypoints.length,
    );
  }
  return AppleWatchRouteResult(
    points: simplifyToBudget(waypoints, maxPoints: kMaxAppleWatchRoutePoints),
    sourcePointCount: waypoints.length,
  );
}

/// Pushes a route to the paired Apple Watch so its `RouteNavigator` has a line
/// to follow during a wrist-recorded run.
///
/// The native half is `WatchIngestBridge.swift` in `apps/mobile_ios/ios/Runner`
/// (the same class that ingests finished watch runs — `WCSession.delegate` is
/// a single slot), which hands the payload to
/// `WCSession.transferUserInfo(_:)`. Queued rather than immediate: the runner
/// picks a route long before the watch app is on screen.
///
/// iOS-only, so both entry points fall closed on any other target platform
/// (decisions §39 — one Dart codebase, platform dispatch inside it). The
/// dispatch reads `defaultTargetPlatform` rather than `Platform.isIOS` so
/// host-run widget tests can drive the iOS branch, matching `apple_auth.dart`.
class AppleWatchRouteBridge {
  /// One instance per process. `attach` is reached from two sites in
  /// `main.dart` — startup and the sign-out nudge — and a second instance
  /// would add a second `LocalRouteStore` listener rather than replace the
  /// first, pushing the same list twice for the life of the app.
  factory AppleWatchRouteBridge() => _instance;

  AppleWatchRouteBridge._();

  static final AppleWatchRouteBridge _instance = AppleWatchRouteBridge._();

  static const _channel = MethodChannel('run_app/watch_route');

  @visibleForTesting
  static const String channelName = 'run_app/watch_route';

  /// Whether a paired watch with the app installed is currently reachable
  /// enough to accept a queued push. False on any non-iOS platform and
  /// whenever the native side isn't registered, so a caller can hide the
  /// affordance rather than offer a button that can only fail.
  static Future<bool> isAvailable() async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return false;
    try {
      return await _channel.invokeMethod<bool>('available') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Queue [points] as the watch's armed route. Throws
  /// [PlatformException] when the payload is rejected or no watch can take
  /// it — the caller surfaces that to the runner rather than reporting a
  /// push that never happened.
  static Future<void> push({
    required String id,
    required String name,
    required double distanceMetres,
    required List<Waypoint> points,
  }) async {
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      throw PlatformException(
        code: 'watch_unavailable',
        message: 'Apple Watch push is iOS-only',
      );
    }
    await _channel.invokeMethod<void>('push', {
      'route_id': id,
      'route_name': name,
      'route_distance_m': distanceMetres,
      'route_lat': [for (final p in points) p.lat],
      'route_lng': [for (final p in points) p.lng],
    });
  }

  // ---- The wrist's route picker (phone -> watch) -------------------------

  /// Shape the starred subset of [routes] into the list the watch picker
  /// offers.
  ///
  /// Each element is byte-for-byte the five-key dictionary a single [push]
  /// carries, so the watch validates it with `ArmedRoute.decode` and arming
  /// one from the wrist is a store write rather than a second decode with a
  /// second set of rules.
  ///
  /// Fail-closed per element: a route the watch could not follow — no id, a
  /// distance that is not a number, fewer than two positions, a coordinate
  /// off the globe — is dropped rather than offered, because arming it would
  /// fail at the start of the run instead, after the runner chose it. The
  /// rest of the list stands: unlike the single push there is no partly
  /// decoded polyline to leave behind, since each element is whole or absent
  /// on its own.
  ///
  /// Ordering is [LocalRouteStore.routes]' own, which is newest-first by
  /// insertion, so the cap keeps the most recently touched routes — the same
  /// intent as Wear OS's `order=updated_at.desc` picker query.
  @visibleForTesting
  static List<Map<String, Object>> encodeSavedRoutesForWatch(
    List<Route> routes,
  ) {
    final out = <Map<String, Object>>[];
    for (final r in routes) {
      if (out.length == kMaxAppleWatchSavedRoutes) break;
      if (!r.isStarred || r.id.isEmpty) continue;
      if (!r.distanceMetres.isFinite || r.distanceMetres < 0) continue;
      if (r.waypoints.length < 2) continue;
      // Before the thinning, not after: Douglas-Peucker can drop the one
      // point that was not a coordinate and hand back a polyline whose shape
      // was computed from it, and `jsonEncode` refuses a non-finite double
      // outright, which would take the diff cache down with it.
      if (r.waypoints.any((p) =>
          !p.lat.isFinite ||
          !p.lng.isFinite ||
          p.lat < -90 ||
          p.lat > 90 ||
          p.lng < -180 ||
          p.lng > 180)) {
        continue;
      }
      final points = simplifyToBudget(
        r.waypoints,
        maxPoints: kMaxAppleWatchSavedRoutePoints,
      );
      out.add({
        'route_id': r.id,
        'route_name': r.name,
        'route_distance_m': r.distanceMetres,
        'route_lat': [for (final p in points) p.lat],
        'route_lng': [for (final p in points) p.lng],
      });
    }
    return out;
  }

  /// Queue [savedRoutes] as the watch picker's list, built by
  /// [encodeSavedRoutesForWatch].
  ///
  /// Never throws, unlike [push]: nobody asked for this and nobody is
  /// waiting on it, so a failure must not reach the route edit that
  /// triggered it. Returns whether the payload reached the native side, so
  /// the caller's diff cache only remembers a push that actually shipped and
  /// the next store change tries again.
  ///
  /// An EMPTY list is a value, not a no-op: it is what a runner unstarring
  /// their last route produces, and it must empty the picker.
  static Future<bool> pushSavedRoutes(
    List<Map<String, Object>> savedRoutes,
  ) async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return false;
    try {
      await _channel.invokeMethod<void>('push_saved', {
        'saved_routes': savedRoutes,
      });
      return true;
    } on MissingPluginException catch (e) {
      debugPrint('Apple Watch saved-route push has no native side: $e');
      return false;
    } on PlatformException catch (e) {
      debugPrint('Apple Watch saved-route push refused: $e');
      return false;
    }
  }

  /// How long the bridge waits after a [LocalRouteStore] notification before
  /// it pushes, so starring ten routes in a row is one push rather than ten.
  /// 250 ms matches `WearRoutesBridge.kPushDebounceWindow` — the same store
  /// fires both. Set to zero for tests that need immediate-fire semantics.
  @visibleForTesting
  static Duration kPushDebounceWindow = const Duration(milliseconds: 250);

  LocalRouteStore? _store;
  VoidCallback? _listener;
  Timer? _pendingPush;

  /// The last payload the channel actually shipped, so an edit that changes
  /// nothing the watch can see — a tag, a description, `is_public` — costs no
  /// transfer. `LocalRouteStore.save` notifies on every route mutation, and
  /// `transferUserInfo` is a DURABLE queue: a redundant push is not a wasted
  /// packet but a wasted slot in a queue the system drains at its own pace.
  String? _lastPushedSavedRoutes;

  /// Subscribe to [store] and keep the wrist's picker in step with it.
  ///
  /// Idempotent — a second attach replaces the prior subscription rather than
  /// leaking it — and a no-op off iOS, where there is no watch to tell and
  /// every notification would encode a list nobody reads.
  ///
  /// The first push fires immediately so a freshly-attached bridge states the
  /// current set; later ones go through [kPushDebounceWindow].
  void attach(LocalRouteStore store) {
    detach();
    if (defaultTargetPlatform != TargetPlatform.iOS) return;
    _store = store;
    _listener = () => _scheduleDebouncedPush(store);
    store.addListener(_listener!);
    _pushStore(store);
  }

  void detach() {
    final store = _store;
    final listener = _listener;
    if (store != null && listener != null) store.removeListener(listener);
    _store = null;
    _listener = null;
    _pendingPush?.cancel();
    _pendingPush = null;
    // Dropped so a re-attach always states the list once: nothing here knows
    // whether the watch is still in step across a detach.
    _lastPushedSavedRoutes = null;
  }

  void _scheduleDebouncedPush(LocalRouteStore store) {
    _pendingPush?.cancel();
    if (kPushDebounceWindow == Duration.zero) {
      _pushStore(store);
      return;
    }
    _pendingPush = Timer(kPushDebounceWindow, () {
      _pendingPush = null;
      _pushStore(store);
    });
  }

  Future<void> _pushStore(LocalRouteStore store) async {
    final payload = encodeSavedRoutesForWatch(
      routesVisibleToWatch(store.routes, store.currentUserIdProvider),
    );
    final encoded = jsonEncode(payload);
    if (encoded == _lastPushedSavedRoutes) return;
    if (await pushSavedRoutes(payload)) _lastPushedSavedRoutes = encoded;
  }
}

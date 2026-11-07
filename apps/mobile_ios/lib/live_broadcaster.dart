import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:flutter/foundation.dart';

import 'live_hub_client.dart';
import 'privacy.dart';

/// Pushes live spectator pings while a recording is in progress.
/// Throttled to one push every [_pingInterval], swallows network /
/// auth errors via `debugPrint` so the recorder's L0/L1 stays
/// untouched (see `docs/architecture/conventions.md § Layered resilience`).
///
/// Activated by the run screen when the user taps "Share live link";
/// inactive otherwise so a private run doesn't write to the
/// spectator table at all. The throttle window is intentionally
/// looser than the recorder's GPS cadence (1 s) — the spectator UI
/// is a glanceable surface, not a bit-for-bit replay.
///
/// Transport:
/// - When [hubClient] is non-null and [LiveHubClient.isConfigured]
///   is true (deploy sets `LIVE_HUB_URL` in `dotenv.env`), pings
///   POST to the Go live hub via the hub client. The hub fans out
///   to subscribed spectators in real-time and stores the last
///   known position for late joiners. No Postgres / Realtime
///   involved.
/// - Otherwise the broadcaster falls back to the legacy path —
///   `ApiClient.insertLivePing` writes a row to `live_run_pings`
///   and Supabase Realtime fans out to the web spectator page.
///
/// The fallback keeps the feature usable on every build pre-deploy
/// and during a Fly.io outage. See `docs/product/followups.md § #13` for
/// the migration plan.
///
/// Privacy-zone enforcement (decisions §33). The Supabase path is
/// protected server-side by the BEFORE INSERT trigger
/// `live_run_pings_drop_in_zone` (migration 20260618_001). The Go hub
/// path bypasses Postgres entirely — it POSTs straight to the hub
/// service which fans out via WebSocket to anonymous spectators with
/// no server-side privacy check. To close that leak, [pushPing]
/// evaluates [privacyZonesProvider] on every call and silently drops
/// any ping whose coordinates fall inside one of the runner's
/// configured privacy zones. The drop happens BEFORE the throttle
/// window updates so a subsequent out-of-zone ping fires on time
/// instead of waiting out the full interval. Even on the Supabase
/// path, client-side dropping cuts wire traffic — every fix sent
/// just to be silently dropped server-side was wasted bandwidth.
class LiveBroadcaster {
  LiveBroadcaster(
    this._api, {
    this.hubClient,
    this.privacyZonesProvider,
    DateTime Function() now = DateTime.now,
  }) : _now = now;

  final DateTime Function() _now;

  final ApiClient _api;
  final LiveHubClient? hubClient;

  /// Source of the runner's privacy zones, re-evaluated on every
  /// [pushPing] so a mid-run settings change takes effect immediately.
  /// When null or returns an empty list, no client-side clipping
  /// happens — the Supabase trigger is the server-side fallback for
  /// that transport, but the Go hub has no equivalent, so production
  /// callers should always wire a non-null provider.
  final List<PrivacyZone> Function()? privacyZonesProvider;

  String? _runId;
  bool _active = false;
  DateTime _lastPingAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime? _attachedAt;
  DateTime? _lastSuccessAt;
  bool _noPingWarned = false;

  static const Duration _pingInterval = Duration(seconds: 5);

  /// How long after [attach] a share may go without one accepted ping
  /// before the runner is told (issue #1300 BUG-007). Six publish
  /// intervals: long enough that a slow first fix is not news, short
  /// enough that the runner hears it while still at the start.
  static const Duration noPingWarnAfter = Duration(seconds: 30);

  bool get isActive => _active;
  String? get runId => _runId;

  /// When a transport last accepted a ping for the current share, or null
  /// while none has.
  DateTime? get lastSuccessAt => _lastSuccessAt;

  /// True exactly once per [attach]: the first call made [noPingWarnAfter]
  /// or more after it while no ping has been accepted. Every failure on the
  /// wire is swallowed (L4), so without this the runner had no way to learn
  /// that spectators were looking at nothing.
  bool takeNoPingWarning() {
    final at = _attachedAt;
    if (!_active || at == null || _lastSuccessAt != null || _noPingWarned) {
      return false;
    }
    if (_now().difference(at) < noPingWarnAfter) return false;
    _noPingWarned = true;
    return true;
  }

  /// Mark the broadcaster as live for [runId]. Caller must have
  /// already pre-created the parent `runs` row via
  /// [ApiClient.beginLiveBroadcast] — this method does not retry
  /// the stub creation.
  void attach(String runId) {
    _runId = runId;
    _active = true;
    _lastPingAt = DateTime.fromMillisecondsSinceEpoch(0);
    _attachedAt = _now();
    _lastSuccessAt = null;
    _noPingWarned = false;
  }

  /// Stop publishing. The run screen calls this after the final
  /// save + concludeLiveBroadcast on stop. After detach, [pushPing] is a
  /// no-op even if a stale snapshot arrives mid-tear-down.
  void detach() {
    _runId = null;
    _active = false;
  }

  /// Fire one ping. Called from the recorder's per-snapshot handler
  /// so it must be cheap on the no-op path: when inactive, when no
  /// GPS fix has landed yet, or when the throttle window hasn't
  /// elapsed since the last successful insert.
  ///
  /// [weakGps] marks a fix the recorder kept for distance but not for its
  /// line; spectators draw it as an approximate position (decisions
  /// § 2357).
  Future<void> pushPing({
    required double lat,
    required double lng,
    double? distanceM,
    int? elapsedS,
    int? bpm,
    double? ele,
    bool weakGps = false,
  }) async {
    final id = _runId;
    if (!_active || id == null) return;
    final now = _now();
    if (now.difference(_lastPingAt) < _pingInterval) return;
    // Privacy-zone drop BEFORE updating _lastPingAt so dropped pings
    // don't burn the throttle window — when the runner leaves the zone
    // the very next out-of-zone fix should fire immediately, not wait
    // out the full 5 s. The Supabase trigger (decisions §33) is the
    // server-side fallback on the legacy transport; the Go hub has no
    // equivalent so this client-side gate is the only enforcement when
    // hubClient is wired.
    final zones = privacyZonesProvider?.call() ?? const <PrivacyZone>[];
    if (zones.isNotEmpty && isInAnyZone(lat, lng, zones)) {
      return;
    }
    _lastPingAt = now;
    final hub = hubClient;
    try {
      if (hub != null && hub.isConfigured) {
        // Forward the recorder's Supabase session JWT so the Go
        // authorizer's owner-on-push check passes. Token may be
        // null on a degraded session — the L4 swallow below
        // absorbs the resulting 403. /audit/livehub May 2026 C1.
        final status = await hub.pushPing(
          runId: id,
          lat: lat,
          lng: lng,
          accessToken: _api.currentAccessToken,
          distanceM: distanceM,
          elapsedS: elapsedS,
          bpm: bpm,
          ele: ele,
          weakGps: weakGps,
        );
        // The fetcher returns the status rather than throwing, so a 403 or
        // a 5xx read as delivered and the share looked healthy.
        if (status < 200 || status >= 300) {
          throw StateError('live hub answered $status');
        }
      } else {
        await _api.insertLivePing(
          runId: id,
          lat: lat,
          lng: lng,
          distanceM: distanceM,
          elapsedS: elapsedS,
          bpm: bpm,
          ele: ele,
          weakGps: weakGps,
        );
      }
      if (_runId == id) _lastSuccessAt = _now();
    } catch (e) {
      debugPrint('[LiveBroadcaster.pushPing] $e');
    }
  }
}

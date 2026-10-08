import 'dart:async';
import 'dart:collection';
import 'dart:math';

// `hide ActivityType`: geolocator's `ActivityType` is iOS's LOCATION activity
// type (`AppleSettings.activityType`), a different vocabulary from the
// `runs.activity_type` enum core_models now carries (decisions § 1013). This
// file means Apple's. Nothing here needs ours, so hiding it is narrower than
// prefixing the whole domain import.
import 'package:core_models/core_models.dart' hide ActivityType;
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';

import 'gps_distance_estimator.dart';
import 'run_snapshot.dart';

/// Thrown by [RunRecorder.prepare] when device location services are turned
/// off (system-level, distinct from app permission). The user must enable
/// them in Settings before a run can start.
class LocationServiceDisabledError extends Error {
  @override
  String toString() => 'Location services are disabled on this device';
}

/// Thrown by [RunRecorder.prepare] when the user denied the location
/// permission prompt (or has previously set it to deniedForever).
class LocationPermissionDeniedError extends Error {
  final bool forever;
  LocationPermissionDeniedError({this.forever = false});
  @override
  String toString() => forever
      ? 'Location permission is permanently denied'
      : 'Location permission was denied';
}

/// A single lap split marked mid-run. Captures the cumulative distance and
/// duration at the moment the user tapped the lap button. Cumulative values
/// are convenient for the recorder loop (no previous-lap bookkeeping); the
/// canonical wire shape (per-lap deltas) is computed at serialisation time
/// by [lapsToCanonicalJson].
class LapSplit {
  final int number;
  final DateTime timestamp;
  final double cumulativeDistanceMetres;
  final Duration cumulativeDuration;

  const LapSplit({
    required this.number,
    required this.timestamp,
    required this.cumulativeDistanceMetres,
    required this.cumulativeDuration,
  });
}

/// Serialise a list of in-memory [LapSplit]s into the canonical JSON shape
/// documented in `docs/backend/metadata.md` § laps:
/// `[{ index: int, start_offset_s: int, distance_m: double, duration_s: int }]`.
///
/// `start_offset_s` is the cumulative duration **up to the start of this
/// lap** (i.e. the previous lap's cumulative duration, 0 for the first
/// lap). `distance_m` and `duration_s` are this lap's deltas, not the
/// cumulative totals — pure per-lap values, matching the Wear OS sender
/// at `apps/watch_wear/.../RunViewModel.kt`. Negative deltas (which can
/// only result from a clock skew between laps) are clamped to 0.
List<Map<String, dynamic>> lapsToCanonicalJson(List<LapSplit> laps) {
  final out = <Map<String, dynamic>>[];
  var prevDist = 0.0;
  var prevDuration = Duration.zero;
  for (final lap in laps) {
    final distM =
        (lap.cumulativeDistanceMetres - prevDist).clamp(0.0, double.infinity);
    final durDelta = lap.cumulativeDuration - prevDuration;
    final durS =
        durDelta.inSeconds < 0 ? 0 : durDelta.inSeconds;
    out.add(<String, dynamic>{
      'index': lap.number,
      'start_offset_s': prevDuration.inSeconds,
      'distance_m': distM,
      'duration_s': durS,
    });
    prevDist = lap.cumulativeDistanceMetres;
    prevDuration = lap.cumulativeDuration;
  }
  return out;
}

/// Inverse of [lapsToCanonicalJson]: reconstruct in-memory cumulative
/// [LapSplit]s from the canonical per-lap-delta JSON persisted in
/// `metadata.laps`. Used by the resume path so a process-killed run keeps its
/// mid-run lap / aid-station marks — numbering and cumulative totals continue
/// unbroken when the recorder is re-hydrated. Timestamps aren't part of the
/// canonical shape (only `start_offset_s` / `distance_m` / `duration_s`), so
/// each split's timestamp is reconstructed as [startedAt] + its cumulative
/// duration; it isn't re-serialised ([lapsToCanonicalJson] ignores timestamp).
List<LapSplit> lapsFromCanonicalJson(List<dynamic> json, {DateTime? startedAt}) {
  final anchor = startedAt ?? DateTime.now();
  final out = <LapSplit>[];
  var cumDist = 0.0;
  var cumDur = Duration.zero;
  for (final entry in json) {
    if (entry is! Map) continue;
    final distM = (entry['distance_m'] as num?)?.toDouble() ?? 0.0;
    final durS = (entry['duration_s'] as num?)?.toInt() ?? 0;
    final index = (entry['index'] as num?)?.toInt() ?? (out.length + 1);
    cumDist += distM;
    cumDur += Duration(seconds: durS);
    out.add(LapSplit(
      number: index,
      timestamp: anchor.add(cumDur),
      cumulativeDistanceMetres: cumDist,
      cumulativeDuration: cumDur,
    ));
  }
  return out;
}

/// Manages a live GPS recording session: opens the position stream, filters
/// noise, accumulates distance, and emits [RunSnapshot]s to the UI. Survives
/// a missing/revoked GPS signal — [prepare] flips [prepared] even when the
/// stream can't open, and a retry loop reopens the stream when services
/// come back.
class RunRecorder {
  /// [clock] exists so tests can drive the monotonic gap the re-anchor escape
  /// in [_onPosition] gates on without waiting out real seconds. Production
  /// always takes the default.
  RunRecorder({Stopwatch? clock}) : _stopwatch = clock ?? Stopwatch();

  static const _uuid = Uuid();

  /// `metadata.distance_estimator` on a GPS-distance run.
  static const distanceEstimatorVersion = 'kalman_v1';

  /// How often [prepare] retries opening the position stream when it is
  /// currently absent (services/permission denied at start, or the stream
  /// errored mid-run). Short enough that re-enabling Location in Settings
  /// feels immediate; long enough to avoid thrash.
  static const _gpsRetryInterval = Duration(seconds: 3);

  final _controller = StreamController<RunSnapshot>.broadcast();
  // Set by [dispose] and never cleared. The GPS retry callback awaits its
  // service/permission precheck, so one already in flight when the recorder is
  // disposed resumes afterwards and would re-open the position stream — a
  // subscription nothing is left to cancel, holding the GPS radio and the
  // foreground service for the life of the process while every fix raises on
  // the closed snapshot sink.
  bool _disposed = false;
  StreamSubscription<Position>? _positionSub;
  Timer? _timer;
  Timer? _gpsRetryTimer;
  final List<LapSplit> _laps = [];

  /// All lap splits recorded so far.
  List<LapSplit> get laps => List.unmodifiable(_laps);

  DateTime? _startTime;
  /// Elapsed time already accumulated by a PRIOR session that this recorder
  /// resumed (see [resumeSession]). Added to the live [_stopwatch] everywhere elapsed
  /// is reported so a process-killed-then-resumed run reports continuous total
  /// elapsed instead of restarting from zero. Zero for a normal fresh run. Only
  /// the time the recorder was actually running is counted — the (unknown-
  /// length) dead-process gap is deliberately not added, keeping the monotonic-
  /// clock honesty the [_stopwatch] design buys.
  Duration _elapsedOffset = Duration.zero;
  /// Monotonic clock for elapsed time. Unlike `DateTime.now()`, [Stopwatch]
  /// is unaffected by wall-clock jumps (NTP sync, manual time change,
  /// timezone change) — the run duration stays correct.
  final Stopwatch _stopwatch;

  /// The headline GPS distance (spec v1.1, `docs/features/gps_distance.md`).
  /// One estimator per un-paused stretch: [resume] folds the finished one into
  /// [_distanceOffsetMetres] and starts another, so a paused span is never
  /// integrated. A resumed session seeds the offset with the prior distance.
  GpsDistanceEstimator _estimator = GpsDistanceEstimator();
  double _distanceOffsetMetres = 0;
  double _stepFilledOffsetMetres = 0;
  double? _priorStrideM;
  // The estimator's clock (see [_estimatorFixTime]).
  double? _estFixT;
  Duration? _estFixMono;
  DateTime? _estFixGps;
  double? _estStepT;

  double get _distanceMetres => _distanceOffsetMetres + _estimator.distanceM;
  final List<Waypoint> _track = [];
  // Single read-only view handed out on every snapshot. `UnmodifiableListView`
  // wraps `_track` by reference — appending to `_track` is still visible
  // through the view, and there's no new wrapper allocated per emission
  // (which used to fire 1×/second minimum + once per GPS fix).
  late final UnmodifiableListView<Waypoint> _trackView =
      UnmodifiableListView(_track);
  // Lowest `_track` index [_calculatePace] may walk back to. Bumped to the
  // current track length on every resume so the rolling-pace window never
  // straddles a pause (or a dead-process gap), whose wall-clock duration would
  // otherwise be charged to the post-resume distance.
  int _paceFloorIdx = 0;
  /// Latest raw GPS fix — drives the blue dot on the live map and updates
  /// on every fix, independent of the track-append threshold.
  Waypoint? _currentWaypoint;
  /// Wall-clock time [_currentWaypoint] was accepted from the sensor. The
  /// 1-second timer re-emits the same fix forever, so this — not the
  /// snapshot's arrival — is the only honest measure of GPS liveness.
  DateTime? _currentWaypointAt;
  /// Last position that was appended to [_track]. Used to gate the next
  /// track append + distance accumulation on real movement.
  Position? _lastTrackedPosition;

  /// Cache for route-relative calculations in [_emitSnapshot]. When the
  /// 1-second elapsed-time timer fires without a new GPS fix, the
  /// `_currentWaypoint` reference is identical to the last one the route
  /// math ran against — reuse the previous off-route / remaining values
  /// instead of re-walking every segment of the loaded route.
  Waypoint? _lastRouteCalcFor;
  double? _cachedOffRoute;
  double? _cachedRouteRemaining;
  double? _cachedRouteAlong;
  // Where on the route the runner was last matched, metres from its start, and
  // the GPS distance recorded at that moment. [_routeProgress] only searches
  // the stretch of route reachable from here (see [_routeMatchLookaheadM]): on
  // a loop the finish is as near as the start, an out-and-back's return leg
  // lies on its outbound one, and a figure-eight crosses itself, so a search
  // over the whole line latched the wrong lap or leg — a loop read "0.00 km to
  // go" at the start and, never searching backwards again, measured off-route
  // against the closing leg alone for the rest of the run.
  double? _matchedAlongM;
  double _distanceAtLastMatch = 0;
  // Whether [_currentWaypoint] is a fix the L1 distance chain accepted into
  // the track. A fix rejected as an implausible teleport still refreshes the
  // blue dot, but must never drive route progress: the matcher anchors its
  // next search on [_matchedAlongM], so one corrupt fix would drag the search
  // window kilometres ahead, inflating off-route distance (up to a false
  // safety escalation) and understating distance remaining.
  bool _currentWaypointTrusted = true;
  DateTime? _lastTrackedPositionAt;
  /// [_stopwatch] reading when [_lastTrackedPosition] was last set. Always
  /// written and cleared together with it — the tracking block treats a
  /// half-set anchor as no anchor at all, so a divergence re-anchors rather
  /// than freezing.
  Duration? _lastTrackedElapsed;
  bool _recording = false;
  bool _paused = false;
  Route? _route;
  // Cumulative route length at each waypoint, precomputed once when the route
  // is set: `_routeCumulativeM[k]` is the distance from the start to waypoint
  // k. The matcher reads segment spans from it instead of re-summing haversine
  // lengths on every GPS fix — O(R²) over a multi-hour run on a 2000-waypoint
  // route.
  List<double>? _routeCumulativeM;
  double _trackThresholdMetres = 3;
  double _maxSpeedMps = 10;
  double _accuracyGateMetres = 20;
  // A hop that fails the <100 m one-hop cap but spans at least this many
  // seconds is treated as a real GPS gap (fixes dropped under cover / in a
  // tunnel / while backgrounded, or a batch), not a corrupt teleport: the
  // anchor is rebased to the new fix without crediting the un-sampled gap
  // distance. ~10 s matches the "GPS lost" mental model and is long enough
  // that a 1 Hz corrupt outlier (dt≈1 s) still fails closed. See #330.
  static const double _gpsReanchorAfterSeconds = 10;
  // Point-onto-segment projections [_reseedRouteFloor] may spend replaying a
  // resumed track. A few milliseconds' worth — the resume path runs on the UI
  // isolate, ahead of the first post-resume fix.
  static const int _resumeFloorProjectionBudget = 200000;

  // Route matcher tuning — the values web `route_geometry.ts` uses.
  static const double _metresPerDegree = 111320.0;
  static const double _routeMatchLookaheadM = 200;
  static const double _routeMatchBacktrackM = 50;
  // The off-route alert threshold: a windowed match further off the line than
  // this sends the matcher looking further along the route.
  static const double _routeMatchReacquireM = 40;
  static const double _alongFwdBiasPerM = 0.05;
  static const double _alongBackBiasPerM = 0.5;
  static const double _maxAlongBiasM = 20;
  static const double _alongContinuityPerM = 1e-6;
  // Rate-limits the "fix dropped for accuracy" log. An always-bad stream
  // would otherwise spam at ~1 Hz for the entire run.
  DateTime? _lastAccuracyDropLogAt;
  // True while the latest fix was rejected by the accuracy gate, so distance
  // has stalled. Surfaced on every snapshot as [RunSnapshot.weakGps] so the
  // run screen can show a "distance paused" banner instead of looking frozen.
  // Set on a dropped fix, cleared the moment a fix passes the gate.
  bool _weakGps = false;
  // Remembered so the retry loop can re-open the position stream with the
  // same accuracy setting the caller passed to [prepare].
  LocationAccuracy _locationAccuracy = LocationAccuracy.high;

  /// Latest heart-rate sample, in BPM. Stamped onto each new [Waypoint]
  /// when constructed so the saved track carries per-point BPM and the
  /// run-detail HR-zone breakdown lights up for phone-recorded runs.
  ///
  /// Push via [setHeartRate] from whatever HR source the caller wires up
  /// (`BleHeartRate` for the chest strap on mobile, or any other plugin
  /// that yields BPM samples). Leave at `null` while no strap is paired
  /// — Waypoints constructed without a sample carry `bpm: null`, which
  /// matches the pre-strap behaviour.
  int? _currentBpm;

  /// Treadmill (FTMS) distance source — an ADDITIVE, OPT-IN alternate to the
  /// GPS L1 distance path. Off by default: every field here stays untouched
  /// during a normal GPS run, and nothing in this block can run unless the
  /// caller explicitly pushes a sample via [setTreadmillSample]. When active,
  /// [_emitSnapshot] + [stop] report [_treadmillDistanceMetres] in place of
  /// the GPS-accumulated [_distanceMetres]; the GPS `_onPosition` path is
  /// never altered (any incidental fix still builds the track, it just stops
  /// driving the headline distance). This is the same shape as [setHeartRate]
  /// — an external sample fed in from a platform plugin the package doesn't
  /// depend on.
  bool _treadmillMode = false;
  double _treadmillDistanceMetres = 0;
  double? _treadmillBaselineMetres;
  // Last cumulative belt total seen. A total BELOW this one is the console
  // having restarted its own session and zeroed the counter; the baseline
  // alone can't detect that (it is usually 0, so nothing is ever below it).
  double? _treadmillLastTotalMetres;
  double _treadmillLastSpeedMps = 0;
  DateTime? _treadmillLastSampleAt;
  // Armed by [pause] so a cumulative-distance belt advance during the pause is
  // frozen out: a sample landing DURING the pause disarms it (the _paused
  // branch rebases the baseline), otherwise the first post-resume sample
  // re-anchors. See [pause] / [resume] / [setTreadmillSample].
  bool _treadmillNeedsRebaseline = false;

  /// Plausibility ceiling for a treadmill belt speed (m/s) ≈ 43 km/h —
  /// faster than any human belt speed, so a reading at/above it is a sensor
  /// glitch. Used BOTH to gate distance accumulation AND to gate carrying
  /// the speed forward as the next interval's integrand; the two MUST agree
  /// or a rejected reading still poisons the next interval (phantom distance).
  static const double _maxTreadmillSpeedMps = 12;

  /// Whether the recorder is currently sourcing distance from a treadmill
  /// rather than GPS.
  bool get treadmillMode => _treadmillMode;

  /// Emits a [RunSnapshot] on every GPS fix once [prepare] has run, and once
  /// per second after [begin] starts recording time.
  Stream<RunSnapshot> get snapshots => _controller.stream;

  /// Whether [prepare] has completed. True even when GPS is unavailable —
  /// the recorder accepts [begin] and emits time-only snapshots until a
  /// fix arrives (or the retry loop re-opens the stream).
  bool get prepared => _prepared;
  bool _prepared = false;

  /// Whether this run records under a permission that only covers the
  /// foreground. True on Android when the grant is "While using the app":
  /// fixes flow normally while the run screen is up, but Android can stop
  /// delivering them once another app takes focus, so distance freezes the
  /// instant the runner opens the camera or locks the screen. Uninterrupted
  /// background recording needs "Allow all the time"
  /// (`ACCESS_BACKGROUND_LOCATION`).
  ///
  /// A limitation, not a failure — the recorder still opens the stream and
  /// records. Callers disclose it; they must NOT treat it as a reason to
  /// skip GPS, which is what left a "while in use" runner staring at an
  /// empty map for the whole run. Always false on iOS, where "While Using
  /// the App" plus the `UIBackgroundModes:location` capability keeps
  /// CoreLocation feeding fixes for the whole session. Resolved by
  /// [prepare]; a mid-run upgrade to "Allow all the time" is picked up by
  /// the next [prepare], not here.
  bool get backgroundLocationLimited => _backgroundLocationLimited;
  bool _backgroundLocationLimited = false;

  /// Whether [begin] has been called and time/distance are accumulating.
  bool get recording => _recording;

  /// Prepare the recorder for a run. Resets state, flips [prepared] to true,
  /// starts the self-healing GPS retry loop, and — if services + permission
  /// are available — opens the position stream so fixes can drive the live
  /// map during the countdown before [begin] is called.
  ///
  /// Call [begin] when the countdown ends to flip on recording. Because
  /// [prepared] flips before the GPS checks, [begin] is usable even for
  /// indoor / treadmill runs where GPS is unavailable at the start.
  ///
  /// [distanceFilterMetres] and [minMovementMetres] are combined into a single
  /// software threshold that gates when a GPS fix gets appended to the track.
  /// It does not gate distance: every fix that clears the accuracy gate feeds
  /// the [GpsDistanceEstimator]. The OS-level filter is always 0 so the blue
  /// dot can update at the GPS sensor's native rate, independent of this
  /// threshold.
  ///
  /// Throws [LocationServiceDisabledError] if device location services are
  /// off. Throws [LocationPermissionDeniedError] if the user denies (or has
  /// permanently denied — see [LocationPermissionDeniedError.forever]) the
  /// permission prompt. Both errors leave [prepared] == true; the recorder is
  /// still usable as a time-only session and the retry loop will re-open the
  /// stream automatically when services / permission come back.
  ///
  /// A foreground-only ("While using the app") grant on Android is NOT an
  /// error — it records fine while the app is on screen, and only background
  /// delivery is at risk. It sets [backgroundLocationLimited] so the caller
  /// can disclose the limitation.
  Future<void> prepare({
    Route? route,
    int distanceFilterMetres = 3,
    double minMovementMetres = 2,
    double maxSpeedMps = 10,
    LocationAccuracy accuracy = LocationAccuracy.high,
    double accuracyGateMetres = 20,
  }) async {
    if (_disposed) {
      throw StateError('RunRecorder.prepare() called after dispose()');
    }
    // Reset state first and flip _prepared = true unconditionally. If GPS
    // setup below throws, the recorder is still usable for a time-only
    // (indoor / treadmill) run — begin() will start the stopwatch, the
    // 1-second timer emits snapshots with a null currentPosition, and the
    // live map falls back to its "Waiting for GPS..." placeholder. If GPS
    // later becomes available the caller can call prepare() again.
    _startTime = null;
    _elapsedOffset = Duration.zero;
    _stopwatch
      ..stop()
      ..reset();
    _track.clear();
    _laps.clear();
    _currentWaypoint = null;
    _currentWaypointAt = null;
    _lastTrackedPosition = null;
    _lastTrackedPositionAt = null;
    _lastTrackedElapsed = null;
    _lastRouteCalcFor = null;
    _cachedOffRoute = null;
    _cachedRouteRemaining = null;
    _cachedRouteAlong = null;
    _matchedAlongM = null;
    _distanceAtLastMatch = 0;
    _currentWaypointTrusted = true;
    _paceFloorIdx = 0;
    _recording = false;
    _paused = false;
    _route = route;
    _routeCumulativeM = _computeRouteCumulative(route);
    _trackThresholdMetres =
        max(distanceFilterMetres.toDouble(), minMovementMetres);
    _maxSpeedMps = maxSpeedMps;
    _resetDistance(0);
    _accuracyGateMetres = accuracyGateMetres;
    _locationAccuracy = accuracy;
    _lastAccuracyDropLogAt = null;
    _backgroundLocationLimited = false;
    _resetTreadmill();
    _prepared = true;

    // Start the self-healing retry loop regardless of whether GPS is
    // available right now. If the user has Location off at the start of
    // the run and flips it on later, or if Android tears the stream down
    // mid-run, the loop re-subscribes within a few seconds.
    _startGpsRetryLoop();

    // Device-level location services must be on before we even try to get a
    // permission or open a position stream — otherwise getPositionStream
    // silently produces nothing and the run never receives a fix.
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw LocationServiceDisabledError();
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (!_permissionAllowsStream(permission)) {
      throw LocationPermissionDeniedError(
        forever: permission == LocationPermission.deniedForever,
      );
    }
    _backgroundLocationLimited = _foregroundOnlyGrant(permission);

    _openPositionStream();
  }

  /// Whether [permission] covers the foreground but not reliably the
  /// background — Android's "While using the app". Drives
  /// [backgroundLocationLimited]. False on iOS: "While Using the App" plus
  /// the `UIBackgroundModes:location` capability is a supported
  /// background-recording configuration there.
  static bool _foregroundOnlyGrant(LocationPermission permission) =>
      defaultTargetPlatform == TargetPlatform.android &&
      permission == LocationPermission.whileInUse;

  /// Whether [permission] allows opening the live GPS position stream at
  /// all. Shared by [prepare]'s gate and [_startGpsRetryLoop]'s periodic
  /// precheck so the two conditions cannot drift apart (#671).
  ///
  /// False only for [LocationPermission.denied] /
  /// [LocationPermission.deniedForever]. A foreground-only grant DOES open
  /// the stream: refusing it recorded nothing at all — no fixes, an empty
  /// "Waiting for GPS" map, a run saved as indoor — to avoid a background
  /// freeze the runner might never have hit, and Android's first-run dialog
  /// cannot grant more than that anyway. It is disclosed through
  /// [backgroundLocationLimited] instead.
  static bool _permissionAllowsStream(LocationPermission permission) =>
      permission != LocationPermission.denied &&
      permission != LocationPermission.deniedForever;

  /// Subscribe to [Geolocator.getPositionStream] with the accuracy settings
  /// remembered from the last [prepare] call. Any stream error (commonly
  /// thrown when the user toggles Location off mid-run) cancels the
  /// subscription and clears [_positionSub] — the retry loop picks it back
  /// up once services are available again.
  void _openPositionStream() {
    if (_disposed) return;
    _positionSub?.cancel();
    _positionSub = Geolocator.getPositionStream(
      locationSettings: _platformLocationSettings(),
    ).listen(
      _onPosition,
      onError: (Object e, StackTrace st) {
        debugPrint('RunRecorder: position stream error — $e');
        _positionSub?.cancel();
        _positionSub = null;
      },
      cancelOnError: true,
    );
  }

  /// Build the per-platform [LocationSettings] for the live position stream.
  ///
  /// iOS gets [AppleSettings] with [ActivityType.fitness] +
  /// `pauseLocationUpdatesAutomatically: false`. CLLocationManager's default
  /// for that flag is `true`, which auto-pauses the GPS the moment iOS
  /// decides the user has stopped moving — including the 30-second pause
  /// taken to photograph something interesting mid-run. That produces the
  /// same silent freeze an Android `whileInUse` grant can produce — see
  /// [backgroundLocationLimited] — fixes stop, distance flat-lines, the
  /// foreground capability stays alive so no error surfaces, and the user
  /// only notices once they look at the finished run. Pinning the flag here
  /// keeps the iOS twin honest. `activityType: fitness` biases the
  /// CoreLocation power-saving heuristics for foot-paced motion.
  ///
  /// Android gets [AndroidSettings] with [ForegroundNotificationConfig] so
  /// the geolocator package can promote its service to a typed foreground
  /// service. `distanceFilter: 0` keeps every fix flowing so software
  /// filtering can drive the blue dot at sensor rate.
  LocationSettings _platformLocationSettings() {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return AppleSettings(
        accuracy: _locationAccuracy,
        activityType: ActivityType.fitness,
        distanceFilter: 0,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: false,
        allowBackgroundLocationUpdates: true,
      );
    }
    return AndroidSettings(
      accuracy: _locationAccuracy,
      // Receive every fix from the OS; movement filtering happens in
      // software so the blue dot can refresh without inflating the track.
      distanceFilter: 0,
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: 'Run in progress',
        notificationText: 'Recording your run',
        enableWakeLock: true,
        notificationIcon:
            AndroidResource(name: 'ic_launcher', defType: 'mipmap'),
      ),
    );
  }

  /// Periodically check whether GPS is available and (re-)open the
  /// position stream if it's currently down. Idempotent — a healthy
  /// stream is a no-op. Gates on [_permissionAllowsStream] — the SAME
  /// predicate [prepare] gates on — so a permission state [prepare] refuses
  /// to open a stream for can never be silently opened by this loop a few
  /// seconds later (#671). A permission granted mid-run (the runner denies
  /// the dialog, then relents from Settings) reopens the stream on the next
  /// tick, since [Geolocator.checkPermission] reflects the new grant.
  void _startGpsRetryLoop() {
    _gpsRetryTimer?.cancel();
    _gpsRetryTimer = Timer.periodic(_gpsRetryInterval, (_) async {
      if (!_prepared) return;
      if (_positionSub != null) return;
      try {
        if (!await Geolocator.isLocationServiceEnabled()) return;
        final p = await Geolocator.checkPermission();
        if (!_permissionAllowsStream(p)) return;
      } catch (e) {
        debugPrint('RunRecorder: GPS retry precheck failed — $e');
        return;
      }
      if (!_prepared || _positionSub != null) return;
      _openPositionStream();
    });
  }

  /// Flip the recorder into recording mode. Must be called after [prepare]
  /// has completed. Starts the elapsed-time clock, clears any track built
  /// before this point, and begins accumulating distance.
  void begin() {
    if (!_prepared) {
      throw StateError('RunRecorder.begin() called before prepare() completed');
    }
    _startTime = DateTime.now();
    _stopwatch
      ..reset()
      ..start();
    _resetDistance(0);
    _track.clear();
    _laps.clear();
    _lastTrackedPosition = null;
    _lastTrackedPositionAt = null;
    _lastTrackedElapsed = null;
    _paceFloorIdx = 0;
    _weakGps = false;
    _resetTreadmillAccumulators();
    _recording = true;
    _paused = false;

    // 1-second timer for elapsed time updates. Fires regardless of whether
    // we've received a GPS fix yet — during warmup or an indoor run the
    // stopwatch still ticks; snapshots just carry a null currentPosition
    // and the UI falls back to its "Waiting for GPS..." placeholder.
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_recording) return;
      _emitSnapshot();
    });
  }

  /// Convenience: [prepare] + [begin] in one call. Kept for callers that
  /// don't need the preload/countdown split.
  Future<void> start({
    Route? route,
    int distanceFilterMetres = 3,
    double minMovementMetres = 2,
    double maxSpeedMps = 10,
    LocationAccuracy accuracy = LocationAccuracy.high,
    double accuracyGateMetres = 20,
  }) async {
    await prepare(
      route: route,
      distanceFilterMetres: distanceFilterMetres,
      minMovementMetres: minMovementMetres,
      maxSpeedMps: maxSpeedMps,
      accuracy: accuracy,
      accuracyGateMetres: accuracyGateMetres,
    );
    begin();
  }

  /// Resume a persisted partial recording, continuing the SAME run rather than
  /// starting a new one. Re-hydrates the accumulated [track], [distanceMetres],
  /// prior [elapsed], original [startedAt], and mid-run [laps], opens the GPS
  /// stream (via [prepare]), then flips straight into recording mode — new
  /// fixes extend the existing track and add on to the existing distance /
  /// elapsed / lap sequence.
  ///
  /// This is the process-kill resume path: a multi-day effort whose OS process
  /// was reaped. Without it the only outcomes were finalizing the partial into
  /// a separate finished Run or discarding it — either way splitting one
  /// continuous effort into two disjoint records.
  ///
  /// Unlike [begin], this does NOT clear the seeded track / distance / laps.
  /// The last-tracked position is re-anchored to null so the first post-resume
  /// fix doesn't add a spurious distance delta across the unknown-length gap
  /// while the process was dead.
  ///
  /// GPS-setup errors from [prepare] are rethrown AFTER the state is seeded and
  /// recording has begun, so the caller can surface the "GPS unavailable"
  /// notice while the recorder still resumes as a time-only session (the retry
  /// loop reopens the stream when services return) — mirroring [begin]'s
  /// tolerance of a GPS-less start.
  ///
  /// Named `resumeSession` (not `resume`) to avoid colliding with [resume],
  /// which un-pauses an already-running recorder.
  Future<void> resumeSession({
    required List<Waypoint> track,
    required double distanceMetres,
    required Duration elapsed,
    required DateTime startedAt,
    List<LapSplit> laps = const [],
    Route? route,
    int distanceFilterMetres = 3,
    double minMovementMetres = 2,
    double maxSpeedMps = 10,
    LocationAccuracy accuracy = LocationAccuracy.high,
    double accuracyGateMetres = 20,
  }) async {
    Object? prepareError;
    try {
      await prepare(
        route: route,
        distanceFilterMetres: distanceFilterMetres,
        minMovementMetres: minMovementMetres,
        maxSpeedMps: maxSpeedMps,
        accuracy: accuracy,
        accuracyGateMetres: accuracyGateMetres,
      );
    } catch (e) {
      // prepare() reset state, flipped _prepared true, and started the retry
      // loop before throwing; seed + begin anyway, then rethrow so the caller
      // can disclose the GPS problem without losing the resumed session.
      prepareError = e;
    }
    _seedResumeState(
      track: track,
      distanceMetres: distanceMetres,
      elapsed: elapsed,
      startedAt: startedAt,
      laps: laps,
    );
    _beginResumed();
    if (prepareError != null) throw prepareError;
  }

  void _seedResumeState({
    required List<Waypoint> track,
    required double distanceMetres,
    required Duration elapsed,
    required DateTime startedAt,
    required List<LapSplit> laps,
  }) {
    _track
      ..clear()
      ..addAll(track);
    _resetDistance(distanceMetres);
    _elapsedOffset = elapsed;
    _startTime = startedAt;
    _laps
      ..clear()
      ..addAll(laps);
    _reseedRouteFloor();
  }

  /// Rebuild the route match from the seeded track.
  ///
  /// [prepare] clears [_matchedAlongM], which hands a resumed run a route
  /// matcher with no memory of the ground already covered: on a loop or an
  /// out-and-back the runner is then matched to the start of the route, so
  /// distance-remaining jumps back up. The seeded track holds exactly the fixes
  /// the live run matched, so replaying it through the same matcher — each
  /// probe told how far the track ran since the previous one — restores the
  /// match the killed process had.
  void _reseedRouteFloor() {
    final route = _route;
    if (route == null || route.waypoints.length < 2 || _track.isEmpty) return;
    // Every probe projects onto the route, so replaying a multi-day track
    // against a dense route in one burst is the whole run's route maths at
    // once. Probe an evenly spaced subset within a fixed budget; the distance
    // between probes is summed from every fix, so a sparse replay still knows
    // how far along the route to look.
    final probes =
        max(1, _resumeFloorProjectionBudget ~/ (route.waypoints.length - 1));
    final step = max(1, (_track.length / probes).ceil());
    var travelled = 0.0;
    for (var i = 0; i < _track.length; i++) {
      if (i > 0) {
        final a = _track[i - 1];
        final b = _track[i];
        travelled += _haversine(a.lat, a.lng, b.lat, b.lng);
      }
      if (i % step == 0 || i == _track.length - 1) {
        _routeProgress(_track[i], travelledM: travelled);
        travelled = 0;
      }
    }
    _distanceAtLastMatch = _distanceMetres;
  }

  /// [begin]-equivalent for [resumeSession]: starts the clock + 1 s snapshot
  /// timer WITHOUT clearing the seeded track / distance / laps. Re-anchors the
  /// last-tracked position so the first post-resume fix doesn't credit the
  /// dead-process gap as distance.
  void _beginResumed() {
    if (!_prepared) {
      throw StateError('RunRecorder.resumeSession() seeding ran before prepare()');
    }
    _stopwatch
      ..reset()
      ..start();
    _lastTrackedPosition = null;
    _lastTrackedPositionAt = null;
    _lastTrackedElapsed = null;
    _paceFloorIdx = _track.length;
    _weakGps = false;
    _resetTreadmillAccumulators();
    _recording = true;
    _paused = false;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_recording) return;
      _emitSnapshot();
    });
  }

  /// Test-only: [resumeSession] without the geolocator stream. Seeds the resumed
  /// state on top of [debugPrepareWithoutStream] then begins, so continuity
  /// (elapsed offset, distance, track, laps) can be exercised by feeding
  /// [debugInjectPosition] fixes.
  @visibleForTesting
  void debugResumeWithoutStream({
    required List<Waypoint> track,
    required double distanceMetres,
    required Duration elapsed,
    required DateTime startedAt,
    List<LapSplit> laps = const [],
    Route? route,
    int distanceFilterMetres = 3,
    double minMovementMetres = 2,
    double maxSpeedMps = 10,
    double accuracyGateMetres = 20,
  }) {
    debugPrepareWithoutStream(
      route: route,
      distanceFilterMetres: distanceFilterMetres,
      minMovementMetres: minMovementMetres,
      maxSpeedMps: maxSpeedMps,
      accuracyGateMetres: accuracyGateMetres,
    );
    _seedResumeState(
      track: track,
      distanceMetres: distanceMetres,
      elapsed: elapsed,
      startedAt: startedAt,
      laps: laps,
    );
    _beginResumed();
  }

  /// Test-only: skip the real geolocator subscription and flip the recorder
  /// into a prepared state with the supplied filter parameters. Tests can
  /// then call [debugInjectPosition] directly to feed simulated GPS fixes
  /// through the same `_onPosition` pipeline the live stream uses.
  @visibleForTesting
  void debugPrepareWithoutStream({
    Route? route,
    int distanceFilterMetres = 3,
    double minMovementMetres = 2,
    double maxSpeedMps = 10,
    double accuracyGateMetres = 20,
  }) {
    _startTime = null;
    _elapsedOffset = Duration.zero;
    _stopwatch
      ..stop()
      ..reset();
    _track.clear();
    _laps.clear();
    _currentWaypoint = null;
    _currentWaypointAt = null;
    _lastTrackedPosition = null;
    _lastTrackedPositionAt = null;
    _lastTrackedElapsed = null;
    _lastRouteCalcFor = null;
    _cachedOffRoute = null;
    _cachedRouteRemaining = null;
    _cachedRouteAlong = null;
    _matchedAlongM = null;
    _distanceAtLastMatch = 0;
    _currentWaypointTrusted = true;
    _paceFloorIdx = 0;
    _recording = false;
    _paused = false;
    _route = route;
    _routeCumulativeM = _computeRouteCumulative(route);
    _trackThresholdMetres =
        max(distanceFilterMetres.toDouble(), minMovementMetres);
    _maxSpeedMps = maxSpeedMps;
    _resetDistance(0);
    _accuracyGateMetres = accuracyGateMetres;
    _resetTreadmill();
    _prepared = true;
  }

  /// Test-only: push a simulated [Position] through the same filter chain
  /// the live geolocator subscription would use.
  @visibleForTesting
  void debugInjectPosition(Position pos) => _onPosition(pos);

  /// Test-only: read-only view of the track built so far.
  @visibleForTesting
  List<Waypoint> get debugTrack => List.unmodifiable(_track);

  /// Test-only: current GPS-accumulated distance (ignores treadmill mode).
  @visibleForTesting
  double get debugDistanceMetres => _distanceMetres;

  /// Test-only: the headline distance the recorder would report on a snapshot
  /// — belt distance in treadmill mode, GPS distance otherwise.
  @visibleForTesting
  double get debugReportedDistanceMetres => _reportedDistanceMetres;

  /// Test-only: whether treadmill mode is currently active.
  @visibleForTesting
  bool get debugTreadmillMode => _treadmillMode;

  /// Test-only: elapsed time as seen by the monotonic stopwatch.
  @visibleForTesting
  Duration get debugElapsed => _stopwatch.elapsed;

  /// Test-only: latest raw waypoint (drives the blue dot).
  @visibleForTesting
  Waypoint? get debugCurrentWaypoint => _currentWaypoint;

  /// Test-only: whether the latest fix was rejected by the accuracy gate
  /// (drives [RunSnapshot.weakGps] / the "distance paused" banner).
  @visibleForTesting
  bool get debugWeakGps => _weakGps;

  /// Test-only: rolling-pace computed from the trailing ~200 m of track.
  /// Returns null when the track is too short or timestamps are missing —
  /// matches the contract documented on [RunSnapshot.currentPaceSecondsPerKm].
  @visibleForTesting
  double? get debugPaceSecondsPerKm => _calculatePace();

  /// Test-only: distance from [pos] to the end of the loaded route, summed
  /// along the remaining route segments. Null when no route is loaded.
  /// Advances the route match, exactly as a trusted fix does.
  @visibleForTesting
  double? debugRouteRemaining(Waypoint pos) => _routeProgress(pos)?.remaining;

  /// Test-only: minimum distance from [pos] to any segment of the loaded
  /// route. Null when no route is loaded. Advances the route match, exactly
  /// as a trusted fix does.
  @visibleForTesting
  double? debugOffRouteDistance(Waypoint pos) => _routeProgress(pos)?.offRoute;

  /// Test-only: the route match the snapshot path uses. Advances the match,
  /// exactly as a trusted fix does.
  @visibleForTesting
  ({double along, double offRoute, double remaining})? debugRouteProgress(
          Waypoint pos) =>
      _routeProgress(pos);

  /// Pause the timer and stop accumulating distance until [resume] is called.
  void pause() {
    if (!_recording || _paused) return;
    _paused = true;
    _stopwatch.stop();
    _finishEstimatorSegment();
    // Arm the cumulative-distance re-anchor. If a belt sample lands DURING the
    // pause it rebases the baseline itself and disarms this; if none does, the
    // first post-resume sample re-anchors instead. Without one or the other,
    // the belt advance during the pause leaks into the distance on resume.
    _treadmillNeedsRebaseline = true;
  }

  /// Resume after a [pause].
  void resume() {
    if (!_recording || !_paused) return;
    _paused = false;
    _stopwatch.start();
    _startEstimatorSegment();
    _lastTrackedPosition = null; // avoid a big jump after resume
    _lastTrackedPositionAt = null;
    _lastTrackedElapsed = null;
    _paceFloorIdx = _track.length;
    // Drop the speed-integration anchor too. Without this, the first
    // post-resume belt sample integrates dt back to a timestamp written
    // during/before the pause, crediting the paused gap as distance for any
    // pause shorter than the 30 s dtSec clamp (the GPS path is reset just
    // above for the same reason). Reset both so the next sample is a fresh
    // anchor.
    _treadmillLastSampleAt = null;
    _treadmillLastSpeedMps = 0;
    // The cumulative-distance re-anchor was armed in pause(): if a sample
    // landed during the pause it already disarmed it and rebased; if not, the
    // flag is still set and the first post-resume sample re-anchors.
  }

  /// Update the latest heart-rate reading the recorder stamps onto new
  /// [Waypoint]s. Pass `null` to clear (e.g. strap dropped). No-op
  /// while not recording — early samples before [begin] just get
  /// overwritten by the next one before they'd be applied.
  void setHeartRate(int? bpm) {
    // Drop obviously bogus readings rather than poison the saved track
    // — same bounds the HR-zone reader applies in apps/mobile_android/
    // lib/hr_zones.dart so a single malformed sample doesn't end up
    // visible in the breakdown anyway.
    if (bpm != null && (bpm < 30 || bpm > 230)) return;
    _currentBpm = bpm;
  }

  /// Feed the pedometer's run-relative cumulative step count. While GPS is
  /// good the estimator learns a stride from it; across a GPS gap longer than
  /// [GpsDistanceEstimator.gapS] the steps x stride fill the distance the
  /// gap would otherwise drop. No-op while paused or not recording; the next
  /// stretch re-anchors on its first sample, so paused steps never count.
  void setStepCount(int cumulative) {
    if (!_recording || _paused) return;
    try {
      _estimator.addSteps(_estimatorStepTime(), cumulative);
    } catch (e) {
      debugPrint('RunRecorder: step sample dropped — $e');
    }
  }

  /// Metres the pedometer filled across GPS gaps this run (0 when none).
  double get stepFilledDistanceMetres =>
      _stepFilledOffsetMetres + _estimator.stepDistanceM;

  /// Stride learned from GPS + pedometer, metres. Null until learned.
  double? get strideMetres => _estimator.strideM ?? _priorStrideM;

  void _resetDistance(double seedMetres) {
    _distanceOffsetMetres = seedMetres;
    _stepFilledOffsetMetres = 0;
    _priorStrideM = null;
    _newEstimator();
  }

  void _finishEstimatorSegment() {
    try {
      _estimator.finish(_estimatorStepTime());
    } catch (e) {
      debugPrint('RunRecorder: estimator finish failed — $e');
    }
  }

  void _startEstimatorSegment() {
    _distanceOffsetMetres += _estimator.distanceM;
    _stepFilledOffsetMetres += _estimator.stepDistanceM;
    _priorStrideM = _estimator.strideM ?? _priorStrideM;
    _newEstimator();
  }

  void _newEstimator() {
    _estimator = GpsDistanceEstimator(
      maxSpeedMps: _maxSpeedMps,
      initialStrideM: _priorStrideM,
    );
    _estFixT = null;
    _estFixMono = null;
    _estFixGps = null;
    _estStepT = null;
  }

  // Estimator time is kept on a 1/1024 s grid: every value is then an exact
  // binary fraction, so an interval of exactly [GpsDistanceEstimator.gapS]
  // reads as exactly 10 s rather than 10 s plus a rounding error that would
  // tip it into a re-anchor.
  static double _seconds(Duration d) =>
      (d.inMicroseconds * 1024 / 1e6).roundToDouble() / 1024;

  /// Estimator time for a fix, seconds, strictly monotonic within a stretch.
  ///
  /// Advances by the GPS-reported interval when it is positive and no longer
  /// than the real elapsed time or [GpsDistanceEstimator.gapS], whichever is
  /// larger, and by the [_stopwatch] interval otherwise. The GPS interval is
  /// what keeps a burst of queued fixes (Android Doze batching, a CPU stall)
  /// one second apart instead of crediting them nothing; the stopwatch is
  /// what a backwards, stalled or leaping device clock falls back to, so a
  /// wall-clock jump can neither freeze the distance nor credit an hour.
  double _estimatorFixTime(DateTime gpsTime) {
    final mono = _stopwatch.elapsed;
    final lastT = _estFixT;
    final lastMono = _estFixMono;
    final lastGps = _estFixGps;
    final double t;
    if (lastT == null || lastMono == null || lastGps == null) {
      t = _seconds(mono);
    } else {
      final monoGap = _seconds(mono - lastMono);
      final gpsGap = _seconds(gpsTime.difference(lastGps));
      final useGps =
          gpsGap > 0 && gpsGap <= max(monoGap, GpsDistanceEstimator.gapS);
      t = lastT + (useGps ? gpsGap : monoGap);
    }
    _estFixT = t;
    _estFixMono = mono;
    _estFixGps = gpsTime;
    return t;
  }

  /// Estimator time for a step sample or [GpsDistanceEstimator.finish]: the
  /// last fix's time plus the real time since it arrived, so the estimator's
  /// "is GPS fresh" and "how long was the gap" questions are answered in real
  /// seconds. Nudged forward if a fix's GPS-clocked advance left it behind the
  /// previous step sample, which the estimator would otherwise discard.
  double _estimatorStepTime() {
    final mono = _stopwatch.elapsed;
    final lastT = _estFixT;
    final lastMono = _estFixMono;
    var t = (lastT == null || lastMono == null)
        ? _seconds(mono)
        : lastT + _seconds(mono - lastMono);
    final prev = _estStepT;
    if (prev != null && t <= prev) t = prev + 1 / 1024;
    _estStepT = t;
    return t;
  }

  /// Feed a treadmill (FTMS) sample. The first call flips the recorder into
  /// treadmill mode, after which the headline distance comes from the belt
  /// rather than GPS. [speedMps] is the belt's instantaneous speed in metres
  /// per second; [totalDistanceMetres], when the belt reports it, is the
  /// cumulative session distance and is preferred over speed integration
  /// (rebased to 0 on the first sample so a belt that was already running
  /// doesn't credit pre-run distance).
  ///
  /// Wrapped in its own try/catch per the layered-resilience contract: a
  /// malformed belt sample must never throw into the recorder loop or
  /// degrade the GPS path. A bad sample is dropped and the last good distance
  /// is kept. No-op until [begin] (distance only accumulates while recording).
  void setTreadmillSample(double speedMps, {double? totalDistanceMetres}) {
    try {
      if (!_treadmillMode) {
        _treadmillMode = true;
        // Mid-run is the only way the belt ever engages, so every activation
        // lands on an already-accumulating run: hand the running total to the
        // source taking over instead of restarting it at the belt's own zero,
        // which dropped the GPS kilometres already run and made the next lap
        // split a negative (clamped to 0 m) delta. Arming the re-anchor makes
        // the first cumulative-total sample baseline onto the carried value,
        // the same formula the pause and console-reset re-anchors use.
        _treadmillDistanceMetres = _distanceMetres;
        _treadmillNeedsRebaseline = true;
      }
      if (!_recording) return;
      final now = DateTime.now();
      if (totalDistanceMetres != null) {
        if (_paused) {
          // The belt keeps counting while the user is paused; rebase the
          // baseline so the paused advance is excluded and the accumulated
          // distance freezes (mirrors the GPS path's `if (_paused) return`
          // and the speed branch's `!_paused` gate). This handles the
          // re-anchor itself, so disarm the post-resume one.
          _treadmillBaselineMetres = totalDistanceMetres - _treadmillDistanceMetres;
          _treadmillNeedsRebaseline = false;
        } else {
          if (_treadmillNeedsRebaseline) {
            // First sample after a resume where no sample landed during the
            // pause: re-anchor at the current belt total but PRESERVE the
            // accumulated distance, so the paused advance is dropped and the
            // distance continues from the pre-pause value (same formula as the
            // _paused branch above).
            _treadmillBaselineMetres =
                totalDistanceMetres - _treadmillDistanceMetres;
            _treadmillNeedsRebaseline = false;
          }
          _treadmillBaselineMetres ??= totalDistanceMetres;
          final lastTotal = _treadmillLastTotalMetres;
          if (lastTotal != null && totalDistanceMetres < lastTotal) {
            // The belt's cumulative counter went BACKWARDS. An FTMS console
            // zeroes it whenever its own session restarts (safety key pulled,
            // stop/start mid-run, workout ended on the console) — a permanent
            // step down, not a transient glitch, so the decrease has to be
            // measured against the last total we saw rather than the baseline
            // (which is usually 0 and so never trips). Holding the last good
            // value froze the headline distance for the rest of the run and
            // then dropped it to 0 once the belt climbed past the baseline
            // again. Rebase onto the new counter origin, preserving what has
            // already been accumulated (same formula as the pause and
            // post-resume re-anchors above), so belt distance is monotonic.
            _treadmillBaselineMetres =
                totalDistanceMetres - _treadmillDistanceMetres;
          }
          _treadmillDistanceMetres =
              totalDistanceMetres - _treadmillBaselineMetres!;
        }
        _treadmillLastTotalMetres = totalDistanceMetres;
      } else {
        final last = _treadmillLastSampleAt;
        if (last != null && !_paused) {
          final dtSec = now.difference(last).inMilliseconds / 1000.0;
          if (dtSec > 0 && dtSec < 30 && speedMps >= 0 && speedMps < _maxTreadmillSpeedMps) {
            _treadmillDistanceMetres += _treadmillLastSpeedMps * dtSec;
          }
        }
      }
      // Carry only a plausible speed forward. A bogus reading that just
      // failed the clamp above must NOT become the integrand for the next
      // interval — otherwise the next good sample integrates the glitch
      // (e.g. 999 m/s × 1 s ≈ 999 m of phantom distance). Keep the last
      // good speed instead.
      if (speedMps >= 0 && speedMps < _maxTreadmillSpeedMps) {
        _treadmillLastSpeedMps = speedMps;
      }
      _treadmillLastSampleAt = now;
    } catch (e) {
      debugPrint('RunRecorder: treadmill sample dropped — $e');
    }
  }

  /// Leave treadmill mode and hand the headline distance back to the GPS path.
  /// Called when the user turns treadmill mode off or the belt is forgotten
  /// mid-session.
  ///
  /// The accumulated total moves onto the GPS accumulator, the mirror of the
  /// carry [setTreadmillSample] does on the way in: one continuous run
  /// distance, handed between sources, never two rival accumulators one of
  /// which is discarded at the switch.
  void clearTreadmillMode() {
    if (_treadmillMode) {
      _distanceOffsetMetres = _treadmillDistanceMetres - _estimator.distanceM;
    }
    _treadmillMode = false;
    _resetTreadmillAccumulators();
  }

  /// Full reset (mode + accumulators) — used by [prepare] so each run starts
  /// on the GPS default until a belt sample flips it back on.
  void _resetTreadmill() {
    _treadmillMode = false;
    _resetTreadmillAccumulators();
  }

  void _resetTreadmillAccumulators() {
    _treadmillDistanceMetres = 0;
    _treadmillBaselineMetres = null;
    _treadmillLastTotalMetres = null;
    _treadmillLastSpeedMps = 0;
    _treadmillLastSampleAt = null;
    _treadmillNeedsRebaseline = false;
  }

  /// Whether a fix carries a usable WGS84 coordinate.
  ///
  /// Nothing between here and Storage re-checks: the waypoint goes into
  /// `_track`, `stop()` hands the track to the caller, and both the local
  /// store and `ApiClient._uploadTrack` serialise it with `jsonEncode`, which
  /// REFUSES a non-finite double. One such fix therefore does not corrupt a
  /// number on a screen — it makes the whole run unsaveable and unuploadable,
  /// which on a multi-day effort is the entire record. The filter chain below
  /// looks like it would catch it and does not: every comparison against a NaN
  /// delta is false, so a NaN fix merely fails the movement test, and the two
  /// paths that append WITHOUT consulting the delta — the first fix after
  /// [begin], and the post-gap re-anchor — take it straight into the track.
  ///
  /// The range half is the same bound the route importers apply, for the same
  /// reason: a latitude past ±90 is not a place, and a finite-but-absurd pair
  /// overflows a haversine to a non-finite distance downstream.
  static bool _isUsableFix(Position pos) =>
      pos.latitude.isFinite &&
      pos.longitude.isFinite &&
      pos.latitude.abs() <= 90 &&
      pos.longitude.abs() <= 180;

  /// Whether the reported horizontal accuracy clears the gate.
  ///
  /// Written as "not <= gate" rather than "> gate" so a NaN fails CLOSED: a
  /// platform that cannot state its accuracy has not thereby stated a good
  /// one, and `NaN > gate` is false, which admitted it as if it were perfect.
  /// A NEGATIVE accuracy is the concrete case — CoreLocation documents a
  /// negative `horizontalAccuracy` as meaning the latitude and longitude are
  /// INVALID, and geolocator passes the value through untouched, so on iOS
  /// the recorder was taking a fix the OS had explicitly disowned and letting
  /// it drive distance and the map. Zero stays acceptable: Android reports it
  /// for "no accuracy attached", which is unknown, not disowned.
  bool _accuracyClearsGate(Position pos) =>
      pos.accuracy >= 0 && pos.accuracy <= _accuracyGateMetres;

  /// Drop the current fix, flag the stall, and log at most once per 5 s — an
  /// always-bad stream would otherwise log at the sensor's rate for the whole
  /// run.
  void _dropFix(String reason) {
    _weakGps = true;
    final now = DateTime.now();
    final last = _lastAccuracyDropLogAt;
    if (last == null || now.difference(last) >= const Duration(seconds: 5)) {
      _lastAccuracyDropLogAt = now;
      debugPrint('RunRecorder: dropping fix — $reason');
    }
  }

  /// Geolocator's fix-quality fields, with the platforms' "not reported"
  /// encodings mapped to null (spec: absent, not zero). iOS reports an
  /// invalid speed, course or accuracy as negative. Android reports a field it
  /// does not have as 0 — and a 0 speed with no speed accuracy is that, not a
  /// measured standstill: read as Doppler it would pin the credited speed
  /// under the stationary floor and record no distance at all. Likewise a 0
  /// bearing with no bearing accuracy is "none", not north.
  static ({
    double? accuracyM,
    double? speedMps,
    double? speedAccuracyMps,
    double? bearingDeg,
  }) _fixQuality(Position pos) {
    bool positive(double v) => v.isFinite && v > 0;
    final speedAcc = positive(pos.speedAccuracy) ? pos.speedAccuracy : null;
    final speedOk = pos.speed.isFinite &&
        pos.speed >= 0 &&
        (pos.speed > 0 || speedAcc != null);
    final bearingOk = pos.heading.isFinite &&
        pos.heading >= 0 &&
        pos.heading <= 360 &&
        (pos.heading > 0 || positive(pos.headingAccuracy));
    return (
      accuracyM: positive(pos.accuracy) ? pos.accuracy : null,
      speedMps: speedOk ? pos.speed : null,
      speedAccuracyMps: speedAcc,
      bearingDeg: bearingOk ? pos.heading : null,
    );
  }

  static double? _round2(double? v) =>
      v == null ? null : (v * 100).roundToDouble() / 100;

  void _onPosition(Position pos) {
    if (_paused) return;

    if (!_isUsableFix(pos)) {
      _dropFix('not a usable coordinate '
          '(${pos.latitude}, ${pos.longitude})');
      return;
    }

    if (!_accuracyClearsGate(pos)) {
      _dropFix('accuracy ${pos.accuracy.toStringAsFixed(1)}m outside '
          '0..${_accuracyGateMetres.toStringAsFixed(0)}m');
      return;
    }
    _weakGps = false;
    final fix = _fixQuality(pos);

    // Always refresh the raw current position so the blue dot updates on
    // every valid fix, independent of the track-append threshold. This
    // happens even before [begin] is called, so the map can show the runner
    // during the countdown.
    //
    // Use pos.timestamp (GPS-reported) rather than DateTime.now() so any
    // downstream consumer that subtracts two waypoint timestamps gets the
    // real elapsed time. Wall-clock dt collapsed to zero whenever positions
    // were processed in a tight loop (queued fixes after a CPU stall, or
    // synthetic injection in unit tests), and _calculatePace silently
    // returned null in those cases. Same lesson the speed-clamp learned
    // earlier in this file (see the "GPS-reported time" comment below).
    _currentWaypoint = Waypoint(
      lat: pos.latitude,
      lng: pos.longitude,
      // Keep the altitude whenever the platform reports a real vertical fix.
      // Gating on `altitude != 0` dropped a legitimate sea-level reading; a
      // finite positive altitudeAccuracy is the platform's signal that the
      // vertical component is a measurement rather than the unset default
      // (which reports 0 / non-finite accuracy).
      elevationMetres: (pos.altitudeAccuracy.isFinite &&
              pos.altitudeAccuracy > 0)
          ? pos.altitude
          : null,
      timestamp: pos.timestamp,
      bpm: _currentBpm,
      accuracyMetres: _round2(fix.accuracyM),
      speedMps: _round2(fix.speedMps),
      speedAccuracyMps: _round2(fix.speedAccuracyMps),
      bearingDeg: _round2(fix.bearingDeg),
    );
    _currentWaypointAt = DateTime.now();

    // Only append to the track and accumulate distance once the run has
    // officially started (post-[begin]).
    if (_recording) {
      // Distance comes from the estimator, which sees EVERY fix that cleared
      // the gates above; the movement-gated rule below only decides what the
      // track keeps for the map and the route match.
      try {
        _estimator.addFix(
          t: _estimatorFixTime(pos.timestamp),
          lat: pos.latitude,
          lng: pos.longitude,
          accuracyM: fix.accuracyM,
          speedMps: fix.speedMps,
          speedAccuracyMps: fix.speedAccuracyMps,
          bearingDeg: fix.bearingDeg,
        );
      } catch (e) {
        debugPrint('RunRecorder: estimator rejected fix — $e');
      }
      final last = _lastTrackedPosition;
      final lastAt = _lastTrackedPositionAt;
      final lastElapsed = _lastTrackedElapsed;
      if (last == null || lastAt == null || lastElapsed == null) {
        _lastTrackedPosition = pos;
        _lastTrackedPositionAt = pos.timestamp;
        _lastTrackedElapsed = _stopwatch.elapsed;
        _track.add(_currentWaypoint!);
        _currentWaypointTrusted = true;
      } else {
        final delta = Geolocator.distanceBetween(
          last.latitude,
          last.longitude,
          pos.latitude,
          pos.longitude,
        );
        // Implausible-speed clamp: compare the delta to the GPS-reported
        // time between the two fixes (not wall-clock) so batched/queued
        // positions processed in a tight loop still get clamped correctly.
        // A corrupt GPS fix can easily imply 50+ m/s — dropping those here
        // stops one bad sample from inflating total distance.
        //
        // A non-positive dt (two fixes sharing a timestamp, or a backwards
        // clock — both happen when Android batches queued fixes or after an
        // NTP correction) makes the speed undefined, so treat it as
        // implausible: with `dtSec > 0` guarding the ratio, a same-timestamp
        // teleport would otherwise skip the speed check and slip through on
        // the < 100 m hop filter alone, inflating distance. Rejecting it here
        // is lossless — the next fix with a real timestamp accumulates the
        // delta from this last-good position over the true elapsed time.
        final dtSec =
            pos.timestamp.difference(lastAt).inMilliseconds / 1000.0;
        final implausible =
            dtSec <= 0 || (delta / dtSec) > _maxSpeedMps;

        // Only grow the track on real movement. Ignore
        // GPS jitter below the threshold, implausible jumps (>100m in one
        // hop), and anything faster than the activity's max plausible speed.
        // The same "has a genuine interval elapsed" question asked of the
        // monotonic clock. dtSec is GPS-reported time, so a device clock that
        // jumps backwards (NTP correction, manual change, a phone that boots
        // with a bad clock and then syncs) leaves lastAt in the future: every
        // later fix computes a non-positive dtSec, which is implausible by the
        // clamp above AND below the re-anchor window, so the anchor could never
        // rebase and distance stayed frozen until real time caught back up past
        // it. A stuck clock (every fix sharing a timestamp) froze it outright.
        // The stopwatch cannot go backwards or stall, so this arm makes the
        // re-anchor fire on real elapsed time no matter what the GPS timestamps
        // do — the escape is now unconditionally self-healing. It cannot weaken
        // the teleport guard: it only fires where GPS time claims a SHORTER gap
        // than the monotonic clock, i.e. exactly where GPS time is untrustworthy.
        final monotonicGapSec =
            (_stopwatch.elapsed - lastElapsed).inMilliseconds / 1000.0;
        if (delta > _trackThresholdMetres && delta < 100 && !implausible) {
          _lastTrackedPosition = pos;
          _lastTrackedPositionAt = pos.timestamp;
          _lastTrackedElapsed = _stopwatch.elapsed;
          _track.add(_currentWaypoint!);
          _currentWaypointTrusted = true;
        } else if (dtSec >= _gpsReanchorAfterSeconds ||
            monotonicGapSec >= _gpsReanchorAfterSeconds) {
          // Real GPS gap: the hop failed the < 100 m cap (the runner genuinely
          // moved away while fixes were dropped) but a genuine interval has
          // elapsed. Rebase the anchor to this fresh fix WITHOUT crediting the
          // un-sampled gap distance — exactly how resume() nulls the anchor so
          // the first post-resume fix re-anchors. Without this the anchor stays
          // stale, every later delta only grows past 100 m, and distance is
          // frozen for the rest of the run (#330). Both gates must agree the
          // gap is short for a hop to fail closed, so a zero/near-zero-dt
          // duplicate arriving immediately is still rejected as a teleport.
          //
          // Seal the pace window at the same time, exactly as resume() and
          // _beginResumed() do — this branch creates the identical
          // discontinuity. The gap's metres are deliberately NOT credited, so
          // a rolling window spanning it times the un-credited distance
          // against the gap's clock: 5 clean fixes at 200 s/km followed by a
          // 12 s Doze batch 150 m on measured 128 s/km, i.e. the recorder
          // claiming zero extra metres and a sub-world-record pace at once.
          // That value feeds the pace-alert and cut-off catch-up voice cues
          // and live_cutoff_eta's projection, so the error runs in the
          // direction that SUPPRESSES a safety warning.
          _paceFloorIdx = _track.length;
          _lastTrackedPosition = pos;
          _lastTrackedPositionAt = pos.timestamp;
          _lastTrackedElapsed = _stopwatch.elapsed;
          _track.add(_currentWaypoint!);
          _currentWaypointTrusted = true;
        } else {
          _currentWaypointTrusted = false;
        }
      }
    } else {
      _currentWaypointTrusted = true;
    }

    _emitSnapshot();
  }

  /// Headline distance: belt distance in treadmill mode, GPS-accumulated
  /// distance otherwise. Reading this is the only place the treadmill source
  /// influences a normal run — when [_treadmillMode] is false (the default)
  /// it is exactly the GPS value.
  double get _reportedDistanceMetres =>
      _treadmillMode ? _treadmillDistanceMetres : _distanceMetres;

  void _emitSnapshot() {
    final current = _currentWaypoint;
    final elapsed = _stopwatch.elapsed + _elapsedOffset;
    final pace = _calculatePace();

    // Route-relative fields are only meaningful once we have a fix AND a
    // route is loaded. When the 1-second timer fires without a new GPS
    // fix (indoor mode, warmup, stationary runner) the position hasn't
    // moved — the last cached off-route / remaining values are still
    // correct. Skipping the O(R) segment projection over the full route
    // on every tick is a real win on long routes (e.g. a 40 km
    // imported ride with 2000 waypoints).
    double? offRoute;
    double? remaining;
    double? along;
    if (current != null) {
      // Reuse the cached values both when the position hasn't changed and when
      // the current fix is one the distance filter rejected — an untrusted fix
      // must not move the route match (see [_currentWaypointTrusted]). The
      // last trusted fix's values are still the best available answer.
      if (identical(current, _lastRouteCalcFor) || !_currentWaypointTrusted) {
        offRoute = _cachedOffRoute;
        remaining = _cachedRouteRemaining;
        along = _cachedRouteAlong;
      } else {
        final progress = _routeProgress(current);
        offRoute = progress?.offRoute;
        remaining = progress?.remaining;
        along = progress?.along;
        _lastRouteCalcFor = current;
        _cachedOffRoute = offRoute;
        _cachedRouteRemaining = remaining;
        _cachedRouteAlong = along;
      }
    }

    // Debug-only guard that the shared track view is still the one
    // callers expect. The efficiency contract is that every snapshot
    // carries the SAME `_trackView` reference (wrapping `_track` by
    // reference). If someone reintroduces a per-emit wrapper
    // allocation here, the reference changes per emit and we regress
    // the allocation fix. Stripped in release.
    assert(
      _trackView.length == _track.length,
      'Shared _trackView out of sync with _track.',
    );

    _controller.add(RunSnapshot(
      elapsed: elapsed,
      distanceMetres: _reportedDistanceMetres,
      currentPaceSecondsPerKm: pace,
      currentPosition: current,
      positionFixedAt: _currentWaypointAt,
      positionTrusted: _currentWaypointTrusted,
      track: _trackView,
      offRouteDistanceMetres: offRoute,
      routeRemainingMetres: remaining,
      routeAlongMetres: along,
      weakGps: _weakGps,
    ));
  }

  /// Off-route distance, distance remaining and distance along the route for
  /// [pos], advancing the route match.
  ///
  /// Port of web `route_geometry.ts#progressAlongRoute` (the matcher, not its
  /// projection: the recorder keeps its own equirectangular frame). Only the
  /// stretch of route the runner can plausibly be on is searched — from
  /// [_routeMatchBacktrackM] behind the previous match to
  /// [_routeMatchLookaheadM] past it plus the GPS distance recorded since —
  /// and within it a tie between overlapping legs goes to forward progress,
  /// with a bias capped at [_maxAlongBiasM] so it never outweighs real
  /// distance off the line. When nothing in that window is within
  /// [_routeMatchReacquireM], or the runner projects past its far end, the rest
  /// of the route ahead is searched, so a
  /// runner who skips ahead or returns after a signal gap is re-acquired; a
  /// runner still off the line keeps the windowed match, unless there is no
  /// previous match to keep.
  ///
  /// `offRoute` is the distance to the nearest point on the WHOLE route: a
  /// runner standing on the line is not off it, whichever lap or leg the
  /// matcher has them on.
  ///
  /// [travelledM] overrides the distance-since-last-match the live path reads
  /// from the GPS accumulator (the resume replay supplies its own). Null when
  /// no route is selected, or when no segment yields a usable projection.
  ({double along, double offRoute, double remaining})? _routeProgress(
    Waypoint pos, {
    double? travelledM,
  }) {
    final route = _route;
    final cum = _routeCumulativeM;
    if (route == null || cum == null || route.waypoints.length < 2) return null;
    final wps = route.waypoints;
    final n = wps.length - 1;
    final total = cum[n];

    // Equirectangular frame per segment, anchored at its start: p is the
    // runner, b the segment end, both in metres east/north of the start.
    double frame(int i, double t, List<double> out) {
      final a = wps[i];
      final b = wps[i + 1];
      final mLng = _metresPerDegree * cos(_toRad(a.lat));
      final px = (pos.lng - a.lng) * mLng;
      final py = (pos.lat - a.lat) * _metresPerDegree;
      final bx = (b.lng - a.lng) * mLng;
      final by = (b.lat - a.lat) * _metresPerDegree;
      final lenSq = bx * bx + by * by;
      final tFree = lenSq == 0 ? 0.0 : ((px * bx + py * by) / lenSq).clamp(0.0, 1.0);
      final tt = t.isNaN ? tFree : t;
      final dx = px - bx * tt;
      final dy = py - by * tt;
      out[0] = tFree;
      return sqrt(dx * dx + dy * dy);
    }

    final scratch = [0.0];
    final tFree = List<double>.filled(n, 0);
    var minDist = double.infinity;
    for (var i = 0; i < n; i++) {
      final d = frame(i, double.nan, scratch);
      tFree[i] = scratch[0];
      if (d < minDist) minDist = d;
    }
    // The running minimum is seeded at +Infinity, and a NaN never compares
    // less than it, so a route every one of whose segments projects to NaN
    // leaves the seed untouched and reports the runner as infinitely far off
    // course. "No usable projection" is the same answer as "no route": null,
    // which every consumer already handles. Reporting a non-finite figure
    // instead put it on the live stats readout and, before the detector was
    // taught to refuse one, spent the run's single off-route escalation.
    if (!minDist.isFinite || !total.isFinite) return null;

    final prevMatch = _matchedAlongM;
    final hasPrev = prevMatch != null;
    final prev = hasPrev ? prevMatch.clamp(0.0, total).toDouble() : 0.0;
    final rawTravelled = travelledM ?? (_distanceMetres - _distanceAtLastMatch);
    final travelled =
        rawTravelled.isFinite && rawTravelled > 0 ? rawTravelled : 0.0;
    final anchor = min(total, prev + travelled);
    final lo = hasPrev ? max(0.0, prev - _routeMatchBacktrackM) : 0.0;

    // `pastEnd` marks a match pinned to `toM` while the runner projects
    // beyond it.
    ({double along, double offset, bool pastEnd})? best(
        double fromM, double toM) {
      ({double along, double offset, bool pastEnd})? found;
      var bestCost = double.infinity;
      for (var i = 0; i < n; i++) {
        final s0 = cum[i];
        final len = cum[i + 1] - s0;
        if (s0 > toM || s0 + len < fromM) continue;
        final tLo = len > 0 ? max(0.0, (fromM - s0) / len) : 0.0;
        final tHi = len > 0 ? min(1.0, (toM - s0) / len) : 0.0;
        final t = min(tHi, max(tLo, tFree[i]));
        final offset = frame(i, t, scratch);
        final along = s0 + t * len;
        final gap = along - anchor;
        final bias = min(
          _maxAlongBiasM,
          gap >= 0 ? gap * _alongFwdBiasPerM : -gap * _alongBackBiasPerM,
        );
        final cost = offset + bias + gap.abs() * _alongContinuityPerM;
        if (cost < bestCost) {
          bestCost = cost;
          found = (along: along, offset: offset, pastEnd: tFree[i] > t);
        }
      }
      return found;
    }

    var match = best(lo, anchor + _routeMatchLookaheadM);
    if (match == null ||
        match.offset > _routeMatchReacquireM ||
        match.pastEnd) {
      final ahead = best(lo, total);
      if (ahead != null &&
          (match == null ||
              (ahead.offset < match.offset &&
                  (!hasPrev || ahead.offset <= _routeMatchReacquireM)))) {
        match = ahead;
      }
    }
    if (match == null) return null;
    final along = match.along.clamp(0.0, total).toDouble();
    _matchedAlongM = along;
    _distanceAtLastMatch = _distanceMetres;
    return (along: along, offRoute: minDist, remaining: max(0.0, total - along));
  }

  /// Cumulative route length at each waypoint (see [_routeCumulativeM]). Null
  /// for a route too short to have a segment.
  static List<double>? _computeRouteCumulative(Route? route) {
    if (route == null || route.waypoints.length < 2) return null;
    final wps = route.waypoints;
    final cum = List<double>.filled(wps.length, 0);
    for (var k = 1; k < wps.length; k++) {
      cum[k] = cum[k - 1] +
          _haversine(wps[k - 1].lat, wps[k - 1].lng, wps[k].lat, wps[k].lng);
    }
    return cum;
  }

  /// Calculate pace from the last ~200m of track.
  double? _calculatePace() {
    // Never walk back across a pause / process-kill boundary. `_track` keeps
    // the pre-pause tail, but its timestamps are separated from the
    // post-resume points by the paused wall-clock gap — which is unbounded
    // (a resumed run may have been dead for up to kResumableWindow). Timing
    // post-resume distance against a pre-pause timestamp reported a pace
    // hundreds of times too slow for the first ~200 m after every resume, and
    // the run screen feeds that number to the pace-alert and cut-off
    // catch-up voice cues.
    final floor = _paceFloorIdx.clamp(0, _track.length);
    if (_track.length - floor < 5) return null;

    double segmentDistance = 0;
    int segmentStart = _track.length - 1;

    for (int i = _track.length - 2; i >= floor; i--) {
      final a = _track[i];
      final b = _track[i + 1];
      segmentDistance += _haversine(a.lat, a.lng, b.lat, b.lng);
      segmentStart = i;
      if (segmentDistance >= 200) break;
    }

    if (segmentDistance < 50) return null;

    final startTs = _track[segmentStart].timestamp;
    final endTs = _track.last.timestamp;
    if (startTs == null || endTs == null) return null;

    final segmentTime = endTs.difference(startTs).inMilliseconds / 1000.0;
    if (segmentTime <= 0) return null;

    return (segmentTime / segmentDistance) * 1000; // seconds per km
  }

  static double _haversine(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0; // Earth radius in metres
    final dLat = _toRad(lat2 - lat1);
    final dLng = _toRad(lng2 - lng1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRad(lat1)) * cos(_toRad(lat2)) * sin(dLng / 2) * sin(dLng / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  static double _toRad(double deg) => deg * pi / 180;

  /// Mark a lap split at the current position. Returns the lap number.
  int lap() {
    if (!_recording) return 0;
    final now = DateTime.now();
    _laps.add(LapSplit(
      number: _laps.length + 1,
      timestamp: now,
      cumulativeDistanceMetres: _reportedDistanceMetres,
      cumulativeDuration: _currentElapsed(),
    ));
    return _laps.length;
  }

  Duration _currentElapsed() => _stopwatch.elapsed + _elapsedOffset;

  /// Stop recording and return the completed [Run].
  Future<Run> stop() async {
    _recording = false;
    _prepared = false;
    _stopwatch.stop();
    _timer?.cancel();
    _timer = null;
    _gpsRetryTimer?.cancel();
    _gpsRetryTimer = null;
    await _positionSub?.cancel();
    _positionSub = null;
    _finishEstimatorSegment();

    final startedAt = _startTime ?? DateTime.now();
    final elapsed = _stopwatch.elapsed + _elapsedOffset;

    final metadata = <String, dynamic>{};
    if (_laps.isNotEmpty) metadata['laps'] = lapsToCanonicalJson(_laps);
    if (_treadmillMode) {
      // Belt-measured distance is not GPS-measured, so the same exclusion the
      // pedometer-estimated indoor path uses applies: `indoor: true` keeps it
      // out of the VDOT ceiling, and `indoor_source` records that the belt
      // (not a pedometer estimate) supplied the distance.
      metadata['indoor'] = true;
      metadata['indoor_source'] = 'treadmill';
      metadata['distance_source'] = 'treadmill';
    } else {
      metadata[MetadataKeys.distanceEstimator] = distanceEstimatorVersion;
      final stepFilled = stepFilledDistanceMetres.round();
      if (stepFilled > 0) {
        metadata[MetadataKeys.distanceStepFilledM] = stepFilled;
      }
    }

    return Run(
      id: _uuid.v4(),
      startedAt: startedAt,
      duration: elapsed,
      distanceMetres: _reportedDistanceMetres,
      track: List.unmodifiable(_track),
      source: RunSource.app,
      metadata: metadata.isEmpty ? null : metadata,
    );
  }

  /// Clean up resources. Terminal: the recorder cannot record again, and
  /// [prepare] on a disposed recorder throws rather than handing back one that
  /// silently never opens a stream.
  void dispose() {
    _disposed = true;
    _recording = false;
    _prepared = false;
    _timer?.cancel();
    _timer = null;
    _gpsRetryTimer?.cancel();
    _gpsRetryTimer = null;
    _positionSub?.cancel();
    _positionSub = null;
    _controller.close();
  }
}

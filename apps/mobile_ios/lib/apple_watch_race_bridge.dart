import 'package:core_models/core_models.dart' show parseIsoStrict;
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform, immutable;
import 'package:flutter/services.dart';

/// The three live-race relays between the phone and the paired Apple Watch,
/// as values and pure decisions. The transport lives in
/// `apps/mobile_ios/ios/Runner/WatchIngestBridge.swift`; everything that has
/// to be RIGHT lives here, where it can be tested without a `WCSession`.
///
/// Wear OS discovers Arm / Go / End by polling `race_sessions` from the wrist
/// (`RaceSessionClient.fetchActive`). The Apple Watch is told instead, because
/// `apps/watch_ios/CLAUDE.md` keeps the Supabase surface off that wrist — but
/// the states, the 10 s ping cadence and the once-only finisher report are
/// Wear's, because a spectator watching one live link must see the same runner
/// whichever wrist was worn (decisions § 1712).
///
/// The two inbound payloads take deliberately opposite durability trades, and
/// this side mirrors them: a ping that cannot be written is DROPPED (a dot an
/// hour old is a lie about where the runner is), a finisher's official time is
/// queued to disk, because it is the one value in the feature nobody can
/// re-derive.

/// The bidirectional method channel. The phone invokes `push` on it; the
/// native side invokes `racePing` and `raceResult` back on the same channel.
const String kAppleWatchRaceChannel = 'run_app/watch_race';

/// A race as the Arm / Go / End push spells it.
///
/// [instanceStart] is carried as the already-serialized key rather than a
/// `DateTime`: `race_sessions` is keyed on `(event_id, instance_start)` and
/// the watch echoes this string back verbatim on every ping and on the
/// finisher report, so re-formatting it anywhere else would be a second place
/// for the key to drift — and a ping keyed to a row that does not exist is
/// dropped by PostgREST without a word.
@immutable
class WatchRace {
  const WatchRace({
    required this.eventId,
    required this.instanceStart,
    required this.status,
    this.eventTitle,
  });

  final String eventId;
  final String instanceStart;

  /// `race_sessions.status` — `armed` | `running` | `finished` | `cancelled`.
  final String status;
  final String? eventTitle;

  bool get isLive => status == 'armed' || status == 'running';

  /// The same race, ended. The watch clears on either terminal word, and a
  /// phone that watched the session simply disappear from its query cannot
  /// tell which of the two it was.
  WatchRace get ended => WatchRace(
        eventId: eventId,
        instanceStart: instanceStart,
        status: 'finished',
        eventTitle: eventTitle,
      );

  Map<String, Object?> toArguments() => <String, Object?>{
        'race_event_id': eventId,
        'race_instance_start': instanceStart,
        'race_status': status,
        if (eventTitle != null && eventTitle!.isNotEmpty)
          'race_event_title': eventTitle,
      };

  @override
  bool operator ==(Object other) =>
      other is WatchRace &&
      other.eventId == eventId &&
      other.instanceStart == instanceStart &&
      other.status == status &&
      other.eventTitle == eventTitle;

  @override
  int get hashCode => Object.hash(eventId, instanceStart, status, eventTitle);
}

/// The pushes a transition from [previous] to [next] owes the wrist.
///
/// The load-bearing case is the empty one: **End must be pushed explicitly.**
/// The watch has no timeout on a live race by design, so a race that simply
/// stops appearing in the phone's query leaves `RACE LIVE` on the wrist
/// forever unless this emits a terminal push for it (decisions § 1712). That
/// is also why a swap between two different races emits two pushes — the End
/// for the one that is over, then the Arm for the one that is not.
List<WatchRace> appleWatchRacePushes({WatchRace? previous, WatchRace? next}) {
  final sameRace = previous != null &&
      next != null &&
      previous.eventId == next.eventId &&
      previous.instanceStart == next.instanceStart;
  final pushes = <WatchRace>[];
  if (previous != null && previous.isLive && !sameRace) pushes.add(previous.ended);
  if (next != null && (!sameRace || previous.status != next.status)) {
    pushes.add(next);
  }
  return pushes;
}

/// One accepted fix the watch relayed, on its way to a `race_pings` row.
@immutable
class WatchRacePing {
  const WatchRacePing({
    required this.eventId,
    required this.instanceStart,
    required this.lat,
    required this.lng,
    this.distanceM,
    this.elapsedS,
    this.bpm,
  });

  final String eventId;
  final DateTime instanceStart;
  final double lat;
  final double lng;
  final double? distanceM;
  final int? elapsedS;
  final int? bpm;

  /// Fail-closed, like `LiveRace.decode` on the other end: a missing key, a
  /// key of the wrong type, a non-finite coordinate or an unparseable
  /// occurrence key drops the whole ping. A partly-read ping would put the
  /// runner somewhere they have not been on a map other people are reading.
  static WatchRacePing? decode(Map<Object?, Object?> payload) {
    final eventId = payload['race_ping_event_id'];
    final instanceRaw = payload['race_ping_instance_start'];
    final lat = payload['race_ping_lat'];
    final lng = payload['race_ping_lng'];
    if (eventId is! String || eventId.isEmpty) return null;
    if (instanceRaw is! String || instanceRaw.isEmpty) return null;
    if (lat is! num || lng is! num) return null;
    if (!lat.toDouble().isFinite || !lng.toDouble().isFinite) return null;
    // `DateTime.tryParse` answers `2026-05-32` with the 1st of June rather
    // than refusing it, and `instance_start` is the occurrence KEY the
    // spectator map joins on — so a rolled date would land the dot on a
    // different race night (decisions § 1344 / § 1377).
    final instance = parseIsoStrict(instanceRaw);
    if (instance == null) return null;
    final distance = payload['race_ping_distance_m'];
    final elapsed = payload['race_ping_elapsed_s'];
    final bpm = payload['race_ping_bpm'];
    return WatchRacePing(
      eventId: eventId,
      instanceStart: instance,
      lat: lat.toDouble(),
      lng: lng.toDouble(),
      distanceM: distance is num && distance.toDouble().isFinite && distance >= 0
          ? distance.toDouble()
          : null,
      elapsedS: elapsed is num && elapsed >= 0 ? elapsed.toInt() : null,
      // Omitted rather than zeroed for the reason the watch omits it:
      // nothing measured a heart rate is a different statement from a heart
      // rate of zero, and the spectator leaderboard renders what it is given.
      bpm: bpm is num && bpm > 0 ? bpm.toInt() : null,
    );
  }
}

/// A finisher's official time, relayed off the wrist.
@immutable
class WatchRaceResult {
  const WatchRaceResult({
    required this.eventId,
    required this.instanceStart,
    required this.runId,
    required this.durationS,
    required this.distanceM,
  });

  final String eventId;
  final DateTime instanceStart;
  final String runId;
  final int durationS;
  final double distanceM;

  /// Fail-closed for the same reason [WatchRacePing.decode] is, and with more
  /// at stake: this writes the one row in the feature nobody can re-derive.
  static WatchRaceResult? decode(Map<Object?, Object?> payload) {
    final eventId = payload['race_result_event_id'];
    final instanceRaw = payload['race_result_instance_start'];
    final runId = payload['race_result_run_id'];
    final durationS = payload['race_result_duration_s'];
    final distanceM = payload['race_result_distance_m'];
    if (eventId is! String || eventId.isEmpty) return null;
    if (instanceRaw is! String || instanceRaw.isEmpty) return null;
    if (runId is! String || runId.isEmpty) return null;
    if (durationS is! num || durationS < 0) return null;
    if (distanceM is! num || !distanceM.toDouble().isFinite || distanceM < 0) {
      return null;
    }
    final instance = parseIsoStrict(instanceRaw);
    if (instance == null) return null;
    return WatchRaceResult(
      eventId: eventId,
      instanceStart: instance,
      runId: runId,
      durationS: durationS.toInt(),
      distanceM: distanceM.toDouble(),
    );
  }
}

/// The phone end of the three relays.
///
/// iOS-only: on any other target platform the channel is not registered, so
/// every entry point here falls closed (decisions § 39 — one Dart codebase,
/// platform dispatch inside it). The dispatch reads `defaultTargetPlatform`
/// rather than `Platform.isIOS` so host-run tests can drive the iOS branch,
/// matching `apple_watch_route_bridge.dart`.
class AppleWatchRaceBridge {
  static const MethodChannel _channel = MethodChannel(kAppleWatchRaceChannel);

  /// Push one Arm / Go / End transition to the wrist.
  ///
  /// Auxiliary (L4) and therefore fire-and-forget: unlike the route push,
  /// nobody asked for this one, so an unreachable watch is a log line rather
  /// than something to throw at a caller that is in the middle of a poll. A
  /// failure here can never reach the race session, the recorder, or the row
  /// this phone is about to write.
  static Future<void> relay(WatchRace race) async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return;
    try {
      await _channel.invokeMethod<void>('push', race.toArguments());
    } on MissingPluginException {
      // No native half registered — the phone is not an iPhone build, or the
      // engine attached before the bridge did. Nothing to say.
    } on PlatformException catch (e) {
      debugPrint('[AppleWatchRaceBridge.relay] ${race.status}: ${e.message}');
    }
  }

  /// Start receiving the watch's two outbound payloads.
  ///
  /// [onPing] is fire-and-forget by contract: a ping the phone cannot write is
  /// dropped, never queued, because a stale position is worse than no
  /// position. [onResult] answers `true` only once the finisher time is
  /// accounted for — written, or durably queued — because the native side
  /// re-delivers anything it is told was not.
  static void attach({
    required void Function(WatchRacePing ping) onPing,
    required Future<bool> Function(WatchRaceResult result) onResult,
  }) {
    _channel.setMethodCallHandler((call) async {
      final args = call.arguments;
      final payload = args is Map<Object?, Object?> ? args : null;
      if (payload == null) return false;
      switch (call.method) {
        case 'racePing':
          final ping = WatchRacePing.decode(payload);
          if (ping == null) return false;
          onPing(ping);
          return true;
        case 'raceResult':
          final result = WatchRaceResult.decode(payload);
          // A payload this build cannot read will not become readable on a
          // retry, so it is refused rather than left to be re-delivered on
          // every watch contact for the life of the process.
          if (result == null) return false;
          return onResult(result);
        default:
          return false;
      }
    });
  }

  /// Stop receiving. Paired with [attach] so a disposed controller does not
  /// keep a dead closure wired to the channel.
  static void detach() => _channel.setMethodCallHandler(null);
}

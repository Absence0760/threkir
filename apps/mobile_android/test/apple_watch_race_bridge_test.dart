// Unit tests for `lib/apple_watch_race_bridge.dart` — the phone end of the
// three live-race relays between the iPhone and the Apple Watch.
//
// Everything here is the part that has to be right: which pushes a transition
// owes the wrist (including the End the watch has no timeout for), and the
// fail-closed decode of the two payloads the watch sends back. The transport
// is `WatchIngestBridge.swift`, which no host test can construct.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/apple_watch_race_bridge.dart';

WatchRace _race({
  String eventId = 'event-1',
  String instanceStart = '2026-05-22T18:00:00.000Z',
  String status = 'armed',
  String? eventTitle = 'Thursday 10K',
}) =>
    WatchRace(
      eventId: eventId,
      instanceStart: instanceStart,
      status: status,
      eventTitle: eventTitle,
    );

Map<Object?, Object?> _ping({
  Object? eventId = 'event-1',
  Object? instanceStart = '2026-05-22T18:00:00.000Z',
  Object? lat = 51.5,
  Object? lng = -0.12,
  Object? distanceM = 4321.5,
  Object? elapsedS = 1234,
  Object? bpm,
}) =>
    <Object?, Object?>{
      if (eventId != null) 'race_ping_event_id': eventId,
      if (instanceStart != null) 'race_ping_instance_start': instanceStart,
      if (lat != null) 'race_ping_lat': lat,
      if (lng != null) 'race_ping_lng': lng,
      if (distanceM != null) 'race_ping_distance_m': distanceM,
      if (elapsedS != null) 'race_ping_elapsed_s': elapsedS,
      if (bpm != null) 'race_ping_bpm': bpm,
    };

Map<Object?, Object?> _result({
  Object? eventId = 'event-1',
  Object? instanceStart = '2026-05-22T18:00:00.000Z',
  Object? runId = 'run-1',
  Object? durationS = 3600,
  Object? distanceM = 10000.0,
}) =>
    <Object?, Object?>{
      if (eventId != null) 'race_result_event_id': eventId,
      if (instanceStart != null) 'race_result_instance_start': instanceStart,
      if (runId != null) 'race_result_run_id': runId,
      if (durationS != null) 'race_result_duration_s': durationS,
      if (distanceM != null) 'race_result_distance_m': distanceM,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('appleWatchRacePushes', () {
    test('nothing to nothing pushes nothing', () {
      expect(appleWatchRacePushes(), isEmpty);
    });

    test('arming a race pushes it', () {
      final pushes = appleWatchRacePushes(next: _race());
      expect(pushes, [_race()]);
    });

    test('GO pushes the running state', () {
      final pushes = appleWatchRacePushes(
        previous: _race(),
        next: _race(status: 'running'),
      );
      expect(pushes, [_race(status: 'running')]);
    });

    test('a re-poll of the same state pushes nothing', () {
      // `_refresh` runs every 60 s and on every realtime event. Re-pushing an
      // unchanged state would cost a WCSession transfer and a wrist republish
      // per poll for the length of a race.
      expect(
        appleWatchRacePushes(previous: _race(), next: _race()),
        isEmpty,
      );
    });

    // ── The trap, pinned ────────────────────────────────────────────────
    test('a race that disappears is ENDED explicitly', () {
      // The watch has no timeout on a live race by design (decisions § 1712),
      // so a race that simply stops matching the phone's query leaves
      // `RACE LIVE` on the wrist forever unless an End is pushed for it.
      final pushes = appleWatchRacePushes(previous: _race(status: 'running'));
      expect(pushes, hasLength(1));
      expect(pushes.single.status, 'finished');
      expect(pushes.single.eventId, 'event-1');
      expect(pushes.single.instanceStart, '2026-05-22T18:00:00.000Z');
    });

    test('an armed race that disappears is ended too', () {
      // Cancelled-before-GO is the common shape of this, and it clears the
      // "waiting for GO" banner rather than a live one.
      final pushes = appleWatchRacePushes(previous: _race(status: 'armed'));
      expect(pushes.single.status, 'finished');
    });

    test('swapping races ends the old one before arming the new one', () {
      final pushes = appleWatchRacePushes(
        previous: _race(eventId: 'event-1', status: 'running'),
        next: _race(eventId: 'event-2'),
      );
      expect(pushes.map((p) => (p.eventId, p.status)),
          [('event-1', 'finished'), ('event-2', 'armed')]);
    });

    test('a new INSTANCE of the same event ends the old instance first', () {
      // Instance 1 of a recurring event is a different race from Instance 2 —
      // different `race_sessions` PK, different RSVP row. Without the End the
      // wrist would carry Instance 1's key into Instance 2's pings.
      final pushes = appleWatchRacePushes(
        previous: _race(instanceStart: '2026-05-22T18:00:00.000Z'),
        next: _race(instanceStart: '2026-05-29T18:00:00.000Z'),
      );
      expect(pushes, hasLength(2));
      expect(pushes.first.status, 'finished');
      expect(pushes.first.instanceStart, '2026-05-22T18:00:00.000Z');
      expect(pushes.last.instanceStart, '2026-05-29T18:00:00.000Z');
    });

    test('a previous that was already terminal is not ended twice', () {
      expect(
        appleWatchRacePushes(previous: _race(status: 'finished')),
        isEmpty,
      );
    });
  });

  group('WatchRace.toArguments', () {
    test('carries exactly the keys LiveRace.decode reads', () {
      expect(_race().toArguments(), {
        'race_event_id': 'event-1',
        'race_instance_start': '2026-05-22T18:00:00.000Z',
        'race_status': 'armed',
        'race_event_title': 'Thursday 10K',
      });
    });

    test('omits an absent or blank title rather than sending one', () {
      // The watch banner falls back to the localized word for an event when
      // the key is missing; an empty string would render a blank line.
      expect(_race(eventTitle: null).toArguments().containsKey('race_event_title'),
          isFalse);
      expect(_race(eventTitle: '').toArguments().containsKey('race_event_title'),
          isFalse);
    });
  });

  group('WatchRacePing.decode', () {
    test('reads a full ping', () {
      final ping = WatchRacePing.decode(_ping(bpm: 152))!;
      expect(ping.eventId, 'event-1');
      expect(ping.instanceStart, DateTime.utc(2026, 5, 22, 18));
      expect(ping.lat, 51.5);
      expect(ping.lng, -0.12);
      expect(ping.distanceM, 4321.5);
      expect(ping.elapsedS, 1234);
      expect(ping.bpm, 152);
    });

    test('the optional fields are optional', () {
      final ping = WatchRacePing.decode(
          _ping(distanceM: null, elapsedS: null, bpm: null))!;
      expect(ping.distanceM, isNull);
      expect(ping.elapsedS, isNull);
      expect(ping.bpm, isNull);
    });

    test('a zero bpm is dropped, not written as a measurement', () {
      expect(WatchRacePing.decode(_ping(bpm: 0))!.bpm, isNull);
    });

    test('a missing or mistyped required field drops the whole ping', () {
      for (final bad in <Map<Object?, Object?>>[
        _ping(eventId: null),
        _ping(eventId: ''),
        _ping(eventId: 42),
        _ping(instanceStart: null),
        _ping(instanceStart: ''),
        _ping(instanceStart: 0),
        _ping(lat: null),
        _ping(lng: null),
        _ping(lat: 'north'),
      ]) {
        expect(WatchRacePing.decode(bad), isNull, reason: '$bad');
      }
    });

    test('a non-finite coordinate is refused', () {
      expect(WatchRacePing.decode(_ping(lat: double.nan)), isNull);
      expect(WatchRacePing.decode(_ping(lng: double.infinity)), isNull);
    });

    test('an out-of-range occurrence key is refused, not rolled over', () {
      // `DateTime.tryParse('2026-05-32')` answers the 1st of June, and
      // `instance_start` is the key the spectator map joins on — a rolled
      // date puts the runner's dot on a different race night.
      expect(WatchRacePing.decode(_ping(instanceStart: '2026-05-32T18:00:00Z')),
          isNull);
    });

    test('a negative distance is dropped while the ping still lands', () {
      final ping = WatchRacePing.decode(_ping(distanceM: -5))!;
      expect(ping.distanceM, isNull);
      expect(ping.lat, 51.5);
    });

    test('a race_result payload is not a ping', () {
      expect(WatchRacePing.decode(_result()), isNull);
    });
  });

  group('WatchRaceResult.decode', () {
    test('reads a full result', () {
      final r = WatchRaceResult.decode(_result())!;
      expect(r.eventId, 'event-1');
      expect(r.instanceStart, DateTime.utc(2026, 5, 22, 18));
      expect(r.runId, 'run-1');
      expect(r.durationS, 3600);
      expect(r.distanceM, 10000.0);
    });

    test('every field is required', () {
      for (final bad in <Map<Object?, Object?>>[
        _result(eventId: null),
        _result(eventId: ''),
        _result(instanceStart: null),
        _result(instanceStart: 'yesterday'),
        _result(runId: null),
        _result(runId: ''),
        _result(durationS: null),
        _result(durationS: '3600'),
        _result(durationS: -1),
        _result(distanceM: null),
        _result(distanceM: double.nan),
        _result(distanceM: -1),
      ]) {
        expect(WatchRaceResult.decode(bad), isNull, reason: '$bad');
      }
    });

    test('an out-of-range occurrence key is refused', () {
      expect(
        WatchRaceResult.decode(_result(instanceStart: '2027-02-29T18:00:00Z')),
        isNull,
      );
    });

    test('a race_ping payload is not a result', () {
      expect(WatchRaceResult.decode(_ping()), isNull);
    });
  });

  group('AppleWatchRaceBridge.relay', () {
    final calls = <MethodCall>[];

    setUp(() {
      calls.clear();
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel(kAppleWatchRaceChannel),
              (call) async {
        calls.add(call);
        return null;
      });
    });

    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel(kAppleWatchRaceChannel), null);
    });

    test('sends the push arguments over the channel', () async {
      await AppleWatchRaceBridge.relay(_race(status: 'running'));
      expect(calls.single.method, 'push');
      expect((calls.single.arguments as Map)['race_status'], 'running');
    });

    test('is a no-op on a non-iOS target', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await AppleWatchRaceBridge.relay(_race());
      expect(calls, isEmpty);
    });

    test('a native refusal is swallowed, never thrown at the poll', () async {
      // The relay is L4: it fires from the middle of the session poll, and a
      // watch on a charger in another room must not be able to abort it.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel(kAppleWatchRaceChannel),
              (call) async {
        throw PlatformException(code: 'watch_unavailable');
      });
      await expectLater(AppleWatchRaceBridge.relay(_race()), completes);
    });

    test('a missing native half is swallowed too', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel(kAppleWatchRaceChannel), null);
      await expectLater(AppleWatchRaceBridge.relay(_race()), completes);
    });
  });

  group('AppleWatchRaceBridge.attach', () {
    final pings = <WatchRacePing>[];
    final results = <WatchRaceResult>[];
    var accept = true;

    Future<dynamic> send(String method, Object? arguments) {
      final codec = const StandardMethodCodec();
      return TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            kAppleWatchRaceChannel,
            codec.encodeMethodCall(MethodCall(method, arguments)),
            null,
          )
          .then((data) => data == null ? null : codec.decodeEnvelope(data));
    }

    setUp(() {
      pings.clear();
      results.clear();
      accept = true;
      AppleWatchRaceBridge.attach(
        onPing: pings.add,
        onResult: (r) async {
          results.add(r);
          return accept;
        },
      );
    });

    tearDown(AppleWatchRaceBridge.detach);

    test('a ping reaches the handler', () async {
      expect(await send('racePing', _ping()), isTrue);
      expect(pings.single.eventId, 'event-1');
    });

    test('a result reaches the handler and reports its outcome', () async {
      expect(await send('raceResult', _result()), isTrue);
      expect(results.single.runId, 'run-1');
      accept = false;
      expect(await send('raceResult', _result(runId: 'run-2')), isFalse);
    });

    test('an undecodable payload is refused without calling the handler',
        () async {
      expect(await send('racePing', _ping(lat: null)), isFalse);
      expect(await send('raceResult', _result(runId: '')), isFalse);
      expect(pings, isEmpty);
      expect(results, isEmpty);
    });

    test('an unknown method and a non-map payload are refused', () async {
      expect(await send('raceSomethingElse', _ping()), isFalse);
      expect(await send('racePing', 'not a map'), isFalse);
    });
  });
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:run_recorder/run_recorder.dart';

/// Pins how `RunRecorder(gnssPositions:)` drives the receiver stream it is
/// handed: when the factory is called, at what interval, when the
/// subscription is cancelled, when it may be opened again, and that the fixes
/// it delivers reach source arbitration. The arbitration logic itself is
/// covered through `debugInjectGnssPosition` in run_recorder_test.dart; this
/// file goes through the real factory and the real platform stream instead.

/// Platform stream fake: granted, precise, services on, one broadcast stream.
class _FakeGeolocatorPlatform extends GeolocatorPlatform {
  StreamController<Position>? _positions;
  int subscriptionsOpened = 0;

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.always;

  @override
  Future<LocationPermission> requestPermission() async =>
      LocationPermission.always;

  @override
  Future<LocationAccuracyStatus> getLocationAccuracy() async =>
      LocationAccuracyStatus.precise;

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) {
    subscriptionsOpened++;
    _positions ??= StreamController<Position>.broadcast();
    return _positions!.stream;
  }

  void emit(Position p) {
    _positions ??= StreamController<Position>.broadcast();
    _positions!.add(p);
  }

  Future<void> dispose() async {
    await _positions?.close();
    _positions = null;
  }
}

/// The receiver stream factory the recorder is constructed with. Each call
/// hands out a fresh single-subscription stream, so a cancel is observable
/// and a reopen is a second call.
class _Receiver {
  final List<Duration> openedAt = [];
  final List<StreamController<Position>> streams = [];
  int cancels = 0;
  bool throwOnOpen = false;

  Stream<Position> open(Duration interval) {
    openedAt.add(interval);
    if (throwOnOpen) throw StateError('receiver unavailable');
    final c = StreamController<Position>(onCancel: () => cancels++);
    streams.add(c);
    return c.stream;
  }

  StreamController<Position> get current => streams.last;

  void emit(Position p) => current.add(p);

  Future<void> dispose() async {
    for (final c in streams) {
      await c.close();
    }
  }
}

/// Holds the recorder's arrival clock still, so every receiver fix counts as
/// arriving steadily and a test advances staleness explicitly.
class _FakeClock extends Stopwatch {
  Duration _value = Duration.zero;
  void advance(Duration by) => _value += by;
  @override
  Duration get elapsed => _value;
}

Position _pos({
  required double metresEast,
  required int secondsFromStart,
  double accuracy = 3,
}) {
  const lat = 47.37;
  const lngBase = 8.54;
  const metrePerDegLng = 111320 * 0.6773;
  return Position(
    longitude: lngBase + metresEast / metrePerDegLng,
    latitude: lat,
    timestamp: DateTime(2026, 4, 10, 10, 0, secondsFromStart),
    accuracy: accuracy,
    altitude: 400,
    altitudeAccuracy: 2,
    heading: 90,
    headingAccuracy: 5,
    speed: 2.5,
    speedAccuracy: 1,
  );
}

Future<void> _drain() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeGeolocatorPlatform platform;
  late _Receiver receiver;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    platform = _FakeGeolocatorPlatform();
    GeolocatorPlatform.instance = platform;
    receiver = _Receiver();
  });

  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    await receiver.dispose();
    await platform.dispose();
  });

  group('RunRecorder(gnssPositions:) — opening the receiver stream', () {
    test('prepare opens it once, at the 1 s fix interval, beside the platform '
        'stream', () async {
      final r = RunRecorder(gnssPositions: receiver.open);
      await r.prepare();
      expect(receiver.openedAt, [const Duration(seconds: 1)]);
      expect(receiver.current.hasListener, isTrue);
      expect(platform.subscriptionsOpened, 1);
      r.dispose();
    });

    test(
      'begin and a healthy retry tick leave the open stream alone',
      () async {
        final r = RunRecorder(gnssPositions: receiver.open);
        await r.prepare();
        r.begin();
        // The retry loop ticks every 3 s; wait past one.
        await Future<void>.delayed(const Duration(seconds: 4));
        expect(
          receiver.openedAt,
          hasLength(1),
          reason: 'the retry loop is a repair path, not a second subscriber',
        );
        expect(receiver.cancels, 0);
        r.dispose();
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );

    test('a factory that throws leaves the run recording on the platform '
        'stream', () async {
      receiver.throwOnOpen = true;
      final r = RunRecorder(gnssPositions: receiver.open);
      await r.prepare();
      expect(r.prepared, isTrue);
      r.begin();
      platform.emit(_pos(metresEast: 0, secondsFromStart: 0));
      await _drain();
      platform.emit(_pos(metresEast: 5, secondsFromStart: 2));
      await _drain();
      expect(r.debugTrack, hasLength(2));
      expect(r.locationProvider, 'fused');
      r.dispose();
    });
  });

  group('RunRecorder(gnssPositions:) — closing and reopening', () {
    test('stop cancels the receiver subscription', () async {
      final r = RunRecorder(gnssPositions: receiver.open);
      await r.prepare();
      r.begin();
      await r.stop();
      expect(receiver.cancels, 1);
      expect(receiver.current.hasListener, isFalse);
      r.dispose();
    });

    test('dispose cancels the receiver subscription', () async {
      final r = RunRecorder(gnssPositions: receiver.open);
      await r.prepare();
      r.begin();
      r.dispose();
      expect(receiver.cancels, 1);
      expect(receiver.current.hasListener, isFalse);
    });

    test('a stream error drops it; the retry loop holds off inside the reopen '
        'throttle, and a fresh prepare reopens it at once', () async {
      final r = RunRecorder(gnssPositions: receiver.open);
      await r.prepare();
      r.begin();
      receiver.current.addError(Exception('receiver torn down'));
      await _drain();
      expect(
        receiver.current.hasListener,
        isFalse,
        reason: 'the subscription is cancelled on error',
      );

      // A retry tick lands well inside the 30 s reopen throttle, so a
      // receiver that keeps failing is not reopened every 3 s.
      await Future<void>.delayed(const Duration(seconds: 4));
      expect(receiver.openedAt, hasLength(1));
      expect(
        platform.subscriptionsOpened,
        1,
        reason: 'the healthy platform stream is never reopened',
      );

      // A new session resets the throttle along with source arbitration.
      await r.prepare();
      expect(receiver.openedAt, hasLength(2));
      expect(receiver.current.hasListener, isTrue);
      r.dispose();
    }, timeout: const Timeout(Duration(seconds: 10)));
  });

  group('RunRecorder(gnssPositions:) — its fixes reach arbitration', () {
    test('a steady receiver takes the run and holds the fused stream off until '
        'it goes stale', () async {
      final arrival = _FakeClock();
      final r = RunRecorder(gnssPositions: receiver.open, sourceClock: arrival);
      await r.prepare();
      r.begin();

      // The first two steady fixes only build the streak; the third switches
      // the run onto the receiver and is recorded as its anchor.
      for (var i = 0; i < 3; i++) {
        receiver.emit(_pos(metresEast: 5.0 * i, secondsFromStart: 2 * i));
        await _drain();
      }
      expect(r.debugTrack, hasLength(1));
      receiver.emit(_pos(metresEast: 15, secondsFromStart: 6));
      await _drain();
      expect(r.debugTrack, hasLength(2));
      expect(r.locationProvider, 'gps');

      // A fused fix while the receiver is fresh is dropped.
      platform.emit(_pos(metresEast: 40, secondsFromStart: 7, accuracy: 5));
      await _drain();
      expect(r.debugTrack, hasLength(2));

      // Past the staleness window the fused stream takes the run back.
      arrival.advance(const Duration(seconds: 13));
      platform.emit(_pos(metresEast: 20, secondsFromStart: 8, accuracy: 5));
      await _drain();
      expect(r.debugTrack, hasLength(3));
      expect(r.locationProvider, 'mixed');
      r.dispose();
    });

    test(
      'a receiver fix outside the arbitration gate does not take the run',
      () async {
        final arrival = _FakeClock();
        final r = RunRecorder(
          gnssPositions: receiver.open,
          sourceClock: arrival,
        );
        await r.prepare();
        r.begin();
        for (var i = 0; i < 4; i++) {
          receiver.emit(
            _pos(metresEast: 5.0 * i, secondsFromStart: 2 * i, accuracy: 30),
          );
          await _drain();
        }
        expect(
          r.debugTrack,
          isEmpty,
          reason: 'canopy-grade receiver fixes never switch the source',
        );
        platform.emit(_pos(metresEast: 0, secondsFromStart: 1, accuracy: 5));
        await _drain();
        expect(r.debugTrack, hasLength(1));
        expect(r.locationProvider, 'fused');
        r.dispose();
      },
    );
  });
}

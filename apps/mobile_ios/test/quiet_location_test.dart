import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/quiet_location.dart';

Position _fix(double lat) => Position(
  latitude: lat,
  longitude: -0.1278,
  timestamp: DateTime.utc(2026, 1, 1),
  accuracy: 5,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

/// Records every geolocator call a browse path makes. The settings and
/// accuracy calls are the ones a browse surface must never reach: each is how
/// a screen asks the OS for more than the permission already granted.
class _SpyGeolocator extends GeolocatorPlatform {
  final calls = <String>[];
  LocationSettings? currentSettings;
  bool? lastKnownForcedManager;
  LocationPermission permission = LocationPermission.whileInUse;

  @override
  Future<LocationPermission> checkPermission() async {
    calls.add('checkPermission');
    return permission;
  }

  @override
  Future<LocationPermission> requestPermission() async {
    calls.add('requestPermission');
    return permission;
  }

  @override
  Future<bool> isLocationServiceEnabled() async {
    calls.add('isLocationServiceEnabled');
    return true;
  }

  @override
  Future<bool> openLocationSettings() async {
    calls.add('openLocationSettings');
    return true;
  }

  @override
  Future<LocationAccuracyStatus> getLocationAccuracy() async {
    calls.add('getLocationAccuracy');
    return LocationAccuracyStatus.precise;
  }

  @override
  Future<LocationAccuracyStatus> requestTemporaryFullAccuracy({
    required String purposeKey,
  }) async {
    calls.add('requestTemporaryFullAccuracy');
    return LocationAccuracyStatus.precise;
  }

  @override
  Future<Position?> getLastKnownPosition({
    bool forceLocationManager = false,
  }) async {
    calls.add('getLastKnownPosition');
    lastKnownForcedManager = forceLocationManager;
    return _fix(1);
  }

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async {
    calls.add('getCurrentPosition');
    currentSettings = locationSettings;
    return _fix(2);
  }

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) {
    calls.add('getPositionStream');
    return const Stream.empty();
  }
}

const _upgradeCalls = [
  'isLocationServiceEnabled',
  'openLocationSettings',
  'getLocationAccuracy',
  'requestTemporaryFullAccuracy',
  'getPositionStream',
];

void _expectBrowseSettings(LocationSettings? s) {
  expect(s, isA<AndroidSettings>(),
      reason: 'an Android browse read must name its own settings');
  final android = s! as AndroidSettings;
  expect(android.forceLocationManager, isTrue,
      reason: 'the fused client raises the Location Accuracy dialog');
  expect(android.accuracy, LocationAccuracy.medium);
}

void main() {
  group('browse intent through the platform', () {
    late GeolocatorPlatform original;
    late _SpyGeolocator spy;

    setUp(() {
      original = GeolocatorPlatform.instance;
      spy = _SpyGeolocator();
      GeolocatorPlatform.instance = spy;
    });

    tearDown(() => GeolocatorPlatform.instance = original);

    test('quietPositionFixes never asks for services or accuracy', () async {
      final fixes = await quietPositionFixes().toList();
      expect(fixes.map((p) => p.latitude), [1, 2]);
      expect(spy.calls, [
        'checkPermission',
        'getLastKnownPosition',
        'getCurrentPosition',
      ]);
      for (final c in _upgradeCalls) {
        expect(spy.calls, isNot(contains(c)));
      }
      expect(spy.lastKnownForcedManager, isTrue);
      _expectBrowseSettings(spy.currentSettings);
    });

    test('locateForBrowse never asks for services or accuracy', () async {
      final pos = await locateForBrowse();
      expect(pos.latitude, 2);
      expect(spy.calls, ['checkPermission', 'getCurrentPosition']);
      _expectBrowseSettings(spy.currentSettings);
    });

    test('locateForBrowse asks for an unanswered permission only', () async {
      spy.permission = LocationPermission.denied;
      await expectLater(
          locateForBrowse(), throwsA(isA<PermissionDeniedException>()));
      expect(spy.calls, ['checkPermission', 'requestPermission']);
    });
  });

  group('browseLocationSettings', () {
    test('Android reads through LocationManager at balanced accuracy', () {
      _expectBrowseSettings(browseLocationSettings(
        platform: TargetPlatform.android,
        timeLimit: const Duration(seconds: 3),
      ));
      expect(
        browseLocationSettings(platform: TargetPlatform.android).timeLimit,
        isNull,
      );
    });

    test('iOS asks for balanced accuracy, never best', () {
      final s = browseLocationSettings(platform: TargetPlatform.iOS);
      expect(s, isNot(isA<AndroidSettings>()));
      expect(s.accuracy, LocationAccuracy.medium);
    });
  });

  group('locateForBrowse', () {
    Future<Position> locate({
      LocationPermission perm = LocationPermission.whileInUse,
      Future<Position?> Function()? lastKnown,
      required Future<Position> Function() current,
      Duration timeout = const Duration(seconds: 10),
    }) =>
        locateForBrowse(
          timeout: timeout,
          checkPermission: () async => perm,
          requestPermission: () async => perm,
          lastKnown: lastKnown ?? () async => null,
          currentPosition: current,
        );

    test('a refused permission throws PermissionDeniedException', () async {
      for (final perm in [
        LocationPermission.denied,
        LocationPermission.deniedForever,
      ]) {
        await expectLater(
          locate(perm: perm, current: () async => _fix(2)),
          throwsA(isA<PermissionDeniedException>()),
        );
      }
    });

    test('a failed fresh read falls back to the cached fix', () async {
      final pos = await locate(
        lastKnown: () async => _fix(1),
        current: () async => throw const LocationServiceDisabledException(),
      );
      expect(pos.latitude, 1);
    });

    test('a timed-out fresh read falls back to the cached fix', () async {
      final pos = await locate(
        timeout: const Duration(milliseconds: 10),
        lastKnown: () async => _fix(1),
        current: () => Completer<Position>().future,
      );
      expect(pos.latitude, 1);
    });

    test('with no cached fix the fresh read error reaches the caller',
        () async {
      await expectLater(
        locate(
          lastKnown: () async => throw StateError('no plugin'),
          current: () async => throw const LocationServiceDisabledException(),
        ),
        throwsA(isA<LocationServiceDisabledException>()),
      );
    });
  });

  group('browseLocateErrorText', () {
    final l10n = lookupAppLocalizations(const Locale('en'));

    test('names the reason a Locate tap failed', () {
      expect(
          browseLocateErrorText(
              l10n, const PermissionDeniedException('denied')),
          'location permission is off');
      expect(
          browseLocateErrorText(l10n, const LocationServiceDisabledException()),
          'location is turned off on this device');
      expect(browseLocateErrorText(l10n, TimeoutException('fix')),
          'no position yet, try again in a moment');
    });

    test('anything else reads as the generic error, never the raw text', () {
      final text = browseLocateErrorText(l10n, StateError('plugin internals'));
      expect(text, l10n.authErrorGeneric);
      expect(text, isNot(contains('plugin internals')));
    });
  });

  group('only the recorder may ask for more than a browse fix', () {
    // RunRecorder (packages/run_recorder) owns the record intent. In this app,
    // a settings or accuracy request is allowed only where the run screen
    // offers the runner a Location settings button, and where START checks,
    // as RunRecorder.prepare does, that a GPS run can get a fix at all.
    // course_drive_location.dart is the third named intent, driving a
    // course (docs/features/course_drive.md gotcha 7): a background stream
    // with no recorder behind it. line_calibration_screen.dart is the fourth:
    // the debug-build-only #1304 tool centres the line under test on one
    // full-accuracy fix, the opposite of a browse read (decisions § 2453).
    // pre_run_status.dart is the recorder's own idle page saying, before
    // START, whether a GPS run can get a fix and how good it is. Its fixes
    // force LocationManager, so it never raises the Accuracy dialog either.
    const allowed = {
      'lib/screens/run_screen.dart': {
        'openLocationSettings',
        'isLocationServiceEnabled',
      },
      'lib/pre_run_status.dart': {
        'isLocationServiceEnabled',
        'openLocationSettings',
        'getLocationAccuracy',
        'getPositionStream',
        'getLastKnownPosition',
      },
      'lib/course_drive_location.dart': {'getPositionStream'},
      'lib/screens/line_calibration_screen.dart': {'getCurrentPosition'},
    };
    final forbidden = RegExp(
        r'\b(isLocationServiceEnabled|openLocationSettings|getLocationAccuracy|'
        r'requestTemporaryFullAccuracy|getPositionStream|getCurrentPosition|'
        r'getLastKnownPosition)\s*\(');

    test('no file in lib/ reaches past the browse helper', () {
      final offenders = <String>[];
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final path = f.path.replaceAll(r'\', '/');
        if (path == 'lib/quiet_location.dart') continue;
        final src = f.readAsStringSync();
        for (final m in forbidden.allMatches(src)) {
          final line = src.substring(0, m.start).split('\n').last.trimLeft();
          if (line.startsWith('//')) continue;
          if (allowed[path]?.contains(m.group(1)) ?? false) continue;
          offenders.add('$path: ${m.group(1)}');
        }
      }
      expect(offenders, isEmpty,
          reason: 'read a position through quiet_location.dart '
              '(quietPositionFixes / locateForBrowse) so a browse screen '
              'cannot raise the Location Accuracy dialog');
    });

    test('the browse helper reads every fresh fix with browse settings', () {
      final src = File('lib/quiet_location.dart').readAsStringSync();
      for (final c in [
        'isLocationServiceEnabled(',
        'openLocationSettings(',
        'getLocationAccuracy(',
        'requestTemporaryFullAccuracy(',
        'getPositionStream(',
        'LocationAccuracy.high',
        'LocationAccuracy.best',
      ]) {
        expect(src, isNot(contains(c)), reason: c);
      }
      expect(
        RegExp(r'getCurrentPosition\(\s*locationSettings:\s*'
                r'browseLocationSettings\(\)')
            .allMatches(src)
            .length,
        RegExp(r'getCurrentPosition\(').allMatches(src).length,
      );
    });
  });

  group('quietPositionFixes', () {
    for (final perm in [
      LocationPermission.denied,
      LocationPermission.deniedForever,
      LocationPermission.unableToDetermine,
    ]) {
      test('$perm yields nothing and never reads a position', () async {
        var reads = 0;
        final fixes = await quietPositionFixes(
          checkPermission: () async => perm,
          lastKnown: () async {
            reads++;
            return _fix(1);
          },
          currentPosition: () async {
            reads++;
            return _fix(2);
          },
        ).toList();
        expect(fixes, isEmpty);
        expect(reads, 0);
      });
    }

    for (final perm in [
      LocationPermission.whileInUse,
      LocationPermission.always,
    ]) {
      test('$perm yields the last-known fix, then the current one', () async {
        final fixes = await quietPositionFixes(
          checkPermission: () async => perm,
          lastKnown: () async => _fix(1),
          currentPosition: () async => _fix(2),
        ).toList();
        expect(fixes.map((p) => p.latitude), [1, 2]);
      });
    }

    test('no last-known fix yields only the current one', () async {
      final fixes = await quietPositionFixes(
        checkPermission: () async => LocationPermission.whileInUse,
        lastKnown: () async => null,
        currentPosition: () async => _fix(2),
      ).toList();
      expect(fixes.map((p) => p.latitude), [2]);
    });

    test(
      'a current fix that times out ends the stream after the last-known',
      () async {
        final never = Completer<Position>();
        final fixes = await quietPositionFixes(
          timeout: const Duration(milliseconds: 10),
          checkPermission: () async => LocationPermission.whileInUse,
          lastKnown: () async => _fix(1),
          currentPosition: () => never.future,
        ).toList();
        expect(fixes.map((p) => p.latitude), [1]);
      },
    );

    test(
      'a throwing permission check ends the stream without an error',
      () async {
        final fixes = await quietPositionFixes(
          checkPermission: () async =>
              throw const LocationServiceDisabledException(),
          lastKnown: () async => _fix(1),
          currentPosition: () async => _fix(2),
        ).toList();
        expect(fixes, isEmpty);
      },
    );

    test(
      'a throwing current fix keeps the last-known and ends quietly',
      () async {
        final fixes = await quietPositionFixes(
          checkPermission: () async => LocationPermission.always,
          lastKnown: () async => _fix(1),
          currentPosition: () async => throw StateError('no plugin'),
        ).toList();
        expect(fixes.map((p) => p.latitude), [1]);
      },
    );

    test('never requests permission', () {
      final src = File('lib/quiet_location.dart').readAsStringSync();
      final body = src.substring(
        src.indexOf('Stream<Position> quietPositionFixes('),
        src.indexOf('Future<Position> locateForBrowse('),
      );
      expect(body, isNot(contains('requestPermission')),
          reason: 'only a Locate tap (locateForBrowse) may ask');
    });
  });
}

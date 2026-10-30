import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

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

void main() {
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
      expect(src, isNot(contains('requestPermission')));
    });
  });
}

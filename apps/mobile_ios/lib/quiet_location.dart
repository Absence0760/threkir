import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// The fixes a map screen centres itself on when it opens: the cached
/// last-known position first, so the camera lands on the runner without
/// waiting, then a fresh fix within [timeout].
///
/// Quiet on purpose. It never asks for permission — a prompt the runner did
/// not tap for is a surprise, and every map screen keeps a Locate button that
/// does ask. With permission withheld, location services off, no plugin (the
/// web build, a widget test) or a fix that times out, the stream simply ends
/// early, and the screen keeps whatever centre it opened on.
///
/// [checkPermission], [lastKnown] and [currentPosition] default to
/// Geolocator; tests pass fakes.
Stream<Position> quietPositionFixes({
  Duration timeout = const Duration(seconds: 5),
  Future<LocationPermission> Function() checkPermission =
      Geolocator.checkPermission,
  Future<Position?> Function() lastKnown = _lastKnownPosition,
  Future<Position> Function() currentPosition = _currentPosition,
}) async* {
  if (kIsWeb) return;
  try {
    final perm = await checkPermission();
    if (perm != LocationPermission.always &&
        perm != LocationPermission.whileInUse) {
      return;
    }
    final last = await lastKnown();
    if (last != null) yield last;
    yield await currentPosition().timeout(timeout);
  } catch (e) {
    debugPrint('quiet location fix unavailable: $e');
  }
}

Future<Position?> _lastKnownPosition() => Geolocator.getLastKnownPosition();

Future<Position> _currentPosition() => Geolocator.getCurrentPosition();

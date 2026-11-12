import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'auth_error.dart';
import 'l10n/gen/app_localizations.dart';

/// Location for **browsing**: centring a map, a Locate button, "routes near
/// me". The one place a screen outside the run recorder reads a position.
///
/// The other intent, **recording**, belongs to `RunRecorder` alone (the
/// run_recorder package). It checks that location services are on, asks for
/// high accuracy and iOS temporary full accuracy, and lets Android's fused
/// provider raise Google's "Location Accuracy" resolution dialog, because GPS
/// quality decides how good a track is.
///
/// A browse fix needs none of that. On Android, geolocator's fused client
/// runs `SettingsClient.checkLocationSettings` before every
/// `getCurrentPosition` and starts the resolution dialog when it fails, at any
/// accuracy, so a phone with Google Location Accuracy switched off was asked
/// to turn it on just for opening the routes map. Browse requests go through
/// `LocationManager` instead ([AndroidSettings.forceLocationManager]), which
/// never shows that dialog: a fix comes from whatever provider the device
/// already has on, or the request fails and the screen keeps the view it had.
///
/// Nothing here calls `isLocationServiceEnabled`, `openLocationSettings`,
/// `getLocationAccuracy` or `requestTemporaryFullAccuracy`;
/// `test/quiet_location_test.dart` fails if this file or any other file in
/// `lib/` grows one of those calls or reads a position without
/// [browseLocationSettings].
LocationSettings browseLocationSettings({
  Duration? timeLimit,
  TargetPlatform? platform,
}) {
  if ((platform ?? defaultTargetPlatform) == TargetPlatform.android) {
    return AndroidSettings(
      accuracy: LocationAccuracy.medium,
      forceLocationManager: true,
      timeLimit: timeLimit,
    );
  }
  return LocationSettings(
    accuracy: LocationAccuracy.medium,
    timeLimit: timeLimit,
  );
}

/// The fixes a map screen centres itself on when it opens: the cached
/// last-known position first, so the camera lands on the runner without
/// waiting, then a fresh browse fix within [timeout].
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
    if (!_granted(perm)) return;
    final last = await lastKnown();
    if (last != null) yield last;
    yield await currentPosition().timeout(timeout);
  } catch (e) {
    debugPrint('quiet location fix unavailable: $e');
  }
}

/// One browse fix for a runner who tapped Locate (or "near me"): asks for
/// permission when it has never been answered, then reads a fresh fix within
/// [timeout], falling back to the cached last-known one when the fresh read
/// fails or runs out of time.
///
/// Throws [PermissionDeniedException] when permission is refused, and
/// rethrows the fresh read's error when there is no cached fix either, so the
/// caller can say why it could not centre. It never asks for location
/// services or a higher accuracy, for the reason [browseLocationSettings]
/// gives.
Future<Position> locateForBrowse({
  Duration timeout = const Duration(seconds: 10),
  Future<LocationPermission> Function() checkPermission =
      Geolocator.checkPermission,
  Future<LocationPermission> Function() requestPermission =
      Geolocator.requestPermission,
  Future<Position?> Function() lastKnown = _lastKnownPosition,
  Future<Position> Function() currentPosition = _currentPosition,
}) async {
  if (kIsWeb) throw UnsupportedError('Locate unavailable on web');
  var perm = await checkPermission();
  if (perm == LocationPermission.denied) perm = await requestPermission();
  if (!_granted(perm)) {
    throw PermissionDeniedException(
      perm == LocationPermission.deniedForever
          ? 'Location permission denied forever'
          : 'Location permission denied',
    );
  }
  try {
    return await currentPosition().timeout(timeout);
  } catch (e, st) {
    Position? last;
    try {
      last = await lastKnown();
    } catch (cached) {
      debugPrint('browse locate: no cached fix either: $cached');
    }
    if (last != null) return last;
    Error.throwWithStackTrace(e, st);
  }
}

/// Why a [locateForBrowse] call failed, for the "Location unavailable:
/// {error}" banners: refused permission, location switched off and no fix in
/// time each say so, anything else reads as [friendlyError]. Never the raw
/// exception text, which is English and names plugin internals.
String browseLocateErrorText(AppLocalizations l10n, Object error) {
  if (error is PermissionDeniedException) {
    return l10n.locationErrorPermissionDenied;
  }
  if (error is LocationServiceDisabledException) {
    return l10n.locationErrorServicesOff;
  }
  if (error is TimeoutException) return l10n.locationErrorNoFix;
  return friendlyError(l10n, error);
}

bool _granted(LocationPermission perm) =>
    perm == LocationPermission.always || perm == LocationPermission.whileInUse;

Future<Position?> _lastKnownPosition() =>
    Geolocator.getLastKnownPosition(forceAndroidLocationManager: true);

Future<Position> _currentPosition() =>
    Geolocator.getCurrentPosition(locationSettings: browseLocationSettings());

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:run_recorder/run_recorder.dart' show kDefaultAccuracyGateMetres;

/// What the idle Run page can say about GPS before a run starts.
///
/// The three blocked states are the ones START would otherwise discover in a
/// dialog (`_confirmStartWithoutGps` in run_screen.dart); the other three
/// grade the fixes the page is already receiving against the recorder's own
/// accuracy gate, so "ready" means fixes the recorder will keep.
enum PreRunGps {
  servicesOff,
  permissionNeeded,
  permissionBlocked,
  searching,
  weak,
  ready,
}

/// How old the newest fix may be before the page stops calling it current.
/// The recorder raises its GPS-lost banner at the same age
/// (`_gpsLostThreshold`, run_recording.md hardening row 2).
const Duration kPreRunFixMaxAge = Duration(seconds: 10);

/// The GPS state for [servicesOn], [permission] and the newest fix's
/// [accuracyM] received [fixAge] ago. A null input is one the page could not
/// read (no plugin, a platform error), which never reads as a block: START
/// still makes its own checks.
PreRunGps resolvePreRunGps({
  required bool? servicesOn,
  required LocationPermission? permission,
  required double? accuracyM,
  required Duration? fixAge,
  double gateMetres = kDefaultAccuracyGateMetres,
}) {
  if (servicesOn == false) return PreRunGps.servicesOff;
  if (permission == LocationPermission.denied) {
    return PreRunGps.permissionNeeded;
  }
  if (permission == LocationPermission.deniedForever) {
    return PreRunGps.permissionBlocked;
  }
  if (accuracyM == null || fixAge == null || fixAge > kPreRunFixMaxAge) {
    return PreRunGps.searching;
  }
  return accuracyM <= gateMetres ? PreRunGps.ready : PreRunGps.weak;
}

/// Whether the page should be listening for fixes in [gps].
bool preRunWantsFixes(PreRunGps gps) => switch (gps) {
      PreRunGps.servicesOff ||
      PreRunGps.permissionNeeded ||
      PreRunGps.permissionBlocked =>
        false,
      _ => true,
    };

/// A permission the recording leans on beyond location, and what its absence
/// costs. Android only: iOS asks for motion on first use and routes the run's
/// lock-screen surface through a Live Activity rather than a notification.
enum PreRunExtra { activityRecognition, notifications }

/// What to offer for a missing [PreRunExtra]: the system prompt while Android
/// will still show one, the app's settings page once it will not.
enum PreRunRemedy { request, openSettings }

/// The remedy for [status], or null when nothing is missing. An unread status
/// (null) is not reported: the page only says what it knows.
PreRunRemedy? preRunRemedy(ph.PermissionStatus? status) => switch (status) {
      ph.PermissionStatus.denied => PreRunRemedy.request,
      ph.PermissionStatus.permanentlyDenied ||
      ph.PermissionStatus.restricted =>
        PreRunRemedy.openSettings,
      _ => null,
    };

/// The platform calls the idle Run page makes. Tests pass a fake.
abstract class PreRunProbe {
  Future<bool> locationServiceEnabled();
  Future<LocationPermission> locationPermission();
  Future<LocationPermission> requestLocationPermission();

  /// False when the grant is approximate only.
  Future<bool> preciseLocation();

  Future<Position?> lastKnownPosition();
  Stream<Position> positions();

  /// Null on a platform where [extra] is not something the page reports.
  Future<ph.PermissionStatus?> extraStatus(PreRunExtra extra);
  Future<ph.PermissionStatus> requestExtra(PreRunExtra extra);

  Future<void> openLocationSettings();
  Future<void> openAppSettings();
}

/// The real probe.
///
/// Its fixes come through Android's `LocationManager`
/// ([AndroidSettings.forceLocationManager]) at high accuracy, never the fused
/// client, which raises Google's Location Accuracy dialog on a request the
/// runner did not tap for (quiet_location.dart). On Android 12+ that is still
/// the fused provider's estimate (run_recording.md, *Why not
/// `forceLocationManager`*), so the accuracy shown is the one the recorder's
/// own fused stream reports. START still hands recording to `RunRecorder`,
/// which may raise the dialog, and which opens its own stream only after this
/// one is closed (`_newRecorder` in run_screen.dart).
class PlatformPreRunProbe implements PreRunProbe {
  const PlatformPreRunProbe();

  bool get _android => defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<bool> locationServiceEnabled() =>
      Geolocator.isLocationServiceEnabled();

  @override
  Future<LocationPermission> locationPermission() =>
      Geolocator.checkPermission();

  @override
  Future<LocationPermission> requestLocationPermission() =>
      Geolocator.requestPermission();

  @override
  Future<bool> preciseLocation() async =>
      await Geolocator.getLocationAccuracy() != LocationAccuracyStatus.reduced;

  @override
  Future<Position?> lastKnownPosition() =>
      Geolocator.getLastKnownPosition(forceAndroidLocationManager: true);

  @override
  Stream<Position> positions() => Geolocator.getPositionStream(
        locationSettings: _android
            ? AndroidSettings(
                accuracy: LocationAccuracy.high,
                forceLocationManager: true,
                intervalDuration: const Duration(seconds: 1),
              )
            : const LocationSettings(accuracy: LocationAccuracy.high),
      );

  ph.Permission _permission(PreRunExtra extra) => switch (extra) {
        PreRunExtra.activityRecognition => ph.Permission.activityRecognition,
        PreRunExtra.notifications => ph.Permission.notification,
      };

  @override
  Future<ph.PermissionStatus?> extraStatus(PreRunExtra extra) async =>
      _android ? await _permission(extra).status : null;

  @override
  Future<ph.PermissionStatus> requestExtra(PreRunExtra extra) =>
      _permission(extra).request();

  @override
  Future<void> openLocationSettings() async {
    await Geolocator.openLocationSettings();
  }

  @override
  Future<void> openAppSettings() async {
    await ph.openAppSettings();
  }
}

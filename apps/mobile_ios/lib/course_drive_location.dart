import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Location for **driving a course** (docs/features/course_drive.md, gotcha
/// 7): the third named location intent, beside browse (`quiet_location.dart`)
/// and record (`RunRecorder`). It needs what browse refuses — fixes every
/// second with the screen locked — and none of what record owns: no track,
/// no recorder, nothing written.
///
/// Android promotes geolocator's service to the same typed foreground
/// service the recorder uses, so the stream survives the screen locking
/// while Google Maps is in front. iOS keeps updating in the background (the
/// app declares the `location` + `audio` modes) with the automotive activity
/// type.
LocationSettings driveLocationSettings({
  required String notificationTitle,
  required String notificationText,
  TargetPlatform? platform,
}) {
  if ((platform ?? defaultTargetPlatform) == TargetPlatform.iOS) {
    return AppleSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      activityType: ActivityType.automotiveNavigation,
      distanceFilter: 0,
      pauseLocationUpdatesAutomatically: false,
      showBackgroundLocationIndicator: true,
      allowBackgroundLocationUpdates: true,
    );
  }
  return AndroidSettings(
    accuracy: LocationAccuracy.high,
    intervalDuration: const Duration(seconds: 1),
    distanceFilter: 0,
    foregroundNotificationConfig: ForegroundNotificationConfig(
      notificationTitle: notificationTitle,
      notificationText: notificationText,
      enableWakeLock: true,
      notificationIcon: const AndroidResource(
        name: 'ic_launcher',
        defType: 'mipmap',
      ),
    ),
  );
}

typedef DrivePosition = ({double lat, double lng, DateTime at});

/// The drive's position stream.
Stream<DrivePosition> drivePositions({
  required String notificationTitle,
  required String notificationText,
}) => Geolocator.getPositionStream(
  locationSettings: driveLocationSettings(
    notificationTitle: notificationTitle,
    notificationText: notificationText,
  ),
).map((p) => (lat: p.latitude, lng: p.longitude, at: p.timestamp));

/// Asks for location when it has not been answered yet, and says whether
/// the drive may follow the phone. Called from the Start tap, so the prompt
/// is one the driver asked for.
Future<bool> ensureDriveLocationPermission() async {
  try {
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
    }
    return p == LocationPermission.whileInUse || p == LocationPermission.always;
  } catch (e) {
    debugPrint('course drive: location permission check failed: $e');
    return false;
  }
}

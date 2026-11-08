import 'package:core_models/core_models.dart' show Waypoint;
import 'package:flutter/foundation.dart';

import 'course_drive.dart';
import 'routing.dart';

/// Which stretches of the course a Maps app will not follow
/// (docs/features/course_drive.md, gotcha 4): each nine-stop leg is routed
/// through OSRM's `car` profile and the joined line is compared with the
/// course. Null when any leg failed to route, so the screen says it could not
/// check rather than implying the course is drivable. Mirrors web's
/// `routes/course_drive_check.ts`.
Future<List<CourseStretch>?> checkDrivable(
  List<DrivePoint> line, {
  OsrmFetcher? fetcher,
}) async {
  final legs = planDriveLegs(line, kMapsWaypointCapGoogle);
  if (legs.isEmpty) return null;
  final routed = <DrivePoint>[];
  for (final leg in legs) {
    final stops = [
      for (final s in [leg.start, ...leg.via, leg.end])
        Waypoint(lat: s.lat, lng: s.lng),
    ];
    try {
      final r = await fetchRouteThrough(
        stops,
        profile: OsrmProfile.car,
        fetcher: fetcher,
      );
      if (r.wasCancelled || r.okSegments < r.totalSegments) return null;
      routed.addAll([for (final w in r.coordinates) DrivePoint(w.lat, w.lng)]);
    } catch (e) {
      debugPrint('course drive check failed: $e');
      return null;
    }
  }
  return undrivableStretches(line, routed);
}

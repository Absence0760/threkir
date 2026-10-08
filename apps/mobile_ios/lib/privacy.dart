import 'run_stats.dart' show haversineMetres;

/// Pure Dart port of `apps/web/src/lib/routes/privacy.ts` (decisions §33).
/// Geofences clipped from the start and end of a track before it
/// renders on any public surface. Non-owner clipping happens server-side via
/// the `clip_track_for_user` RPC; this is the client copy of the same rule,
/// for what the owner's own device publishes (the share image).

class PrivacyZone {
  final double lat;
  final double lng;
  final double radiusM;
  const PrivacyZone({
    required this.lat,
    required this.lng,
    required this.radiusM,
  });

  factory PrivacyZone.fromJson(Map<String, dynamic> json) => PrivacyZone(
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        radiusM: (json['radius_m'] as num).toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lng': lng,
        'radius_m': radiusM,
      };
}

/// Settings-bag key matching web's `PRIVACY_ZONES_KEY`.
const String privacyZonesKey = 'privacy_zones';

/// True when [point] is within the radius of any of [zones].
bool isInAnyZone(double lat, double lng, List<PrivacyZone> zones) {
  for (final z in zones) {
    if (haversineMetres(lat, lng, z.lat, z.lng) <= z.radiusM) return true;
  }
  return false;
}

/// True when either position a stored fix carries is inside a zone: the raw
/// [lat] / [lng], or the GPS smoother's [smoothedLat] / [smoothedLng] when
/// both halves are finite. The run line draws the smoothed position, and the
/// smoother can pull a fix just outside the edge to just inside it, so a raw
/// test alone would let a drawn endpoint sit in the zone. Mirrors
/// `isFixInAnyZone` in `privacy.ts` and the end-walk predicate of
/// `clip_track_for_user` (migration 20270719000005).
bool isFixInAnyZone(
  double lat,
  double lng,
  double? smoothedLat,
  double? smoothedLng,
  List<PrivacyZone> zones,
) {
  if (isInAnyZone(lat, lng, zones)) return true;
  return smoothedLat != null &&
      smoothedLng != null &&
      smoothedLat.isFinite &&
      smoothedLng.isFinite &&
      isInAnyZone(smoothedLat, smoothedLng, zones);
}

/// Walk forward from index 0 and drop fixes in any zone; walk backward from
/// the end with the same predicate; keep the contiguous middle. A fix is in a
/// zone when its raw OR its smoothed position is ([isFixInAnyZone]), the rule
/// the server's `clip_track_for_user` applies for non-owners, so an image the
/// owner exports carries the same trimmed line a stranger is served. The
/// smoothed accessors are required, not defaulted, so no caller can drop the
/// smoothed half of the test by omission; pass `(_) => null` for a point type
/// that has none. Mirrors `clipPointsToZones` in `privacy.ts`.
List<T> clipPointsToZones<T>(
  List<T> points,
  List<PrivacyZone> zones, {
  required double Function(T) latOf,
  required double Function(T) lngOf,
  required double? Function(T) smoothedLatOf,
  required double? Function(T) smoothedLngOf,
}) {
  if (zones.isEmpty || points.isEmpty) return points;
  bool inZone(T p) =>
      isFixInAnyZone(latOf(p), lngOf(p), smoothedLatOf(p), smoothedLngOf(p),
          zones);
  var start = 0;
  while (start < points.length && inZone(points[start])) {
    start++;
  }
  if (start >= points.length) return const [];
  var end = points.length - 1;
  while (end > start && inZone(points[end])) {
    end--;
  }
  return points.sublist(start, end + 1);
}

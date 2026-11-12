import 'dart:math';

import 'package:latlong2/latlong.dart';

import '../official_distance.dart' show courseDistanceScale;
import '../run_stats.dart' show haversineMetres;

/// A km / mile boundary along a recorded track. The map renders a small
/// circular pin with [label] inside (1, 2, 3 …).
class DistanceMarker {
  final LatLng position;
  final int label;
  const DistanceMarker(this.position, this.label);
}

/// A direction arrow placed along the track. [angleRadians] is the
/// bearing of the local track segment (atan2 of `dy / dx` in lat/lng
/// units). The map rotates a chevron icon by this angle.
class TrackChevron {
  final LatLng position;
  final double angleRadians;
  const TrackChevron(this.position, this.angleRadians);
}

const double _metresPerMile = 1609.344;

/// The `LatLng` door onto the shared `haversineMetres`, not a second formula.
double _haversineMetres(LatLng a, LatLng b) =>
    haversineMetres(a.latitude, a.longitude, b.latitude, b.longitude);

/// Walk the polyline and emit a [DistanceMarker] at every kilometre (or
/// mile when [useMiles] is true) boundary. Mirrors `computeDistanceMarkers`
/// in `apps/web/src/lib/runs/distance_markers.ts`.
///
/// When the authoritative [totalDistanceM] is meaningfully greater than
/// the polyline length (sparse user clicks / seed data), every marker's
/// *along-the-polyline* position is scaled by `polyline / real` so the
/// marker count reflects the real distance even though the rendered
/// geometry is a coarse approximation. A route's [officialDistanceM] wins
/// over both, short or long, so km 42 of a traced marathon sits where the
/// race's sign does (`courseDistanceScale`). Markers at index 0 (covered by
/// the green start cap) are skipped.
List<DistanceMarker> computeDistanceMarkers(
  List<LatLng> coords, {
  required bool useMiles,
  double? totalDistanceM,
  double? officialDistanceM,
}) {
  final out = <DistanceMarker>[];
  if (coords.length < 2) return out;
  final stepM = useMiles ? _metresPerMile : 1000.0;

  double polylineTotal = 0;
  for (int i = 1; i < coords.length; i++) {
    polylineTotal += _haversineMetres(coords[i - 1], coords[i]);
  }

  final realTotal =
      (totalDistanceM != null && totalDistanceM > polylineTotal * 1.1)
      ? totalDistanceM
      : polylineTotal;
  final scale = officialDistanceM != null && officialDistanceM > 0
      ? 1 / courseDistanceScale(polylineTotal, officialDistanceM)
      : polylineTotal > 0
      ? polylineTotal / realTotal
      : 1.0;

  double cumulative = 0;
  double nextMarker = stepM * scale;
  final maxAlongPolyline = polylineTotal;
  for (int i = 1; i < coords.length; i++) {
    final segmentM = _haversineMetres(coords[i - 1], coords[i]);
    while (cumulative + segmentM >= nextMarker &&
        segmentM > 0 &&
        nextMarker <= maxAlongPolyline + 0.5) {
      final t = (nextMarker - cumulative) / segmentM;
      final lat =
          coords[i - 1].latitude +
          (coords[i].latitude - coords[i - 1].latitude) * t;
      final lng =
          coords[i - 1].longitude +
          (coords[i].longitude - coords[i - 1].longitude) * t;
      final realPos = nextMarker / scale;
      final label = (realPos / stepM).round();
      out.add(DistanceMarker(LatLng(lat, lng), label));
      nextMarker += stepM * scale;
    }
    cumulative += segmentM;
  }
  return out;
}

/// Which km / mile badges survive when the map is too zoomed out to show
/// them all: every 10th first, then every 5th, then the even ones, then the
/// rest. Lower ranks are placed first. Mirrors `distanceMarkerRank` in
/// `apps/web/src/lib/runs/distance_markers.ts`.
int distanceMarkerRank(int label) {
  if (label % 10 == 0) return 0;
  if (label % 5 == 0) return 1;
  if (label % 2 == 0) return 2;
  return 3;
}

/// Screen distance, in logical pixels, two km / mile badges must keep: the
/// 26 px pin plus a hair.
const double distanceMarkerGapPx = 28;

/// The badges that fit at map [zoom] without touching, placed best rank
/// first. flutter_map has no collision pass, so this is the phone's
/// counterpart of the web layer's `symbol-sort-key` + collision: a marathon
/// zoomed to fit, or both legs of an out-and-back, otherwise stack every
/// badge on the next. The spacing is measured in Web Mercator world pixels,
/// which depend on zoom alone, so a pan never changes the answer. Returned
/// in the input order.
List<DistanceMarker> thinDistanceMarkers(
  List<DistanceMarker> markers, {
  required double zoom,
  double minGapPx = distanceMarkerGapPx,
}) {
  final worldPx = 256 * pow(2, zoom).toDouble();
  Point<double> project(LatLng p) {
    final sinLat = sin(p.latitude * pi / 180).clamp(-0.9999, 0.9999);
    return Point(
      (p.longitude + 180) / 360 * worldPx,
      (0.5 - log((1 + sinLat) / (1 - sinLat)) / (4 * pi)) * worldPx,
    );
  }

  final order = List<int>.generate(markers.length, (i) => i)
    ..sort((a, b) {
      final byRank = distanceMarkerRank(
        markers[a].label,
      ).compareTo(distanceMarkerRank(markers[b].label));
      return byRank != 0
          ? byRank
          : markers[a].label.compareTo(markers[b].label);
    });
  final placed = <Point<double>>[];
  final keep = List<bool>.filled(markers.length, false);
  for (final i in order) {
    final p = project(markers[i].position);
    if (placed.every((q) => p.distanceTo(q) >= minGapPx)) {
      placed.add(p);
      keep[i] = true;
    }
  }
  return [
    for (var i = 0; i < markers.length; i++)
      if (keep[i]) markers[i],
  ];
}

/// Screen gap between direction chevrons, in logical pixels — the phone
/// counterpart of the web map's `symbol-spacing: 60`, a touch wider for a
/// smaller screen. A fixed gap in metres (the old half-mile) left a 6 km run
/// with five arrows when zoomed to fit, and a pile of them when zoomed in.
const double chevronSpacingPx = 70;

/// Metres between chevrons at map [zoom] near latitude [lat], so they sit
/// [chevronSpacingPx] apart on screen at every zoom. The zoom is snapped down
/// to the half level so a pinch doesn't re-walk the track every frame.
double chevronStepMetresForZoom(double zoom, double lat) {
  final z = (zoom * 2).floor() / 2;
  final metresPerPixel = 156543.03392 * cos(lat * pi / 180) / pow(2, z);
  return max(10, chevronSpacingPx * metresPerPixel);
}

/// Walk the polyline and emit a [TrackChevron] every [stepMetres]. Each
/// chevron points along the local segment so the runner's direction is
/// obvious at a glance. Pair with [chevronStepMetresForZoom] for the
/// equivalent of MapLibre's `symbol-placement: line` arrows on the web
/// map. Skips chevrons within
/// `stepMetres / 2` of the start and end so they don't crowd the green /
/// red caps.
List<TrackChevron> computeChevrons(
  List<LatLng> coords, {
  required double stepMetres,
}) {
  final out = <TrackChevron>[];
  if (coords.length < 2 || stepMetres <= 0) return out;

  double polylineTotal = 0;
  for (int i = 1; i < coords.length; i++) {
    polylineTotal += _haversineMetres(coords[i - 1], coords[i]);
  }
  if (polylineTotal < stepMetres) return out;

  double cumulative = 0;
  // Start one step in so the first chevron isn't on top of the start
  // cap, and stop a step before the end so we don't crowd the end cap.
  double nextChevron = stepMetres;
  final maxAlong = polylineTotal - stepMetres / 2;
  for (int i = 1; i < coords.length; i++) {
    final segmentM = _haversineMetres(coords[i - 1], coords[i]);
    while (cumulative + segmentM >= nextChevron &&
        segmentM > 0 &&
        nextChevron <= maxAlong) {
      final t = (nextChevron - cumulative) / segmentM;
      final lat =
          coords[i - 1].latitude +
          (coords[i].latitude - coords[i - 1].latitude) * t;
      final lng =
          coords[i - 1].longitude +
          (coords[i].longitude - coords[i - 1].longitude) * t;
      // Bearing in screen-space (lat increasing = up). The chevron
      // glyph points right at angle 0 so we rotate by the screen-space
      // angle of the local segment.
      final dLat = coords[i].latitude - coords[i - 1].latitude;
      final dLng = coords[i].longitude - coords[i - 1].longitude;
      // Screen-y grows downward; latitude grows upward — invert dLat so
      // a north-bound segment shows the chevron pointing up.
      final angle = atan2(-dLat, dLng);
      out.add(TrackChevron(LatLng(lat, lng), angle));
      nextChevron += stepMetres;
    }
    cumulative += segmentM;
  }
  return out;
}

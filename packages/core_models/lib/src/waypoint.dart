import 'package:json_annotation/json_annotation.dart';

part 'waypoint.g.dart';

@JsonSerializable()
class Waypoint {
  final double lat;
  final double lng;
  final double? elevationMetres;
  final DateTime? timestamp;

  /// Per-point heart rate in BPM when the recorder captured HR samples
  /// alongside GPS. Optional: most historical runs only carry the scalar
  /// `metadata.avg_bpm`; per-point values arrive from Strava streams,
  /// FIT/TCX importers, and watch recorders. See `docs/backend/metadata.md`.
  final int? bpm;

  /// Raw fix quality the recorder saw, kept so the server can recompute
  /// distance from a stored track with the same Doppler input the phone used
  /// (`docs/features/gps_distance.md` § Waypoint fields). All optional and
  /// omitted from the JSON when absent, so old tracks parse unchanged and
  /// recompute through the position-only path.
  @JsonKey(includeIfNull: false)
  final double? accuracyMetres;
  @JsonKey(includeIfNull: false)
  final double? speedMps;
  @JsonKey(includeIfNull: false)
  final double? speedAccuracyMps;
  @JsonKey(includeIfNull: false)
  final double? bearingDeg;

  /// The smoothed GPS distance filter's position for this fix (spec v1.2,
  /// `docs/features/gps_distance.md` § Waypoint fields), written at save.
  /// [lat] / [lng] stay the raw fix. Omitted when the smoother placed no
  /// position on the fix, and on every track recorded before it existed.
  @JsonKey(includeIfNull: false)
  final double? smoothedLat;
  @JsonKey(includeIfNull: false)
  final double? smoothedLng;

  const Waypoint({
    required this.lat,
    required this.lng,
    this.elevationMetres,
    this.timestamp,
    this.bpm,
    this.accuracyMetres,
    this.speedMps,
    this.speedAccuracyMps,
    this.bearingDeg,
    this.smoothedLat,
    this.smoothedLng,
  });

  /// Whether the stored track carries a usable smoothed position for this
  /// fix: both halves present and finite, as `hasSmoothedPosition` in web
  /// `lib/runs/track_line.ts` reads it. A NaN half would otherwise put the
  /// line vertex nowhere instead of on the raw fix.
  bool get hasSmoothedPosition =>
      (smoothedLat?.isFinite ?? false) && (smoothedLng?.isFinite ?? false);

  /// Where the run line, a route match or a hop-sum distance places this
  /// fix: the smoothed position when both halves are present, else the raw
  /// fix. Never an estimator input — the estimator always takes [lat] /
  /// [lng].
  double get lineLat => hasSmoothedPosition ? smoothedLat! : lat;
  double get lineLng => hasSmoothedPosition ? smoothedLng! : lng;

  /// This fix with the smoother's position attached (or cleared, with nulls).
  Waypoint withSmoothedPosition(double? smoothedLat, double? smoothedLng) =>
      Waypoint(
        lat: lat,
        lng: lng,
        elevationMetres: elevationMetres,
        timestamp: timestamp,
        bpm: bpm,
        accuracyMetres: accuracyMetres,
        speedMps: speedMps,
        speedAccuracyMps: speedAccuracyMps,
        bearingDeg: bearingDeg,
        smoothedLat: smoothedLat,
        smoothedLng: smoothedLng,
      );

  factory Waypoint.fromJson(Map<String, dynamic> json) =>
      _$WaypointFromJson(json);

  Map<String, dynamic> toJson() => _$WaypointToJson(this);
}

/// The waypoints of [track] that are actually locations, with any non-finite
/// elevation or fix-quality field dropped to null.
///
/// Two reasons, and the second is the one that loses a run. A non-finite
/// latitude or longitude is not a coordinate but the absence of one
/// (decisions § 954). And `jsonEncode` REFUSES a non-finite double: it throws
/// `JsonUnsupportedObjectError`, an `Error` rather than an `Exception`, so a
/// single such point makes the whole track unencodable — the run cannot be
/// written to the local store and cannot be uploaded, on every retry forever,
/// with nothing in the failure to say it will never succeed.
///
/// Dropping the point removes nothing real, which is why this is a filter and
/// not a refusal: the alternative is a four-day effort that never leaves the
/// phone. Every other boundary in the tree already answers this way — the
/// recorder refuses to append a non-finite fix (§ 956) and the four route
/// importers drop one (§ 954); this is the same rule at the two serializers
/// the producers those guards do not cover all pass through.
///
/// Returns the input list itself when nothing needed dropping, so the common
/// path allocates nothing.
List<Waypoint> finiteWaypoints(List<Waypoint> track) {
  var needsFilter = false;
  for (final w in track) {
    if (!w.lat.isFinite ||
        !w.lng.isFinite ||
        _nonFinite(w.elevationMetres) ||
        _nonFinite(w.accuracyMetres) ||
        _nonFinite(w.speedMps) ||
        _nonFinite(w.speedAccuracyMps) ||
        _nonFinite(w.bearingDeg) ||
        _nonFinite(w.smoothedLat) ||
        _nonFinite(w.smoothedLng)) {
      needsFilter = true;
      break;
    }
  }
  if (!needsFilter) return track;
  return <Waypoint>[
    for (final w in track)
      if (w.lat.isFinite && w.lng.isFinite)
        Waypoint(
          lat: w.lat,
          lng: w.lng,
          elevationMetres: _finiteOrNull(w.elevationMetres),
          timestamp: w.timestamp,
          bpm: w.bpm,
          accuracyMetres: _finiteOrNull(w.accuracyMetres),
          speedMps: _finiteOrNull(w.speedMps),
          speedAccuracyMps: _finiteOrNull(w.speedAccuracyMps),
          bearingDeg: _finiteOrNull(w.bearingDeg),
          // A half-finite smoothed pair is no position: both or neither.
          smoothedLat: _finiteSmoothedPair(w) ? w.smoothedLat : null,
          smoothedLng: _finiteSmoothedPair(w) ? w.smoothedLng : null,
        ),
  ];
}

bool _nonFinite(double? v) => v != null && !v.isFinite;

bool _finiteSmoothedPair(Waypoint w) =>
    (w.smoothedLat?.isFinite ?? false) && (w.smoothedLng?.isFinite ?? false);

double? _finiteOrNull(double? v) => (v?.isFinite ?? false) ? v : null;

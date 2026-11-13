import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:typed_data';

import 'metadata_keys.dart';
import 'run.dart';
import 'waypoint.dart';

/// Heart rate is kept only with health-data consent (decisions § 2514).
///
/// The database strips the heart-rate keys from a run written by a runner
/// without consent, but it cannot see inside the gzipped track, and the
/// storage policy refuses the heart-rate sidecar outright. So every client
/// that uploads or stores a run strips it first with [runWithoutHeartRate]:
/// the run, its distance, its time and its track are all kept; only the
/// heart rate goes. Live heart rate on screen during a run is not affected,
/// because nothing here runs until the run is saved.
///
/// Twin of `apps/web/src/lib/core/health_consent.ts`'s `stripHeartRate` —
/// keep the key list, the rule and the test count in lockstep.

/// The `runs.metadata` keys that are heart rate. `hr_series_url` is a column
/// on the server; the mobile client carries it in the bag (`_runFromRow`).
const List<String> heartRateMetadataKeys = <String>[
  MetadataKeys.avgBpm,
  MetadataKeys.maxBpm,
  MetadataKeys.hrCoverage,
  MetadataKeys.hrSeriesUrl,
];

/// Whether [run] carries any heart rate: a heart-rate metadata key or a
/// per-point bpm.
bool runHasHeartRate(Run run) {
  final meta = run.metadata;
  if (meta != null && heartRateMetadataKeys.any(meta.containsKey)) return true;
  return run.track.any((w) => w.bpm != null);
}

/// [run] without its heart rate, or [run] itself when it has none.
Run runWithoutHeartRate(Run run) {
  if (!runHasHeartRate(run)) return run;
  final meta = run.metadata == null
      ? null
      : (Map<String, dynamic>.of(run.metadata!)
        ..removeWhere((k, _) => heartRateMetadataKeys.contains(k)));
  return Run(
    id: run.id,
    startedAt: run.startedAt,
    duration: run.duration,
    distanceMetres: run.distanceMetres,
    track: [for (final w in run.track) w.bpm == null ? w : _withoutBpm(w)],
    routeId: run.routeId,
    source: run.source,
    externalId: run.externalId,
    metadata: meta,
    createdAt: run.createdAt,
  );
}

Waypoint _withoutBpm(Waypoint w) => Waypoint(
      lat: w.lat,
      lng: w.lng,
      elevationMetres: w.elevationMetres,
      timestamp: w.timestamp,
      accuracyMetres: w.accuracyMetres,
      speedMps: w.speedMps,
      speedAccuracyMps: w.speedAccuracyMps,
      bearingDeg: w.bearingDeg,
      smoothedLat: w.smoothedLat,
      smoothedLng: w.smoothedLng,
      baroElevationMetres: w.baroElevationMetres,
      cumulativeDistanceMetres: w.cumulativeDistanceMetres,
      offTrack: w.offTrack,
      segmentStart: w.segmentStart,
    );

/// A gzipped stored track with every point's `bpm` removed, or [bytes]
/// itself when no point carries one. Used where a track is uploaded as stored
/// bytes (a backup restore). Throws on bytes that are not a gzipped JSON
/// array, so the caller reports the track rather than storing something it
/// could not check.
Uint8List trackBytesWithoutBpm(Uint8List bytes) {
  final points = jsonDecode(utf8.decode(gzip.decode(bytes)));
  if (points is! List) throw const FormatException('track is not a list');
  var changed = false;
  for (final p in points) {
    if (p is Map && p.containsKey('bpm')) {
      p.remove('bpm');
      changed = true;
    }
  }
  if (!changed) return bytes;
  return Uint8List.fromList(gzip.encode(utf8.encode(jsonEncode(points))));
}

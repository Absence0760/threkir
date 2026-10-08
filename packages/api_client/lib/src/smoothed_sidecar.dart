import 'dart:convert';

import 'package:core_models/core_models.dart';
import 'package:crypto/crypto.dart';

/// The smoothed-position sidecar the job_worker writes beside a track it
/// replayed, `{user_id}/{run_id}.smoothed.json.gz` in the `runs` bucket
/// (`docs/features/gps_distance.md` § Waypoint fields): the GPS distance
/// smoother's position per stored waypoint plus the fingerprint of the exact
/// track bytes it was computed from. Merged only onto that track, and only
/// onto a waypoint with no pair of its own, so a track re-uploaded after the
/// sidecar was written keeps its own positions. The run names the track a
/// stored sidecar was built for in `metadata.smoothed_sidecar_sha256`, and a
/// reader fetches the sidecar only when that names the bytes it holds.
///
/// Same rule as `apps/web/src/lib/runs/smoothed_sidecar.ts` and the Deno copy
/// in `_shared/smoothed_sidecar.ts`; all replay
/// `fixtures/smoothed_sidecar_vectors.json`, as does the Go writer.
const int smoothedSidecarVersion = 1;

String smoothedSidecarPath(String userId, String runId) =>
    '$userId/$runId.smoothed.json.gz';

/// Lower-case hex SHA-256 of the decompressed track bytes.
String trackSha256Hex(List<int> decompressed) =>
    sha256.convert(decompressed).toString();

/// Whether the run's [metadata] names a sidecar built for the track whose
/// bytes hash to [sha256Hex]: the job_worker records
/// `smoothed_sidecar_sha256` while the sidecar is stored, so a run without it,
/// or whose hash names another track (a re-upload), has nothing to fetch.
/// Checked before the sidecar download so a run with no sidecar costs no
/// Storage request; [mergeSmoothedSidecar] still checks the sidecar's own
/// fingerprint.
bool sidecarNamedFor(Map<String, dynamic>? metadata, String sha256Hex) =>
    metadata?[MetadataKeys.smoothedSidecarSha256] == sha256Hex;

/// Whether a sidecar could add anything: a track with no smoothed pair on any
/// waypoint.
bool needsSmoothedSidecar(List<Waypoint> track) =>
    track.isNotEmpty && !track.any((w) => w.hasSmoothedPosition);

bool _usablePosition(Object? v) {
  if (v is! List || v.length != 2) return false;
  final lat = v[0];
  final lng = v[1];
  return lat is num &&
      lng is num &&
      lat.isFinite &&
      lng.isFinite &&
      lat.abs() <= 90 &&
      lng.abs() <= 180;
}

/// [track] with the sidecar's positions attached where a waypoint has no
/// pair of its own, or [track] itself when the sidecar is not for this track
/// (version, point count or hash differ) or is not a sidecar at all. `lat` /
/// `lng` are never altered.
List<Waypoint> mergeSmoothedSidecar(
  List<Waypoint> track,
  Object? sidecar, {
  required int points,
  required String sha256Hex,
}) {
  if (sidecar is! Map) return track;
  final named = sidecar['track'];
  final positions = sidecar['positions'];
  if (sidecar['version'] != smoothedSidecarVersion ||
      named is! Map ||
      named['points'] != points ||
      named['sha256'] != sha256Hex ||
      points != track.length ||
      positions is! List ||
      positions.length != track.length) {
    return track;
  }
  return [
    for (var i = 0; i < track.length; i++)
      if (track[i].hasSmoothedPosition || !_usablePosition(positions[i]))
        track[i]
      else
        track[i].withSmoothedPosition(
          ((positions[i] as List)[0] as num).toDouble(),
          ((positions[i] as List)[1] as num).toDouble(),
        ),
  ];
}

/// Decodes a sidecar's inflated JSON, or null when it is not JSON.
Object? decodeSmoothedSidecar(List<int> inflated) {
  try {
    return jsonDecode(utf8.decode(inflated));
  } on FormatException {
    return null;
  }
}

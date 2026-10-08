import 'dart:convert';
import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:test/test.dart';

/// Replays `fixtures/smoothed_sidecar_vectors.json`, shared with the web
/// (`apps/web/src/lib/runs/smoothed_sidecar.test.ts`) and Deno
/// (`_shared/smoothed_sidecar.test.ts`) readers and the Go writer
/// (`apps/job_worker/internal/smoothed_sidecar_test.go`).
void main() {
  final fixture = jsonDecode(
    File('../../fixtures/smoothed_sidecar_vectors.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final trackJson = fixture['trackJson'] as String;
  final sha = fixture['sha256'] as String;
  final cases = (fixture['cases'] as List).cast<Map<String, dynamic>>();

  List<Waypoint> track() => (jsonDecode(trackJson) as List)
      .cast<Map<String, dynamic>>()
      .map((m) => Waypoint(
            lat: (m['lat'] as num).toDouble(),
            lng: (m['lng'] as num).toDouble(),
            timestamp: DateTime.parse(m['ts'] as String),
            smoothedLat: (m['smoothedLat'] as num?)?.toDouble(),
            smoothedLng: (m['smoothedLng'] as num?)?.toDouble(),
          ))
      .toList();

  test('the fixture is for sidecar version 1 and holds cases', () {
    expect(fixture['version'], smoothedSidecarVersion);
    expect(cases, isNotEmpty);
  });

  test('the track fingerprint is the SHA-256 of the decompressed bytes, '
      'lower-case hex', () {
    expect(trackSha256Hex(utf8.encode(trackJson)), sha);
  });

  for (final c in cases) {
    test('merge: ${c['name']}', () {
      final points = track();
      final merged = mergeSmoothedSidecar(
        points,
        c['sidecar'],
        points: points.length,
        sha256Hex: sha,
      );
      final expected = (c['expected'] as List);
      expect(merged, hasLength(expected.length));
      for (var i = 0; i < merged.length; i++) {
        expect([merged[i].lat, merged[i].lng], [points[i].lat, points[i].lng],
            reason: 'waypoint $i: raw lat/lng must never change');
        final got = merged[i].hasSmoothedPosition
            ? [merged[i].smoothedLat, merged[i].smoothedLng]
            : null;
        final want = expected[i] == null
            ? null
            : (expected[i] as List).map((v) => (v as num).toDouble()).toList();
        expect(got, want, reason: 'waypoint $i');
      }
    });
  }

  test('only a track with no pair anywhere needs a sidecar', () {
    expect(needsSmoothedSidecar(const []), isFalse);
    expect(
      needsSmoothedSidecar(const [
        Waypoint(lat: 1, lng: 2),
        Waypoint(lat: 1, lng: 2, smoothedLat: 1),
      ]),
      isTrue,
    );
    expect(
      needsSmoothedSidecar(const [
        Waypoint(lat: 1, lng: 2),
        Waypoint(lat: 1, lng: 2, smoothedLat: 1, smoothedLng: 2),
      ]),
      isFalse,
    );
  });

  test('a sidecar body that is not JSON decodes to nothing', () {
    expect(decodeSmoothedSidecar(utf8.encode('not json')), isNull);
  });

  test('the sidecar sits beside the track in the owner folder', () {
    expect(smoothedSidecarPath('u-1', 'r-1'), 'u-1/r-1.smoothed.json.gz');
  });
}

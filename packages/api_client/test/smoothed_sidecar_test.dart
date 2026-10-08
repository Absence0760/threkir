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

  test('only metadata naming this exact track names a sidecar to fetch', () {
    expect(sidecarNamedFor({'smoothed_sidecar_sha256': sha}, sha), isTrue);
    expect(
      sidecarNamedFor({'smoothed_sidecar_sha256': sha, 'title': 'Tempo'}, sha),
      isTrue,
    );
    expect(sidecarNamedFor(null, sha), isFalse);
    expect(sidecarNamedFor(const {}, sha), isFalse,
        reason: 'a run with no recorded sidecar has nothing to fetch');
    expect(
      sidecarNamedFor({'smoothed_sidecar_sha256': '0' * 64}, sha),
      isFalse,
      reason: 'a hash carried forward from a re-uploaded track names another',
    );
    expect(
        sidecarNamedFor({'smoothed_sidecar_sha256': sha.toUpperCase()}, sha),
        isFalse);
    expect(sidecarNamedFor({'smoothed_sidecar_sha256': true}, sha), isFalse);
  });

  group('a locally held track', () {
    // A watch run relayed through the phone, as the bridge hands it over:
    // local-zone and sub-second timestamps, Doppler keys, no smoothed pair.
    final recorded = [
      for (var i = 0; i < 5; i++)
        Waypoint(
          lat: 40 + i * 0.0001,
          lng: -75.0,
          elevationMetres: i == 2 ? null : 12.5,
          timestamp: DateTime(2026, 10, 8, 7, 0, i, 250, 125),
          bpm: 140 + i,
          accuracyMetres: 4,
          speedMps: 2.5,
          speedAccuracyMps: 0.4,
          bearingDeg: 0,
        ),
    ];

    test('fingerprints as the blob the upload stores', () {
      expect(
        ApiClient.localTrackSha256(recorded),
        trackSha256Hex(utf8.encode(ApiClient.debugTrackBlobJson(recorded))),
      );
    });

    test('keeps that fingerprint through the local run store codec', () {
      final run = Run(
        id: 'run-1',
        startedAt: DateTime.utc(2026, 10, 8, 7),
        duration: const Duration(seconds: 4),
        distanceMetres: 44.5,
        track: recorded,
        source: RunSource.watch,
      );
      final reloaded = Run.fromJson(
        jsonDecode(jsonEncode(run.toJson())) as Map<String, dynamic>,
      );
      expect(ApiClient.localTrackSha256(reloaded.track),
          ApiClient.localTrackSha256(recorded),
          reason: 'the sidecar names the uploaded bytes; a copy the phone '
              'reloaded from disk must hash to the same, or it never merges');
    });

    test('a different track does not share the fingerprint', () {
      final moved = [
        ...recorded.take(4),
        Waypoint(lat: 40.0005, lng: -75.0, timestamp: recorded[4].timestamp),
      ];
      expect(ApiClient.localTrackSha256(moved),
          isNot(ApiClient.localTrackSha256(recorded)));
    });
  });
}

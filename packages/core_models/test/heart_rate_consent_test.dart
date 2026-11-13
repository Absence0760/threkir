import 'package:core_models/core_models.dart';
import 'package:test/test.dart';

// Twin of apps/web/src/lib/core/health_consent.test.ts's stripHeartRate
// suite (decisions § 2513) — same cases, same count.
void main() {
  final t0 = DateTime.utc(2026, 11, 1, 8);
  Run run({Map<String, dynamic>? metadata, List<Waypoint> track = const []}) =>
      Run(
        id: 'r1',
        startedAt: t0,
        duration: const Duration(minutes: 30),
        distanceMetres: 5000,
        source: RunSource.app,
        metadata: metadata,
        track: track,
      );

  group('runWithoutHeartRate', () {
    test('the heart-rate keys are avg_bpm, max_bpm, hr_coverage and hr_series_url', () {
      expect(heartRateMetadataKeys,
          ['avg_bpm', 'max_bpm', 'hr_coverage', 'hr_series_url']);
    });

    test('a run with no heart rate comes back unchanged', () {
      final r = run(metadata: {'title': 'Easy'}, track: [
        Waypoint(lat: 1, lng: 2, timestamp: t0),
      ]);
      expect(runHasHeartRate(r), isFalse);
      expect(identical(runWithoutHeartRate(r), r), isTrue);
    });

    test('the heart-rate metadata keys go and every other key stays', () {
      final r = run(metadata: {
        'avg_bpm': 150,
        'max_bpm': 181,
        'hr_coverage': 0.9,
        'hr_series_url': 'u/r1.hr.json.gz',
        'title': 'Tempo',
      });
      final out = runWithoutHeartRate(r);
      expect(out.metadata, {'title': 'Tempo'});
      expect(out.distanceMetres, 5000);
      expect(r.metadata!['avg_bpm'], 150, reason: 'the input is not mutated');
    });

    test('per-point bpm goes and every other point field stays', () {
      final r = run(track: [
        Waypoint(lat: 1, lng: 2, elevationMetres: 30, timestamp: t0, bpm: 140),
        Waypoint(lat: 1.1, lng: 2.1, timestamp: t0, segmentStart: true),
      ]);
      final out = runWithoutHeartRate(r);
      expect(out.track.map((w) => w.bpm), [null, null]);
      expect(out.track.first.elevationMetres, 30);
      expect(out.track.first.timestamp, t0);
      expect(out.track.last.segmentStart, isTrue);
    });

    test('a bpm on the track alone counts as heart rate', () {
      expect(
          runHasHeartRate(run(track: [Waypoint(lat: 1, lng: 2, bpm: 99)])),
          isTrue);
    });
  });
}

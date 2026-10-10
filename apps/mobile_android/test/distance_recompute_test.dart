import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/distance_recompute.dart';

const owner = '00000000-0000-0000-0000-000000000001';
const other = '00000000-0000-0000-0000-000000000002';

RecomputeCandidate run({
  String? userId = owner,
  RunSource source = RunSource.app,
  String? trackUrl = '$owner/run.json.gz',
  Map<String, dynamic>? metadata = const {'activity_type': 'run'},
}) =>
    RecomputeCandidate(
      userId: userId,
      source: source,
      trackUrl: trackUrl,
      metadata: metadata,
    );

void main() {
  test('the owner of an app-recorded tracked run may recompute', () {
    expect(canRecomputeDistance(run(), owner), isTrue);
  });

  test('a watch-recorded run is recomputable too', () {
    expect(canRecomputeDistance(run(source: RunSource.watch), owner), isTrue);
  });

  test('only our own recorders are recomputable sources', () {
    expect(
      recomputableSources.map((s) => s.name).toList()..sort(),
      ['app', 'watch'],
    );
    const imported = [
      RunSource.healthkit,
      RunSource.healthconnect,
      RunSource.strava,
      RunSource.garmin,
      RunSource.parkrun,
      RunSource.race,
    ];
    for (final source in imported) {
      expect(canRecomputeDistance(run(source: source), owner), isFalse,
          reason: source.name);
    }
  });

  test('a non-owner, or no viewer, is never offered the action', () {
    expect(canRecomputeDistance(run(), other), isFalse);
    expect(canRecomputeDistance(run(), null), isFalse);
    expect(canRecomputeDistance(run(), ''), isFalse);
    expect(canRecomputeDistance(null, owner), isFalse);
  });

  test('a run with no stored track has nothing to recompute from', () {
    expect(canRecomputeDistance(run(trackUrl: null), owner), isFalse);
    expect(canRecomputeDistance(run(trackUrl: ''), owner), isFalse);
  });

  test('any distance provenance tag blocks the recompute, as the worker skips it',
      () {
    for (final tag in ['pedometer', 'treadmill', 'something_new']) {
      expect(canRecomputeDistance(run(metadata: {'distance_source': tag}), owner),
          isFalse,
          reason: tag);
    }
    expect(canRecomputeDistance(run(metadata: {'distance_source': ''}), owner),
        isTrue);
    expect(canRecomputeDistance(run(metadata: {'distance_source': 7}), owner),
        isTrue);
  });

  test('an in-progress stub, a manual entry and an indoor run are never offered',
      () {
    for (final key in [
      'in_progress',
      'manual_entry',
      'indoor',
      'indoor_estimated',
    ]) {
      expect(canRecomputeDistance(run(metadata: {key: true}), owner), isFalse,
          reason: key);
      expect(canRecomputeDistance(run(metadata: {key: false}), owner), isTrue,
          reason: key);
      expect(canRecomputeDistance(run(metadata: {key: 'true'}), owner), isTrue,
          reason: key);
    }
  });

  test('a run already on the current estimator is not offered again', () {
    expect(currentDistanceEstimator, 'kalman_v3');
    expect(
      canRecomputeDistance(
          run(metadata: {'distance_estimator': 'kalman_v3'}), owner),
      isFalse,
    );
    expect(
      canRecomputeDistance(
          run(metadata: {
            'distance_estimator': 'kalman_v3',
            'distance_recomputed_at': '2026-10-08T08:00:00Z',
          }),
          owner),
      isFalse,
    );
    expect(
      canRecomputeDistance(
          run(metadata: {
            'distance_estimator': 'kalman_v2',
            'distance_recomputed_at': '2026-10-08T08:00:00Z',
          }),
          owner),
      isTrue,
      reason: 'a run recomputed under spec v1.2 gains the v1.3 Doppler scale',
    );
  });

  test('a run its recorder stamped live is not offered, whatever the estimator',
      () {
    // The Wear OS and watchOS recorders stamp kalman_v1 on every run; the
    // worker skips a live stamp because the stored track is movement-gated.
    for (final estimator in ['kalman_v1', 'something_older']) {
      expect(
        canRecomputeDistance(
            run(
                source: RunSource.watch,
                metadata: {'distance_estimator': estimator}),
            owner),
        isFalse,
        reason: estimator,
      );
    }
    expect(
      canRecomputeDistance(run(metadata: {'distance_estimator': null}), owner),
      isFalse,
    );
  });

  test('a run a recompute stamped kalman_v1 (the v1.1 forward filter) is '
      'offered again', () {
    expect(
      canRecomputeDistance(
          run(source: RunSource.watch, metadata: {
            'distance_estimator': 'kalman_v1',
            'distance_recomputed_at': '2026-10-08T08:00:00Z',
          }),
          owner),
      isTrue,
    );
  });

  test('null metadata reads as an old, recomputable run', () {
    expect(canRecomputeDistance(run(metadata: null), owner), isTrue);
  });

  test('recordedDistanceM returns only a usable positive number', () {
    expect(recordedDistanceM({'distance_recorded_m': 6309.4}), 6309.4);
    expect(recordedDistanceM({'distance_recorded_m': 6309}), 6309.0);
    expect(recordedDistanceM({'distance_recorded_m': 0}), isNull);
    expect(recordedDistanceM({'distance_recorded_m': -3}), isNull);
    expect(recordedDistanceM({'distance_recorded_m': '6309'}), isNull);
    expect(recordedDistanceM({'distance_recorded_m': double.nan}), isNull);
    expect(recordedDistanceM({}), isNull);
    expect(recordedDistanceM(null), isNull);
  });

  test('classifyRecomputeError maps the RPC refusals', () {
    expect(
      classifyRecomputeError(const DistanceRecomputeRefused(
          DistanceRecomputeRefusal.notAuthorized)),
      RecomputeFailure.notAuthorized,
    );
    expect(
      classifyRecomputeError(
          const DistanceRecomputeRefused(DistanceRecomputeRefusal.noTrack)),
      RecomputeFailure.noTrack,
    );
    expect(classifyRecomputeError(Exception('network')),
        RecomputeFailure.other);
    expect(classifyRecomputeError(null), RecomputeFailure.other);
  });

  test('fromRun reads the track url out of a local run\'s metadata', () {
    final local = Run(
      id: 'r1',
      startedAt: DateTime.utc(2026, 9, 1),
      duration: const Duration(minutes: 30),
      distanceMetres: 5000,
      source: RunSource.app,
      metadata: const {'track_url': '$owner/r1.json.gz'},
    );
    final candidate = RecomputeCandidate.fromRun(local, ownerId: owner);
    expect(candidate.trackUrl, '$owner/r1.json.gz');
    expect(canRecomputeDistance(candidate, owner), isTrue);
    expect(
      canRecomputeDistance(
          RecomputeCandidate.fromRun(
              Run(
                id: 'r2',
                startedAt: DateTime.utc(2026, 9, 1),
                duration: const Duration(minutes: 30),
                distanceMetres: 5000,
                source: RunSource.app,
              ),
              ownerId: owner),
          owner),
      isFalse,
    );
  });
}

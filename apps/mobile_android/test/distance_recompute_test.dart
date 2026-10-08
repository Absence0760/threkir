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

  test(
      'a pedometer distance is not recomputable, a treadmill tag is no '
      'blocker by itself', () {
    expect(
      canRecomputeDistance(
          run(metadata: {'distance_source': 'pedometer'}), owner),
      isFalse,
    );
    expect(
      canRecomputeDistance(
          run(metadata: {'distance_source': 'treadmill'}), owner),
      isTrue,
    );
  });

  test('a run already on the current estimator is not offered again', () {
    expect(currentDistanceEstimator, 'kalman_v2');
    expect(
      canRecomputeDistance(
          run(metadata: {'distance_estimator': 'kalman_v2'}), owner),
      isFalse,
    );
    expect(
      canRecomputeDistance(
          run(metadata: {'distance_estimator': 'something_older'}), owner),
      isTrue,
    );
  });

  test('a kalman_v1 run (the v1.1 forward filter, no smoother) is offered again',
      () {
    expect(
      canRecomputeDistance(
          run(metadata: {'distance_estimator': 'kalman_v1'}), owner),
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

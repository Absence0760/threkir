// Mirror of apps/web/src/lib/training/race_predictor.test.ts — keep the case
// set + count in lockstep.

import 'package:flutter_test/flutter_test.dart';

import '../lib/race_predictor.dart';
import '../lib/training.dart'
    show riegelPredict, PredictionConfidence, PredictionReason;

void main() {
  test('empty pool returns null', () {
    expect(predictRaceLadder([]), isNull);
  });

  test('non-finite / non-positive efforts are filtered out, empty -> null', () {
    final bad = [
      const EffortForPrediction(distanceM: 0, durationS: 1200, ageDays: 1),
      const EffortForPrediction(distanceM: 5000, durationS: 0, ageDays: 1),
      EffortForPrediction(distanceM: 5000, durationS: 1200, ageDays: double.nan),
    ];
    expect(predictRaceLadder(bad), isNull);
  });

  test('one effort produces a full ladder with all four rungs', () {
    final out = predictRaceLadder(
        [const EffortForPrediction(distanceM: 5000, durationS: 1200, ageDays: 3)]);
    expect(out, isNotNull);
    expect(out!.rungs.length, kRaceLadderM.length);
    expect(out.rungs.map((r) => r.distanceM).toList(), kRaceLadderM);
  });

  test('rungs project from the chosen anchor via Riegel (numbers match the engine)',
      () {
    final out = predictRaceLadder(
        [const EffortForPrediction(distanceM: 5000, durationS: 1200, ageDays: 0)]);
    expect(out, isNotNull);
    for (final r in out!.rungs) {
      final expected = riegelPredict(5000, 1200, r.distanceM);
      expect((r.predictedSec - expected).abs() < 1e-6, isTrue);
    }
  });

  test('pace is finish-time over distance in km', () {
    final out = predictRaceLadder(
        [const EffortForPrediction(distanceM: 10000, durationS: 2400, ageDays: 1)]);
    expect(out, isNotNull);
    final tenK = out!.rungs.firstWhere((r) => r.distanceM == 10000);
    expect((tenK.paceSecPerKm - 240).abs() < 1e-6, isTrue);
  });

  test('a recent effort out-anchors a faster-but-stale PR', () {
    const stalePr = EffortForPrediction(
        distanceM: 10000, durationS: 2400, ageDays: 2 * kAnchorRecencyHalflifeDays);
    const fresh =
        EffortForPrediction(distanceM: 10000, durationS: 2700, ageDays: 0);
    final out = predictRaceLadder([stalePr, fresh]);
    expect(out, isNotNull);
    expect(out!.anchor.durationS, 2700);
    expect(out.anchor.ageDays, 0);
  });

  test('a recent PR still wins when it is also the fastest', () {
    const recentPr =
        EffortForPrediction(distanceM: 10000, durationS: 2400, ageDays: 1);
    const slower =
        EffortForPrediction(distanceM: 10000, durationS: 3000, ageDays: 1);
    final out = predictRaceLadder([slower, recentPr]);
    expect(out, isNotNull);
    expect(out!.anchor.durationS, 2400);
  });

  test('qualifyingCount reflects the filtered pool size', () {
    final out = predictRaceLadder([
      const EffortForPrediction(distanceM: 5000, durationS: 1200, ageDays: 1),
      const EffortForPrediction(distanceM: 10000, durationS: 2700, ageDays: 5),
      const EffortForPrediction(distanceM: 0, durationS: 999, ageDays: 1),
    ]);
    expect(out, isNotNull);
    expect(out!.qualifyingCount, 2);
  });

  test('a 10K anchor grades the marathon rung lower than the 10K rung', () {
    final out = predictRaceLadder(
        [const EffortForPrediction(distanceM: 10000, durationS: 2400, ageDays: 1)]);
    expect(out, isNotNull);
    final tenK = out!.rungs.firstWhere((r) => r.distanceM == 10000);
    final marathon = out.rungs.firstWhere((r) => r.distanceM == 42195);
    expect(marathon.quality.confidence, PredictionConfidence.low);
    expect(tenK.quality.confidence, isNot(PredictionConfidence.low));
  });

  test('a stale-only pool still produces a prediction (no null-out)', () {
    final out = predictRaceLadder(
        [const EffortForPrediction(distanceM: 10000, durationS: 2700, ageDays: 5000)]);
    expect(out, isNotNull);
    expect(out!.rungs.length, kRaceLadderM.length);
    final tenK = out.rungs.firstWhere((r) => r.distanceM == 10000);
    expect(tenK.quality.confidence, PredictionConfidence.low);
    expect(tenK.quality.reason, PredictionReason.stale);
  });

  test('future-dated effort (clock skew) is treated as weight 1, not amplified',
      () {
    final out = predictRaceLadder(
        [const EffortForPrediction(distanceM: 5000, durationS: 1200, ageDays: -3)]);
    expect(out, isNotNull);
    expect(out!.anchor.ageDays, -3);
  });

  // Mirrors the web pair's Infinity cases. durationS is an int here, so only
  // the distance can be infinite; `> 0` admits it and it would otherwise still
  // count toward the pool size that grades every rung's confidence.
  test('an effort with an infinite distance or duration is filtered out, not counted',
      () {
    const real = EffortForPrediction(distanceM: 10000, durationS: 2700, ageDays: 3);
    final out = predictRaceLadder([
      real,
      const EffortForPrediction(
          distanceM: double.infinity, durationS: 2700, ageDays: 1),
    ]);
    expect(out, isNotNull);
    expect(out!.qualifyingCount, 1);
    expect([out.anchor.distanceM, out.anchor.durationS, out.anchor.ageDays],
        [real.distanceM, real.durationS, real.ageDays]);
    expect(out.rungs.map((r) => r.predictedSec).toList(),
        predictRaceLadder([real])!.rungs.map((r) => r.predictedSec).toList());
  });

  test('a pool of only infinite efforts is empty: null, not a throw', () {
    expect(
        predictRaceLadder([
          const EffortForPrediction(
              distanceM: double.infinity, durationS: 1200, ageDays: 1),
        ]),
        isNull);
  });

  group('goalAheadOfRecentRuns', () {
    // Three recent 10 km runs in 50:00, so a 10K goal projects to 3000 s off
    // a well-sampled, recent, same-distance anchor (high confidence).
    final tenKPool = [
      for (final ageDays in [5, 10, 15])
        EffortForPrediction(
            distanceM: 10000, durationS: 3000, ageDays: ageDays.toDouble()),
    ];

    test('flags a goal more than the margin faster than recent runs project',
        () {
      // 2600 s is 13% under the 3000 s projection; the margin is 10%.
      expect(kGoalAheadMargin, 0.1);
      expect(goalAheadOfRecentRuns(10000, 2600, tenKPool), 3000);
    });

    test('stays quiet for a goal inside the margin', () {
      // 2750 s is 8.3% under the projection, and 2700 s exactly 10%: neither
      // flags.
      expect(goalAheadOfRecentRuns(10000, 2750, tenKPool), isNull);
      expect(goalAheadOfRecentRuns(10000, 2700, tenKPool), isNull);
      expect(goalAheadOfRecentRuns(10000, 3300, tenKPool), isNull);
    });

    test('stays quiet when the projection is a low-confidence guess', () {
      // A marathon off 5 km runs is an 8.4x extrapolation, past the 4x cap.
      final fiveK = [
        for (final ageDays in [5, 10, 15])
          EffortForPrediction(
              distanceM: 5000, durationS: 1500, ageDays: ageDays.toDouble()),
      ];
      expect(goalAheadOfRecentRuns(42195, 3 * 3600, fiveK), isNull);
    });

    test('is null with no goal time or no usable effort', () {
      expect(goalAheadOfRecentRuns(10000, null, tenKPool), isNull);
      expect(goalAheadOfRecentRuns(10000, 0, tenKPool), isNull);
      expect(goalAheadOfRecentRuns(10000, 2600, const []), isNull);
    });
  });
}

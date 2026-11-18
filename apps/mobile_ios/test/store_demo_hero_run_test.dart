import 'package:flutter_test/flutter_test.dart';

import '../integration_test/store/demo_data.dart';
import '../lib/fitness.dart' show qualifyingRuns;
import '../lib/hr_zones.dart';
import '../lib/pace_analysis.dart';
import '../lib/race_predictor.dart';
import '../lib/run_altitude.dart';
import '../lib/run_stats.dart';
import '../lib/training.dart';

// The store listing's record panel shows the demo account's hero run, so what
// its caption and the coach thread say about it has to be what the app
// computes from it. These read the run through the same helpers the run
// detail screen and the Progress predictor use (assets/store/README.md).

void main() {
  final hero = heroLoop(DateTime(2026, 11, 14, 7, 20));
  final altitude = runAltitude(hero.track, hero.source).track;
  final splits = computeSplitDurations(
    hero.track,
    1000,
    hero.startedAt,
    totalDistanceMetres: splitAxisTotalMetres(hero.source, hero.distanceMetres),
  );
  final gap = gradeAdjustedSplitPaces(
    altitude,
    List.filled(splits.length, 1000.0),
  );

  test('the route is the park\'s 6.1-mile full loop', () {
    expect(hero.distanceMetres, closeTo(6.1 * 1609.344, 0.01 * 6.1 * 1609.344));
    expect(hero.metadata?['title'], kHeroRunTitle);
  });

  test('every point carries a heart rate, inside the athlete\'s range', () {
    expect(hero.track.every((w) => w.bpm != null), isTrue);
    final stats = bpmStatsOf(hero.track)!;
    expect(stats.min, greaterThanOrEqualTo(85));
    expect(stats.max, lessThan(188));
  });

  test('raw pace fades over the second half while the effort holds', () {
    final pacing = analysePacing(altitude)!;
    expect(pacing.raw.verdict, PacingVerdict.positive);
    expect(pacing.gradeAdjusted!.verdict, PacingVerdict.even);
    // The run detail shows the adjusted sentence only past this margin.
    expect(
      (pacing.gradeAdjusted!.deltaSecPerKm - pacing.raw.deltaSecPerKm).abs(),
      greaterThanOrEqualTo(2),
    );
  });

  test('the slowest km is the climb, and it was not slow on effort', () {
    expect(splits.length, inInclusiveRange(7, 9));
    var slowest = 0;
    for (var i = 1; i < splits.length; i++) {
      if (splits[i].duration > splits[slowest].duration) slowest = i;
    }
    expect(
      slowest + 1,
      greaterThan(hero.distanceMetres / 2000),
      reason: 'the climb is in the second half',
    );
    expect(splits[slowest].elevationMetres, greaterThan(0));
    final raw = splits[slowest].duration.inSeconds;
    expect(raw - gap[slowest]!, greaterThanOrEqualTo(30));
    final sorted = [for (final g in gap) g!]..sort();
    final median = sorted[sorted.length ~/ 2];
    expect((gap[slowest]! - median).abs(), lessThanOrEqualTo(3));
  });

  test('heart rate lands in all five zones', () {
    final zones = hrZoneBreakdown(
      hero.track,
      cutoffs: defaultZoneCutoffs(maxHrBpm: 188),
    );
    expect(zones.every((z) => z.pct > 0), isTrue, reason: '$zones');
  });

  test(
    'the Progress predictor shows a 1:45 half whichever day the capture runs',
    () {
      // 2026-11-16 is a Monday: one capture per weekday, at 09:00.
      for (var d = 16; d <= 22; d++) {
        final now = DateTime(2026, 11, d, 9);
        final ladder = predictRaceLadder([
          for (final r in qualifyingRuns(demoRuns(now)))
            EffortForPrediction(
              distanceM: r.distanceMetres,
              durationS: r.duration.inSeconds,
              ageDays: now.difference(r.startedAt).inMilliseconds / 86400000,
            ),
        ])!;
        expect(ladder.anchor.durationS, kTuneUpSeconds, reason: 'on $now');
        final half = ladder.rungs
            .firstWhere((r) => r.distanceM == 21097.5)
            .predictedSec
            .round();
        expect(half, inInclusiveRange(6300, 6329), reason: 'on $now');
      }
    },
  );

  // The seeded plan (store_demo_seed.sql) must be the one the app's own
  // generator writes for the demo profile, whose sex is unset, and a 1:45:00
  // half with no recent 5K. Change the seed and these numbers together.
  test('the seeded plan is the generator\'s plan for the demo profile', () {
    final plan = generatePlan(
      GeneratePlanInput(
        goalEvent: GoalEvent.distanceHalf,
        goalTimeSec: 6300,
        startDate: DateTime(2026, 10, 12),
        daysPerWeek: 5,
        weeks: 12,
      ),
    );
    // The VDOT chip: plan_detail_screen.dart stores it to two places.
    expect((plan.vdot! * 100).round() / 100, 42.64);
    final paces = <WorkoutKind, Set<int?>>{};
    final structured = <int?>{};
    for (final w in plan.weeks.expand((w) => w.workouts)) {
      paces.putIfAbsent(w.kind, () => {}).add(w.targetPaceSecPerKm);
      structured
        ..add(w.structure?.steady?['pace_sec_per_km'] as int?)
        ..add(w.structure?.repeats?['pace_sec_per_km'] as int?);
    }
    expect(paces[WorkoutKind.tempo], {290});
    expect(paces[WorkoutKind.easy], {364});
    expect(paces[WorkoutKind.long], {364});
    expect(paces[WorkoutKind.recovery], {364});
    expect(paces[WorkoutKind.interval], {269});
    expect(paces[WorkoutKind.race], {299});
    expect(structured.whereType<int>().toSet(), containsAll([290, 269]));
  });
}

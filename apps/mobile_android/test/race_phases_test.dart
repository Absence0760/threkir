import 'package:core_models/core_models.dart' show Waypoint;
import 'package:flutter_test/flutter_test.dart';
import '../lib/race_phases.dart';

const double tenMileFraction = 16093.44 / 42195;

double weightedMeanFactor(List<RacePhase> phases) {
  final total = phases.last.endM;
  var sum = 0.0;
  for (final p in phases) {
    sum += p.paceFactor * (p.endM - p.startM);
  }
  return sum / total;
}

const double mPerDegLat = 111320;

/// A meridian-aligned track of [legs], each `(metres, pace s/km)` in 50 m
/// steps; a `(seconds, null)` leg holds position for that many seconds.
List<Waypoint> trackOf(List<(double, double?)> legs) {
  var cumM = 0.0;
  var tMs = DateTime.utc(2026, 4, 12, 7).millisecondsSinceEpoch;
  Waypoint at() => Waypoint(
      lat: 40 + cumM / mPerDegLat,
      lng: -105,
      timestamp: DateTime.fromMillisecondsSinceEpoch(tMs, isUtc: true));
  final out = <Waypoint>[at()];
  for (final (m, pace) in legs) {
    if (pace == null) {
      tMs += (m * 1000).round();
      out.add(at());
      continue;
    }
    final n = (m / 50).round() < 1 ? 1 : (m / 50).round();
    for (var i = 0; i < n; i++) {
      cumM += m / n;
      tMs += (m / n * pace).round();
      out.add(at());
    }
  }
  return out;
}

const half = PacingStrategy(
    preset: RacePhasePreset.negativeSplit, distanceM: 10000, goalTimeS: 3000);

void main() {
  test('even preset is one full-distance phase at factor 1', () {
    final plan = buildPhasePlan(10000, RacePhasePreset.even);
    expect(plan.length, 1);
    expect(plan[0].startM, 0);
    expect(plan[0].endM, 10000);
    expect(plan[0].intent, RacePhaseIntent.even);
    expect(plan[0].paceFactor, 1);
  });

  test('ten_ten_ten boundaries land on the generalised 10-mile fractions for a marathon', () {
    final plan = buildPhasePlan(42195, RacePhasePreset.tenTenTen);
    expect(plan.length, 3);
    expect(plan[0].startM, 0);
    expect(plan[1].startM, closeTo(16093.44, 1e-9));
    expect(plan[2].startM, closeTo(32186.88, 1e-9));
    expect(plan[2].endM, 42195);
    expect(plan[0].endM, plan[1].startM);
    expect(plan[1].endM, plan[2].startM);
  });

  test('ten_ten_ten intents and factors: hold back, settle, then a derived faster finish', () {
    final plan = buildPhasePlan(42195, RacePhasePreset.tenTenTen);
    expect(plan.map((p) => p.intent).toList(),
        [RacePhaseIntent.holdBack, RacePhaseIntent.settle, RacePhaseIntent.race]);
    expect(plan[0].paceFactor, 1.02);
    expect(plan[1].paceFactor, 1);
    const f = tenMileFraction;
    const derived = (1 - f * 1.02 - f * 1) / (1 - f - f);
    expect(plan[2].paceFactor, closeTo(derived, 1e-12));
    expect(plan[2].paceFactor > 0.96 && plan[2].paceFactor < 0.97, isTrue);
  });

  test('distance-weighted mean factor is 1 for ten_ten_ten at any distance', () {
    for (final distanceM in [42195.0, 10000.0, 160934.0]) {
      final plan = buildPhasePlan(distanceM, RacePhasePreset.tenTenTen);
      expect(weightedMeanFactor(plan), closeTo(1, 1e-9));
    }
  });

  test('negative_split is two halves: held back then a derived faster finish, mean 1', () {
    final plan = buildPhasePlan(21097.5, RacePhasePreset.negativeSplit);
    expect(plan.length, 2);
    expect(plan.map((p) => p.intent).toList(),
        [RacePhaseIntent.holdBack, RacePhaseIntent.race]);
    expect(plan[0].endM, 21097.5 / 2);
    expect(plan[1].startM, 21097.5 / 2);
    expect(plan[0].paceFactor, 1.02);
    expect(plan[1].paceFactor, closeTo((1 - 0.5 * 1.02) / 0.5, 1e-12));
    expect(weightedMeanFactor(plan), closeTo(1, 1e-9));
  });

  test('phaseAt: an exact boundary belongs to the next phase', () {
    final plan = buildPhasePlan(42195, RacePhasePreset.tenTenTen);
    expect(phaseAt(plan, 0), 0);
    expect(phaseAt(plan, plan[1].startM - 0.001), 0);
    expect(phaseAt(plan, plan[1].startM), 1);
    expect(phaseAt(plan, plan[2].startM), 2);
  });

  test('phaseAt clamps: past the end to last, negative to first, empty to -1', () {
    final plan = buildPhasePlan(42195, RacePhasePreset.tenTenTen);
    expect(phaseAt(plan, 42195), 2);
    expect(phaseAt(plan, 100000), 2);
    expect(phaseAt(plan, -5), 0);
    expect(phaseAt([], 1000), -1);
  });

  test('a non-positive or non-finite distance yields an empty plan', () {
    for (final distanceM in [0.0, -42195.0, double.nan, double.infinity]) {
      expect(buildPhasePlan(distanceM, RacePhasePreset.tenTenTen), isEmpty);
      expect(buildPhasePlan(distanceM, RacePhasePreset.negativeSplit), isEmpty);
      expect(buildPhasePlan(distanceM, RacePhasePreset.even), isEmpty);
    }
  });

  test('goalPaceSecPerKm divides the goal time over the km and rejects bad inputs', () {
    expect(goalPaceSecPerKm(10000, 3000), 300);
    expect(goalPaceSecPerKm(0, 3000), isNull);
    expect(goalPaceSecPerKm(-1, 3000), isNull);
    expect(goalPaceSecPerKm(10000, 0), isNull);
    expect(goalPaceSecPerKm(10000, -60), isNull);
    expect(goalPaceSecPerKm(double.nan, 3000), isNull);
    expect(goalPaceSecPerKm(10000, double.nan), isNull);
  });

  test('phaseTargetPaceSecPerKm scales the goal pace by the phase factor and rejects bad pace', () {
    final plan = buildPhasePlan(42195, RacePhasePreset.tenTenTen);
    expect(phaseTargetPaceSecPerKm(plan[0], 300), closeTo(306, 1e-9));
    expect(phaseTargetPaceSecPerKm(plan[1], 300), 300);
    expect(phaseTargetPaceSecPerKm(plan[0], null), isNull);
    expect(phaseTargetPaceSecPerKm(plan[0], 0), isNull);
    expect(phaseTargetPaceSecPerKm(plan[0], -300), isNull);
    expect(phaseTargetPaceSecPerKm(plan[0], double.nan), isNull);
  });

  test('preset and intent wire names are stable', () {
    expect(RacePhasePreset.values.map((p) => p.wire).toList(),
        ['ten_ten_ten', 'negative_split', 'even']);
    expect(RacePhaseIntent.values.map((i) => i.wire).toList(),
        ['hold_back', 'settle', 'race', 'even']);
  });

  test('parsePacingStrategy reads the writer shape and drops an absent goal to null', () {
    final full = parsePacingStrategy(
        {'preset': 'ten_ten_ten', 'distance_m': 42195, 'goal_time_s': 12600})!;
    expect(full.preset, RacePhasePreset.tenTenTen);
    expect(full.distanceM, 42195);
    expect(full.goalTimeS, 12600);
    final even = parsePacingStrategy({'preset': 'even', 'distance_m': 5000})!;
    expect(even.preset, RacePhasePreset.even);
    expect(even.distanceM, 5000);
    expect(even.goalTimeS, isNull);
  });

  test('parsePacingStrategy refuses an unknown preset, a bad distance, and a non-object', () {
    expect(parsePacingStrategy({'preset': 'pyramid', 'distance_m': 10000}), isNull);
    expect(parsePacingStrategy({'preset': 'even', 'distance_m': 0}), isNull);
    expect(parsePacingStrategy({'preset': 'even', 'distance_m': '5000'}), isNull);
    expect(parsePacingStrategy({'preset': 'even'}), isNull);
    expect(parsePacingStrategy('even'), isNull);
    expect(parsePacingStrategy(null), isNull);
    expect(parsePacingStrategy(<Object>[]), isNull);
  });

  test('gradePhases grades phases on moving time, so a stop does not read as a slow phase', () {
    final r = gradePhases(
        trackOf([(2500, 306), (240, null), (2500, 306), (5000, 294)]), half);
    expect(r.phases.map((p) => p.grade).toList(),
        [PhaseGrade.onTarget, PhaseGrade.onTarget]);
    expect(r.verdict, PhaseReviewVerdict.onPlan);
    expect((r.phases[0].actualPaceSecPerKm! - 306).abs(), lessThanOrEqualTo(1));
  });

  test('gradePhases without a track keeps the goal targets and grades nothing', () {
    final r = gradePhases(null, half);
    expect(r.verdict, PhaseReviewVerdict.ungraded);
    expect(r.ungradedReason, PhaseUngradedReason.noTrack);
    expect(r.completed, isFalse);
    expect(
        r.phases
            .map((p) => [p.coverage, p.targetPaceSecPerKm, p.actualPaceSecPerKm])
            .toList(),
        [
          [PhaseCoverage.notReached, 306, null],
          [PhaseCoverage.notReached, 294, null],
        ]);
  });

  test('gradePhases calls a fast first phase followed by a slow finish going out too fast', () {
    final r = gradePhases(trackOf([(5000, 290), (5000, 310)]), half);
    expect(r.phases.map((p) => p.grade).toList(),
        [PhaseGrade.fast, PhaseGrade.slow]);
    expect(r.verdict, PhaseReviewVerdict.wentOutTooFast);
    expect(r.phases[0].gapSecPerKm! < 0 && r.phases[1].gapSecPerKm! > 0, isTrue);
  });

  test('gradePhases on a run well short of the plan marks it incomplete and leaves later phases unreached', () {
    final r = gradePhases(trackOf([(3000, 306)]), half);
    expect(r.completed, isFalse);
    expect(r.phases.map((p) => p.coverage).toList(),
        [PhaseCoverage.partial, PhaseCoverage.notReached]);
    expect(r.phases[1].actualPaceSecPerKm, isNull);
    expect(r.verdict, PhaseReviewVerdict.onPlan);
  });

  test('gradePhases needs a goal time to grade a single-phase even plan', () {
    final r = gradePhases(trackOf([(5000, 300)]),
        const PacingStrategy(preset: RacePhasePreset.even, distanceM: 5000));
    expect(r.basis, PhaseTargetBasis.average);
    expect(r.verdict, PhaseReviewVerdict.ungraded);
    expect(r.ungradedReason, PhaseUngradedReason.noGoal);
    expect(r.phases[0].targetPaceSecPerKm, isNull);
  });

  test('gradePhases band: a 1.4% miss is on target, a 2.7% miss is not', () {
    expect(phaseBandPct, 0.015);
    const even = PacingStrategy(
        preset: RacePhasePreset.even, distanceM: 5000, goalTimeS: 1500);
    expect(gradePhases(trackOf([(5000, 304)]), even).phases[0].grade,
        PhaseGrade.onTarget);
    expect(gradePhases(trackOf([(5000, 308)]), even).phases[0].grade,
        PhaseGrade.slow);
    expect(gradePhases(trackOf([(5000, 292)]), even).phases[0].grade,
        PhaseGrade.fast);
  });
}

/// Race pacing-strategy phase plans — pure, locale/unit-agnostic. Slices a
/// race distance into intent phases (hold back / settle / race) whose pace
/// factors multiply the goal pace, with the derived final factor chosen so the
/// distance-weighted mean factor is exactly 1.0 — the plan still lands the
/// goal time.
///
/// Presets: even (one flat phase), negativeSplit (2% held-back first half,
/// derived-faster second half), and tenTenTen (the classic marathon
/// 10 mi / 10 mi / 10 K strategy generalised proportionally to any distance).
/// Intent is an identifier — i18n labels resolve at the render layer and are
/// not part of the pair.
///
/// [gradePhases] is the post-run half: it reads the strategy the phone stamped
/// into `runs.metadata.pacing_strategy` back against the recorded track and
/// grades each phase's actual pace against its target (decisions § 1915).
///
/// Twin of `apps/web/src/lib/runs/race_phases.ts` — keep logic, edge cases,
/// and test count in lockstep. `fixtures/race_phase_vectors.json` pins the two
/// [gradePhases] outputs to each other.
library;

import 'package:core_models/core_models.dart' show Waypoint;

import 'pace_analysis.dart' show sliceTrackAtDistances;
import 'run_stats.dart' show haversineMetres;

enum RacePhasePreset { tenTenTen, negativeSplit, even }

extension RacePhasePresetWire on RacePhasePreset {
  String get wire => switch (this) {
        RacePhasePreset.tenTenTen => 'ten_ten_ten',
        RacePhasePreset.negativeSplit => 'negative_split',
        RacePhasePreset.even => 'even',
      };
}

enum RacePhaseIntent { holdBack, settle, race, even }

extension RacePhaseIntentWire on RacePhaseIntent {
  String get wire => switch (this) {
        RacePhaseIntent.holdBack => 'hold_back',
        RacePhaseIntent.settle => 'settle',
        RacePhaseIntent.race => 'race',
        RacePhaseIntent.even => 'even',
      };
}

class RacePhase {
  final double startM;
  final double endM;
  final RacePhaseIntent intent;
  final double paceFactor;

  const RacePhase({
    required this.startM,
    required this.endM,
    required this.intent,
    required this.paceFactor,
  });
}

const double _tenMileFraction = 16093.44 / 42195;
const double _holdBackFactor = 1.02;

List<RacePhase> buildPhasePlan(double distanceM, RacePhasePreset preset) {
  if (!distanceM.isFinite || distanceM <= 0) return [];

  if (preset == RacePhasePreset.even) {
    return [
      RacePhase(
          startM: 0, endM: distanceM, intent: RacePhaseIntent.even, paceFactor: 1),
    ];
  }

  if (preset == RacePhasePreset.negativeSplit) {
    const raceFactor = (1 - 0.5 * _holdBackFactor) / 0.5;
    return [
      RacePhase(
          startM: 0,
          endM: distanceM / 2,
          intent: RacePhaseIntent.holdBack,
          paceFactor: _holdBackFactor),
      RacePhase(
          startM: distanceM / 2,
          endM: distanceM,
          intent: RacePhaseIntent.race,
          paceFactor: raceFactor),
    ];
  }

  const f1 = _tenMileFraction;
  const f2 = _tenMileFraction;
  const f3 = 1 - f1 - f2;
  const raceFactor = (1 - f1 * _holdBackFactor - f2 * 1) / f3;
  return [
    RacePhase(
        startM: 0,
        endM: distanceM * f1,
        intent: RacePhaseIntent.holdBack,
        paceFactor: _holdBackFactor),
    RacePhase(
        startM: distanceM * f1,
        endM: distanceM * (f1 + f2),
        intent: RacePhaseIntent.settle,
        paceFactor: 1),
    RacePhase(
        startM: distanceM * (f1 + f2),
        endM: distanceM,
        intent: RacePhaseIntent.race,
        paceFactor: raceFactor),
  ];
}

/// Index of the phase containing [distanceM] (start-inclusive, end-exclusive;
/// >= the last end clamps to the last index, < 0 clamps to the first).
/// Empty plan → -1.
int phaseAt(List<RacePhase> phases, double distanceM) {
  if (phases.isEmpty) return -1;
  if (distanceM < 0) return 0;
  for (var i = 0; i < phases.length; i++) {
    if (distanceM >= phases[i].startM && distanceM < phases[i].endM) return i;
  }
  return phases.length - 1;
}

double? phaseTargetPaceSecPerKm(RacePhase phase, double? goalPaceSecPerKm) {
  if (goalPaceSecPerKm == null ||
      !goalPaceSecPerKm.isFinite ||
      goalPaceSecPerKm <= 0) {
    return null;
  }
  return goalPaceSecPerKm * phase.paceFactor;
}

double? goalPaceSecPerKm(double distanceM, double goalTimeS) {
  if (!distanceM.isFinite || distanceM <= 0) return null;
  if (!goalTimeS.isFinite || goalTimeS <= 0) return null;
  return goalTimeS / (distanceM / 1000);
}

class PacingStrategy {
  final RacePhasePreset preset;
  final double distanceM;
  final double? goalTimeS;
  const PacingStrategy({
    required this.preset,
    required this.distanceM,
    this.goalTimeS,
  });
}

/// The `runs.metadata.pacing_strategy` bag as the phone writes it
/// (`{ preset, distance_m, goal_time_s? }`, docs/backend/metadata.md). Null for
/// anything the reader cannot rebuild a plan from — a preset a later build
/// added, a missing or non-positive distance — so the review renders nothing
/// rather than grading against a guess. A bad goal time drops to null and the
/// review falls back to the run's own average.
PacingStrategy? parsePacingStrategy(Object? raw) {
  if (raw is! Map) return null;
  RacePhasePreset? preset;
  for (final p in RacePhasePreset.values) {
    if (p.wire == raw['preset']) preset = p;
  }
  if (preset == null) return null;
  final d = raw['distance_m'];
  if (d is! num || !d.isFinite || d <= 0) return null;
  final g = raw['goal_time_s'];
  final goalTimeS = g is num && g.isFinite && g > 0 ? g.toDouble() : null;
  return PacingStrategy(
      preset: preset, distanceM: d.toDouble(), goalTimeS: goalTimeS);
}

/// Relative band around a phase's target pace inside which the phase is on
/// target: 1.5 %, 4.5 s/km at a 5:00/km target. It has to sit inside the 2 %
/// hold-back step, or running the hold-back phase at goal pace — the exact
/// mistake the strategy exists to prevent — would grade as on target.
const double phaseBandPct = 0.015;

/// How far the recorded distance may sit from the planned one and still count
/// as the whole race: 10 %. Inside it the phase boundaries scale to the track,
/// so a GPS line that measured a marathon 300 m long or short is cut where the
/// runner actually crossed the 10-mile marks; outside it the boundaries stay at
/// their planned metres and a short run reads as stopped short.
const double finishTolerancePct = 0.1;

/// Below this much moving distance a phase is shown but not graded.
const double minGradedPhaseM = 200;

/// A segment slower than this is a stop, not running — the threshold
/// `movingTimeOf` uses. Phase paces are moving paces, so a pause, an aid
/// station or a traffic light does not grade as a phase run slow.
const double movingMinSpeedMps = 0.5;

enum PhaseCoverage { full, partial, notReached }

enum PhaseGrade { onTarget, fast, slow }

enum PhaseTargetBasis { goal, average }

enum PhaseReviewVerdict {
  onPlan,
  wentOutTooFast,
  faded,
  negativeSplit,
  fasterThanPlan,
  slowerThanPlan,
  ungraded,
}

enum PhaseUngradedReason { noTrack, noGoal }

class PhaseResult {
  final RacePhaseIntent intent;
  final double paceFactor;

  /// Planned boundaries, metres from the start.
  final double startM;
  final double endM;
  final PhaseCoverage coverage;
  final double coveredM;
  final double movingS;
  final double movingM;
  final int? actualPaceSecPerKm;
  int? targetPaceSecPerKm;

  /// Actual minus target, seconds per km. Positive = slower than planned.
  int? gapSecPerKm;
  PhaseGrade? grade;

  PhaseResult({
    required this.intent,
    required this.paceFactor,
    required this.startM,
    required this.endM,
    required this.coverage,
    required this.coveredM,
    required this.movingS,
    required this.movingM,
    required this.actualPaceSecPerKm,
  });
}

class PhaseReview {
  final PacingStrategy strategy;
  final PhaseTargetBasis basis;
  final int? basisPaceSecPerKm;
  final double trackDistanceM;
  final bool completed;
  final List<PhaseResult> phases;
  final PhaseReviewVerdict verdict;
  final PhaseUngradedReason? ungradedReason;

  const PhaseReview({
    required this.strategy,
    required this.basis,
    required this.basisPaceSecPerKm,
    required this.trackDistanceM,
    required this.completed,
    required this.phases,
    required this.verdict,
    required this.ungradedReason,
  });
}

double _pathLength(List<Waypoint> track) {
  var total = 0.0;
  for (var i = 1; i < track.length; i++) {
    total += haversineMetres(
        track[i - 1].lat, track[i - 1].lng, track[i].lat, track[i].lng);
  }
  return total;
}

/// Grade a recorded run against the pacing strategy it was run under.
///
/// Phases are cut by DISTANCE with the same slicer `analysePacing` uses (see
/// [finishTolerancePct] for when the boundaries scale to the track). Each
/// phase's actual pace is its moving time over its moving distance. Targets
/// come from the goal time when one was set; otherwise from the run's own
/// average moving pace, re-weighted by the factors of the distance covered, so
/// the review grades the SHAPE of the run against the plan's shape — which
/// needs at least two graded phases to mean anything.
///
/// Verdict, first match wins, with g = (actual - target) / target of the first
/// (F) and last (L) graded phases and b = [phaseBandPct]:
///   no graded phase                → ungraded
///   every graded phase within b    → onPlan
///   one graded phase               → fasterThanPlan / slowerThanPlan
///   gF < -b and gL - gF > b        → wentOutTooFast
///   gL > b and gL - gF > b         → faded
///   gF - gL > b                    → negativeSplit (finished stronger than planned)
///   otherwise, by the distance-weighted mean gap → faster / slowerThanPlan
PhaseReview gradePhases(List<Waypoint>? track, PacingStrategy strategy) {
  final plan = buildPhasePlan(strategy.distanceM, strategy.preset);
  final pts = track ?? const <Waypoint>[];
  final total = pts.length >= 2 ? _pathLength(pts) : 0.0;
  final planned = strategy.distanceM;
  final withinTolerance =
      total > 0 && (total - planned).abs() <= planned * finishTolerancePct;
  final completed = total >= planned * (1 - finishTolerancePct);
  final scale = withinTolerance ? total / planned : 1.0;
  final slices = total > 0
      ? sliceTrackAtDistances(pts,
          [for (final p in plan.sublist(0, plan.length - 1)) p.endM * scale])
      : [for (final _ in plan) <Waypoint>[]];

  final phases = <PhaseResult>[];
  for (var i = 0; i < plan.length; i++) {
    final p = plan[i];
    final slice = slices[i];
    final last = i == plan.length - 1;
    final PhaseCoverage coverage;
    if (total <= p.startM * scale) {
      coverage = PhaseCoverage.notReached;
    } else if (last ? completed : total >= p.endM * scale) {
      coverage = PhaseCoverage.full;
    } else {
      coverage = PhaseCoverage.partial;
    }
    var movingS = 0.0;
    var movingM = 0.0;
    for (var j = 1; j < slice.length; j++) {
      final a = slice[j - 1].timestamp;
      final b = slice[j].timestamp;
      if (a == null || b == null) continue;
      final dt = b.difference(a).inMilliseconds / 1000;
      if (dt <= 0) continue;
      final d = haversineMetres(
          slice[j - 1].lat, slice[j - 1].lng, slice[j].lat, slice[j].lng);
      if (d / dt < movingMinSpeedMps) continue;
      movingS += dt;
      movingM += d;
    }
    final graded = movingM >= minGradedPhaseM && movingS > 0;
    phases.add(PhaseResult(
      intent: p.intent,
      paceFactor: p.paceFactor,
      startM: p.startM,
      endM: p.endM,
      coverage: coverage,
      coveredM: slice.length >= 2 ? _pathLength(slice) : 0,
      movingS: movingS,
      movingM: movingM,
      actualPaceSecPerKm:
          graded ? (movingS / (movingM / 1000)).round() : null,
    ));
  }

  final measured =
      phases.where((p) => p.actualPaceSecPerKm != null).toList();
  var basis = PhaseTargetBasis.goal;
  double? basisPace;
  PhaseUngradedReason? ungradedReason;
  if (strategy.goalTimeS != null) {
    basisPace = goalPaceSecPerKm(planned, strategy.goalTimeS!);
  } else {
    basis = PhaseTargetBasis.average;
    if (measured.length >= 2) {
      final sumS = measured.fold<double>(0, (s, p) => s + p.movingS);
      final sumM = measured.fold<double>(0, (s, p) => s + p.movingM);
      final weighted =
          measured.fold<double>(0, (s, p) => s + p.paceFactor * p.movingM) /
              sumM;
      basisPace = sumS / (sumM / 1000) / weighted;
    }
  }
  if (measured.isEmpty) {
    ungradedReason = PhaseUngradedReason.noTrack;
  } else if (basisPace == null) {
    ungradedReason = PhaseUngradedReason.noGoal;
  }

  if (basisPace != null) {
    for (final p in phases) {
      final target = (basisPace * p.paceFactor).round();
      p.targetPaceSecPerKm = target;
      final actual = p.actualPaceSecPerKm;
      if (actual == null) continue;
      final gap = actual - target;
      p.gapSecPerKm = gap;
      final rel = gap / target;
      p.grade = rel.abs() <= phaseBandPct
          ? PhaseGrade.onTarget
          : rel < 0
              ? PhaseGrade.fast
              : PhaseGrade.slow;
    }
  }

  return PhaseReview(
    strategy: strategy,
    basis: basis,
    basisPaceSecPerKm: basisPace?.round(),
    trackDistanceM: total,
    completed: completed,
    phases: phases,
    verdict: _verdictOf(phases.where((p) => p.grade != null).toList()),
    ungradedReason: ungradedReason,
  );
}

PhaseReviewVerdict _verdictOf(List<PhaseResult> graded) {
  if (graded.isEmpty) return PhaseReviewVerdict.ungraded;
  if (graded.every((p) => p.grade == PhaseGrade.onTarget)) {
    return PhaseReviewVerdict.onPlan;
  }
  double rel(PhaseResult p) => p.gapSecPerKm! / p.targetPaceSecPerKm!;
  if (graded.length == 1) {
    return rel(graded.first) < 0
        ? PhaseReviewVerdict.fasterThanPlan
        : PhaseReviewVerdict.slowerThanPlan;
  }
  final gF = rel(graded.first);
  final gL = rel(graded.last);
  if (gF < -phaseBandPct && gL - gF > phaseBandPct) {
    return PhaseReviewVerdict.wentOutTooFast;
  }
  if (gL > phaseBandPct && gL - gF > phaseBandPct) {
    return PhaseReviewVerdict.faded;
  }
  if (gF - gL > phaseBandPct) return PhaseReviewVerdict.negativeSplit;
  final gap = graded.fold<double>(0, (s, p) => s + p.gapSecPerKm! * p.movingM);
  return gap < 0
      ? PhaseReviewVerdict.fasterThanPlan
      : PhaseReviewVerdict.slowerThanPlan;
}

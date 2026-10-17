/// Multi-distance race-time predictor.
///
/// Dart twin of `apps/web/src/lib/training/race_predictor.ts` — keep the
/// algorithm, edge cases, outputs, and test counts in lockstep. Projects the
/// whole standard race ladder (5K / 10K / Half / Marathon) from a pool of
/// qualifying efforts in one pass: the anchor is the recency-weighted best
/// Riegel equivalent (a recent strong effort outranks a stale PR), and each
/// rung's confidence reuses `predictionConfidence` from training.dart with the
/// same thresholds the single-distance race panel uses.
///
/// Pure — no Flutter / Supabase. Reuses `riegelPredict` + `predictionConfidence`
/// from training.dart so the numbers can't drift from the engine.

import 'dart:math';

import 'training.dart'
    show
        riegelPredict,
        predictionConfidence,
        PredictionConfidence,
        PredictionQuality;

/// The standard race ladder we project, in metres (5K / 10K / Half / Marathon).
/// Matches `kGoalDistancesM` in training.dart; ordered shortest-to-longest.
const List<double> kRaceLadderM = [5000, 10000, 21097.5, 42195];

/// A single qualifying effort feeding the predictor — the minimal shape
/// (distance, time, age) so the caller maps a run down to it.
class EffortForPrediction {
  final double distanceM;
  final int durationS;

  /// Age of the effort in days at prediction time (>= 0).
  final double ageDays;

  const EffortForPrediction({
    required this.distanceM,
    required this.durationS,
    required this.ageDays,
  });
}

class LadderPrediction {
  /// Target race distance in metres (one of [kRaceLadderM]).
  final double distanceM;

  /// Predicted finish time in seconds.
  final double predictedSec;

  /// Predicted average pace in seconds per km.
  final double paceSecPerKm;

  /// Data-quality grade for THIS rung.
  final PredictionQuality quality;

  const LadderPrediction({
    required this.distanceM,
    required this.predictedSec,
    required this.paceSecPerKm,
    required this.quality,
  });
}

class RaceLadderAnchor {
  final double distanceM;
  final int durationS;
  final double ageDays;
  const RaceLadderAnchor(this.distanceM, this.durationS, this.ageDays);
}

class RacePrediction {
  /// The anchor effort the whole ladder is projected from.
  final RaceLadderAnchor anchor;

  /// Number of qualifying efforts that fed the anchor selection.
  final int qualifyingCount;

  /// One prediction per ladder rung, shortest-to-longest.
  final List<LadderPrediction> rungs;

  const RacePrediction({
    required this.anchor,
    required this.qualifyingCount,
    required this.rungs,
  });
}

/// Half-life (days) of the recency weight applied when picking the anchor
/// effort. At 30 days an effort counts half as much as a same-quality effort
/// today. Matches the ~30-day "recent" cliff in `predictionConfidence`.
const double kAnchorRecencyHalflifeDays = 30;

/// Reference distance the anchor comparison is normalised to (10K — the middle
/// of the ladder). Only affects WHICH effort wins the anchor slot, never the
/// final per-rung predictions (those project from the anchor's real
/// distance + time).
const double _anchorReferenceM = 10000;

double _recencyWeight(double ageDays) {
  final age = ageDays < 0 ? 0.0 : ageDays;
  return pow(0.5, age / kAnchorRecencyHalflifeDays).toDouble();
}

/// Build the multi-distance race prediction from a pool of qualifying efforts.
///
/// Returns null when the pool is empty — the caller hides the surface rather
/// than showing a fabricated ladder (fail-closed). Anchor selection
/// Riegel-equivalences each effort to [_anchorReferenceM] and picks the one
/// whose recency-weighted equivalent time is fastest; the ladder then projects
/// from the chosen anchor's ACTUAL distance + time.
RacePrediction? predictRaceLadder(List<EffortForPrediction> efforts) {
  // `> 0` alone admits an infinite distance (durationS is an int, so only
  // the double can be one), which projects to NaN, can never win the
  // anchor, and still counted toward `qualifyingCount` — and a pool of
  // nothing else left no anchor at all and threw.
  final pool = efforts
      .where((e) =>
          e.distanceM.isFinite &&
          e.distanceM > 0 &&
          e.durationS > 0 &&
          e.ageDays.isFinite)
      .toList();
  if (pool.isEmpty) return null;

  EffortForPrediction? best;
  var bestEffectiveSec = double.infinity;
  for (final e in pool) {
    final equivSec = riegelPredict(e.distanceM, e.durationS, _anchorReferenceM);
    final weight = _recencyWeight(e.ageDays);
    final effectiveSec = weight > 0 ? equivSec / weight : double.infinity;
    if (effectiveSec < bestEffectiveSec) {
      bestEffectiveSec = effectiveSec;
      best = e;
    }
  }
  // Every effort had weight 0 (all impossibly old) — fall back to the raw
  // fastest equivalent so we still anchor on something rather than null out.
  if (best == null) {
    bestEffectiveSec = double.infinity;
    for (final e in pool) {
      final equivSec =
          riegelPredict(e.distanceM, e.durationS, _anchorReferenceM);
      if (equivSec < bestEffectiveSec) {
        bestEffectiveSec = equivSec;
        best = e;
      }
    }
  }
  final anchor = best!;

  final rungs = kRaceLadderM.map((distanceM) {
    final predictedSec =
        riegelPredict(anchor.distanceM, anchor.durationS, distanceM);
    return LadderPrediction(
      distanceM: distanceM,
      predictedSec: predictedSec,
      paceSecPerKm: predictedSec / (distanceM / 1000),
      quality: predictionConfidence(
        knownDistanceM: anchor.distanceM,
        targetDistanceM: distanceM,
        daysSinceBest: anchor.ageDays.round(),
        qualifyingRunCount: pool.length,
      ),
    );
  }).toList();

  return RacePrediction(
    anchor: RaceLadderAnchor(anchor.distanceM, anchor.durationS, anchor.ageDays),
    qualifyingCount: pool.length,
    rungs: rungs,
  );
}

/// How much faster than the recent-runs projection a goal has to be before the
/// plan wizard says so. Generous on purpose: the anchor is usually a training
/// run rather than a race, so it under-reads race fitness, and a goal a few
/// percent quicker than it is an ordinary race goal, not an ambitious one.
const double kGoalAheadMargin = 0.1;

/// Is a plan's goal time faster than the runner's recent running supports?
///
/// With no confirmed recent 5K, the plan sets every pace from the goal time,
/// so an ambitious or stale goal gives easy and interval paces that are too
/// fast. This projects the goal distance from the same recency-weighted anchor
/// the race predictor uses and returns that projection (seconds) when the goal
/// beats it by more than [kGoalAheadMargin], or null otherwise.
///
/// Fail-closed: no usable effort, a non-positive goal, or a projection whose
/// confidence is `low` (a far extrapolation, a stale anchor, a thin pool) all
/// return null. Telling a runner their goal is unrealistic off a guess would
/// be worse than saying nothing.
double? goalAheadOfRecentRuns(
  double goalDistanceM,
  int? goalTimeSec,
  List<EffortForPrediction> efforts,
) {
  if (goalTimeSec == null || goalTimeSec <= 0) return null;
  if (!goalDistanceM.isFinite || goalDistanceM <= 0) return null;
  final prediction = predictRaceLadder(efforts);
  if (prediction == null) return null;
  final anchor = prediction.anchor;
  final quality = predictionConfidence(
    knownDistanceM: anchor.distanceM,
    targetDistanceM: goalDistanceM,
    daysSinceBest: anchor.ageDays.round(),
    qualifyingRunCount: prediction.qualifyingCount,
  );
  if (quality.confidence == PredictionConfidence.low) return null;
  final predictedSec =
      riegelPredict(anchor.distanceM, anchor.durationS, goalDistanceM);
  if (goalTimeSec >= predictedSec * (1 - kGoalAheadMargin)) return null;
  return predictedSec;
}

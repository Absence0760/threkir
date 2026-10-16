/// A mini-taper and a recovery window around each B and C race a plan holds
/// (decisions § 2051). The plan's phases (base/build/peak/taper/race) come
/// from week position toward the end date, so they only ever taper for the A
/// race; a B race in week 14 of a 30-week block got no easing either side of
/// it. Pure: takes the plan's workouts, its races ([planRaces]) and today, and
/// proposes per-workout changes the plan screen previews before applying.
///
/// Dart twin of `apps/web/src/lib/training/race_taper.ts` — keep the windows,
/// scales, tie-breaks and test counts in lockstep.
library;

import 'cycle_plan.dart' show daysBetweenIso;
import 'plan_races.dart';

/// Days before a B race whose sessions are cut, and the cut: 35% off volume
/// across the 6 days, every quality session run easy. A tune-up race wants a
/// mini-taper of about a week at a 30-40% reduction, not the 2-3 weeks an A
/// race gets (Pfitzinger, Advanced Marathoning, tune-up races; Mujika &
/// Padilla 2003: volume is the lever, intensity can stay — but a B race is
/// the intensity that week, so the quality session goes).
const int bTaperDays = 6;
const double bTaperScale = 0.65;

/// The last 2 days before a B race carry only an easy shakeout: half the
/// prescribed distance, never more than 5 km.
const int bShakeoutDays = 2;
const double shakeoutScale = 0.5;
const double shakeoutMaxM = 5000;

/// Easy days after a B race: one per 3 km raced, held between 4 and 7
/// (5 when the race has no distance). The "a day per mile raced" rule is for
/// an all-out A effort; a B race is run hard off a short taper, so half that
/// density, inside the 4-7 day window a 10 km-to-half recovers in.
const int bRecoveryKmPerDay = 3;
const int bRecoveryMinDays = 4;
const int bRecoveryMaxDays = 7;
const int bRecoveryDefaultDays = 5;

/// A C race is a training-load race (a parkrun, a club 10 km): 3 days before
/// eased by 20%, quality run easy, and 2 easy days after.
const int cTaperDays = 3;
const double cTaperScale = 0.8;
const int cRecoveryDays = 2;

/// The long run inside a recovery window is held to 75% of its prescription.
const double recoveryLongScale = 0.75;

const Set<String> _qualityKinds = {'tempo', 'interval', 'marathon_pace'};

/// The A race's own taper already governs these weeks; a B race inside them
/// does not get to cut it twice.
const Set<String> _protectedPhases = {'taper', 'race'};

enum RaceTaperReason { preRace, shakeout, postRace }

class RaceTaperWorkout {
  final String id;
  final String scheduledDate;
  final String kind;
  final double? targetDistanceM;

  /// Phase of the week the workout sits in, when known.
  final String? phase;

  /// Linked to a run or ticked done by hand.
  final bool completed;
  final bool skipped;

  const RaceTaperWorkout({
    required this.id,
    required this.scheduledDate,
    required this.kind,
    required this.targetDistanceM,
    this.phase,
    this.completed = false,
    this.skipped = false,
  });
}

class RaceTaperChange {
  final String workoutId;
  final String scheduledDate;
  final RaceTaperReason reason;
  final String raceDate;
  final String? raceName;
  final String racePriority;
  final String fromKind;
  final String toKind;
  final double? fromMetres;
  final double? toMetres;

  /// The session loses its pace target, tolerance and interval structure.
  final bool clearsPace;

  const RaceTaperChange({
    required this.workoutId,
    required this.scheduledDate,
    required this.reason,
    required this.raceDate,
    required this.raceName,
    required this.racePriority,
    required this.fromKind,
    required this.toKind,
    required this.fromMetres,
    required this.toMetres,
    required this.clearsPace,
  });
}

int _severity(RaceTaperReason r) => switch (r) {
      RaceTaperReason.shakeout => 3,
      RaceTaperReason.preRace => 2,
      RaceTaperReason.postRace => 1,
    };

int _recoveryDays(PlanRace race) {
  if (race.priority == 'C') return cRecoveryDays;
  final d = race.distanceM;
  if (d == null || !(d > 0)) return bRecoveryDefaultDays;
  final days = (d / 1000 / bRecoveryKmPerDay).round();
  return days.clamp(bRecoveryMinDays, bRecoveryMaxDays);
}

RaceTaperReason? _windowFor(PlanRace race, int offset) {
  if (offset < 0) {
    final before = -offset;
    if (race.priority == 'B') {
      if (before <= bShakeoutDays) return RaceTaperReason.shakeout;
      return before <= bTaperDays ? RaceTaperReason.preRace : null;
    }
    return before <= cTaperDays ? RaceTaperReason.preRace : null;
  }
  if (offset > 0 && offset <= _recoveryDays(race)) {
    return RaceTaperReason.postRace;
  }
  return null;
}

double? _scaled(double? m, double scale) =>
    m == null ? null : (m * scale).roundToDouble();

({String toKind, double? toMetres, bool clearsPace}) _adjust(
    RaceTaperWorkout w, RaceTaperReason reason, String priority) {
  final quality = _qualityKinds.contains(w.kind);
  // Only a quality session or a long run changes kind: an easy, recovery or
  // walk/run day is already the right kind of session, just shorter.
  final eased = quality || w.kind == 'long' ? 'easy' : w.kind;
  switch (reason) {
    case RaceTaperReason.shakeout:
      final half = _scaled(w.targetDistanceM, shakeoutScale);
      return (
        toKind: eased,
        toMetres: half == null ? null : (half < shakeoutMaxM ? half : shakeoutMaxM),
        clearsPace: quality,
      );
    case RaceTaperReason.preRace:
      final scale = priority == 'B' ? bTaperScale : cTaperScale;
      return (
        toKind: eased,
        toMetres: _scaled(w.targetDistanceM, scale),
        clearsPace: quality,
      );
    case RaceTaperReason.postRace:
      if (quality) {
        return (toKind: 'easy', toMetres: w.targetDistanceM, clearsPace: true);
      }
      if (w.kind == 'long') {
        return (
          toKind: 'long',
          toMetres: _scaled(w.targetDistanceM, recoveryLongScale),
          clearsPace: false,
        );
      }
      return (toKind: w.kind, toMetres: w.targetDistanceM, clearsPace: false);
  }
}

/// The proposed changes around every B and C race dated after [today],
/// sorted by date then workout id. Expects [races] sorted, as [planRaces]
/// returns them. Only workouts dated today or later that are not done,
/// skipped, a rest day, a race, or inside the A race's taper/race weeks are
/// touched. A workout inside two races' windows takes the stronger rule
/// (shakeout, then taper, then recovery; then the B race, then the earlier
/// race). A workout the rule would leave unchanged yields no change.
List<RaceTaperChange> raceTaperProposals({
  required List<RaceTaperWorkout> workouts,
  required List<PlanRace> races,
  required String today,
}) {
  final candidates = [
    for (final r in races)
      if ((r.priority == 'B' || r.priority == 'C') &&
          r.date.compareTo(today) > 0)
        r,
  ];
  final changes = <RaceTaperChange>[];
  for (final w in workouts) {
    if (w.scheduledDate.compareTo(today) < 0) continue;
    if (w.completed || w.skipped) continue;
    if (w.kind == 'rest' || w.kind == 'race') continue;
    if (w.phase != null && _protectedPhases.contains(w.phase)) continue;
    RaceTaperReason? bestReason;
    PlanRace? bestRace;
    for (final race in candidates) {
      final offset = daysBetweenIso(race.date, w.scheduledDate);
      if (offset == null) continue;
      final reason = _windowFor(race, offset);
      if (reason == null) continue;
      if (bestReason == null ||
          _severity(reason) > _severity(bestReason) ||
          (_severity(reason) == _severity(bestReason) &&
              race.priority == 'B' &&
              bestRace!.priority == 'C')) {
        bestReason = reason;
        bestRace = race;
      }
    }
    if (bestReason == null || bestRace == null) continue;
    final a = _adjust(w, bestReason, bestRace.priority);
    if (a.toKind == w.kind &&
        a.toMetres == w.targetDistanceM &&
        !a.clearsPace) {
      continue;
    }
    changes.add(RaceTaperChange(
      workoutId: w.id,
      scheduledDate: w.scheduledDate,
      reason: bestReason,
      raceDate: bestRace.date,
      raceName: bestRace.name,
      racePriority: bestRace.priority,
      fromKind: w.kind,
      toKind: a.toKind,
      fromMetres: w.targetDistanceM,
      toMetres: a.toMetres,
      clearsPace: a.clearsPace,
    ));
  }
  changes.sort((x, y) {
    final byDate = x.scheduledDate.compareTo(y.scheduledDate);
    if (byDate != 0) return byDate;
    return x.workoutId.compareTo(y.workoutId);
  });
  return changes;
}

/// The plan_workouts columns one change writes, keyed by column name.
Map<String, Object?> raceTaperPatch(RaceTaperChange c) {
  final patch = <String, Object?>{};
  if (c.toKind != c.fromKind) patch['kind'] = c.toKind;
  if (c.toMetres != c.fromMetres) patch['target_distance_m'] = c.toMetres;
  if (c.clearsPace) {
    patch['target_pace_sec_per_km'] = null;
    patch['target_pace_tolerance_sec'] = null;
    patch['structure'] = null;
  }
  return patch;
}

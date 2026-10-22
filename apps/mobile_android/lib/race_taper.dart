/// A mini-taper and a recovery window around each B and C race a plan holds
/// (decisions § 2051). The plan's phases (base/build/peak/taper/race) come
/// from week position toward the end date, so they only ever taper for the A
/// race; a B race in week 14 of a 30-week block got no easing either side of
/// it. Pure: takes the plan's workouts, its races ([planRaces]) and today, and
/// proposes per-workout changes the plan screen previews before applying.
///
/// Dart twin of `apps/web/src/lib/training/race_taper.ts` — keep the windows,
/// scales, tie-breaks and test counts in lockstep. The windows also have a
/// one-way SQL copy, `private.in_bc_race_window` (migration 20271021000050,
/// decisions § 2230): a window change here needs a new migration there.
library;

import 'dart:math' show min;

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

/// Past the marathon a B race costs more than a week: the recovery keeps the
/// 7 days a marathon gets and adds a day per 2 km beyond it, up to 21.
/// Mirrors race_taper.ts.
const int bUltraRecoveryKmPerDay = 2;
const int bUltraRecoveryMaxDays = 21;

/// An ultra B race's taper starts 8 days out instead of 6, so the whole
/// weekend before it is eased. Mirrors race_taper.ts.
const int bUltraTaperDays = 8;
const double _marathonM = 42195;

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
  final int? targetDurationSeconds;

  /// The workout's `structure` jsonb; only a walk/run's is rebuilt.
  final Object? structure;
  final String? notes;

  /// Phase of the week the workout sits in, when known.
  final String? phase;

  /// Linked to a run or ticked done by hand.
  final bool completed;
  final bool skipped;

  /// Already eased by an applied taper (`race_taper_applied_at`). Its
  /// distance is the eased one, so scaling it again would compound.
  final bool taperApplied;

  const RaceTaperWorkout({
    required this.id,
    required this.scheduledDate,
    required this.kind,
    required this.targetDistanceM,
    this.targetDurationSeconds,
    this.structure,
    this.notes,
    this.phase,
    this.completed = false,
    this.skipped = false,
    this.taperApplied = false,
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
  final int? fromDurationS;
  final int? toDurationS;

  /// The session loses its pace target, tolerance and interval structure.
  final bool clearsPace;

  /// `structure` is rewritten to [toStructure]: a walk/run's repeats cut to
  /// the shorter session, or null when the kind changes under it.
  final bool structureChanged;
  final Map<String, Object?>? toStructure;

  /// The notes described a session that no longer exists (the kind changed,
  /// or a walk/run's structure was rebuilt), so they are cleared.
  final bool clearsNotes;

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
    this.fromDurationS,
    this.toDurationS,
    required this.clearsPace,
    this.structureChanged = false,
    this.toStructure,
    this.clearsNotes = false,
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
  if (d > _marathonM) {
    final extra = (d - _marathonM) / 1000 / bUltraRecoveryKmPerDay;
    return min(bUltraRecoveryMaxDays, (bRecoveryMaxDays + extra).round());
  }
  final days = (d / 1000 / bRecoveryKmPerDay).round();
  return days.clamp(bRecoveryMinDays, bRecoveryMaxDays);
}

RaceTaperReason? _windowFor(PlanRace race, int offset) {
  if (offset < 0) {
    final before = -offset;
    if (race.priority == 'B') {
      if (before <= bShakeoutDays) return RaceTaperReason.shakeout;
      final d = race.distanceM;
      final taperDays =
          d != null && d > _marathonM ? bUltraTaperDays : bTaperDays;
      return before <= taperDays ? RaceTaperReason.preRace : null;
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

/// A walk/run structure cut by [factor]: the repeat count scales (rounded, at
/// least one) and the run and walk lengths stay — they are the runner's stage
/// of the progression, which a taper week does not move. A single continuous
/// run (count 1) scales its run length instead. Null when nothing changes.
Map<String, Object?>? _scaledWalkRun(Object? structure, double factor) {
  if (structure is! Map || structure['repeats'] is! Map) return null;
  final s = Map<String, Object?>.from(structure);
  final reps = Map<String, Object?>.from(structure['repeats'] as Map);
  final rawCount = reps['count'];
  final count = rawCount is num ? rawCount : 1;
  if (count > 1) {
    final next = (count * factor).round();
    final clamped = next < 1 ? 1 : next;
    if (clamped == count) return null;
    return {...s, 'repeats': {...reps, 'count': clamped}};
  }
  final dur = reps['duration_s'];
  if (dur is! num) return null;
  final next = (dur * factor).round();
  final clamped = next < 1 ? 1 : next;
  if (clamped == dur) return null;
  return {...s, 'repeats': {...reps, 'duration_s': clamped}};
}

num _secs(Object? v) => v is num && v.isFinite ? v : 0;

/// Total seconds a walk/run structure prescribes: warm-up, every run, the
/// walks between them, cool-down.
num _walkRunSeconds(Map<String, Object?> structure) {
  final reps = structure['repeats'] is Map ? structure['repeats'] as Map : const {};
  final rawCount = reps['count'];
  final count = rawCount is num ? rawCount : 1;
  final warm = structure['warmup'] is Map
      ? _secs((structure['warmup'] as Map)['duration_s'])
      : 0;
  final cool = structure['cooldown'] is Map
      ? _secs((structure['cooldown'] as Map)['duration_s'])
      : 0;
  return warm +
      count * _secs(reps['duration_s']) +
      (count - 1 < 0 ? 0 : count - 1) * _secs(reps['recovery_duration_s']) +
      cool;
}

/// The rule's volume factor before any cap: what a session with no distance
/// is scaled by.
double _ruleScale(RaceTaperWorkout w, RaceTaperReason reason, String priority) =>
    switch (reason) {
      RaceTaperReason.shakeout => shakeoutScale,
      RaceTaperReason.preRace => priority == 'B' ? bTaperScale : cTaperScale,
      RaceTaperReason.postRace => w.kind == 'long' ? recoveryLongScale : 1,
    };

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
/// skipped, a rest day, a race, already eased by an applied taper, or inside
/// the A race's taper/race weeks are touched. A workout inside two races' windows takes the stronger rule
/// (shakeout, then taper, then recovery; then the B race, then the earlier
/// race). A workout the rule would leave unchanged yields no change. The
/// whole prescription eases together (issue #1183): duration by the factor
/// the distance moved, a walk/run's repeats cut to match, and notes cleared
/// once they describe a session that no longer exists.
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
    if (w.completed || w.skipped || w.taperApplied) continue;
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
    // The factor the distance actually moved by (the shakeout's 5 km cap
    // included), so duration and structure shrink with it; the rule's own
    // factor when there is no distance to measure by.
    final from = w.targetDistanceM;
    final factor = from != null && from > 0 && a.toMetres != null
        ? a.toMetres! / from
        : _ruleScale(w, bestReason, bestRace.priority);
    final kindChanged = a.toKind != w.kind;
    Map<String, Object?>? toStructure;
    var structureChanged = false;
    Map<String, Object?>? rebuiltWalkRun;
    if (!a.clearsPace && kindChanged && w.structure != null) {
      structureChanged = true;
    } else if (!a.clearsPace && w.kind == 'walk_run') {
      rebuiltWalkRun = _scaledWalkRun(w.structure, factor);
      if (rebuiltWalkRun != null) {
        toStructure = rebuiltWalkRun;
        structureChanged = true;
      }
    }
    final fromDuration = w.targetDurationSeconds;
    final int? toDurationS = fromDuration == null
        ? null
        : rebuiltWalkRun != null && _walkRunSeconds(rebuiltWalkRun) > 0
            ? _walkRunSeconds(rebuiltWalkRun).round()
            : (fromDuration * factor).round();
    final clearsNotes =
        w.notes != null && (kindChanged || rebuiltWalkRun != null);
    if (!kindChanged &&
        a.toMetres == w.targetDistanceM &&
        !a.clearsPace &&
        toDurationS == fromDuration &&
        !structureChanged &&
        !clearsNotes) {
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
      fromDurationS: fromDuration,
      toDurationS: toDurationS,
      clearsPace: a.clearsPace,
      structureChanged: structureChanged,
      toStructure: toStructure,
      clearsNotes: clearsNotes,
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
  if (c.toDurationS != c.fromDurationS) {
    patch['target_duration_seconds'] = c.toDurationS;
  }
  if (c.clearsPace) {
    patch['target_pace_sec_per_km'] = null;
    patch['target_pace_tolerance_sec'] = null;
    patch['structure'] = null;
  } else if (c.structureChanged) {
    patch['structure'] = c.toStructure;
  }
  if (c.clearsNotes) patch['notes'] = null;
  return patch;
}

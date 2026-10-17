// Display derivations for one planned workout: the segment timeline, its
// total, the walk-run pattern a beginner reads instead of a distance and a
// pace, and the name behind a pace-zone code. Pure and locale-free; each
// platform formats the result with its own catalogue.
//
// Parity pair with apps/web/src/lib/training/workout_summary.ts — keep in
// lockstep (docs/architecture/parity_pairs.md).

import 'training.dart' show WorkoutStructure;

enum SegmentRole { warmup, work, recovery, steady, cooldown }

class StructureSegment {
  final SegmentRole role;

  /// Share of the session's summed magnitude, 0-1.
  final double fraction;
  const StructureSegment(this.role, this.fraction);
}

typedef _Measured = ({num? distanceM, num? durationS});

num? _positive(Object? n) =>
    n is num && n.isFinite && n > 0 ? n : null;

_Measured _measured(Map<String, dynamic>? block) =>
    (distanceM: _positive(block?['distance_m']), durationS: _positive(block?['duration_s']));

// A step is measured by its distance when it names one, else its duration,
// which is the order the recorder reads them in.
num _magnitude(_Measured m) => m.distanceM ?? m.durationS ?? 0;

int _repCount(Map<String, dynamic> r) {
  final c = r['count'];
  return c is num && c.isFinite && c > 0 ? c.floor() : 0;
}

/// The steps the recorder runs, in order. A recovery sits BETWEEN
/// consecutive reps, never after the last one, matching expandWorkoutSteps.
List<({SegmentRole role, _Measured step})> _executedSteps(WorkoutStructure s) {
  final out = <({SegmentRole role, _Measured step})>[];
  final warmup = _measured(s.warmup);
  if (s.warmup != null && _magnitude(warmup) > 0) {
    out.add((role: SegmentRole.warmup, step: warmup));
  }
  final r = s.repeats;
  if (r != null) {
    final rep = _measured(r);
    if (_magnitude(rep) > 0) {
      final count = _repCount(r);
      final _Measured recovery = (
        distanceM: _positive(r['recovery_distance_m']),
        durationS: _positive(r['recovery_duration_s']),
      );
      final hasRecovery = _magnitude(recovery) > 0;
      for (var i = 0; i < count; i++) {
        out.add((role: SegmentRole.work, step: rep));
        if (hasRecovery && i < count - 1) {
          out.add((role: SegmentRole.recovery, step: recovery));
        }
      }
    }
  }
  final steady = _measured(s.steady);
  if (s.steady != null && _magnitude(steady) > 0) {
    out.add((role: SegmentRole.steady, step: steady));
  }
  final cooldown = _measured(s.cooldown);
  if (s.cooldown != null && _magnitude(cooldown) > 0) {
    out.add((role: SegmentRole.cooldown, step: cooldown));
  }
  return out;
}

/// One proportional bar per executed step. The fractions mix metres and
/// seconds when a session mixes the two, which is acceptable for a picture
/// and is why [structureTotal] refuses to sum such a session.
List<StructureSegment> structureSegments(WorkoutStructure? s) {
  if (s == null) return const [];
  final steps = _executedSteps(s);
  final total = steps.fold<num>(0, (sum, x) => sum + _magnitude(x.step));
  if (total <= 0) return const [];
  return [
    for (final x in steps) StructureSegment(x.role, _magnitude(x.step) / total),
  ];
}

sealed class StructureTotal {
  const StructureTotal();
}

class StructureTotalDistance extends StructureTotal {
  final num metres;
  const StructureTotalDistance(this.metres);
  @override
  bool operator ==(Object other) =>
      other is StructureTotalDistance && other.metres == metres;
  @override
  int get hashCode => metres.hashCode;
}

class StructureTotalDuration extends StructureTotal {
  final num seconds;
  const StructureTotalDuration(this.seconds);
  @override
  bool operator ==(Object other) =>
      other is StructureTotalDuration && other.seconds == seconds;
  @override
  int get hashCode => seconds.hashCode;
}

/// The session's total, only when every executed step uses one measure.
StructureTotal? structureTotal(WorkoutStructure? s) {
  if (s == null) return null;
  final steps = _executedSteps(s);
  if (steps.isEmpty) return null;
  if (steps.every((x) => x.step.distanceM != null)) {
    return StructureTotalDistance(
        steps.fold<num>(0, (sum, x) => sum + x.step.distanceM!));
  }
  if (steps.every((x) => x.step.distanceM == null && x.step.durationS != null)) {
    return StructureTotalDuration(
        steps.fold<num>(0, (sum, x) => sum + x.step.durationS!));
  }
  return null;
}

class WalkRunPattern {
  final num? warmupS;
  final int count;
  final num runS;

  /// Null when the session is one continuous run (the graduation week).
  final num? walkS;
  final num? cooldownS;
  final num totalS;

  const WalkRunPattern({
    required this.warmupS,
    required this.count,
    required this.runS,
    required this.walkS,
    required this.cooldownS,
    required this.totalS,
  });

  @override
  bool operator ==(Object other) =>
      other is WalkRunPattern &&
      other.warmupS == warmupS &&
      other.count == count &&
      other.runS == runS &&
      other.walkS == walkS &&
      other.cooldownS == cooldownS &&
      other.totalS == totalS;

  @override
  int get hashCode =>
      Object.hash(warmupS, count, runS, walkS, cooldownS, totalS);
}

// Seconds when [block] is measured by time only; [_mixed] when it names a
// distance; null when absent.
const Object _mixed = Object();
Object? _timeOnly(Map<String, dynamic>? block) {
  if (block == null) return null;
  final m = _measured(block);
  if (m.distanceM != null) return _mixed;
  return m.durationS;
}

/// The timed pattern of a walk-run session (a repeats block whose recovery
/// is a walk, the same test expandWorkoutSteps uses), or null for any other
/// session and for one that measures a step by distance.
WalkRunPattern? walkRunPattern(WorkoutStructure? s) {
  final r = s?.repeats;
  if (s == null || r == null || r['recovery_pace'] != 'walk') return null;
  final runS = _timeOnly(r);
  final count = _repCount(r);
  if (runS is! num || count == 0) return null;
  if (_positive(r['recovery_distance_m']) != null) return null;
  final warmupS = _timeOnly(s.warmup);
  final cooldownS = _timeOnly(s.cooldown);
  if (identical(warmupS, _mixed) ||
      identical(cooldownS, _mixed) ||
      s.steady != null) {
    return null;
  }
  final walk = _positive(r['recovery_duration_s']);
  final walkS = count > 1 && walk != null ? walk : null;
  final w = warmupS as num?;
  final c = cooldownS as num?;
  return WalkRunPattern(
    warmupS: w,
    count: count,
    runS: runS,
    walkS: walkS,
    cooldownS: c,
    totalS: (w ?? 0) +
        count * runS +
        (walkS != null ? (count - 1) * walkS : 0) +
        (c ?? 0),
  );
}

sealed class SpokenDuration {
  const SpokenDuration();
}

class SpokenMinutes extends SpokenDuration {
  final int minutes;
  const SpokenMinutes(this.minutes);
  @override
  bool operator ==(Object other) =>
      other is SpokenMinutes && other.minutes == minutes;
  @override
  int get hashCode => minutes.hashCode;
}

class SpokenSeconds extends SpokenDuration {
  final int seconds;
  const SpokenSeconds(this.seconds);
  @override
  bool operator ==(Object other) =>
      other is SpokenSeconds && other.seconds == seconds;
  @override
  int get hashCode => seconds.hashCode;
}

class SpokenMinSec extends SpokenDuration {
  final int minutes;
  final int seconds;
  const SpokenMinSec(this.minutes, this.seconds);
  @override
  bool operator ==(Object other) =>
      other is SpokenMinSec &&
      other.minutes == minutes &&
      other.seconds == seconds;
  @override
  int get hashCode => Object.hash(minutes, seconds);
}

/// How an interval length reads aloud: whole minutes as minutes, anything
/// under two minutes that isn't whole as seconds ("90 s"), else both.
SpokenDuration spokenDuration(num totalSeconds) {
  final sec = totalSeconds < 0 ? 0 : totalSeconds.round();
  if (sec >= 60 && sec % 60 == 0) return SpokenMinutes(sec ~/ 60);
  if (sec < 120) return SpokenSeconds(sec);
  return SpokenMinSec(sec ~/ 60, sec % 60);
}

/// A session length rounded to whole minutes, never below one.
int aboutMinutes(num totalSeconds) {
  final m = (totalSeconds / 60).round();
  return m < 1 ? 1 : m;
}

enum PaceZoneName { easy, marathon, tempo, interval, repetition }

const _zoneNames = <String, PaceZoneName>{
  'e': PaceZoneName.easy,
  'easy': PaceZoneName.easy,
  'm': PaceZoneName.marathon,
  'mp': PaceZoneName.marathon,
  'marathon': PaceZoneName.marathon,
  't': PaceZoneName.tempo,
  'tempo': PaceZoneName.tempo,
  'threshold': PaceZoneName.tempo,
  'i': PaceZoneName.interval,
  'interval': PaceZoneName.interval,
  'r': PaceZoneName.repetition,
  'rep': PaceZoneName.repetition,
  'repetition': PaceZoneName.repetition,
};

/// The Daniels pace a `plan_workouts.pace_zone` code names, or null for
/// free text the editor let a coach type.
PaceZoneName? paceZoneName(String? zone) {
  if (zone == null) return null;
  return _zoneNames[zone.trim().toLowerCase()];
}

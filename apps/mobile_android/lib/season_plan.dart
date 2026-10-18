/// The season builder (issue #1181): a confirmed race list becomes one plan
/// per A race, chained back to back with a recovery gap after each A race,
/// and every B / C race written as a race workout into the plan whose window
/// holds it. The generator still authors every training workout (decisions
/// § 12, § 1930); this only sizes the windows and places the races.
///
/// Dart twin of `apps/web/src/lib/training/season_plan.ts` (parity pair: keep
/// the rules, constants, refusals and test counts in lockstep). Web returns a
/// discriminated union; this side carries both arms on one result class.
///
/// Dates are whole UTC epoch-days, as in `race_plan_preset.dart`, so a window
/// that crosses a DST change is never a day short.
library;

import 'dart:math' as math;

import 'race_plan_preset.dart';
import 'season_types.dart';
import 'training.dart';

/// The longest plan the season builder writes: the wizard's own maximum on
/// the week field.
const int kSeasonMaxPlanWeeks = 24;

/// A race name becomes both the plan's name (80 chars) and its race
/// workout's `race_name` (120), so the tighter cap holds.
const int kSeasonRaceNameMax = 80;

/// Recovery after an A race before the next plan starts: one day per 3 km
/// raced, held to 3–28 days. Half the density of "a day per mile raced",
/// because the next plan opens with its easy base phase and carries the back
/// half of the recovery itself.
const double kSeasonRecoveryKmPerDay = 3;
const int kSeasonRecoveryMinDays = 3;
const int kSeasonRecoveryMaxDays = 28;

const int _dayMs = 86400000;

enum SeasonRefusal {
  empty,
  invalidRace,
  raceNotAhead,
  noARace,
  firstTooSoon,
  aRacesTooClose,
}

enum SeasonUnplacedReason { beforeFirstPlan, betweenPlans, afterLastPlan, sameDay }

class SeasonPlanDraft {
  final String name;
  final SeasonRace race;
  final GoalEvent goalEvent;
  final double goalDistanceM;
  final int? goalTimeSec;

  /// ISO `yyyy-mm-dd`, always a Sunday.
  final String startDate;

  /// The A race's date.
  final String endDate;
  final int weeks;
  final int daysPerWeek;

  /// The B / C races written into this plan, by date.
  final List<SeasonRace> races;

  /// What `TrainingService.createPlan` writes.
  final GeneratedPlan generated;

  const SeasonPlanDraft({
    required this.name,
    required this.race,
    required this.goalEvent,
    required this.goalDistanceM,
    required this.goalTimeSec,
    required this.startDate,
    required this.endDate,
    required this.weeks,
    required this.daysPerWeek,
    required this.races,
    required this.generated,
  });
}

class SeasonGap {
  final String afterRace;
  final String from;
  final String to;
  final int days;
  final int recoveryDays;

  const SeasonGap({
    required this.afterRace,
    required this.from,
    required this.to,
    required this.days,
    required this.recoveryDays,
  });
}

class SeasonUnplaced {
  final SeasonRace race;
  final SeasonUnplacedReason reason;

  const SeasonUnplaced(this.race, this.reason);
}

class SeasonBuildResult {
  final List<SeasonPlanDraft> plans;
  final List<SeasonGap> gaps;
  final List<SeasonUnplaced> unplaced;
  final SeasonRefusal? reason;

  /// The races a refusal names.
  final List<String> races;

  const SeasonBuildResult.ok({
    required this.plans,
    required this.gaps,
    required this.unplaced,
  })  : reason = null,
        races = const [];

  const SeasonBuildResult.refused(SeasonRefusal this.reason,
      [this.races = const []])
      : plans = const [],
        gaps = const [],
        unplaced = const [];

  bool get ok => reason == null;
}

final RegExp _isoDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');

int? _epochDay(String iso) {
  if (!_isoDate.hasMatch(iso)) return null;
  final p = iso.split('-').map(int.parse).toList();
  final utc = DateTime.utc(p[0], p[1], p[2]);
  if (utc.year != p[0] || utc.month != p[1] || utc.day != p[2]) return null;
  return utc.millisecondsSinceEpoch ~/ _dayMs;
}

String _isoFromEpochDay(int day) {
  final d = DateTime.fromMillisecondsSinceEpoch(day * _dayMs, isUtc: true);
  final mm = d.month.toString().padLeft(2, '0');
  final dd = d.day.toString().padLeft(2, '0');
  return '${d.year.toString().padLeft(4, '0')}-$mm-$dd';
}

int _dayOfWeek(int day) => ((day + 4) % 7 + 7) % 7;

int _sundayOnOrAfter(int day) => day + (7 - _dayOfWeek(day)) % 7;

/// Days of recovery after an A race of [distanceM] before the next plan.
int seasonRecoveryDays(double distanceM) {
  final days = (distanceM / 1000 / kSeasonRecoveryKmPerDay).round();
  return math.min(
      kSeasonRecoveryMaxDays, math.max(kSeasonRecoveryMinDays, days));
}

/// The generator goal for a race distance: a standard event within
/// `goalEventForDistance`'s tolerance, else a custom goal at the distance.
({GoalEvent goalEvent, double goalDistanceM}) seasonGoal(double distanceM) {
  final event = goalEventForDistance(distanceM);
  if (event != null && event != GoalEvent.custom) {
    return (goalEvent: event, goalDistanceM: kGoalDistancesM[event]!);
  }
  return (goalEvent: GoalEvent.custom, goalDistanceM: distanceM);
}

String seasonPriorityLetter(SeasonRacePriority p) => switch (p) {
      SeasonRacePriority.a => 'A',
      SeasonRacePriority.b => 'B',
      SeasonRacePriority.c => 'C',
    };

bool _raceIsValid(SeasonRace r) {
  final name = r.name.trim();
  final goal = r.goalTimeSec;
  return name.isNotEmpty &&
      name.length <= kSeasonRaceNameMax &&
      _epochDay(r.date) != null &&
      r.distanceM.isFinite &&
      r.distanceM > 0 &&
      (goal == null || goal > 0);
}

int _byDate(SeasonRace a, SeasonRace b) {
  final c = a.date.compareTo(b.date);
  return c != 0 ? c : a.name.compareTo(b.name);
}

GeneratedWorkout _raceWorkout(
    DateTime date, SeasonRace race, double distanceM, int? pace) {
  return GeneratedWorkout(
    scheduledDate: date,
    kind: WorkoutKind.race,
    targetDistanceM: distanceM,
    targetDurationSeconds: race.goalTimeSec,
    targetPaceSecPerKm: pace,
    targetPaceToleranceSec: pace == null ? null : 5,
    raceName: race.name.trim(),
    racePriority: seasonPriorityLetter(race.priority),
  );
}

GeneratedWorkout _restWorkout(DateTime date) =>
    GeneratedWorkout(scheduledDate: date, kind: WorkoutKind.rest);

/// Puts [workout] on its date, replacing whatever the generator put there.
List<List<GeneratedWorkout>> _placeWorkout(
    List<List<GeneratedWorkout>> weeks, GeneratedWorkout workout) {
  final iso = toIsoDate(workout.scheduledDate);
  for (final week in weeks) {
    final i = week.indexWhere((w) => toIsoDate(w.scheduledDate) == iso);
    if (i >= 0) {
      week[i] = workout;
      return weeks;
    }
  }
  final target = weeks.reversed.firstWhere(
      (w) => w.isNotEmpty && toIsoDate(w.first.scheduledDate).compareTo(iso) <= 0,
      orElse: () => weeks.first);
  target
    ..add(workout)
    ..sort((a, b) => a.scheduledDate.compareTo(b.scheduledDate));
  return weeks;
}

class _Mutable {
  final GeneratedPlan source;
  final List<GeneratedWeek> heads;
  final List<List<GeneratedWorkout>> weeks;
  String endDate;

  _Mutable(this.source)
      : heads = List.of(source.weeks),
        weeks = [for (final w in source.weeks) List.of(w.workouts)],
        endDate = toIsoDate(source.endDate);

  GeneratedPlan freeze() {
    final out = <GeneratedWeek>[];
    for (var i = 0; i < heads.length; i++) {
      if (weeks[i].isEmpty) continue;
      final h = heads[i];
      out.add(GeneratedWeek(
        weekIndex: h.weekIndex,
        phase: h.phase,
        targetVolumeM:
            weeks[i].fold(0.0, (s, w) => s + (w.targetDistanceM ?? 0)),
        notes: h.notes,
        workouts: weeks[i],
      ));
    }
    return GeneratedPlan(
      weeks: out,
      paces: source.paces,
      vdot: source.vdot,
      endDate: parseIsoDate(endDate),
      goalDistanceM: source.goalDistanceM,
      pacesAreFallback: source.pacesAreFallback,
    );
  }
}

/// Ends the generated plan on the A race: the race workout moves from the
/// race week's Sunday to race day (the Sunday slot becomes rest), and the
/// days after race day are dropped.
void _fitToARace(_Mutable plan, SeasonRace race, double goalDistanceM) {
  int? pace;
  for (var i = 0; i < plan.weeks.length; i++) {
    final kept = <GeneratedWorkout>[];
    for (final w in plan.weeks[i]) {
      if (toIsoDate(w.scheduledDate).compareTo(race.date) > 0) continue;
      if (w.kind == WorkoutKind.race) {
        pace = w.targetPaceSecPerKm;
        kept.add(_restWorkout(w.scheduledDate));
      } else {
        kept.add(w);
      }
    }
    plan.weeks[i] = kept;
  }
  for (var i = plan.weeks.length - 1; i >= 0; i--) {
    if (plan.weeks[i].isEmpty) {
      plan.weeks.removeAt(i);
      plan.heads.removeAt(i);
    }
  }
  _placeWorkout(plan.weeks,
      _raceWorkout(parseIsoDate(race.date), race, goalDistanceM, pace));
  plan.endDate = race.date;
}

SeasonBuildResult buildSeason({
  required List<SeasonRace> races,
  required String todayIso,
  required int daysPerWeek,
  int? recent5kSec,
  TrainingGender gender,
  int? age,
  bool extraRecovery = false,
}) {
  if (races.isEmpty) {
    return const SeasonBuildResult.refused(SeasonRefusal.empty);
  }
  final invalid = races.where((r) => !_raceIsValid(r)).toList();
  if (invalid.isNotEmpty) {
    return SeasonBuildResult.refused(SeasonRefusal.invalidRace,
        [for (final r in invalid) r.name.trim()]);
  }
  final today = _epochDay(todayIso);
  if (today == null) {
    return const SeasonBuildResult.refused(SeasonRefusal.invalidRace);
  }
  final past = races.where((r) => _epochDay(r.date)! <= today).toList();
  if (past.isNotEmpty) {
    return SeasonBuildResult.refused(
        SeasonRefusal.raceNotAhead, [for (final r in past) r.name.trim()]);
  }

  final sorted = List.of(races)..sort(_byDate);
  final aRaces =
      sorted.where((r) => r.priority == SeasonRacePriority.a).toList();
  if (aRaces.isEmpty) {
    return const SeasonBuildResult.refused(SeasonRefusal.noARace);
  }

  final mutables = <_Mutable>[];
  final heads = <SeasonPlanDraft>[];
  final gaps = <SeasonGap>[];
  for (var i = 0; i < aRaces.length; i++) {
    final race = aRaces[i];
    final raceDay = _epochDay(race.date)!;
    final prev = i > 0 ? aRaces[i - 1] : null;
    final recovery = prev != null ? seasonRecoveryDays(prev.distanceM) : 0;
    final earliest = prev != null
        ? _sundayOnOrAfter(_epochDay(prev.date)! + 1 + recovery)
        : _sundayOnOrAfter(today);
    final raceWeekStart = raceDay - _dayOfWeek(raceDay);
    final available = ((raceWeekStart - earliest) / 7).floor() + 1;
    if (available < kRacePlanMinWeeks) {
      return prev != null
          ? SeasonBuildResult.refused(SeasonRefusal.aRacesTooClose,
              [prev.name.trim(), race.name.trim()])
          : SeasonBuildResult.refused(
              SeasonRefusal.firstTooSoon, [race.name.trim()]);
    }
    final goal = seasonGoal(race.distanceM);
    // The first plan takes the goal's usual length and starts later, as a
    // single race plan does; a later plan fills the gap from the end of
    // recovery, so the season has no unplanned weeks between its blocks.
    final cap = prev != null
        ? kSeasonMaxPlanWeeks
        : math.min(kSeasonMaxPlanWeeks,
            defaultPlanWeeks(goal.goalEvent, goal.goalDistanceM));
    final weeks = math.min(available, cap);
    final start = raceWeekStart - (weeks - 1) * 7;
    final generated = generatePlan(GeneratePlanInput(
      goalEvent: goal.goalEvent,
      goalDistanceM: goal.goalDistanceM,
      goalTimeSec: race.goalTimeSec,
      recent5kSec: recent5kSec,
      startDate: parseIsoDate(_isoFromEpochDay(start)),
      daysPerWeek: daysPerWeek,
      weeks: weeks,
      gender: gender,
      age: age,
      extraRecovery: extraRecovery,
    ));
    final m = _Mutable(generated);
    _fitToARace(m, race, goal.goalDistanceM);
    mutables.add(m);
    heads.add(SeasonPlanDraft(
      name: race.name.trim(),
      race: race,
      goalEvent: goal.goalEvent,
      goalDistanceM: goal.goalDistanceM,
      goalTimeSec: race.goalTimeSec,
      startDate: _isoFromEpochDay(start),
      endDate: race.date,
      weeks: weeks,
      daysPerWeek: daysPerWeek,
      races: const [],
      generated: generated,
    ));
    if (prev != null) {
      final prevDay = _epochDay(prev.date)!;
      gaps.add(SeasonGap(
        afterRace: prev.name.trim(),
        from: _isoFromEpochDay(prevDay + 1),
        to: _isoFromEpochDay(start - 1),
        days: start - prevDay - 1,
        recoveryDays: recovery,
      ));
    }
  }

  final attached = [for (final _ in heads) <SeasonRace>[]];
  final unplaced = <SeasonUnplaced>[];
  for (final race in sorted) {
    if (race.priority == SeasonRacePriority.a) continue;
    final idx = heads.indexWhere((p) =>
        p.startDate.compareTo(race.date) <= 0 &&
        race.date.compareTo(p.endDate) <= 0);
    if (idx < 0) {
      final reason = race.date.compareTo(heads.first.startDate) < 0
          ? SeasonUnplacedReason.beforeFirstPlan
          : race.date.compareTo(heads.last.endDate) > 0
              ? SeasonUnplacedReason.afterLastPlan
              : SeasonUnplacedReason.betweenPlans;
      unplaced.add(SeasonUnplaced(race, reason));
      continue;
    }
    if (race.date == heads[idx].endDate ||
        attached[idx].any((r) => r.date == race.date)) {
      unplaced.add(SeasonUnplaced(race, SeasonUnplacedReason.sameDay));
      continue;
    }
    final goal = race.goalTimeSec;
    final pace = goal == null ? null : (goal / (race.distanceM / 1000)).round();
    _placeWorkout(mutables[idx].weeks,
        _raceWorkout(parseIsoDate(race.date), race, race.distanceM, pace));
    attached[idx].add(race);
  }

  final plans = <SeasonPlanDraft>[
    for (var i = 0; i < heads.length; i++)
      SeasonPlanDraft(
        name: heads[i].name,
        race: heads[i].race,
        goalEvent: heads[i].goalEvent,
        goalDistanceM: heads[i].goalDistanceM,
        goalTimeSec: heads[i].goalTimeSec,
        startDate: heads[i].startDate,
        endDate: heads[i].endDate,
        weeks: heads[i].weeks,
        daysPerWeek: heads[i].daysPerWeek,
        races: List.unmodifiable(attached[i]),
        generated: mutables[i].freeze(),
      ),
  ];
  return SeasonBuildResult.ok(plans: plans, gaps: gaps, unplaced: unplaced);
}

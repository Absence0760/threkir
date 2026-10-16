import 'package:flutter_test/flutter_test.dart';

import '../lib/race_plan_preset.dart';
import '../lib/season_plan.dart';
import '../lib/season_types.dart';
import '../lib/training.dart';

const String _today = '2026-08-14'; // a Friday
const int _dayMs = 86400000;

SeasonRace _race(String name, String date, double distanceM,
        SeasonRacePriority priority, [int? goalTimeSec]) =>
    SeasonRace(
        name: name,
        date: date,
        distanceM: distanceM,
        priority: priority,
        goalTimeSec: goalTimeSec);

const _a = SeasonRacePriority.a;
const _b = SeasonRacePriority.b;
const _c = SeasonRacePriority.c;

final _richmond = _race('Richmond Marathon', '2026-11-14', 42195, _a, 12600);
final _twoOceans = _race('Two Oceans', '2027-04-03', 56000, _b, 21600);
final _comrades = _race('Comrades', '2027-06-13', 87000, _a);

SeasonBuildResult _build(List<SeasonRace> races, [int daysPerWeek = 4]) =>
    buildSeason(races: races, todayIso: _today, daysPerWeek: daysPerWeek);

SeasonBuildResult _ok(SeasonBuildResult r) {
  expect(r.ok, isTrue, reason: 'expected a season, got ${r.reason}');
  return r;
}

List<GeneratedWorkout> _workouts(SeasonPlanDraft p) =>
    [for (final w in p.generated.weeks) ...w.workouts];

String _iso(GeneratedWorkout w) => toIsoDate(w.scheduledDate);

int _utcDay(String iso) {
  final p = iso.split('-').map(int.parse).toList();
  return DateTime.utc(p[0], p[1], p[2]).millisecondsSinceEpoch ~/ _dayMs;
}

bool _isSunday(String iso) => ((_utcDay(iso) + 4) % 7 + 7) % 7 == 0;

void main() {
  test('seasonRecoveryDays: a day per 3 km raced, held to 3-28 days', () {
    expect(seasonRecoveryDays(5000), 3);
    expect(seasonRecoveryDays(10000), 3);
    expect(seasonRecoveryDays(21097.5), 7);
    expect(seasonRecoveryDays(42195), 14);
    expect(seasonRecoveryDays(56000), 19);
    expect(seasonRecoveryDays(87000), 28);
    expect(seasonRecoveryDays(160934), 28);
  });

  test('seasonGoal: a road distance maps to its event, anything else is custom',
      () {
    expect(seasonGoal(42195),
        (goalEvent: GoalEvent.distanceFull, goalDistanceM: 42195.0));
    expect(seasonGoal(42300),
        (goalEvent: GoalEvent.distanceFull, goalDistanceM: 42195.0));
    expect(seasonGoal(10000),
        (goalEvent: GoalEvent.distance10k, goalDistanceM: 10000.0));
    expect(seasonGoal(56000),
        (goalEvent: GoalEvent.custom, goalDistanceM: 56000.0));
  });

  test('buildSeason refuses an empty race list', () {
    final r = _build([]);
    expect(r.reason, SeasonRefusal.empty);
    expect(r.races, isEmpty);
  });

  test('buildSeason refuses a season with no A race rather than promoting one',
      () {
    final r = _build([
      _race('Club 10k', '2026-10-10', 10000, _c),
      _race('Half', '2026-11-01', 21097.5, _b),
    ]);
    expect(r.reason, SeasonRefusal.noARace);
    expect(r.races, isEmpty);
  });

  test('buildSeason refuses an invalid race and names every one', () {
    final r = _build([
      _richmond,
      _race('Bad date', '2026-02-31', 10000, _c),
      _race('No distance', '2026-10-10', 0, _c),
      _race('x' * (kSeasonRaceNameMax + 1), '2026-10-10', 5000, _c),
      _race('Zero goal', '2026-10-10', 5000, _c, 0),
    ]);
    expect(r.ok, isFalse);
    expect(r.reason, SeasonRefusal.invalidRace);
    expect(r.races.length, 4);
    expect(_build([_race('  ', '2026-10-10', 5000, _a)]).ok, isFalse);
  });

  test('buildSeason refuses a race that is today or past', () {
    final r = _build([_richmond, _race('Last week', _today, 5000, _c)]);
    expect(r.reason, SeasonRefusal.raceNotAhead);
    expect(r.races, ['Last week']);
  });

  test('buildSeason refuses a first A race fewer than the minimum weeks away',
      () {
    final r = _build([_race('Soon Half', '2026-09-05', 21097.5, _a)]);
    expect(r.reason, SeasonRefusal.firstTooSoon);
    expect(r.races, ['Soon Half']);
  });

  test('buildSeason refuses two A races too close and names both', () {
    final r = _build([
      _race('Autumn Half', '2026-10-11', 21097.5, _a),
      _race('Fast 10k', '2026-11-08', 10000, _a),
    ]);
    expect(r.reason, SeasonRefusal.aRacesTooClose);
    expect(r.races, ['Autumn Half', 'Fast 10k']);
  });

  test(
      'one A race: a plan from the next Sunday at the goal default length, ending on race day',
      () {
    final r = _ok(_build([_race('Spring 10k', '2026-12-06', 10000, _a, 2700)]));
    expect(r.plans.length, 1);
    expect(r.gaps, isEmpty);
    expect(r.unplaced, isEmpty);
    final p = r.plans.single;
    expect(p.name, 'Spring 10k');
    expect(p.goalEvent, GoalEvent.distance10k);
    expect(p.weeks, 8);
    expect(_isSunday(p.startDate), isTrue);
    expect(p.endDate, '2026-12-06');
    expect(toIsoDate(p.generated.endDate), '2026-12-06');
    final last = _workouts(p).last;
    expect(_iso(last), '2026-12-06');
    expect(last.kind, WorkoutKind.race);
    expect(last.raceName, 'Spring 10k');
    expect(last.racePriority, 'A');
    expect(last.targetDurationSeconds, 2700);
  });

  test(
      'an A race off a Sunday moves the race to race day and drops the days after it',
      () {
    final p = _ok(_build([_richmond])).plans.single;
    expect(p.startDate, '2026-08-16');
    expect(p.weeks, 13);
    final all = _workouts(p);
    expect(all.every((w) => _iso(w).compareTo('2026-11-14') <= 0), isTrue);
    final races = all.where((w) => w.kind == WorkoutKind.race).toList();
    expect(races.length, 1);
    expect(_iso(races.single), '2026-11-14');
    expect(races.single.targetDistanceM, 42195);
    expect(all.firstWhere((w) => _iso(w) == '2026-11-08').kind,
        WorkoutKind.rest);
  });

  test(
      'two A races chain: the later plan starts on a Sunday after the recovery gap',
      () {
    final r = _ok(_build([_richmond, _comrades]));
    expect(r.plans.length, 2);
    final a = r.plans[0];
    final b = r.plans[1];
    expect(_isSunday(b.startDate), isTrue);
    expect(_utcDay(b.startDate) - _utcDay(a.endDate) - 1,
        greaterThanOrEqualTo(seasonRecoveryDays(42195)));
    expect(r.gaps.length, 1);
    expect(r.gaps.single.afterRace, 'Richmond Marathon');
    expect(r.gaps.single.from, '2026-11-15');
    expect(r.gaps.single.to, '2027-01-02');
    expect(r.gaps.single.days, 49);
    expect(r.gaps.single.recoveryDays, 14);
  });

  test('a later plan fills the gap up to the maximum length', () {
    final r = _ok(_build([_richmond, _comrades]));
    expect(r.plans[1].weeks, kSeasonMaxPlanWeeks);
    expect(r.plans[1].startDate, '2027-01-03');
    final close = _ok(_build([
      _race('Autumn Half', '2026-10-11', 21097.5, _a),
      _race('Winter Marathon', '2026-12-13', 42195, _a),
    ]));
    expect(close.plans[1].startDate, '2026-10-25');
    expect(close.plans[1].weeks, 8);
    expect(close.gaps.single.days, 13);
  });

  test('a custom distance A race plans at its own distance', () {
    final p = _ok(_build([_race('Two Oceans', '2027-04-03', 56000, _a)]))
        .plans
        .single;
    expect(p.goalEvent, GoalEvent.custom);
    expect(p.goalDistanceM, 56000);
    expect(
        _workouts(p).firstWhere((w) => w.kind == WorkoutKind.race).targetDistanceM,
        56000);
  });

  test('a 56 km and a 90 km A race chain, the first taking the ultra default length',
      () {
    final r = _ok(_build([
      _race('Two Oceans', '2027-04-03', 56000, _a),
      _race('Comrades', '2027-06-13', 90000, _a),
    ]));
    expect([
      for (final p in r.plans)
        (p.name, p.goalEvent, p.goalDistanceM, p.weeks, p.startDate, p.endDate)
    ], [
      ('Two Oceans', GoalEvent.custom, 56000.0, 16, '2026-12-13', '2027-04-03'),
      ('Comrades', GoalEvent.custom, 90000.0, 8, '2027-04-25', '2027-06-13'),
    ]);
    expect((r.gaps.single.days, r.gaps.single.recoveryDays), (21, 19));
    expect(_workouts(r.plans[1]).last.targetDistanceM, 90000);
  });

  test(
      'a B race inside a plan becomes a race workout on its date, replacing the generated one',
      () {
    final r = _ok(_build([_richmond, _twoOceans, _comrades]));
    expect(r.unplaced, isEmpty);
    expect(r.plans[0].races, isEmpty);
    expect(r.plans[1].races, [_twoOceans]);
    final onDay =
        _workouts(r.plans[1]).where((w) => _iso(w) == '2027-04-03').toList();
    expect(onDay.length, 1);
    final w = onDay.single;
    expect(w.kind, WorkoutKind.race);
    expect(w.targetDistanceM, 56000);
    expect(w.targetDurationSeconds, 21600);
    expect(w.targetPaceSecPerKm, 386);
    expect(w.targetPaceToleranceSec, 5);
    expect(w.structure, isNull);
    expect(w.notes, isNull);
    expect(w.raceName, 'Two Oceans');
    expect(w.racePriority, 'B');
  });

  test('a C race with no goal time carries no pace', () {
    final r = _ok(_build([_race('parkrun', '2026-10-03', 5000, _c), _richmond]));
    final w = _workouts(r.plans[0]).firstWhere((x) => _iso(x) == '2026-10-03');
    expect(w.kind, WorkoutKind.race);
    expect(w.racePriority, 'C');
    expect(w.targetPaceSecPerKm, isNull);
    expect(w.targetPaceToleranceSec, isNull);
  });

  test(
      'B / C races outside every plan are reported unplaced, with where they fell',
      () {
    final r = _ok(_build([
      _race('Early parkrun', '2026-08-15', 5000, _c),
      _richmond,
      _race('Turkey Trot', '2026-11-26', 10000, _c),
      _comrades,
      _race('Winter 10k', '2027-07-04', 10000, _b),
    ]));
    expect([for (final u in r.unplaced) (u.race.name, u.reason)], [
      ('Early parkrun', SeasonUnplacedReason.beforeFirstPlan),
      ('Turkey Trot', SeasonUnplacedReason.betweenPlans),
      ('Winter 10k', SeasonUnplacedReason.afterLastPlan),
    ]);
    expect(r.plans.every((p) => p.races.isEmpty), isTrue);
  });

  test(
      'a B / C race on an A race day or on a placed race day is unplaced as same_day',
      () {
    final r = _ok(_build([
      _richmond,
      _race('Shadow 5k', '2026-11-14', 5000, _c),
      _race('Club 10k', '2026-10-10', 10000, _b),
      _race('Club 5k', '2026-10-10', 5000, _c),
    ]));
    expect([for (final u in r.unplaced) (u.race.name, u.reason)], [
      ('Club 5k', SeasonUnplacedReason.sameDay),
      ('Shadow 5k', SeasonUnplacedReason.sameDay),
    ]);
    expect([for (final x in r.plans[0].races) x.name], ['Club 10k']);
  });

  test('every week restates its volume from the workouts it now holds', () {
    final r = _ok(_build([_richmond, _twoOceans, _comrades]));
    for (final p in r.plans) {
      for (final w in p.generated.weeks) {
        expect(w.targetVolumeM,
            w.workouts.fold(0.0, (s, x) => s + (x.targetDistanceM ?? 0)));
      }
    }
  });

  test(
      'plans never overlap and every window holds the minimum and maximum lengths',
      () {
    final plans = _ok(_build([_richmond, _twoOceans, _comrades], 5)).plans;
    for (var i = 0; i < plans.length; i++) {
      final p = plans[i];
      expect(p.weeks >= kRacePlanMinWeeks && p.weeks <= kSeasonMaxPlanWeeks,
          isTrue);
      expect(p.startDate.compareTo(_today) >= 0, isTrue);
      final days = [for (final w in _workouts(p)) _iso(w)];
      expect(days.first, p.startDate);
      expect(days.last, p.endDate);
      if (i > 0) {
        expect(p.startDate.compareTo(plans[i - 1].endDate) > 0, isTrue);
      }
      expect(p.daysPerWeek, 5);
    }
  });

  test('the race list order does not matter', () {
    final a = _ok(_build([_comrades, _twoOceans, _richmond]));
    final b = _ok(_build([_richmond, _twoOceans, _comrades]));
    expect([for (final p in a.plans) (p.name, p.startDate, p.endDate)],
        [for (final p in b.plans) (p.name, p.startDate, p.endDate)]);
  });
}

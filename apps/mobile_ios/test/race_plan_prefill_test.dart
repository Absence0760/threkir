import 'package:flutter_test/flutter_test.dart';

import '../lib/race_plan_prefill.dart';

const _today = '2026-08-14'; // a Friday
const _richmond = RacePlanRace(
    name: 'Richmond Marathon', raceDateIso: '2026-11-14', distanceM: 42195);

RacePlanOwnPlan _plan(
  String id,
  String endDateIso, {
  String? name,
  String status = 'active',
  num? goalDistanceM,
  num? goalTimeSeconds,
}) =>
    RacePlanOwnPlan(
      id: id,
      name: name ?? id,
      status: status,
      endDateIso: endDateIso,
      goalDistanceM: goalDistanceM,
      goalTimeSeconds: goalTimeSeconds,
    );

String _full({int maxChars = kRacePlanDescribeMax}) => racePlanDescribe(
      race: _richmond,
      goalTimeS: 13500,
      recentEffort:
          const RacePlanEffort(distanceM: 10000, durationS: 2910, ageDays: 12.3),
      course:
          const RacePlanCourse(ascentM: 250.4, descentM: 240, surface: ' road '),
      maxChars: maxChars,
    );

void main() {
  test('describe: every field, in priority order', () {
    expect(
      _full(),
      'Race: Richmond Marathon on 2026-11-14. Distance: 42.2 km. Goal time: 3:45:00. '
      'Recent effort: 10 km in 48:30, 12 days ago. Course: 250 m ascent, 240 m descent, road surface.',
    );
  });

  test('describe: no fitness and no course fall back to the race and goal', () {
    expect(
      racePlanDescribe(race: _richmond, goalTimeS: 13500),
      'Race: Richmond Marathon on 2026-11-14. Distance: 42.2 km. Goal time: 3:45:00.',
    );
  });

  test('describe: unusable values are left out rather than written as zero', () {
    const mystery =
        RacePlanRace(name: 'Mystery Trail', raceDateIso: '2026-11-14');
    expect(
      racePlanDescribe(
        race: mystery,
        goalTimeS: 0,
        recentEffort:
            const RacePlanEffort(distanceM: 5000, durationS: 0, ageDays: 3),
        course: const RacePlanCourse(descentM: 0, surface: '   '),
      ),
      'Race: Mystery Trail on 2026-11-14.',
    );
    expect(racePlanDescribe(race: mystery, goalTimeS: double.nan),
        'Race: Mystery Trail on 2026-11-14.');
  });

  test('describe: the 600-char cap holds for an absurd listing', () {
    final out = racePlanDescribe(
      race: RacePlanRace(
          name: 'x' * 1000, raceDateIso: '2026-11-14', distanceM: 42195),
      goalTimeS: 13500,
      recentEffort:
          const RacePlanEffort(distanceM: 10000, durationS: 2910, ageDays: 12),
      course: RacePlanCourse(
          ascentM: 1000000, descentM: 1000000, surface: 'y' * 500),
    );
    expect(kRacePlanDescribeMax, 600);
    expect(out.length <= 600, isTrue, reason: '${out.length}');
    expect(out.startsWith('Race: ${'x' * 120} on 2026-11-14. Distance: 42.2 km.'),
        isTrue,
        reason: out);
    expect(out.endsWith('${'y' * 40} surface.'), isTrue, reason: out);
  });

  test('describe: a tighter cap drops lower-priority sentences whole', () {
    expect(_full(maxChars: 60),
        'Race: Richmond Marathon on 2026-11-14. Distance: 42.2 km.');
    expect(_full(maxChars: 40), 'Race: Richmond Marathon on 2026-11-14.');
  });

  test('describe: distances, clocks and ages format the same on both platforms',
      () {
    const race = RacePlanRace(
        name: 'Two  Oceans\nHalf', raceDateIso: '2027-04-04', distanceM: 21097.5);
    expect(
      racePlanDescribe(
        race: race,
        goalTimeS: 5999,
        recentEffort:
            const RacePlanEffort(distanceM: 5000, durationS: 1499.6, ageDays: 0.6),
      ),
      'Race: Two Oceans Half on 2027-04-04. Distance: 21.1 km. Goal time: 1:39:59. '
      'Recent effort: 5 km in 25:00, 1 day ago.',
    );
    expect(
      racePlanDescribe(
        race: race,
        recentEffort:
            const RacePlanEffort(distanceM: 5000, durationS: 1500, ageDays: 0.2),
      ).endsWith('5 km in 25:00, today.'),
      isTrue,
    );
  });

  test('chain: follows the latest active plan ending before race day', () {
    final plans = [
      _plan('a', '2026-09-20', goalDistanceM: 21097.5),
      _plan('b', '2026-10-04', name: 'Autumn 10k', goalDistanceM: 10000),
      _plan('c', '2026-10-30', status: 'completed'),
      _plan('d', '2026-11-14'),
    ];
    final chain = racePlanChain(plans, _richmond, _today)!;
    expect(chain.planId, 'b');
    expect(chain.planName, 'Autumn 10k');
    expect(chain.planEndIso, '2026-10-04');
    expect(chain.recoveryDays, 3);
    expect(chain.notBeforeIso, '2026-10-08');
  });

  test('chain: none when no active plan ends before race day', () {
    final plans = [
      _plan('c', '2026-10-30', status: 'completed'),
      _plan('d', '2026-11-14'),
    ];
    expect(racePlanChain(plans, _richmond, _today), isNull);
    expect(racePlanChain(const [], _richmond, _today), isNull);
  });

  test('chain: none when the recovery floor is already behind today', () {
    final plans = [_plan('old', '2026-07-20', goalDistanceM: 5000)];
    expect(racePlanChain(plans, _richmond, _today), isNull);
  });

  test('chain: none when the race is too close to build after the earlier plan',
      () {
    final plans = [_plan('m', '2026-10-25', goalDistanceM: 42195)];
    expect(racePlanChain(plans, _richmond, _today), isNull);
  });

  test('goal time: an active plan ending on race day supplies it', () {
    final plans = [
      _plan('done', '2026-11-14', status: 'completed', goalTimeSeconds: 10000),
      _plan('live', '2026-11-14', goalTimeSeconds: 13500.4),
    ];
    expect(racePlanGoalTimeS(plans, '2026-11-14'), 13500);
  });

  test('goal time: none without a matching plan that carries one', () {
    final plans = [
      _plan('other', '2026-11-15', goalTimeSeconds: 13500),
      _plan('blank', '2026-11-14', goalTimeSeconds: 0),
    ];
    expect(racePlanGoalTimeS(plans, '2026-11-14'), isNull);
  });
}

// Mirrors apps/web/src/lib/training/plan_current.test.ts case-for-case.
import 'package:flutter_test/flutter_test.dart';

import '../lib/plan_current.dart';

typedef _Plan = ({String id, String start, String end});

_Plan _p(String id, String start, String end) =>
    (id: id, start: start, end: end);

CurrentPlanPick<_Plan> _pick(List<_Plan> plans, String today) =>
    pickCurrentPlan(plans, today, start: (p) => p.start, end: (p) => p.end);

List<String> _overlap(List<_Plan> plans, String start, String end) =>
    overlappingPlans(plans, start, end, start: (p) => p.start, end: (p) => p.end)
        .map((p) => p.id)
        .toList();

final _marathon = _p('marathon', '2026-08-02', '2026-11-15');
final _ultra = _p('ultra', '2026-11-16', '2027-06-14');
final _later = _p('later', '2027-07-01', '2027-09-30');

void main() {
  test('pickCurrentPlan: the plan covering today is current, the next one upcoming',
      () {
    final r = _pick([_ultra, _marathon], '2026-10-15');
    expect(r.current?.id, 'marathon');
    expect(r.upcoming?.id, 'ultra');
  });

  test('pickCurrentPlan: start and end days are inside the window', () {
    expect(_pick([_marathon, _ultra], '2026-08-02').current?.id, 'marathon');
    expect(_pick([_marathon, _ultra], '2026-11-15').current?.id, 'marathon');
    expect(_pick([_marathon, _ultra], '2026-11-15').upcoming?.id, 'ultra');
    final handover = _pick([_marathon, _ultra], '2026-11-16');
    expect(handover.current?.id, 'ultra');
    expect(handover.upcoming, isNull);
  });

  test('pickCurrentPlan: in a gap the latest-ended plan is current and the next is upcoming',
      () {
    final r = _pick([_later, _marathon, _ultra], '2027-06-20');
    expect(r.current?.id, 'ultra');
    expect(r.upcoming?.id, 'later');
  });

  test('pickCurrentPlan: only future plans leaves current null and picks the earliest upcoming',
      () {
    final r = _pick([_later, _ultra], '2026-10-15');
    expect(r.current, isNull);
    expect(r.upcoming?.id, 'ultra');
  });

  test('pickCurrentPlan: only ended plans picks the latest end, no upcoming',
      () {
    final r = _pick([_marathon, _ultra], '2027-08-01');
    expect(r.current?.id, 'ultra');
    expect(r.upcoming, isNull);
  });

  test('pickCurrentPlan: no plans yields nothing', () {
    final r = _pick([], '2026-10-15');
    expect(r.current, isNull);
    expect(r.upcoming, isNull);
  });

  test('overlappingPlans: a window touching a plan on its last day overlaps',
      () {
    expect(_overlap([_marathon, _ultra], '2026-11-15', '2027-01-31'),
        ['marathon', 'ultra']);
  });

  test('overlappingPlans: a window starting the day after a plan ends does not overlap it',
      () {
    expect(_overlap([_marathon], '2026-11-16', '2027-06-14'), isEmpty);
  });

  test('overlappingPlans: a window ending on a plan start day overlaps', () {
    expect(_overlap([_ultra], '2026-09-01', '2026-11-16'), ['ultra']);
  });

  test('overlappingPlans: a window inside a plan overlaps, one wholly before it does not',
      () {
    expect(_overlap([_marathon], '2026-09-01', '2026-09-07'), ['marathon']);
    expect(_overlap([_marathon], '2026-07-01', '2026-08-01'), isEmpty);
  });
}

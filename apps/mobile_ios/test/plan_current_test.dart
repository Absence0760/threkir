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

final _marathon = _p('marathon', '2026-08-03', '2026-11-15');
final _ultra = _p('ultra', '2026-11-16', '2027-03-01');

void main() {
  group('pickCurrentPlan', () {
    test('the plan covering today is current and the queued one is upcoming',
        () {
      final pick = _pick([_ultra, _marathon], '2026-10-01');
      expect(pick.current?.id, 'marathon');
      expect(pick.upcoming?.id, 'ultra');
    });

    test('in a gap between plans the latest-ended plan is current', () {
      final spring = _p('spring', '2026-03-01', '2026-05-24');
      final autumn = _p('autumn', '2026-06-01', '2026-07-31');
      final pick = _pick([spring, _ultra, autumn], '2026-09-10');
      expect(pick.current?.id, 'autumn');
      expect(pick.upcoming?.id, 'ultra');
    });

    test('with only future plans there is no current and the earliest is upcoming',
        () {
      final pick = _pick([_ultra, _marathon], '2026-07-01');
      expect(pick.current, isNull);
      expect(pick.upcoming?.id, 'marathon');
    });

    test('a plan is current on its start day', () {
      final pick = _pick([_marathon, _ultra], '2026-11-16');
      expect(pick.current?.id, 'ultra');
      expect(pick.upcoming, isNull);
    });

    test('a plan is current on its end day', () {
      final pick = _pick([_marathon, _ultra], '2026-11-15');
      expect(pick.current?.id, 'marathon');
      expect(pick.upcoming?.id, 'ultra');
    });

    test('no plans picks nothing', () {
      final pick = _pick(const [], '2026-10-01');
      expect(pick.current, isNull);
      expect(pick.upcoming, isNull);
    });
  });

  group('overlappingPlans', () {
    test('a window sharing only the last day overlaps', () {
      expect(_overlap([_marathon], '2026-11-15', '2027-01-01'), ['marathon']);
    });

    test('a window sharing only the first day overlaps', () {
      expect(_overlap([_marathon], '2026-06-01', '2026-08-03'), ['marathon']);
    });

    test('a window starting the day after a plan ends does not overlap', () {
      expect(_overlap([_marathon], '2026-11-16', '2027-01-01'), isEmpty);
    });

    test('a window ending the day before a plan starts does not overlap', () {
      expect(_overlap([_marathon], '2026-06-01', '2026-08-02'), isEmpty);
    });

    test('a window spanning two plans overlaps both', () {
      expect(_overlap([_marathon, _ultra], '2026-11-01', '2026-12-01'),
          ['marathon', 'ultra']);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import '../lib/plan_start.dart';

void main() {
  test('nextSunday is a no-op on a Sunday', () {
    // 2026-06-07 is a Sunday.
    expect(nextSunday(DateTime(2026, 6, 7)), DateTime(2026, 6, 7));
    expect(isSunday(DateTime(2026, 6, 7)), isTrue);
  });

  test('nextSunday snaps a midweek date forward to the next Sunday', () {
    // 2026-06-03 is a Wednesday → 2026-06-07.
    expect(nextSunday(DateTime(2026, 6, 3)), DateTime(2026, 6, 7));
    expect(isSunday(DateTime(2026, 6, 3)), isFalse);
  });

  test('nextSunday snaps a Saturday forward one day', () {
    // 2026-06-06 is a Saturday → 2026-06-07.
    expect(nextSunday(DateTime(2026, 6, 6)), DateTime(2026, 6, 7));
  });

  test('nextSunday crosses a month boundary', () {
    // 2026-06-30 is a Tuesday → 2026-07-05 (Sunday).
    expect(nextSunday(DateTime(2026, 6, 30)), DateTime(2026, 7, 5));
  });

  test('planStartAllowed exempts a walk-run plan from the Sunday rule', () {
    // 2026-06-03 is a Wednesday, 2026-06-07 a Sunday.
    expect(planStartAllowed(DateTime(2026, 6, 3), walkRun: true), isTrue);
    expect(planStartAllowed(DateTime(2026, 6, 3), walkRun: false), isFalse);
    expect(planStartAllowed(DateTime(2026, 6, 7), walkRun: false), isTrue);
  });

  test('alignPlanStart keeps a walk-run start and snaps any other', () {
    expect(alignPlanStart(DateTime(2026, 6, 3), walkRun: true),
        DateTime(2026, 6, 3));
    expect(alignPlanStart(DateTime(2026, 6, 3), walkRun: false),
        DateTime(2026, 6, 7));
  });

  test('defaultPlanStart starts a walk-run plan tomorrow', () {
    // Tuesday 2026-06-30 → Wednesday 2026-07-01, across the month boundary.
    expect(defaultPlanStart(DateTime(2026, 6, 30), walkRun: true),
        DateTime(2026, 7, 1));
  });

  test('defaultPlanStart starts any other plan on the Sunday a week or more out',
      () {
    // Wednesday 2026-06-03 + 7 = Wednesday 2026-06-10 → Sunday 2026-06-14.
    expect(defaultPlanStart(DateTime(2026, 6, 3), walkRun: false),
        DateTime(2026, 6, 14));
    // A Sunday + 7 is already a Sunday: exactly a week out, not two.
    expect(defaultPlanStart(DateTime(2026, 6, 7), walkRun: false),
        DateTime(2026, 6, 14));
  });
}

// Mirrors apps/web/src/lib/training/plan_overlap.test.ts case-for-case.
import 'package:flutter_test/flutter_test.dart';

import '../lib/plan_overlap.dart';

typedef _Plan = ({String start, String end});

const _before = (start: '2031-03-02', end: '2031-04-26');
const _after = (start: '2031-04-20', end: '2031-06-01');

bool _canTrim(List<_Plan> plans, String newStart) =>
    canTrimOverlap(plans, newStart, start: (p) => p.start);

String _clonedEnd(_Plan template, String startIso) =>
    clonedPlanEndIso(template, startIso,
        start: (p) => p.start, end: (p) => p.end);

void main() {
  test('canTrimOverlap: every overlapping plan starting before the new start allows trimming',
      () {
    expect(_canTrim([_before], '2031-04-12'), isTrue);
    expect(_canTrim([_before, _after], '2031-04-12'), isFalse);
  });

  test('canTrimOverlap: a plan starting on the new start day cannot be trimmed',
      () {
    expect(_canTrim([_before], '2031-03-02'), isFalse);
  });

  test('canTrimOverlap: no overlapping plans means nothing to trim', () {
    expect(_canTrim(const [], '2031-04-12'), isFalse);
  });

  test('clonedPlanEndIso: moves the template end by the same offset as its start',
      () {
    const template = (start: '2030-01-05', end: '2030-01-18');
    expect(_clonedEnd(template, '2031-03-23'), '2031-04-05');
    expect(_clonedEnd(template, '2031-02-20'), '2031-03-05');
  });
}

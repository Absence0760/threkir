// Mirrors apps/web/src/lib/training/plan_assign.test.ts case for case.
import 'package:flutter_test/flutter_test.dart';

import '../lib/plan_assign.dart';

typedef _P = ({String name, String start, String end});

String _s(_P p) => p.start;
String _e(_P p) => p.end;

const _P current = (name: 'Spring half', start: '2027-03-01', end: '2027-04-25');
const _P queued = (name: 'Autumn full', start: '2027-06-01', end: '2027-09-26');
const _P ended = (name: 'Winter base', start: '2027-01-01', end: '2027-02-28');
const _P third = (name: 'Winter ultra', start: '2027-10-10', end: '2027-12-12');

void main() {
  test('assignBlockers keeps every plan still ahead of today, in start order',
      () {
    expect(assignBlockers([queued, current], '2027-03-10', start: _s, end: _e),
        [current, queued]);
    expect(assignBlockers([ended, queued], '2027-03-10', start: _s, end: _e),
        [queued]);
    expect(assignBlockers([current], '2027-04-25', start: _s, end: _e),
        [current]);
    expect(assignBlockers(<_P>[], '2027-03-10', start: _s, end: _e), isEmpty);
    expect(
        assignBlockers([third, ended, queued, current], '2027-03-10',
            start: _s, end: _e),
        [current, queued, third]);
  });

  test('firstStartAfter is the day after the last blocker, or today with none '
      'ahead', () {
    expect(firstStartAfter([current, queued], '2027-03-10', end: _e),
        '2027-09-27');
    expect(firstStartAfter([current], '2027-03-10', end: _e), '2027-04-26');
    expect(firstStartAfter(<_P>[], '2027-03-10', end: _e), '2027-03-10');
    expect(firstStartAfter([current, queued, third], '2027-03-10', end: _e),
        '2027-12-13');
  });

  test('assignCollision names the blocker the assigned window runs into, '
      'latest-ending first', () {
    const fourWeeks = (start: '2020-01-01', end: '2020-01-28');
    const year = (start: '2020-01-01', end: '2020-12-31');
    _P? hit(({String start, String end}) source, String startIso,
            [List<_P> blockers = const [current, queued]]) =>
        assignCollision(blockers, source, startIso,
            start: _s,
            end: _e,
            sourceStart: (s) => s.start,
            sourceEnd: (s) => s.end);
    expect(hit(fourWeeks, '2027-04-26'), isNull);
    expect(hit(fourWeeks, '2027-04-20'), current);
    expect(hit(fourWeeks, '2027-05-10'), queued);
    expect(hit(year, '2027-04-01'), queued);
    expect(hit(fourWeeks, '2027-05-04'), isNull);
    expect(hit(fourWeeks, '2027-12-13', [current, queued, third]), isNull);
    expect(hit(fourWeeks, '2027-09-27', [current, queued, third]), third);
  });
}

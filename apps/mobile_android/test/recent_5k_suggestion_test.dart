import 'package:flutter_test/flutter_test.dart';
import '../lib/recent_5k_suggestion.dart';

final int _now = DateTime.parse('2026-10-18T12:00:00Z').millisecondsSinceEpoch;

Recent5kCandidate _run(
  String id,
  String startedAt,
  num? fastest5kS, {
  String? activityType = 'run',
  bool? isDnf = false,
}) => Recent5kCandidate(
  id: id,
  startedAt: startedAt,
  fastest5kS: fastest5kS,
  activityType: activityType,
  isDnf: isDnf,
);

String _iso(int ms) =>
    DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toIso8601String();

void main() {
  test('no runs suggests nothing', () {
    expect(pickRecent5k(const [], _now, null), isNull);
  });

  test('the fastest 5K in the window is the one suggested', () {
    final s = pickRecent5k(
      [
        _run('a', '2026-10-10T08:00:00Z', 1500),
        _run('b', '2026-10-03T08:00:00Z', 1450),
        _run('c', '2026-09-20T08:00:00Z', 1480),
      ],
      _now,
      null,
    );
    expect(
      s,
      const Recent5kSuggestion(
        runId: 'b',
        startedAt: '2026-10-03T08:00:00Z',
        seconds: 1450,
      ),
    );
  });

  test('a tie goes to the more recent run', () {
    final s = pickRecent5k(
      [
        _run('old', '2026-09-01T08:00:00Z', 1450),
        _run('new', '2026-10-01T08:00:00Z', 1450),
      ],
      _now,
      null,
    );
    expect(s?.runId, 'new');
  });

  test('the window is 56 days, inclusive of its first instant', () {
    expect(kRecent5kWindowDays, 56);
    final edge = _iso(_now - 56 * Duration.millisecondsPerDay);
    final outside = _iso(_now - 56 * Duration.millisecondsPerDay - 1000);
    expect(pickRecent5k([_run('edge', edge, 1450)], _now, null)?.runId, 'edge');
    expect(pickRecent5k([_run('out', outside, 1300)], _now, null), isNull);
  });

  test('a run dated in the future is not offered', () {
    expect(
      pickRecent5k([_run('f', '2026-10-19T08:00:00Z', 1450)], _now, null),
      isNull,
    );
  });

  test('only runs count, and a run with no activity type is a run', () {
    final s = pickRecent5k(
      [
        _run('walk', '2026-10-10T08:00:00Z', 1300, activityType: 'walk'),
        _run('ride', '2026-10-11T08:00:00Z', 800, activityType: 'cycle'),
        _run(
          'stroller',
          '2026-10-12T08:00:00Z',
          1350,
          activityType: 'stroller',
        ),
        _run('legacy', '2026-10-09T08:00:00Z', 1500, activityType: null),
      ],
      _now,
      null,
    );
    expect(s?.runId, 'legacy');
  });

  test('a DNF is not offered', () {
    final s = pickRecent5k(
      [
        _run('dnf', '2026-10-10T08:00:00Z', 1300, isDnf: true),
        _run('ok', '2026-10-09T08:00:00Z', 1500, isDnf: null),
      ],
      _now,
      null,
    );
    expect(s?.runId, 'ok');
  });

  test('a time the wizard cannot take is not offered', () {
    final s = pickRecent5k(
      [
        _run('none', '2026-10-10T08:00:00Z', null),
        _run('tooFast', '2026-10-10T08:00:00Z', 600),
        _run('tooSlow', '2026-10-10T08:00:00Z', 3600),
        _run('fraction', '2026-10-10T08:00:00Z', 1400.5),
      ],
      _now,
      null,
    );
    expect(s, isNull);
  });

  test('after a dismissal only a run started later brings it back', () {
    final runs = [
      _run('seen', '2026-10-01T08:00:00Z', 1400),
      _run('between', '2026-10-05T08:00:00Z', 1500),
    ];
    expect(pickRecent5k(runs, _now, '2026-10-06T00:00:00Z'), isNull);
    expect(pickRecent5k(runs, _now, '2026-10-05T08:00:00Z'), isNull);
    final later = [...runs, _run('newer', '2026-10-12T08:00:00Z', 1550)];
    expect(pickRecent5k(later, _now, '2026-10-06T00:00:00Z')?.runId, 'newer');
  });

  test('an unreadable dismissal stamp is treated as no dismissal', () {
    final s = pickRecent5k(
      [_run('a', '2026-10-01T08:00:00Z', 1450)],
      _now,
      'not a date',
    );
    expect(s?.runId, 'a');
  });

  test('a run whose start cannot be read is skipped', () {
    final s = pickRecent5k(
      [
        _run('bad', 'yesterday', 1300),
        _run('good', '2026-10-01T08:00:00Z', 1450),
      ],
      _now,
      null,
    );
    expect(s?.runId, 'good');
  });

  test('isPlausibleRecent5k takes 12:00 to 59:59 in whole seconds', () {
    expect(isPlausibleRecent5k(719), isFalse);
    expect(isPlausibleRecent5k(720), isTrue);
    expect(isPlausibleRecent5k(3599), isTrue);
    expect(isPlausibleRecent5k(3600), isFalse);
    expect(isPlausibleRecent5k(1450.5), isFalse);
    expect(isPlausibleRecent5k(null), isFalse);
  });
}

import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../lib/runs_history_items.dart';

Run _r(DateTime startedAt, {String id = ''}) {
  final actual = id.isEmpty
      ? 'r-${startedAt.toIso8601String()}'
      : id;
  return Run(
    id: actual,
    startedAt: startedAt,
    duration: const Duration(minutes: 30),
    distanceMetres: 5000,
    source: RunSource.app,
  );
}

void main() {
  setUpAll(() => initializeDateFormatting());

  final now = DateTime(2026, 5, 19);

  group('buildHistoryItems', () {
    test('returns an empty list on empty input', () {
      final items = buildHistoryItems(const [], now: now);
      expect(items, isEmpty);
    });

    test('emits a single header for runs in the same month', () {
      final items = buildHistoryItems(
        [
          _r(DateTime(2026, 5, 18, 7)),
          _r(DateTime(2026, 5, 11, 7)),
          _r(DateTime(2026, 5, 4, 7)),
        ],
        now: now,
      );
      expect(items, hasLength(4));
      expect(items.first, isA<HistoryMonthHeader>());
      expect(items.skip(1).every((i) => i is HistoryRun), isTrue);
    });

    test('inserts a header at every month boundary', () {
      // Three runs across three distinct months.
      final items = buildHistoryItems(
        [
          _r(DateTime(2026, 5, 11, 7)), // May 2026
          _r(DateTime(2026, 4, 28, 7)), // Apr 2026
          _r(DateTime(2026, 4, 7, 7)),  // Apr 2026 (same as previous)
          _r(DateTime(2026, 3, 30, 7)), // Mar 2026
        ],
        now: now,
      );
      // Headers: May / Apr / Mar = 3. Runs: 4. Total 7.
      expect(items, hasLength(7));
      final headers = items.whereType<HistoryMonthHeader>().toList();
      expect(headers, hasLength(3));
      expect(headers[0].label, 'May');
      expect(headers[1].label, 'April');
      expect(headers[2].label, 'March');
      // Months pinned numerically (the label format may evolve).
      expect(headers.map((h) => h.month).toList(), [5, 4, 3]);
    });

    test('current-year headers omit the year; prior years include it', () {
      final items = buildHistoryItems(
        [
          _r(DateTime(2026, 5, 11, 7)), // current year (2026)
          _r(DateTime(2025, 12, 28, 7)), // prior year
        ],
        now: now,
      );
      final headers = items.whereType<HistoryMonthHeader>().toList();
      expect(headers[0].label, 'May',
          reason: 'current-year header omits the year for visual quiet');
      expect(headers[1].label, 'December 2025',
          reason: 'prior-year headers must include the year — otherwise '
              'May 2024 and May 2026 collapse visually');
    });

    test('summariseRuns returns zeros for empty input', () {
      expect(summariseRuns(const []).runCount, 0);
      expect(summariseRuns(const []).totalDistanceM, 0);
      expect(summariseRuns(const []).totalDuration, Duration.zero);
    });

    test('summariseRuns sums distance + duration + count', () {
      final runs = [
        Run(
          id: 'a',
          startedAt: DateTime(2026, 5, 1),
          duration: const Duration(minutes: 25),
          distanceMetres: 5000,
          source: RunSource.app,
        ),
        Run(
          id: 'b',
          startedAt: DateTime(2026, 5, 8),
          duration: const Duration(minutes: 50),
          distanceMetres: 10000,
          source: RunSource.app,
        ),
        Run(
          id: 'c',
          startedAt: DateTime(2026, 5, 15),
          duration: const Duration(hours: 1, minutes: 30),
          distanceMetres: 20000,
          source: RunSource.app,
        ),
      ];
      final s = summariseRuns(runs);
      expect(s.runCount, 3);
      expect(s.totalDistanceM, 35000);
      expect(s.totalDuration, const Duration(hours: 2, minutes: 45));
    });

    test('preserves run order within each section', () {
      // Caller hands in newest-first; the helper must not reorder.
      final r1 = _r(DateTime(2026, 5, 18, 7));
      final r2 = _r(DateTime(2026, 5, 11, 7));
      final r3 = _r(DateTime(2026, 5, 4, 7));
      final items = buildHistoryItems([r1, r2, r3], now: now);
      final runs = items.whereType<HistoryRun>().map((i) => i.run.id).toList();
      expect(runs, [r1.id, r2.id, r3.id]);
    });

    test('a ranking sort emits no month headers, so months never interleave',
        () {
      // Production: sorted longest-first, the list read JULY (13.4 mi) above
      // OCTOBER (13.0 mi, 6.56 mi) and would repeat July further down.
      final jul = _r(DateTime(2026, 7, 14, 7), id: 'jul');
      final oct17 = _r(DateTime(2026, 10, 17, 7), id: 'oct17');
      final oct9 = _r(DateTime(2026, 10, 9, 7), id: 'oct9');
      final feb = _r(DateTime(2026, 2, 3, 7), id: 'feb');
      final items = buildHistoryItems(
        [jul, oct17, oct9, feb],
        now: now,
        groupByMonth: false,
      );
      expect(items.whereType<HistoryMonthHeader>(), isEmpty);
      expect(
        items.whereType<HistoryRun>().map((i) => i.run.id).toList(),
        ['jul', 'oct17', 'oct9', 'feb'],
        reason: 'the ranking order is the caller\'s and is kept',
      );
    });

    test('date-ordered input yields each month header once, newest first',
        () {
      final items = buildHistoryItems(
        [
          _r(DateTime(2026, 10, 17, 7)),
          _r(DateTime(2026, 10, 9, 7)),
          _r(DateTime(2026, 7, 14, 7)),
          _r(DateTime(2025, 12, 30, 7)),
        ],
        now: DateTime(2026, 10, 18),
      );
      final headers = items.whereType<HistoryMonthHeader>().toList();
      expect(
        [for (final h in headers) (h.year, h.month)],
        [(2026, 10), (2026, 7), (2025, 12)],
      );
      expect(headers.last.label, contains('2025'),
          reason: 'a header outside the current year names its year');
    });
  });
}

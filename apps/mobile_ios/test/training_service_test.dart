import 'package:flutter_test/flutter_test.dart';

import '../lib/training_service.dart';

void main() {
  // CI regression pin: TrainingService.fetchViewerGender is called
  // from `_PlanNewScreenState.initState`. When Supabase isn't
  // initialised (every widget test that doesn't boot the local
  // stack), the `_c` getter throws a StateError. A previous version
  // of `fetchViewerGender` only wrapped the network read in
  // try/catch, leaving the `_uid` -> `_c` access exposed — the
  // initState thus crashed the entire test. The fix moved the
  // try/catch to cover both, restoring the L4-best-effort contract.
  //
  // This test is the smallest possible reproducer: a default-
  // constructed TrainingService (no override, no Supabase.initialize)
  // returns null from fetchViewerGender instead of throwing.

  test(
    'fetchViewerGender returns null (no throw) when Supabase is uninitialised',
    () async {
      final svc = TrainingService();
      final g = await svc.fetchViewerGender();
      expect(g, isNull);
    },
  );

  // Same contract for the age read, which shares the profile fetch: both go
  // through `get_my_profile()` now (the direct column selects they replaced
  // are refused by the column lockdown, 20260707_001, so they could only ever
  // report "unset"), and both are awaited unblocking from the same initState.
  test(
    'fetchViewerAge returns null (no throw) when Supabase is uninitialised',
    () async {
      final svc = TrainingService();
      final a = await svc.fetchViewerAge();
      expect(a, isNull);
    },
  );

  group('planRunHistoryFromRows', () {
    final now = DateTime.utc(2026, 10, 17, 12);
    Map<String, dynamic> row(int daysAgo, double m, int s,
            {String type = 'run', String source = 'app', Map? metadata}) =>
        {
          'id': 'r$daysAgo',
          'started_at':
              now.subtract(Duration(days: daysAgo)).toIso8601String(),
          'distance_m': m,
          'duration_s': s,
          'activity_type': type,
          'source': source,
          'metadata': metadata,
        };

    test('every row counts toward volume; only recent qualifying runs are efforts',
        () {
      final h = planRunHistoryFromRows([
        row(2, 5000, 1800),
        row(3, 20000, 2400, type: 'cycle'),
        row(4, 5000, 1800, metadata: {'indoor': true}),
        row(120, 10000, 3600),
      ], now.millisecondsSinceEpoch);
      expect(h.runs, hasLength(4));
      expect(h.efforts, hasLength(1));
      expect(h.efforts.single.distanceM, 5000);
      expect(h.efforts.single.durationS, 1800);
      expect(h.efforts.single.ageDays, closeTo(2, 1e-9));
    });

    test('a row with no start time counts nowhere as an effort', () {
      final h = planRunHistoryFromRows([
        {'id': 'x', 'started_at': null, 'distance_m': 5000, 'duration_s': 1800},
      ], now.millisecondsSinceEpoch);
      expect(h.runs, hasLength(1));
      expect(h.efforts, isEmpty);
    });
  });
}


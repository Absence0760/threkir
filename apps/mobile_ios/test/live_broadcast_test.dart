import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/live_broadcast.dart';

// Mirrors apps/web/src/lib/runs/live_broadcast.test.ts. Web's empty-string and
// missing-duration cases have no Dart counterpart: RunRow types concluded_at as
// a DateTime and duration_s as a non-null int.
void main() {
  RunRow row({required int durationS, DateTime? concludedAt}) => RunRow(
        safetyAudience: false,
        id: 'r1',
        userId: 'u1',
        startedAt: DateTime(2026, 8, 5, 8),
        durationS: durationS,
        distanceM: 0,
        source: 'app',
        activityType: 'run',
        isDnf: false,
        followersOnly: false,
        concludedAt: concludedAt,
      );

  test('a live stub (0 duration, never concluded) reads as live', () {
    expect(isLiveBroadcast(row(durationS: 0)), isTrue);
  });

  test('a finished run is never live', () {
    expect(isLiveBroadcast(row(durationS: 3600)), isFalse);
  });

  test('concluded_at wins over a stale zero duration', () {
    final concluded = DateTime.utc(2026, 8, 5, 10);
    expect(isLiveBroadcast(row(durationS: 0, concludedAt: concluded)), isFalse);
    expect(isLiveBroadcast(row(durationS: 3600, concludedAt: concluded)), isFalse);
  });

  test('a missing row is not live (fail closed)', () {
    expect(isLiveBroadcast(null), isFalse);
  });

  test('a negative duration cannot pass as a finished run', () {
    expect(isLiveBroadcast(row(durationS: -1)), isTrue);
  });
}

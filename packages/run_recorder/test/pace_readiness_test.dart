import 'package:flutter_test/flutter_test.dart';
import 'package:run_recorder/run_recorder.dart';

void main() {
  group('paceIsReady', () {
    test('needs both 50 m and 20 s', () {
      expect(paceIsReady(50, 20), isTrue);
      expect(paceIsReady(49.9, 600), isFalse);
      expect(paceIsReady(5000, 19), isFalse);
      expect(paceIsReady(0, 0), isFalse);
    });
  });

  group('readyAveragePaceSecPerKm', () {
    test('a standing start 15 s into a run reads no average (issue #1300)', () {
      // 19 m in 15 s, which the old 10 m / 1 s gate showed as 20:49 /mi
      // while the rolling Pace tile was still blank.
      expect(readyAveragePaceSecPerKm(19, 15), isNull);
    });

    test('reads elapsed over distance once ready', () {
      expect(readyAveragePaceSecPerKm(2000, 600), closeTo(300, 1e-9));
      expect(readyAveragePaceSecPerKm(50, 20), closeTo(400, 1e-9));
    });

    test('a long stop under 50 m still reads nothing', () {
      expect(readyAveragePaceSecPerKm(30, 900), isNull);
    });
  });
}

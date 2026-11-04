import 'package:flutter_test/flutter_test.dart';

import '../lib/monotonic_clock.dart';

void main() {
  test('never runs backwards, whatever the wall clock does', () {
    var last = monotonicNow();
    for (var i = 0; i < 10000; i++) {
      final now = monotonicNow();
      expect(now >= last, isTrue);
      last = now;
    }
  });
}

import 'package:flutter_test/flutter_test.dart';

import '../lib/a11y_announce.dart';

/// The marks a countdown speaks at (#1374 A11Y-2): coarse, so a race armed
/// hours early is not read out every second.
void main() {
  test('the marks are hours, ten minutes in the last hour, minutes in the last ten, then 30/10/5', () {
    final marks = [
      for (var s = 7200; s >= 0; s--)
        if (isCountdownAnnouncementMark(s)) s,
    ];
    expect(marks, [
      7200, 3600, 3000, 2400, 1800, 1200, //
      600, 540, 480, 420, 360, 300, 240, 180, 120, 60, 30, 10, 5,
    ]);
  });

  test('a countdown announces on start and when it crosses a mark, once', () {
    expect(countdownAnnouncementDue(null, 4000), isTrue, reason: 'armed');
    expect(countdownAnnouncementDue(4000, 3999), isFalse);
    expect(countdownAnnouncementDue(3601, 3600), isTrue);
    expect(countdownAnnouncementDue(3600, 3599), isFalse);
    expect(countdownAnnouncementDue(62, 59), isTrue,
        reason: 'a skipped tick still announces the minute it passed');
    expect(countdownAnnouncementDue(59, 58), isFalse);
    expect(countdownAnnouncementDue(6, 5), isTrue);
    expect(countdownAnnouncementDue(5, 4), isFalse);
    expect(countdownAnnouncementDue(1, 0), isFalse, reason: 'GO is announced by the race going live');
    expect(countdownAnnouncementDue(30, 31), isFalse);
    expect(countdownAnnouncementDue(90000, 80000), isTrue);
  });

  test('a per-second countdown from ten minutes speaks 13 times, not 600', () {
    var spoken = 0;
    int? prev;
    for (var s = 600; s >= 0; s--) {
      if (countdownAnnouncementDue(prev, s)) spoken++;
      prev = s;
    }
    // Arm at 600, then 540..60 (9), 30, 10, 5.
    expect(spoken, 13);
  });
}

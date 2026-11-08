import 'package:flutter_test/flutter_test.dart';

import '../lib/course_drive.dart';
import '../lib/course_drive_tracker.dart';

/// Due north from 37.5,-77.45, one point every ~111 m: about 4.4 km.
List<DrivePoint> north(int n, {double from = 37.5}) => [
  for (var i = 0; i < n; i++) DrivePoint(from + i * 0.001, -77.45),
];

final t0 = DateTime.utc(2026, 11, 8, 9);
DateTime at(int s) => t0.add(Duration(seconds: s));

void main() {
  test('a fix far from the course waits, and the first near one joins it', () {
    final t = CourseDriveTracker(north(41));
    final far = t.update(37.5, -77.40, at(0));
    expect(far.state, DriveTrackState.approaching);
    final join = t.update(37.5201, -77.4501, at(5));
    expect(join.state, DriveTrackState.onCourse);
    expect(join.joined, isTrue);
    expect(join.alongM, closeTo(20 * 111.19, 15));
    expect(t.update(37.5205, -77.45, at(6)).joined, isFalse);
  });

  test('car speeds are followed and measured, not rejected', () {
    final t = CourseDriveTracker(north(41));
    t.update(37.5, -77.45, at(0));
    DriveFix? fix;
    // ~25 m/s: one point every 111 m, a fix every 4.4 s.
    for (var i = 1; i <= 10; i++) {
      fix = t.update(
        37.5 + i * 0.001,
        -77.45,
        t0.add(Duration(milliseconds: 4448 * i)),
      );
    }
    expect(fix!.state, DriveTrackState.onCourse);
    expect(fix.alongM, closeTo(10 * 111.19, 2));
    expect(fix.speedMps, closeTo(25, 1));
  });

  test(
    'an out-and-back is followed out, then back, without jumping passes',
    () {
      final out = north(19);
      final line = [
        ...out,
        ...out.reversed.map((p) => DrivePoint(p.lat, p.lng + 0.00023)),
      ];
      final t = CourseDriveTracker(line);
      t.update(37.5, -77.45, at(0));
      var s = 0;
      for (var i = 1; i < 19; i++) {
        final f = t.update(37.5 + i * 0.001, -77.45, at(s += 8));
        expect(f.alongM, lessThan(2100), reason: 'out pass, fix $i');
      }
      var last = 0.0;
      for (var i = 17; i >= 3; i--) {
        final f = t.update(37.5 + i * 0.001, -77.45 + 0.00023, at(s += 8));
        expect(f.alongM, greaterThan(last));
        last = f.alongM;
      }
      expect(last, greaterThan(3000));
    },
  );

  test('progress never moves backwards', () {
    final t = CourseDriveTracker(north(41));
    t.update(37.51, -77.45, at(0));
    final ahead = t.update(37.512, -77.45, at(10));
    final back = t.update(37.5119, -77.45, at(11));
    expect(back.alongM, ahead.alongM);
  });

  test('a loop joined at its shared start and finish starts at the start', () {
    final out = north(10);
    final loop = [
      ...out,
      for (var i = 9; i >= 0; i--) DrivePoint(37.5 + i * 0.001, -77.4495),
      out.first,
    ];
    final t = CourseDriveTracker(loop);
    final join = t.update(37.5, -77.4498, at(0));
    expect(join.state, DriveTrackState.onCourse);
    expect(join.alongM, lessThan(100));
  });

  test(
    'reaching the end of the line finishes the drive, and it stays finished',
    () {
      final t = CourseDriveTracker(north(41));
      t.update(37.535, -77.45, at(0));
      final end = t.update(37.5399, -77.45, at(30));
      expect(end.state, DriveTrackState.finished);
      expect(t.update(37.5, -77.45, at(40)).state, DriveTrackState.finished);
    },
  );

  test(
    'ten minutes off the course ends the drive; coming back before that resumes it',
    () {
      final t = CourseDriveTracker(north(41));
      t.update(37.51, -77.45, at(0));
      expect(t.update(37.511, -77.44, at(60)).state, DriveTrackState.offCourse);
      expect(t.update(37.512, -77.45, at(300)).state, DriveTrackState.onCourse);
      expect(
        t.update(37.513, -77.44, at(360)).state,
        DriveTrackState.offCourse,
      );
      expect(
        t.update(37.513, -77.44, at(959)).state,
        DriveTrackState.offCourse,
      );
      expect(
        t.update(37.513, -77.44, at(960)).state,
        DriveTrackState.abandoned,
      );
    },
  );
}

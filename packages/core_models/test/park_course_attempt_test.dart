import 'package:core_models/core_models.dart';
import 'package:test/test.dart';

void main() {
  Map<String, dynamic> row([Map<String, dynamic> over = const {}]) => {
        'park_course_id': 'c-1',
        'course_name': 'Beaver Lake Trail',
        'park_name': 'Pocahontas State Park',
        'region_code': 'US-VA',
        'park_slug': 'pocahontas',
        'course_slug': 'beaver-lake-trail',
        'outcome': 'skipped_checkpoint',
        'progress_m': 1447,
        'course_m': 3595,
        'missed_checkpoint': 2,
        'checkpoint_count': 4,
        ...over,
      };

  test('reads a whole row', () {
    final a = ParkCourseAttempt.fromRow(row())!;
    expect(a.parkCourseId, 'c-1');
    expect(a.courseName, 'Beaver Lake Trail');
    expect(a.parkName, 'Pocahontas State Park');
    expect(a.region, 'US-VA');
    expect(a.parkSlug, 'pocahontas');
    expect(a.courseSlug, 'beaver-lake-trail');
    expect(a.outcome, ParkCourseAttemptOutcome.skippedCheckpoint);
    expect(a.progressM, 1447);
    expect(a.courseM, 3595);
    expect(a.missedCheckpoint, 2);
    expect(a.checkpointCount, 4);
  });

  test('every outcome reads back from its column spelling', () {
    for (final o in ParkCourseAttemptOutcome.values) {
      expect(ParkCourseAttemptOutcome.fromWire(o.wire), o);
    }
    expect(
      ParkCourseAttemptOutcome.values.map((o) => o.wire),
      [
        'stopped_short',
        'skipped_checkpoint',
        'off_course',
        'gps_gap',
        'wrong_direction',
      ],
    );
  });

  test('a row it cannot read whole is left out, not guessed', () {
    expect(ParkCourseAttempt.fromRow(row({'outcome': 'lost'})), isNull);
    expect(ParkCourseAttempt.fromRow(row({'progress_m': null})), isNull);
    expect(ParkCourseAttempt.fromRow(row({'course_name': null})), isNull);
    expect(ParkCourseAttempt.fromRow(row({'missed_checkpoint': 'two'})), isNull);
    expect(
      ParkCourseAttempt.fromRow(
              row({'outcome': 'stopped_short', 'missed_checkpoint': null}))!
          .missedCheckpoint,
      isNull,
    );
  });
}

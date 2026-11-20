/// Why a run that set out on a park course got no time on it (issue #1446),
/// one row of `get_run_park_course_attempts`.
///
/// [ParkCourseAttemptOutcome] is one of the rails
/// `apps/web/scripts/check_constraint_unions.mjs` reads against the
/// `park_course_attempts.outcome` CHECK (read as snake_case), so the
/// vocabulary and the CHECK move together. Mirrors web `ParkCourseAttempt`
/// in `apps/web/src/lib/types.ts`.
library;

enum ParkCourseAttemptOutcome {
  stoppedShort,
  skippedCheckpoint,
  offCourse,
  gpsGap,
  wrongDirection;

  /// The column's spelling.
  String get wire => switch (this) {
    ParkCourseAttemptOutcome.stoppedShort => 'stopped_short',
    ParkCourseAttemptOutcome.skippedCheckpoint => 'skipped_checkpoint',
    ParkCourseAttemptOutcome.offCourse => 'off_course',
    ParkCourseAttemptOutcome.gpsGap => 'gps_gap',
    ParkCourseAttemptOutcome.wrongDirection => 'wrong_direction',
  };

  /// Null for a value this build does not know.
  static ParkCourseAttemptOutcome? fromWire(Object? value) {
    for (final o in ParkCourseAttemptOutcome.values) {
      if (o.wire == value) return o;
    }
    return null;
  }
}

class ParkCourseAttempt {
  final String parkCourseId;
  final String courseName;
  final String parkName;

  /// The park's region code (`parks.region_code`, e.g. `US-VA`).
  final String region;
  final String parkSlug;
  final String courseSlug;
  final ParkCourseAttemptOutcome outcome;

  /// How far along the course the run got while still on it, 0..[courseM].
  final int progressM;
  final int courseM;

  /// 1-based; set only for [ParkCourseAttemptOutcome.skippedCheckpoint].
  final int? missedCheckpoint;
  final int checkpointCount;

  const ParkCourseAttempt({
    required this.parkCourseId,
    required this.courseName,
    required this.parkName,
    required this.region,
    required this.parkSlug,
    required this.courseSlug,
    required this.outcome,
    required this.progressM,
    required this.courseM,
    required this.missedCheckpoint,
    required this.checkpointCount,
  });

  /// One RPC row, or null when it cannot be read whole: a missing field or an
  /// outcome this build does not know leaves the card out rather than showing
  /// a guess.
  static ParkCourseAttempt? fromRow(Map<String, dynamic> r) {
    final outcome = ParkCourseAttemptOutcome.fromWire(r['outcome']);
    final id = r['park_course_id'];
    final courseName = r['course_name'];
    final parkName = r['park_name'];
    final region = r['region_code'];
    final parkSlug = r['park_slug'];
    final courseSlug = r['course_slug'];
    final progress = r['progress_m'];
    final course = r['course_m'];
    final missed = r['missed_checkpoint'];
    final count = r['checkpoint_count'];
    if (outcome == null ||
        id is! String ||
        courseName is! String ||
        parkName is! String ||
        region is! String ||
        parkSlug is! String ||
        courseSlug is! String ||
        progress is! num ||
        course is! num ||
        count is! num ||
        (missed != null && missed is! num)) {
      return null;
    }
    return ParkCourseAttempt(
      parkCourseId: id,
      courseName: courseName,
      parkName: parkName,
      region: region,
      parkSlug: parkSlug,
      courseSlug: courseSlug,
      outcome: outcome,
      progressM: progress.toInt(),
      courseM: course.toInt(),
      missedCheckpoint: (missed as num?)?.toInt(),
      checkpointCount: count.toInt(),
    );
  }
}

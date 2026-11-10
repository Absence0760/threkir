// "Report a problem with this course" (issue #1346, decisions § 2449): the
// reasons a park course report takes, the limits the sheet shows and the
// refusal codes of the `park-course-report` Edge Function.
//
// The reasons are a rail of `reports.reason` in
// `apps/web/scripts/check_constraint_unions.mjs`; the web list is
// `COURSE_REPORT_REASONS` in `apps/web/src/lib/parks/course_report.ts`. The
// limits mirror `submit_park_course_report`, which is the authority.

/// The reasons a park course takes, in the order the sheet offers them.
const kCourseReportReasons = <String>[
  'course_hazard',
  'course_closure',
  'course_off_trail',
  'land_manager_request',
  'other',
];

const kCourseReportNotesMax = 1000;
const kCourseReportEmailMax = 254;

final _emailShape = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// True for an empty field (the email is optional) or a plausible address.
bool courseReportEmailOk(String raw) {
  final e = raw.trim();
  return e.isEmpty ||
      (e.length <= kCourseReportEmailMax && _emailShape.hasMatch(e));
}

/// The refusals the sheet words, by the code the function answered with.
enum CourseReportRefusal {
  rateLimited,
  alreadyReported,
  notFound,
  invalidEmail,
  invalid,
  failed,
}

/// Reads the `{error: code}` body of a refused filing (a
/// `FunctionException.details`). Anything unrecognised is [failed].
CourseReportRefusal courseReportRefusal(Object? details) {
  final code = details is Map ? details['error'] : null;
  switch (code) {
    case 'rate_limited':
    case 'rate_limit_exceeded':
    case 'rate_limit_unavailable':
      return CourseReportRefusal.rateLimited;
    case 'already_reported':
      return CourseReportRefusal.alreadyReported;
    case 'course_not_found':
      return CourseReportRefusal.notFound;
    case 'invalid_email':
      return CourseReportRefusal.invalidEmail;
    case 'notes_required':
    case 'notes_too_long':
    case 'invalid_report':
    case 'invalid_reason':
    case 'invalid_course':
    case 'invalid_body':
      return CourseReportRefusal.invalid;
    default:
      return CourseReportRefusal.failed;
  }
}

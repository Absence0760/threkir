/// Which sentence a `park_course_month_closed` notification reads as in the
/// inbox (issue #1343). The row carries the course, the month as the
/// park-local 1st and the runner's best time from it, never a rank
/// (decisions § 2511). A course the reader can no longer see (its park or
/// segment pulled) or a row missing its month or time reads as the plain
/// sentence rather than a half-filled one. The web bell words the same row
/// from the same rules; the two are not a parity pair, because each builds
/// its sentence from its own catalogue.
library;

import 'l10n/date_format.dart';
import 'l10n/gen/app_localizations.dart';
import 'preferences.dart' show formatEffortTime;

String parkMonthNoticeText(
  AppLocalizations l10n, {
  required String? courseName,
  required DateTime? month,
  required int? timeS,
  required String localeTag,
}) {
  if (courseName == null ||
      courseName.isEmpty ||
      month == null ||
      timeS == null ||
      timeS <= 0) {
    return l10n.profileNotifParkCourseMonthClosed;
  }
  return l10n.profileNotifParkCourseMonthClosedNamed(
    courseName,
    formatMonthYear(DateTime(month.year, month.month), localeTag),
    formatEffortTime(timeS.toDouble()),
  );
}

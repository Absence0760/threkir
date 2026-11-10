/// How a park course's distance reads, and the order a park lists its
/// courses in (issue #1352). A course distance is a name more than a
/// measurement, so it reads "5 km", "21.1 km" or "3.1 mi": whole when the
/// one-decimal value lands on a whole number, else one decimal, never two.
///
/// Parity pair with `apps/web/src/lib/parks/park_course_distance.ts`
/// (docs/architecture/parity_pairs.md). Pure (explicit unit and locale) so it
/// tests without a widget tree; callers pass the unit preference and the UI
/// locale.
library;

import 'package:core_models/core_models.dart' show DistanceUnit, kMetresPerMile;

import 'l10n/locale_support.dart' show activeLocaleTag;
import 'l10n/number_format.dart' show formatFixed;

class CourseDistanceParts {
  /// Already rounded to [fractionDigits].
  final double value;
  final int fractionDigits;
  final DistanceUnit unit;

  const CourseDistanceParts({
    required this.value,
    required this.fractionDigits,
    required this.unit,
  });

  @override
  bool operator ==(Object other) =>
      other is CourseDistanceParts &&
      other.value == value &&
      other.fractionDigits == fractionDigits &&
      other.unit == unit;

  @override
  int get hashCode => Object.hash(value, fractionDigits, unit);
}

String _unitLabel(DistanceUnit unit) => unit == DistanceUnit.mi ? 'mi' : 'km';

/// Null for a distance that is not a finite, non-negative number.
CourseDistanceParts? courseDistanceParts(double metres, DistanceUnit unit) {
  if (!metres.isFinite || metres < 0) return null;
  final raw = unit == DistanceUnit.mi ? metres / kMetresPerMile : metres / 1000;
  final tenths = (raw * 10).round();
  return CourseDistanceParts(
    value: tenths / 10,
    fractionDigits: tenths % 10 == 0 ? 0 : 1,
    unit: unit,
  );
}

String _formatParts(CourseDistanceParts p, String localeTag) =>
    formatFixed(p.value, p.fractionDigits, localeTag);

/// `5000, km` -> `5 km`; `21100, km` -> `21.1 km`; null when unreadable.
String? courseDistanceLabel(
  double metres,
  DistanceUnit unit, [
  String? localeTag,
]) {
  final p = courseDistanceParts(metres, unit);
  if (p == null) return null;
  return '${_formatParts(p, localeTag ?? activeLocaleTag)} ${_unitLabel(p.unit)}';
}

/// A park's shortest to longest course, `5–50 km`, or one label when they
/// read the same. Unreadable distances are skipped; null when none is left.
String? courseDistanceRange(
  Iterable<double> metres,
  DistanceUnit unit, [
  String? localeTag,
]) {
  double? min;
  double? max;
  for (final m in metres) {
    if (courseDistanceParts(m, unit) == null) continue;
    if (min == null || m < min) min = m;
    if (max == null || m > max) max = m;
  }
  if (min == null || max == null) return null;
  final tag = localeTag ?? activeLocaleTag;
  final loText = _formatParts(courseDistanceParts(min, unit)!, tag);
  final hiText = _formatParts(courseDistanceParts(max, unit)!, tag);
  final label = _unitLabel(unit);
  if (loText == hiText) return '$loText $label';
  return '$loText–$hiText $label';
}

class ParkCourseSortKey {
  final double distanceM;
  final String name;
  final String slug;
  final String status;

  const ParkCourseSortKey({
    required this.distanceM,
    required this.name,
    required this.slug,
    required this.status,
  });
}

/// Closed courses last, then shortest first, then name, then slug.
int compareParkCourses(ParkCourseSortKey a, ParkCourseSortKey b) {
  final closed =
      (a.status == 'closed' ? 1 : 0) - (b.status == 'closed' ? 1 : 0);
  if (closed != 0) return closed;
  final byDistance = a.distanceM.compareTo(b.distanceM);
  if (byDistance != 0) return byDistance;
  final byName = a.name.compareTo(b.name);
  if (byName != 0) return byName;
  return a.slug.compareTo(b.slug);
}

/// A park's courses in list order, as a new list; [courses] is untouched.
List<T> sortParkCourses<T>(
  List<T> courses,
  ParkCourseSortKey Function(T course) key,
) {
  final rows = [for (final c in courses) (course: c, k: key(c))];
  rows.sort((a, b) => compareParkCourses(a.k, b.k));
  return [for (final r in rows) r.course];
}

/// Whether a course's shape is worth a label. Nearly every park course is a
/// loop, so "Loop" says nothing; out-and-back and point-to-point do.
bool courseShapeShown(String? shape) =>
    shape == 'out_and_back' || shape == 'point_to_point';

/// The laps a chip names, or null when there is no chip (one lap or unknown).
int? courseLapsChip(int? laps) => laps != null && laps > 1 ? laps : null;

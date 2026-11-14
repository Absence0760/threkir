/// The order of the "Run any time" park courses on Races & courses (issue
/// #1352). Nearest first when there is a point to measure from, otherwise a
/// stable order that does not depend on where the reader is. Either way a
/// closed course sinks below every course that can be run.
///
/// Parity pair with `apps/web/src/lib/parks/any_time_courses.ts`
/// (docs/architecture/parity_pairs.md).
library;

import 'catalogue_browse.dart' show fold;
import 'park_courses.dart' show regionName;
import 'run_stats.dart' show haversineMetres;

class AnyTimeCourseKey {
  final String regionCode;
  final String parkName;
  final String courseName;
  final String slug;
  final double distanceM;
  final String status;

  /// Where the course starts; null when its geometry has no first point.
  final ({double lat, double lng})? start;

  const AnyTimeCourseKey({
    required this.regionCode,
    required this.parkName,
    required this.courseName,
    required this.slug,
    required this.distanceM,
    required this.status,
    this.start,
  });
}

class OrderedCourse<T> {
  final T course;

  /// Metres from the origin to the course start; null with no origin or start.
  final double? awayM;

  const OrderedCourse(this.course, this.awayM);
}

int _compareStable(AnyTimeCourseKey a, AnyTimeCourseKey b) {
  var c = a.regionCode.compareTo(b.regionCode);
  if (c != 0) return c;
  c = a.parkName.compareTo(b.parkName);
  if (c != 0) return c;
  c = a.distanceM.compareTo(b.distanceM);
  if (c != 0) return c;
  c = a.courseName.compareTo(b.courseName);
  if (c != 0) return c;
  return a.slug.compareTo(b.slug);
}

/// Courses in "Run any time" order. With an origin, by great-circle distance
/// from it to each course start, a course with no start after every course
/// that has one; without, by region, park, distance, then name. Closed
/// courses come last in both. Returns a new list; [courses] is untouched.
List<OrderedCourse<T>> orderAnyTimeCourses<T>(
  List<T> courses,
  AnyTimeCourseKey Function(T course) key,
  ({double lat, double lng})? origin,
) {
  final rows = [
    for (final course in courses)
      (
        course: course,
        k: key(course),
      ),
  ].map((r) {
    final start = r.k.start;
    final awayM = origin != null && start != null
        ? haversineMetres(origin.lat, origin.lng, start.lat, start.lng)
        : null;
    return (course: r.course, k: r.k, awayM: awayM);
  }).toList();
  rows.sort((a, b) {
    final closed = (a.k.status == 'closed' ? 1 : 0) -
        (b.k.status == 'closed' ? 1 : 0);
    if (closed != 0) return closed;
    if (origin != null) {
      final aw = a.awayM;
      final bw = b.awayM;
      if (aw != null && bw != null && aw != bw) return aw.compareTo(bw);
      if (aw == null && bw != null) return 1;
      if (aw != null && bw == null) return -1;
    }
    return _compareStable(a.k, b.k);
  });
  return [for (final r in rows) OrderedCourse(r.course, r.awayM)];
}

/// The words of a park or park course search, folded the way the segment
/// catalogue's search folds (case and accents ignored). A blank query has
/// none, and no words match everything.
List<String> parkSearchTerms(String query) => [
      for (final t in fold(query).split(RegExp(r'\s+')))
        if (t.isNotEmpty) t,
    ];

/// Whether every one of [terms] is in the course's name, its park's name or
/// the park's place (the region's name or code), so "pocahontas 5k" and
/// "virginia beaver" both find a course. With no [courseName] it asks about
/// the park alone.
bool parkSearchMatches(
  List<String> terms, {
  String courseName = '',
  required String parkName,
  required String regionCode,
}) {
  if (terms.isEmpty) return true;
  final text = fold(
      [courseName, parkName, regionName(regionCode), regionCode].join(' '));
  return terms.every(text.contains);
}

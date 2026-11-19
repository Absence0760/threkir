/// The order of the "Run any time" parks and park courses on Races & courses
/// (issue #1352). Nearest first when there is a point to measure from,
/// otherwise a stable order that does not depend on where the reader is.
/// Either way what cannot be run sinks below what can. The section lists
/// parks; a course is listed on its own only when a search finds it by its
/// own name (decisions § 2550).
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

class AnyTimeParkKey {
  final String regionCode;
  final String parkName;
  final String slug;

  /// True when every course the park lists is closed.
  final bool allClosed;

  /// Its courses' starts, the points the park is measured by.
  final List<({double lat, double lng})> starts;

  /// The park's own location, measured only when no course has a start.
  final ({double lat, double lng})? location;

  const AnyTimeParkKey({
    required this.regionCode,
    required this.parkName,
    required this.slug,
    required this.allClosed,
    this.starts = const [],
    this.location,
  });
}

class OrderedPark<T> {
  final T park;

  /// Metres from the origin to the park's nearest course start; null with no
  /// origin or point.
  final double? awayM;

  const OrderedPark(this.park, this.awayM);
}

double? _parkAwayM(({double lat, double lng}) origin, AnyTimeParkKey k) {
  final location = k.location;
  final points = k.starts.isNotEmpty
      ? k.starts
      : location != null
          ? [location]
          : const <({double lat, double lng})>[];
  double? best;
  for (final p in points) {
    final d = haversineMetres(origin.lat, origin.lng, p.lat, p.lng);
    if (best == null || d < best) best = d;
  }
  return best;
}

/// Parks in "Run any time" order: the course rule applied per park. With an
/// origin, by the distance to the park's nearest course start (its own
/// location when no course has one), a park with neither after every
/// measured one; without, by region then name. A park whose courses are all
/// closed comes last in both. Returns a new list; [parks] is untouched.
List<OrderedPark<T>> orderAnyTimeParks<T>(
  List<T> parks,
  AnyTimeParkKey Function(T park) key,
  ({double lat, double lng})? origin,
) {
  final rows = [
    for (final park in parks)
      (park: park, k: key(park)),
  ].map((r) => (
        park: r.park,
        k: r.k,
        awayM: origin == null ? null : _parkAwayM(origin, r.k),
      )).toList();
  rows.sort((a, b) {
    final closed = (a.k.allClosed ? 1 : 0) - (b.k.allClosed ? 1 : 0);
    if (closed != 0) return closed;
    if (origin != null) {
      final aw = a.awayM;
      final bw = b.awayM;
      if (aw != null && bw != null && aw != bw) return aw.compareTo(bw);
      if (aw == null && bw != null) return 1;
      if (aw != null && bw == null) return -1;
    }
    var c = a.k.regionCode.compareTo(b.k.regionCode);
    if (c != 0) return c;
    c = a.k.parkName.compareTo(b.k.parkName);
    if (c != 0) return c;
    return a.k.slug.compareTo(b.k.slug);
  });
  return [for (final r in rows) OrderedPark(r.park, r.awayM)];
}

class AnyTimeSearchView {
  final String parkId;
  final String courseName;
  final String parkName;
  final String regionCode;

  const AnyTimeSearchView({
    required this.parkId,
    required this.courseName,
    required this.parkName,
    required this.regionCode,
  });
}

class AnyTimeHits<C> {
  /// The parks to list, each once, in the order their first course came.
  final List<String> parkIds;

  /// The courses to list on their own.
  final List<C> courses;

  const AnyTimeHits(this.parkIds, this.courses);
}

/// What "Run any time" lists for a search. With no words, every park and no
/// course on its own. With words, the parks whose own name or place matches,
/// plus each course that matches by its own name where its park does not, so
/// "beaver" finds Beaver Lake Trail and "pocahontas" finds the park, not its
/// six courses again.
AnyTimeHits<C> anyTimeSearchHits<C>(
  List<C> courses,
  AnyTimeSearchView Function(C course) view,
  List<String> terms,
) {
  final parkIds = <String>[];
  final seen = <String>{};
  final hits = <C>[];
  for (final c in courses) {
    final v = view(c);
    if (parkSearchMatches(terms,
        parkName: v.parkName, regionCode: v.regionCode)) {
      if (seen.add(v.parkId)) parkIds.add(v.parkId);
    } else if (parkSearchMatches(terms,
        courseName: v.courseName,
        parkName: v.parkName,
        regionCode: v.regionCode)) {
      hits.add(c);
    }
  }
  return AnyTimeHits(parkIds, hits);
}

/// The words of a park or park course search, folded the way the segment
/// catalogue's search folds (case and accents ignored). A blank query has
/// none, and no words match everything.
List<String> parkSearchTerms(String query) => [
      for (final t in fold(query).split(RegExp(r'\s+')))
        if (t.isNotEmpty) t,
    ];

final _wordChar = RegExp(r'[\p{L}\p{N}]', unicode: true);

/// Whether [term] starts a word somewhere in [text]: at its start, or after a
/// character that is neither a letter nor a digit. "belle" starts a word of
/// "belle isle state park" and "va" one of "us-va"; "ark" starts none, so it
/// does not find every park.
bool _startsAWord(String text, String term) {
  for (var i = text.indexOf(term); i != -1; i = text.indexOf(term, i + 1)) {
    if (i == 0 || !_wordChar.hasMatch(text[i - 1])) return true;
  }
  return false;
}

/// Whether every one of [terms] starts a word of the course's name, its
/// park's name or the park's place (the region's name or code), so
/// "pocahontas 5k", "virginia beaver" and "swift cr" all find a course while
/// "ark" does not find every park. With no [courseName] it asks about the
/// park alone. The cases are `fixtures/park_search_cases.json`, read on both
/// sides.
bool parkSearchMatches(
  List<String> terms, {
  String courseName = '',
  required String parkName,
  required String regionCode,
}) {
  if (terms.isEmpty) return true;
  final text = fold(
      [courseName, parkName, regionName(regionCode), regionCode].join(' '));
  return terms.every((t) => _startsAWord(text, t));
}

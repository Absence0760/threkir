/// Park courses (issue #1313, decisions § 2383): the vocabularies the
/// `parks` / `park_courses` CHECK constraints allow, and the pure readers both
/// clients use on those rows.
///
/// Parity pair with `apps/web/src/lib/parks/park_courses.ts`
/// (docs/architecture/parity_pairs.md). The vocabularies are rails in
/// `apps/web/scripts/check_constraint_unions.mjs`.
library;

import 'route_gpx.dart';

const List<String> kParkAgencies = ['nps', 'state', 'county', 'other'];

const List<String> kCourseShapes = ['loop', 'out_and_back', 'point_to_point'];

const List<String> kCourseStatuses = ['open', 'closed', 'seasonal'];

const List<String> kGeometrySources = ['osm', 'nps', 'agency', 'traced'];

const List<String> kCourseDifficulties = ['easy', 'moderate', 'hard'];

class CourseCheckpoint {
  final double lat;
  final double lng;
  const CourseCheckpoint({required this.lat, required this.lng});

  @override
  bool operator ==(Object other) =>
      other is CourseCheckpoint && other.lat == lat && other.lng == lng;

  @override
  int get hashCode => Object.hash(lat, lng);
}

/// The most checkpoints a course may carry; mirrors the CHECK constraint.
const int kMaxCourseCheckpoints = 50;

/// Reads `park_courses.checkpoints`. Returns null — never a shorter list —
/// when the value is not a list or any entry is not a finite in-range
/// lat/lng, because a scorer handed a partial list would time a run that
/// skipped the dropped checkpoint. A caller that gets null must not score
/// the course.
List<CourseCheckpoint>? parseCourseCheckpoints(Object? raw) {
  if (raw is! List || raw.length > kMaxCourseCheckpoints) return null;
  final out = <CourseCheckpoint>[];
  for (final entry in raw) {
    if (entry is! Map) return null;
    final lat = entry['lat'];
    final lng = entry['lng'];
    if (lat is! num || lng is! num) return null;
    final la = lat.toDouble();
    final lo = lng.toDouble();
    if (!la.isFinite || !lo.isFinite) return null;
    if (la < -90 || la > 90 || lo < -180 || lo > 180) return null;
    out.add(CourseCheckpoint(lat: la, lng: lo));
  }
  return out;
}

/// `US-VA` -> `us-va`, the region segment of `/parks/[region]/...`.
String regionSlug(String regionCode) => regionCode.toLowerCase();

/// `us-va` -> `US-VA`; null for anything that is not an ISO 3166-2 shape.
String? regionCodeFromSlug(String slug) {
  final code = slug.toUpperCase();
  return RegExp(r'^[A-Z]{2}-[A-Z0-9]{1,3}$').hasMatch(code) ? code : null;
}

/// English names of the US subdivisions park courses launch in. A proper
/// noun, so it is not translated; a region outside the table shows its code.
const Map<String, String> kRegionNames = {
  'US-AL': 'Alabama',
  'US-AK': 'Alaska',
  'US-AZ': 'Arizona',
  'US-AR': 'Arkansas',
  'US-CA': 'California',
  'US-CO': 'Colorado',
  'US-CT': 'Connecticut',
  'US-DE': 'Delaware',
  'US-DC': 'District of Columbia',
  'US-FL': 'Florida',
  'US-GA': 'Georgia',
  'US-HI': 'Hawaii',
  'US-ID': 'Idaho',
  'US-IL': 'Illinois',
  'US-IN': 'Indiana',
  'US-IA': 'Iowa',
  'US-KS': 'Kansas',
  'US-KY': 'Kentucky',
  'US-LA': 'Louisiana',
  'US-ME': 'Maine',
  'US-MD': 'Maryland',
  'US-MA': 'Massachusetts',
  'US-MI': 'Michigan',
  'US-MN': 'Minnesota',
  'US-MS': 'Mississippi',
  'US-MO': 'Missouri',
  'US-MT': 'Montana',
  'US-NE': 'Nebraska',
  'US-NV': 'Nevada',
  'US-NH': 'New Hampshire',
  'US-NJ': 'New Jersey',
  'US-NM': 'New Mexico',
  'US-NY': 'New York',
  'US-NC': 'North Carolina',
  'US-ND': 'North Dakota',
  'US-OH': 'Ohio',
  'US-OK': 'Oklahoma',
  'US-OR': 'Oregon',
  'US-PA': 'Pennsylvania',
  'US-RI': 'Rhode Island',
  'US-SC': 'South Carolina',
  'US-SD': 'South Dakota',
  'US-TN': 'Tennessee',
  'US-TX': 'Texas',
  'US-UT': 'Utah',
  'US-VT': 'Vermont',
  'US-VA': 'Virginia',
  'US-WA': 'Washington',
  'US-WV': 'West Virginia',
  'US-WI': 'Wisconsin',
  'US-WY': 'Wyoming',
};

String regionName(String regionCode) => kRegionNames[regionCode] ?? regionCode;

/// Whether a course counts toward collections (passport, "courses run") right
/// now. A closed course keeps its efforts and boards but drops out of counts
/// while it is closed; a seasonal one still counts.
bool courseIsCountable(String status) =>
    status == 'open' || status == 'seasonal';

class ParkRegionGroup<T> {
  final String regionCode;
  final List<T> parks;
  const ParkRegionGroup({required this.regionCode, required this.parks});
}

/// Groups parks by region code, regions in code order and parks by name
/// within each, for the parks index.
List<ParkRegionGroup<T>> groupParksByRegion<T>(
  List<T> parks, {
  required String Function(T) regionCodeOf,
  required String Function(T) nameOf,
}) {
  final byRegion = <String, List<T>>{};
  for (final park in parks) {
    byRegion.putIfAbsent(regionCodeOf(park), () => []).add(park);
  }
  final codes = byRegion.keys.toList()..sort();
  return [
    for (final code in codes)
      ParkRegionGroup(
        regionCode: code,
        parks: [...byRegion[code]!]
          ..sort((a, b) => nameOf(a).compareTo(nameOf(b))),
      ),
  ];
}

const GpxAttribution _osmAttribution = GpxAttribution(
  notice: 'Course line © OpenStreetMap contributors, available under the '
      'Open Database License (ODbL).',
  author: 'OpenStreetMap contributors',
  licenseUrl: 'https://opendatacommons.org/licenses/odbl/1-0/',
  linkHref: 'https://www.openstreetmap.org/copyright',
  linkText: '© OpenStreetMap contributors',
);

const GpxAttribution _npsAttribution = GpxAttribution(
  notice: 'Course line from National Park Service trail data.',
  author: 'National Park Service',
  licenseUrl: null,
  linkHref: 'https://www.nps.gov/',
  linkText: 'National Park Service',
);

/// The credit an exported course file carries, from the course's
/// `geometry_source` and its park. Canonical English, like every other GPX
/// `<desc>` the app writes, so the file is the same whoever downloads it.
/// Null for a value outside the vocabulary: the CHECK constraint makes that
/// unreachable for a stored course, and a caller with no course passes null.
/// A park the reader cannot see (pulled) still yields a credit, unnamed.
///
/// `osm` names the ODbL and links OpenStreetMap's copyright page, which is
/// what its licence asks of a produced work. `nps` credits the National Park
/// Service whatever licence a given dataset states. `agency` credits the park
/// and links its own site; `traced` was drawn by us, so it names no rights
/// holder and only says what it was traced against.
GpxAttribution? courseAttribution(
  String? geometrySource, {
  required String? parkName,
  required String? parkWebsiteUrl,
}) {
  final website = parkWebsiteUrl != null && parkWebsiteUrl.startsWith('https://')
      ? parkWebsiteUrl
      : null;
  switch (geometrySource) {
    case 'osm':
      return _osmAttribution;
    case 'nps':
      return _npsAttribution;
    case 'agency':
      return GpxAttribution(
        notice:
            'Course line from trail data published by ${parkName ?? 'the park'}.',
        author: parkName,
        licenseUrl: null,
        linkHref: website,
        linkText: parkName ?? website ?? '',
      );
    case 'traced':
      return GpxAttribution(
        notice: 'Course line traced against the published trail map of '
            '${parkName ?? 'the park'}.',
        author: null,
        licenseUrl: null,
        linkHref: website,
        linkText: parkName ?? website ?? '',
      );
    default:
      return null;
  }
}

/// The GPX a course screen shares: the course line, one `<wpt>` per
/// checkpoint in order (so a watch shows the points a run must pass), and the
/// geometry credit in `<metadata>`. A checkpoint list that could not be read
/// (null) writes no waypoints rather than a partial set. [waypoints] are
/// `(lat, lng, ele)` triples.
String parkCourseGpx({
  required String name,
  required List<({double lat, double lng, double? ele})> waypoints,
  required List<CourseCheckpoint>? checkpoints,
  required GpxAttribution? attribution,
}) {
  final cps = checkpoints ?? const <CourseCheckpoint>[];
  return toRouteGpxWithMarkers(
    name,
    [for (final w in waypoints) [w.lng, w.lat]],
    [for (final w in waypoints) w.ele ?? 0],
    [
      for (var i = 0; i < cps.length; i++)
        RouteGpxMarker(
          label: 'Checkpoint ${i + 1}',
          lat: cps[i].lat,
          lng: cps[i].lng,
          kind: 'checkpoint',
          meta: const {},
        ),
    ],
    attribution,
  );
}

/// One park course effort in a recap period: the course and the park it is in.
class RecapParkRow {
  final String parkId;
  final String parkName;
  final String regionCode;
  final String courseId;
  const RecapParkRow({
    required this.parkId,
    required this.parkName,
    required this.regionCode,
    required this.courseId,
  });
}

/// One park on the recap's "Parks you ran" list.
class RecapPark {
  final String parkId;
  final String name;
  final String regionCode;
  final int courseCount;
  const RecapPark({
    required this.parkId,
    required this.name,
    required this.regionCode,
    required this.courseCount,
  });
}

class RecapParkSummary {
  final int courseCount;
  final int parkCount;
  final List<RecapPark> parks;
  const RecapParkSummary({
    required this.courseCount,
    required this.parkCount,
    required this.parks,
  });
}

/// The recap's park lines from the period's efforts: distinct courses, distinct
/// parks, and each park with the distinct courses run there, most first, then
/// by name. A course run twice counts once.
RecapParkSummary recapParkSummary(List<RecapParkRow> rows) {
  final coursesByPark = <String, Set<String>>{};
  final parkOf = <String, RecapParkRow>{};
  final courses = <String>{};
  for (final r in rows) {
    courses.add(r.courseId);
    coursesByPark.putIfAbsent(r.parkId, () => <String>{}).add(r.courseId);
    parkOf.putIfAbsent(r.parkId, () => r);
  }
  final parks = [
    for (final e in coursesByPark.entries)
      RecapPark(
        parkId: e.key,
        name: parkOf[e.key]!.parkName,
        regionCode: parkOf[e.key]!.regionCode,
        courseCount: e.value.length,
      ),
  ]..sort((a, b) {
      final byCount = b.courseCount - a.courseCount;
      return byCount != 0 ? byCount : a.name.compareTo(b.name);
    });
  return RecapParkSummary(
    courseCount: courses.length,
    parkCount: coursesByPark.length,
    parks: parks,
  );
}

/// One row of `run_park_course_times`: a park course the run completed.
class RunParkCourseTime {
  final String courseName;
  final String parkName;
  final int timeSeconds;
  final int season;
  final int? seasonRank;
  const RunParkCourseTime({
    required this.courseName,
    required this.parkName,
    required this.timeSeconds,
    required this.season,
    required this.seasonRank,
  });

  factory RunParkCourseTime.fromRow(Map<String, dynamic> row) => RunParkCourseTime(
        courseName: row['course_name'] as String,
        parkName: row['park_name'] as String,
        timeSeconds: (row['time_seconds'] as num).round(),
        season: (row['season'] as num).toInt(),
        seasonRank: (row['season_rank'] as num?)?.toInt(),
      );
}

/// The course the share sticker prints: the best season rank among the run's
/// ranked courses, else the first course; null when the run completed none.
RunParkCourseTime? pickShareCourse(List<RunParkCourseTime> rows) {
  RunParkCourseTime? best;
  for (final r in rows) {
    final rank = r.seasonRank;
    if (rank == null) continue;
    if (best == null || rank < best.seasonRank!) best = r;
  }
  return best ?? (rows.isEmpty ? null : rows.first);
}

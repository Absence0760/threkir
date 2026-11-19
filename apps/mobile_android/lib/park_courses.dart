/// Park courses (issue #1313, decisions § 2383): the vocabularies the
/// `parks` / `park_courses` CHECK constraints allow, and the pure readers both
/// clients use on those rows.
///
/// Parity pair with `apps/web/src/lib/parks/park_courses.ts`
/// (docs/architecture/parity_pairs.md). The vocabularies are rails in
/// `apps/web/scripts/check_constraint_unions.mjs`.
library;

import 'dart:math' as math;

import 'route_gpx.dart';
import 'route_guide.dart';
import 'run_stats.dart' show haversineMetres;

const List<String> kParkAgencies = ['nps', 'state', 'county', 'other'];

/// What a catalogue entry is: a park, or a long trail through several parks
/// that belongs to none (decisions § 2581). Mirrors web `PARK_KINDS`.
const List<String> kParkKinds = ['park', 'trail'];

const List<String> kCourseShapes = ['loop', 'out_and_back', 'point_to_point'];

const List<String> kCourseStatuses = ['open', 'closed', 'seasonal'];

const List<String> kGeometrySources = ['osm', 'nps', 'agency', 'traced'];

const List<String> kCourseDifficulties = ['easy', 'moderate', 'hard'];

/// When an organised group regularly uses a course's paths
/// (`park_courses.shared_use`, decisions § 2460). A key, never free text, so
/// the give-way note rendered from it names no one.
const List<String> kSharedUses = ['saturday_morning_group'];

/// Reads `park_courses.shared_use`; null for no shared use or a value this
/// client does not know.
String? parseSharedUse(Object? raw) =>
    raw is String && kSharedUses.contains(raw) ? raw : null;

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

/// Whether the course page offers the way round: Navigate, the GPX and the
/// route guide. A closed course offers none of them, so nothing reads as an
/// invitation to run it while the park has it shut.
bool courseOffersWayfinding(String status) => status != 'closed';

/// Courses longer than this carry the long-course notice.
const double kLongCourseThresholdM = 15000;

/// Whether a course is long enough for the long-course lines of its notices.
bool isLongCourse(double distanceM) =>
    distanceM.isFinite && distanceM > kLongCourseThresholdM;

/// A line of a course's Before you run notice beyond the safety line. Twin of
/// web's `CourseNoticeKey`.
enum CourseNotice { ford, pavedTrail, longTrail, parkHours, parkHoursLong }

/// The lines of a course's Before you run notice that its data supports
/// (decisions § 2582), hazards first, never a fact the data does not hold:
/// [CourseNotice.ford] when the route guide crosses a ford; on a trail
/// ([parkKind] `trail`), [CourseNotice.pavedTrail] when the surface is paved
/// (`road`, a shared-use path), else [CourseNotice.longTrail] on a long
/// course, since a trail has no closing time to name; in a park,
/// [CourseNotice.parkHoursLong] on a long course, else
/// [CourseNotice.parkHours]. Twin of web's `courseNotices`.
List<CourseNotice> courseNotices({
  required String? parkKind,
  required String? surface,
  required double distanceM,
  required RouteGuide? guide,
}) {
  final out = <CourseNotice>[];
  if (guide != null &&
      guide.steps.any((s) => s.kind == 'crossing' && s.crossing == 'ford')) {
    out.add(CourseNotice.ford);
  }
  final long = isLongCourse(distanceM);
  if (parkKind == 'trail') {
    if (surface == 'road') {
      out.add(CourseNotice.pavedTrail);
    } else if (long) {
      out.add(CourseNotice.longTrail);
    }
  } else {
    out.add(long ? CourseNotice.parkHoursLong : CourseNotice.parkHours);
  }
  return out;
}

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
/// checkpoint in order (so a watch shows the points a run must pass), the
/// geometry credit in `<metadata>`, and the route guide as the track's
/// `<desc>`, in canonical English and led by whether it has been checked on
/// the ground. A checkpoint list that could not be read (null) writes no
/// waypoints rather than a partial set. [waypoints] are `(lat, lng, ele)`
/// triples.
String parkCourseGpx({
  required String name,
  required List<({double lat, double lng, double? ele})> waypoints,
  required List<CourseCheckpoint>? checkpoints,
  required GpxAttribution? attribution,
  ({RouteGuide guide, String? checkedAt})? guide,
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
    guide == null
        ? null
        : routeGuideEnglish(guide.guide, guide.checkedAt).join('\n'),
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
  final String effortId;
  final String courseName;
  final String courseSlug;
  final String parkName;
  final String parkSlug;
  final String regionCode;
  final int timeSeconds;
  final int season;
  final int? seasonRank;

  /// The effort's calendar month (1-12) where the park is.
  final int month;

  /// Its place on that month's fastest board, when it is the runner's best
  /// that month and in the top 100.
  final int? monthRank;
  const RunParkCourseTime({
    required this.effortId,
    required this.courseName,
    required this.courseSlug,
    required this.parkName,
    required this.parkSlug,
    required this.regionCode,
    required this.timeSeconds,
    required this.season,
    required this.seasonRank,
    required this.month,
    required this.monthRank,
  });

  factory RunParkCourseTime.fromRow(Map<String, dynamic> row) => RunParkCourseTime(
        effortId: row['effort_id'] as String,
        courseName: row['course_name'] as String,
        courseSlug: row['course_slug'] as String,
        parkName: row['park_name'] as String,
        parkSlug: row['park_slug'] as String,
        regionCode: row['region_code'] as String,
        timeSeconds: (row['time_seconds'] as num).round(),
        season: (row['season'] as num).toInt(),
        seasonRank: (row['season_rank'] as num?)?.toInt(),
        month: (row['month'] as num).toInt(),
        monthRank: (row['month_rank'] as num?)?.toInt(),
      );
}

/// The sticker adds the year's place only when it is this high (issue #1343).
const int kShareCourseYearPlaceMax = 10;

/// The course the share sticker prints: the best month place among the run's
/// park course times (the year place breaking a tie), else the first course;
/// null when the run completed none.
RunParkCourseTime? pickShareCourse(List<RunParkCourseTime> rows) {
  RunParkCourseTime? best;
  for (final r in rows) {
    final rank = r.monthRank;
    if (rank == null) continue;
    if (best == null ||
        rank < best.monthRank! ||
        (rank == best.monthRank &&
            (r.seasonRank ?? double.infinity) <
                (best.seasonRank ?? double.infinity))) {
      best = r;
    }
  }
  return best ?? (rows.isEmpty ? null : rows.first);
}

/// The places a share sticker prints for a course time: the month place, and
/// the year place only when it is in the top [kShareCourseYearPlaceMax].
({int? monthRank, int? seasonRank}) shareCoursePlaces(RunParkCourseTime t) => (
      monthRank: t.monthRank,
      seasonRank: t.seasonRank != null && t.seasonRank! <= kShareCourseYearPlaceMax
          ? t.seasonRank
          : null,
    );

/// Which period a park course board shows (issue #1343).
enum BoardPeriodKind { month, year, all }

/// The period a park course board shows: one calendar month or the year, each
/// where the park is, or all time. A month or year is the `p_season` /
/// `p_month` pair the boards take.
class BoardPeriod {
  final BoardPeriodKind kind;
  final int? season;
  final int? month;

  const BoardPeriod.month(int this.season, int this.month)
      : kind = BoardPeriodKind.month;
  const BoardPeriod.year(int this.season)
      : kind = BoardPeriodKind.year,
        month = null;
  const BoardPeriod.all()
      : kind = BoardPeriodKind.all,
        season = null,
        month = null;

  @override
  bool operator ==(Object other) =>
      other is BoardPeriod &&
      other.kind == kind &&
      other.season == season &&
      other.month == month;

  @override
  int get hashCode => Object.hash(kind, season, month);

  @override
  String toString() => 'BoardPeriod($kind, $season, $month)';
}

/// The earliest season either board accepts (`p_season` between 2000 and 2200).
const int kBoardFirstSeason = 2000;

/// "Now" where the park is, read from `park_season` and `park_month`.
typedef ParkNow = ({int season, int month});

/// Reads a `period` value: `YYYY-MM` is that month, `all` is all time.
/// Anything else, a month outside 1-12, a season the boards refuse, or a
/// month after the park's current one is null, and the caller shows this
/// year.
BoardPeriod? parseBoardPeriod(String? raw, ParkNow now) {
  if (raw == 'all') return const BoardPeriod.all();
  final m = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(raw ?? '');
  if (m == null) return null;
  final season = int.parse(m.group(1)!);
  final month = int.parse(m.group(2)!);
  if (month < 1 || month > 12 || season < kBoardFirstSeason) return null;
  if (season > now.season || (season == now.season && month > now.month)) {
    return null;
  }
  return BoardPeriod.month(season, month);
}

/// The `period` value for a period. Null for the year, the default, so the
/// page's own URL stays bare; only the park's current year is ever shown.
String? boardPeriodParam(BoardPeriod period) => switch (period.kind) {
      BoardPeriodKind.all => 'all',
      BoardPeriodKind.year => null,
      BoardPeriodKind.month =>
        '${period.season}-${period.month.toString().padLeft(2, '0')}',
    };

/// The `p_season` / `p_month` a board call passes for a period; null leaves
/// the argument out.
({int? season, int? month}) boardPeriodArgs(BoardPeriod period) =>
    (season: period.season, month: period.month);

/// The month [delta] months from a month period, or null when that would
/// pass the park's current month or come before the first season the boards
/// accept. Any other period has no neighbour.
BoardPeriod? stepBoardMonth(BoardPeriod period, int delta, ParkNow now) {
  if (period.kind != BoardPeriodKind.month) return null;
  final index = period.season! * 12 + (period.month! - 1) + delta;
  final season = index ~/ 12;
  final month = index % 12 + 1;
  if (season < kBoardFirstSeason) return null;
  if (season > now.season || (season == now.season && month > now.month)) {
    return null;
  }
  return BoardPeriod.month(season, month);
}

/// A start and finish this close are one place, as on a loop: the distance
/// the web course map draws one start-and-finish pin at (`SAME_PLACE_M`).
const double kSameCourseEndM = 30;

class CourseEnds {
  final ({double lat, double lng}) start;

  /// Null when the course starts and finishes in the same place.
  final ({double lat, double lng})? finish;

  const CourseEnds(this.start, this.finish);
}

({double lat, double lng})? _gatePoint(({double? lat, double? lng})? g) {
  final lat = g?.lat;
  final lng = g?.lng;
  return lat != null && lng != null && lat.isFinite && lng.isFinite
      ? (lat: lat, lng: lng)
      : null;
}

/// Where a course starts and finishes: the centre of its start and end timing
/// lines when it has them (the points the matcher times from), else the first
/// and last point of the line drawn on the screen. A loop, or a course whose
/// two ends are within [kSameCourseEndM] of each other, has one place for
/// both. Null when there is no point to give.
CourseEnds? courseEnds({
  required List<({double lat, double lng})> line,
  ({double? lat, double? lng})? startGate,
  ({double? lat, double? lng})? endGate,
  String? shape,
}) {
  final start = _gatePoint(startGate) ?? (line.isEmpty ? null : line.first);
  final finish = _gatePoint(endGate) ?? (line.isEmpty ? null : line.last);
  if (start == null || finish == null) return null;
  final same = shape == 'loop' ||
      haversineMetres(start.lat, start.lng, finish.lat, finish.lng) <=
          kSameCourseEndM;
  return CourseEnds(start, same ? null : finish);
}

String _fixed5(double v) {
  final s = v.toStringAsFixed(5);
  return s == '-0.00000' ? '0.00000' : s;
}

/// A point as "lat, lng" to five decimals (about 1 m), the order Google Maps
/// and Apple Maps both read when it is pasted into their search.
String formatLatLng(({double lat, double lng}) p) =>
    '${_fixed5(p.lat)}, ${_fixed5(p.lng)}';

/// Checkpoints closer than this share of the course's extent share one
/// marker.
const double kCheckpointMergeFraction = 0.05;

/// ...and never closer than this, whatever the course's size.
const double kCheckpointMergeMinM = 25;

/// A checkpoint marker on a course map: one or more numbers, or an
/// out-and-back's turn ([isTurn]).
class CheckpointMark {
  CheckpointMark({
    required this.isTurn,
    required this.numbers,
    required this.lat,
    required this.lng,
  });

  final bool isTurn;

  /// The 1-based checkpoint numbers it stands for, in course order.
  final List<int> numbers;
  final double lat;
  final double lng;
}

/// What a course map marks for its checkpoints (decisions § 2582). On an
/// out-and-back the last checkpoint is the turn, marked as such. The rest
/// are numbered, and checkpoints so close that their markers would cover
/// each other at the whole-course zoom share one marker that carries every
/// number: closer than [kCheckpointMergeFraction] of the line's
/// bounding-box diagonal, at least [kCheckpointMergeMinM], to the first
/// checkpoint of a marker. Twin of web's `checkpointMarks`.
List<CheckpointMark> checkpointMarks({
  required List<({double lat, double lng})> checkpoints,
  required List<({double lat, double lng})> line,
  required String? shape,
}) {
  var s = double.infinity;
  var w = double.infinity;
  var n = double.negativeInfinity;
  var e = double.negativeInfinity;
  for (final p in line) {
    s = math.min(s, p.lat);
    n = math.max(n, p.lat);
    w = math.min(w, p.lng);
    e = math.max(e, p.lng);
  }
  final extent = s.isFinite ? haversineMetres(s, w, n, e) : 0.0;
  final mergeM =
      math.max(kCheckpointMergeMinM, kCheckpointMergeFraction * extent);
  final turn = shape == 'out_and_back' && checkpoints.isNotEmpty
      ? checkpoints.length - 1
      : -1;
  final marks = <CheckpointMark>[];
  for (var i = 0; i < checkpoints.length; i++) {
    if (i == turn) continue;
    final c = checkpoints[i];
    CheckpointMark? near;
    for (final m in marks) {
      if (haversineMetres(m.lat, m.lng, c.lat, c.lng) < mergeM) {
        near = m;
        break;
      }
    }
    if (near != null) {
      near.numbers.add(i + 1);
    } else {
      marks.add(CheckpointMark(
          isTurn: false, numbers: [i + 1], lat: c.lat, lng: c.lng));
    }
  }
  if (turn >= 0) {
    marks.add(CheckpointMark(
      isTurn: true,
      numbers: [turn + 1],
      lat: checkpoints[turn].lat,
      lng: checkpoints[turn].lng,
    ));
  }
  return marks;
}

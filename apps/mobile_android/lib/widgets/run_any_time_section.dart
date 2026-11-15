import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' show Position;
import 'package:ui_kit/ui_kit.dart'
    show AppSpace, EmptyState, ListCard, ListSkeleton, SectionHeader;

import '../any_time_courses.dart';
import '../backend_timeout.dart';
import '../l10n/gen/app_localizations.dart';
import '../park_course_distance.dart' show courseLapsChip, courseShapeShown;
import '../park_courses.dart' show regionName;
import '../preferences.dart' show compactDistanceForPref, formatEffortTime;
import '../quiet_location.dart';
import '../screens/park_courses_screen.dart';

/// How many parks (and searched courses) the section lists before "See all".
/// Mirrors `ANY_TIME_LIMIT` on web `/races`.
const int kRunAnyTimeLimit = 8;

/// The "Run any time" half of Races & courses (issue #1352): the parks whose
/// courses a runner can go and do on any day, nearest first once the phone
/// already knows where it is, each opening its park page of courses. A course
/// is listed on its own only when the search finds it by its own name
/// (decisions § 2549). When [limit] cuts the list short, the heading offers
/// "See all N courses", which opens `ParksScreen` (the full index) on the
/// same search; a list that is already whole (the Courses view) has no such
/// link.
///
/// It loads on its own, so a failed race search never hides it and a failed
/// course read never hides the races above it. This season's records, shown
/// on a searched course, are a second, auxiliary read that only a signed-in
/// runner can make: when it fails the courses still list, without records.
class RunAnyTimeSection extends StatefulWidget {
  final ApiClient api;

  /// Test seam; production reads the quiet browse fix, which never prompts.
  final Stream<Position> Function()? positions;

  /// How many parks, and searched courses, to list; null lists every one, as
  /// Races & courses does when the courses are all it shows.
  final int? limit;

  /// The tab's search, already debounced. Every course is loaded, so it is
  /// matched here on the list rather than asked of the server
  /// ([anyTimeSearchHits]: parks by name and place, courses by their own
  /// name).
  final String query;

  /// Empties the search, offered when nothing matches it. Null offers no
  /// way out but the field itself.
  final VoidCallback? onClearQuery;

  const RunAnyTimeSection({
    super.key,
    required this.api,
    this.positions,
    this.limit = kRunAnyTimeLimit,
    this.query = '',
    this.onClearQuery,
  });

  @override
  State<RunAnyTimeSection> createState() => _RunAnyTimeSectionState();
}

typedef _Entry = ({ParkListing park, ParkCourseListing course});
typedef _Park = ({ParkListing park, List<ParkCourseListing> courses});

/// What the section lists: the parks and searched courses after [limit],
/// whether it cut either, and how many courses the whole list stands for.
typedef _Listing = ({
  List<OrderedPark<_Park>> parks,
  List<OrderedCourse<_Entry>> courses,
  bool truncated,
  int courseTotal,
});

class _RunAnyTimeSectionState extends State<RunAnyTimeSection> {
  List<_Entry> _courses = const [];
  bool _loading = true;
  bool _failed = false;
  Map<String, ParkCourseRecord> _records = const {};
  bool _recordsFailed = false;
  ({double lat, double lng})? _origin;
  StreamSubscription<Position>? _fixes;

  @override
  void initState() {
    super.initState();
    _loadCourses();
    _loadRecords();
    try {
      _fixes = (widget.positions ?? quietPositionFixes)().listen(
        (p) {
          if (mounted) {
            setState(() => _origin = (lat: p.latitude, lng: p.longitude));
          }
        },
        onError: (Object e) => debugPrint('run any time: no fix: $e'),
      );
    } catch (e) {
      debugPrint('run any time: location unavailable: $e');
    }
  }

  @override
  void dispose() {
    _fixes?.cancel();
    super.dispose();
  }

  Future<void> _loadCourses() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final (parks, courses) = await (
        widget.api.fetchParks(),
        widget.api.fetchAllParkCourses(),
      ).wait.timeout(kBackendLoadTimeout);
      final byId = {for (final p in parks) p.park.id: p};
      if (!mounted) return;
      setState(() {
        _courses = [
          for (final c in courses)
            if (byId[c.course.parkId] case final park?)
              (park: park, course: c),
        ];
        _loading = false;
      });
    } catch (e) {
      debugPrint('run any time: park courses read failed: $e');
      if (!mounted) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  Future<void> _loadRecords() async {
    // The board behind the records refuses an anonymous caller, so a
    // signed-out runner gets the courses without the line rather than a
    // failure they can do nothing about.
    if (widget.api.userId == null) return;
    setState(() => _recordsFailed = false);
    try {
      final records = await widget.api
          .fetchParkCourseRecords()
          .timeout(kBackendLoadTimeout);
      if (mounted) setState(() => _records = records);
    } catch (e) {
      debugPrint('run any time: course records read failed: $e');
      if (mounted) setState(() => _recordsFailed = true);
    }
  }

  static AnyTimeCourseKey _key(_Entry e) {
    final waypoints = e.course.segment.waypoints;
    final first = waypoints.isEmpty ? null : waypoints.first;
    final lat = first?['lat'];
    final lng = first?['lng'];
    return AnyTimeCourseKey(
      regionCode: e.park.park.regionCode,
      parkName: e.park.park.name,
      courseName: e.course.segment.name,
      slug: e.course.course.slug,
      distanceM: e.course.segment.distanceM,
      status: e.course.course.status,
      start: lat is num && lng is num
          ? (lat: lat.toDouble(), lng: lng.toDouble())
          : null,
    );
  }

  void _open(_Entry e) => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ParkCourseScreen(
            api: widget.api,
            listing: e.park,
            course: e.course,
          ),
        ),
      );

  void _openPark(ParkListing park) => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ParkScreen(api: widget.api, listing: park),
        ),
      );

  void _openAll() => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              ParksScreen(api: widget.api, initialQuery: widget.query.trim()),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final listing = _loading || _failed ? null : _listing();
    final truncated = listing?.truncated ?? false;
    return Column(
      key: const Key('races-any-time'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: SectionHeader.title(
            label: l10n.racesSectionAnyTime,
            trailing: truncated
                ? TextButton(
                    key: const Key('races-any-time-all'),
                    onPressed: _openAll,
                    child: Text(l10n.racesAnyTimeSeeAll(listing!.courseTotal)),
                  )
                : null,
          ),
        ),
        ..._body(l10n, theme, listing),
      ],
    );
  }

  static ({double lat, double lng})? _start(ParkCourseListing c) {
    final waypoints = c.segment.waypoints;
    final first = waypoints.isEmpty ? null : waypoints.first;
    final lat = first?['lat'];
    final lng = first?['lng'];
    return lat is num && lng is num
        ? (lat: lat.toDouble(), lng: lng.toDouble())
        : null;
  }

  static AnyTimeParkKey _parkKey(_Park p) {
    final park = p.park.park;
    final lat = park.centroidLat;
    final lng = park.centroidLng;
    return AnyTimeParkKey(
      regionCode: park.regionCode,
      parkName: park.name,
      slug: park.slug,
      allClosed: p.courses.every((c) => c.course.status == 'closed'),
      starts: [for (final c in p.courses) ?_start(c)],
      location: lat != null && lng != null ? (lat: lat, lng: lng) : null,
    );
  }

  /// The parks the search keeps (every one when there is none) and the
  /// courses it finds by their own name, each in order and cut to [limit].
  _Listing _listing() {
    final hits = anyTimeSearchHits(
      _courses,
      (e) => AnyTimeSearchView(
        parkId: e.park.park.id,
        courseName: e.course.segment.name,
        parkName: e.park.park.name,
        regionCode: e.park.park.regionCode,
      ),
      parkSearchTerms(widget.query),
    );
    final byPark = <String, _Park>{};
    for (final e in _courses) {
      byPark
          .putIfAbsent(e.park.park.id, () => (park: e.park, courses: []))
          .courses
          .add(e.course);
    }
    final parks = orderAnyTimeParks(
      [for (final id in hits.parkIds) ?byPark[id]],
      _parkKey,
      _origin,
    );
    final courses = orderAnyTimeCourses(hits.courses, _key, _origin);
    final limit = widget.limit;
    return (
      parks: limit == null ? parks : parks.take(limit).toList(),
      courses: limit == null ? courses : courses.take(limit).toList(),
      truncated:
          limit != null && (parks.length > limit || courses.length > limit),
      courseTotal:
          parks.fold<int>(0, (n, p) => n + p.park.courses.length) +
              courses.length,
    );
  }

  List<Widget> _body(
      AppLocalizations l10n, ThemeData theme, _Listing? listing) {
    if (_loading) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ListSkeleton.section(label: l10n.parksLoading, rows: 3),
        ),
      ];
    }
    if (_failed) {
      return [
        _InlineFailure(
          key: const Key('races-any-time-error'),
          message: l10n.parksLoadFailed,
          retry: l10n.parksRetry,
          onRetry: _loadCourses,
        ),
      ];
    }
    final parks = listing!.parks;
    final ordered = listing.courses;
    final empty = parks.isEmpty && ordered.isEmpty;
    if (empty && widget.query.trim().isNotEmpty) {
      return [
        EmptyState(
          key: const Key('races-any-time-no-match'),
          icon: Icons.search_off,
          title: l10n.racesAnyTimeNoMatch(widget.query.trim()),
          ctaLabel: widget.onClearQuery == null ? null : l10n.commonClearSearch,
          ctaIcon: Icons.close,
          onCta: widget.onClearQuery,
        ),
      ];
    }
    if (empty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(l10n.parksEmpty, key: const Key('races-any-time-empty')),
        ),
      ];
    }
    final signedIn = widget.api.userId != null;
    return [
      // A sub-heading only when a search lists courses beside the parks.
      if (parks.isNotEmpty && ordered.isNotEmpty)
        _SubHeading(l10n.racesAnyTimeParks),
      for (final row in parks)
        Padding(
          key: ValueKey('races-any-time-park-${row.park.park.park.id}'),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ParkCard(
                listing: row.park.park,
                courses: row.park.courses,
                onTap: () => _openPark(row.park.park),
              ),
              if (row.awayM case final away?)
                Padding(
                  padding: const EdgeInsets.only(top: 2, left: 4),
                  child: Text(
                    l10n.racesAnyTimeAway(compactDistanceForPref(away)),
                    key: ValueKey(
                        'races-any-time-park-away-${row.park.park.park.id}'),
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
            ],
          ),
        ),
      if (ordered.isNotEmpty) _SubHeading(l10n.racesShowCourses),
      if (_recordsFailed && ordered.isNotEmpty)
        _InlineFailure(
          key: const Key('races-any-time-records-failed'),
          message: l10n.racesAnyTimeFastestFailed,
          retry: l10n.parksRetry,
          onRetry: _loadRecords,
        ),
      for (final row in ordered)
        _CourseCard(
          entry: row.course,
          awayM: row.awayM,
          record: _records[row.course.course.course.id],
          showRecord: signedIn && !_recordsFailed,
          onTap: () => _open(row.course),
          onOpenPark: () => _openPark(row.course.park),
        ),
    ];
  }
}

class _CourseCard extends StatelessWidget {
  final _Entry entry;
  final double? awayM;
  final ParkCourseRecord? record;
  final bool showRecord;
  final VoidCallback onTap;
  final VoidCallback onOpenPark;

  const _CourseCard({
    required this.entry,
    required this.awayM,
    required this.record,
    required this.showRecord,
    required this.onTap,
    required this.onOpenPark,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final park = entry.park.park;
    final course = entry.course.course;
    final segment = entry.course.segment;
    final laps = courseLapsChip(course.laps);
    final pills = [
      if (laps != null)
        courseFactPill(
          context,
          l10n.parksCourseLaps(laps),
          key: ValueKey('races-any-time-laps-${course.id}'),
        ),
      if (courseShapeShown(course.courseShape))
        courseFactPill(context, courseShapeLabel(l10n, course.courseShape)),
    ];
    final meta = [
      courseDistanceForPref(segment.distanceM),
      if (awayM case final away?)
        l10n.racesAnyTimeAway(compactDistanceForPref(away)),
    ].join(' · ');
    final r = record;
    final recordLine = !showRecord
        ? null
        : r == null
            ? l10n.racesAnyTimeNoTimeYet
            : r.displayName != null && r.displayName!.trim().isNotEmpty
                ? l10n.racesAnyTimeFastestBy('${r.season}',
                    formatEffortTime(r.timeSeconds), r.displayName!)
                : l10n.racesAnyTimeFastest(
                    '${r.season}', formatEffortTime(r.timeSeconds));
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    // The content form, not ListCard.row: the park name is a link of its own
    // inside the card, which a row would merge into the card's label.
    return ListCard(
      key: ValueKey('races-any-time-course-${course.id}'),
      margin: ListCard.listMargin,
      dense: true,
      onTap: onTap,
      child: Row(
        children: [
          Icon(Icons.park_outlined, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  segment.name,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                ParkNameLink(
                  key: ValueKey('races-any-time-park-link-${course.id}'),
                  label: '${park.name}, ${regionName(park.regionCode)}',
                  onTap: onOpenPark,
                ),
                Text(meta, style: muted),
                if (pills.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpace.xs),
                    child: Wrap(spacing: 6, runSpacing: 4, children: pills),
                  ),
                if (recordLine != null) Text(recordLine),
              ],
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          if (course.status == 'open')
            Icon(
              Icons.chevron_right,
              color: theme.colorScheme.onSurfaceVariant,
            )
          else
            Flexible(
              child: Chip(label: Text(courseStatusLabel(l10n, course.status))),
            ),
        ],
      ),
    );
  }
}

class _SubHeading extends StatelessWidget {
  final String label;

  const _SubHeading(this.label);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Semantics(
          header: true,
          child: Text(label, style: Theme.of(context).textTheme.titleSmall),
        ),
      );
}

class _InlineFailure extends StatelessWidget {
  final String message;
  final String retry;
  final VoidCallback onRetry;

  const _InlineFailure({
    super.key,
    required this.message,
    required this.retry,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        children: [
          Text(message, style: theme.textTheme.bodyMedium),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: Text(retry),
          ),
        ],
      ),
    );
  }
}

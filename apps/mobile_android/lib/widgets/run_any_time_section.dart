import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' show Position;
import 'package:ui_kit/ui_kit.dart' show ListSkeleton;

import '../any_time_courses.dart';
import '../backend_timeout.dart';
import '../l10n/gen/app_localizations.dart';
import '../park_course_distance.dart' show courseLapsChip, courseShapeShown;
import '../park_courses.dart' show regionName;
import '../preferences.dart' show formatDistanceForPref, formatEffortTime;
import '../quiet_location.dart';
import '../screens/park_courses_screen.dart';

/// How many courses the section lists before "All park courses". Mirrors
/// `ANY_TIME_LIMIT` on web `/races`.
const int kRunAnyTimeLimit = 8;

/// The "Run any time" half of Races & courses (issue #1352): the park courses
/// a runner can go and do on any day, nearest first once the phone already
/// knows where it is, each opening its course page. `ParksScreen` stays the
/// full index, one tap away at the foot.
///
/// It loads on its own, so a failed race search never hides it and a failed
/// course read never hides the races above it. This season's records are a
/// second, auxiliary read that only a signed-in runner can make: when it
/// fails the courses still list, without records.
class RunAnyTimeSection extends StatefulWidget {
  final ApiClient api;

  /// Test seam; production reads the quiet browse fix, which never prompts.
  final Stream<Position> Function()? positions;

  const RunAnyTimeSection({super.key, required this.api, this.positions});

  @override
  State<RunAnyTimeSection> createState() => _RunAnyTimeSectionState();
}

typedef _Entry = ({ParkListing park, ParkCourseListing course});

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

  void _openAll() => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ParksScreen(api: widget.api),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      key: const Key('races-any-time'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: Semantics(
            header: true,
            child: Text(l10n.racesSectionAnyTime,
                style: theme.textTheme.titleMedium),
          ),
        ),
        ..._body(l10n, theme),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: const Key('races-any-time-all'),
              onPressed: _openAll,
              icon: const Icon(Icons.park_outlined),
              label: Text(l10n.parksBackToParks),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _body(AppLocalizations l10n, ThemeData theme) {
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
    final ordered =
        orderAnyTimeCourses(_courses, _key, _origin).take(kRunAnyTimeLimit);
    if (ordered.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(l10n.parksEmpty, key: const Key('races-any-time-empty')),
        ),
      ];
    }
    final signedIn = widget.api.userId != null;
    return [
      if (_recordsFailed)
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

  const _CourseCard({
    required this.entry,
    required this.awayM,
    required this.record,
    required this.showRecord,
    required this.onTap,
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
        l10n.racesAnyTimeAway(formatDistanceForPref(away)),
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
    return Card(
      key: ValueKey('races-any-time-course-${course.id}'),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: const Icon(Icons.park_outlined),
        title: Text(segment.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${park.name}, ${regionName(park.regionCode)}', style: muted),
            Text(meta, style: muted),
            if (pills.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(spacing: 6, runSpacing: 4, children: pills),
              ),
            if (recordLine != null) Text(recordLine),
          ],
        ),
        trailing: course.status == 'open'
            ? const Icon(Icons.chevron_right)
            : Chip(label: Text(courseStatusLabel(l10n, course.status))),
        onTap: onTap,
      ),
    );
  }
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

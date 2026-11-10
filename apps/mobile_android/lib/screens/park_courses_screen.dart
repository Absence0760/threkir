import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ui_kit/ui_kit.dart'
    show
        AppSemanticColors,
        ChoiceChipOption,
        ChoiceChipRow,
        EmptyState,
        IdentityAvatar,
        ListSkeleton,
        StatGrid,
        StatTile,
        StatusPill,
        StatusPillSize,
        TextLane;
import 'package:url_launcher/url_launcher.dart';

import '../adaptive_width.dart';
import '../auth_error.dart';
import '../backend_timeout.dart';
import '../elevation_profile.dart' show elevationSeries;
import '../l10n/date_format.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../park_course_distance.dart';
import '../park_courses.dart';
import '../preferences.dart';
import '../route_guide.dart';
import '../route_surface_label.dart';
import '../share_sheet.dart';
import '../widgets/elevation_chart.dart';
import '../widgets/error_state.dart';
import 'help_screen.dart' show openGuide;
import 'public_route_screen.dart';
import '../widgets/head_to_head_card.dart' show showHeadToHeadSheet;
import '../widgets/live_run_map.dart' show currentBasemapIsDark;
import '../widgets/park_course_map.dart';
import '../widgets/park_course_report_sheet.dart';
import '../widgets/sign_in_required_state.dart';
import '../widgets/top_banner.dart';
import '../widgets/old_match_note.dart';
import '../widgets/track_preview.dart';

/// Park courses (issue #1313, decisions § 2383): parks by region, each a card
/// with its course lines, how many courses it has and their distance range.
/// Mobile mirror of web `/parks`. The catalogue is world-readable, so this
/// works signed out; only the boards on [ParkCourseScreen] need an account.
class ParksScreen extends StatefulWidget {
  final ApiClient? api;

  const ParksScreen({super.key, this.api});

  @override
  State<ParksScreen> createState() => _ParksScreenState();
}

class _ParksScreenState extends State<ParksScreen> {
  List<ParkListing> _parks = const [];
  bool _loading = true;
  bool _error = false;

  /// Every listed course, by park id. A second read the cards only decorate
  /// with, so a failure leaves the parks listed without their lines.
  Map<String, List<ParkCourseListing>> _coursesByPark = const {};

  @override
  void initState() {
    super.initState();
    _load();
    _loadCourses();
  }

  Future<void> _load() async {
    final api = widget.api;
    if (api == null) {
      setState(() {
        _error = true;
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final parks = await api.fetchParks().timeout(kBackendLoadTimeout);
      if (!mounted) return;
      setState(() {
        _parks = parks;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = true;
        _loading = false;
      });
    }
  }

  Future<void> _loadCourses() async {
    final api = widget.api;
    if (api == null) return;
    try {
      final courses =
          await api.fetchAllParkCourses().timeout(kBackendLoadTimeout);
      final byPark = <String, List<ParkCourseListing>>{};
      for (final c in courses) {
        byPark.putIfAbsent(c.course.parkId, () => []).add(c);
      }
      if (mounted) setState(() => _coursesByPark = byPark);
    } catch (e) {
      debugPrint('parks index: course read failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final groups = groupParksByRegion<ParkListing>(
      _parks,
      regionCodeOf: (p) => p.park.regionCode,
      nameOf: (p) => p.park.name,
    );
    final wide = widthClassOf(context) == WidthClass.expanded;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.parksTitle)),
      body: _loading
          ? ListView(
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                ListSkeleton.section(label: l10n.parksLoading, rows: 5),
              ],
            )
          : _error
          ? ErrorState(message: l10n.parksLoadFailed, onRetry: _load)
          : _parks.isEmpty
          ? EmptyState(
              key: const Key('parks-empty'),
              icon: Icons.park_outlined,
              title: l10n.parksEmpty,
              body: l10n.parksIntro,
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                contentColumn(
                  context,
                  maxWidth: 1080,
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        l10n.parksIntro,
                        key: const Key('parks-intro'),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      for (final group in groups) ...[
                        Padding(
                          padding: const EdgeInsets.only(top: 20, bottom: 8),
                          child: Semantics(
                            header: true,
                            child: Text(
                              regionName(group.regionCode),
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                        ),
                        if (wide)
                          _TwoColumns(
                            children: [
                              for (final listing in group.parks)
                                _parkCard(listing),
                            ],
                          )
                        else
                          for (final listing in group.parks)
                            _parkCard(listing),
                      ],
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _parkCard(ParkListing listing) => _ParkCard(
        key: ValueKey('parks-park-${listing.park.id}'),
        listing: listing,
        courses: _coursesByPark[listing.park.id],
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ParkScreen(api: widget.api, listing: listing),
          ),
        ),
      );
}

/// Lays [children] out two to a row, each half the width.
class _TwoColumns extends StatelessWidget {
  final List<Widget> children;
  const _TwoColumns({required this.children});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          const gap = 12.0;
          final w = (constraints.maxWidth - gap) / 2;
          return Wrap(
            spacing: gap,
            children: [
              for (final c in children) SizedBox(width: w, child: c),
            ],
          );
        },
      );
}

class _ParkCard extends StatelessWidget {
  final ParkListing listing;

  /// Null while the course read is out or after it failed.
  final List<ParkCourseListing>? courses;
  final VoidCallback onTap;

  const _ParkCard({
    super.key,
    required this.listing,
    required this.courses,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final park = listing.park;
    final sorted = courses == null ? null : sortedParkCourses(courses!);
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final range = sorted == null
        ? null
        : courseDistanceRange(
            [for (final c in sorted) c.segment.distanceM],
            activeDistanceUnit,
          );
    final summary = sorted == null || sorted.isEmpty
        ? null
        : [l10n.parksCourseCount(sorted.length), ?range].join(' · ');
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (sorted != null && sorted.isNotEmpty)
              ParkOverviewMap(
                lines: [
                  for (final c in sorted)
                    ApiClient.globalSegmentGeometry(c.segment),
                ],
                aspectRatio: 2.4,
                showStarts: false,
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(park.name, style: theme.textTheme.titleMedium),
                        Text(agencyLabel(l10n, park.agency), style: muted),
                        if (summary != null)
                          Text(
                            summary,
                            key: ValueKey('parks-park-summary-${park.id}'),
                            style: theme.textTheme.bodyMedium,
                          ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A park's courses in list order (shortest first, closed last).
List<ParkCourseListing> sortedParkCourses(List<ParkCourseListing> courses) =>
    sortParkCourses(
      courses,
      (c) => ParkCourseSortKey(
        distanceM: c.segment.distanceM,
        name: c.segment.name,
        slug: c.course.slug,
        status: c.course.status,
      ),
    );

/// A course distance as a course reads it: "5 km", "21.1 km", "3.1 mi".
String courseDistanceForPref(double metres) =>
    courseDistanceLabel(metres, activeDistanceUnit) ??
    formatDistanceForPref(metres);

String agencyLabel(AppLocalizations l10n, String agency) => switch (agency) {
  'nps' => l10n.parksAgencyNps,
  'state' => l10n.parksAgencyState,
  'county' => l10n.parksAgencyCounty,
  _ => l10n.parksAgencyOther,
};

String courseShapeLabel(AppLocalizations l10n, String shape) => switch (shape) {
  'loop' => l10n.parksShapeLoop,
  'out_and_back' => l10n.parksShapeOutAndBack,
  'point_to_point' => l10n.parksShapePointToPoint,
  _ => shape,
};

String courseStatusLabel(AppLocalizations l10n, String status) =>
    switch (status) {
      'open' => l10n.parksStatusOpen,
      'closed' => l10n.parksStatusClosed,
      'seasonal' => l10n.parksStatusSeasonal,
      _ => status,
    };

String? courseDifficultyLabel(AppLocalizations l10n, String? difficulty) =>
    switch (difficulty) {
      'easy' => l10n.parksDifficultyEasy,
      'moderate' => l10n.parksDifficultyModerate,
      'hard' => l10n.parksDifficultyHard,
      _ => null,
    };

String geometryAttribution(AppLocalizations l10n, String source) =>
    switch (source) {
      'osm' => l10n.parksAttributionOsm,
      'nps' => l10n.parksAttributionNps,
      'agency' => l10n.parksAttributionAgency,
      _ => l10n.parksAttributionTraced,
    };

/// The one credit line a course carries: the catalogue's own credit when it
/// has one, else the label for where its line came from.
String courseCredit(AppLocalizations l10n, ParkCourseRow course) {
  final own = course.attribution?.trim();
  return own != null && own.isNotEmpty
      ? own
      : geometryAttribution(l10n, course.geometrySource);
}

/// A course's status as a pill, or null for an open course.
Widget? courseStatusPill(BuildContext context, String status) {
  if (status == 'open') return null;
  final l10n = AppLocalizations.of(context);
  final semantic = AppSemanticColors.of(context);
  final colour = status == 'closed' ? semantic.danger : semantic.warning;
  return StatusPill(
    label: courseStatusLabel(l10n, status),
    foreground: colour,
    outline: colour,
    size: StatusPillSize.compact,
  );
}

/// A neutral fact about a course (laps, shape, climb, difficulty) as a pill.
Widget courseFactPill(BuildContext context, String label, {Key? key}) {
  final scheme = Theme.of(context).colorScheme;
  return StatusPill(
    key: key,
    label: label,
    foreground: scheme.onSurfaceVariant,
    fill: scheme.surfaceContainerHighest,
    size: StatusPillSize.compact,
  );
}

/// The pills a course carries beside its distance: laps when there is more
/// than one, the shape only when it is not a loop, the climb, the difficulty
/// and a status that is not open.
List<Widget> courseFactPills(
  BuildContext context,
  ParkCourseListing c, {
  bool includeClimb = true,
}) {
  final l10n = AppLocalizations.of(context);
  final course = c.course;
  final laps = courseLapsChip(course.laps);
  final climb = c.segment.elevationM;
  final difficulty = courseDifficultyLabel(l10n, course.difficulty);
  return [
    if (laps != null)
      courseFactPill(
        context,
        l10n.parksCourseLaps(laps),
        key: ValueKey('park-course-laps-${course.id}'),
      ),
    if (courseShapeShown(course.courseShape))
      courseFactPill(context, courseShapeLabel(l10n, course.courseShape)),
    if (includeClimb && climb != null && climb > 0)
      courseFactPill(
        context,
        l10n.parksCourseClimb(formatElevationForPref(climb)),
      ),
    if (difficulty != null) courseFactPill(context, difficulty),
    ?courseStatusPill(context, course.status),
  ];
}

String _recordLine(AppLocalizations l10n, ParkCourseRecord? r) {
  if (r == null) return l10n.racesAnyTimeNoRecord;
  final name = r.displayName?.trim();
  return name != null && name.isNotEmpty
      ? l10n.racesAnyTimeRecordBy(
          '${r.season}', formatEffortTime(r.timeSeconds), name)
      : l10n.racesAnyTimeRecord('${r.season}', formatEffortTime(r.timeSeconds));
}

Future<void> _openParkWebsite(BuildContext context, String url) async {
  final l10n = AppLocalizations.of(context);
  var ok = false;
  try {
    ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (e) {
    debugPrint('park website: launch failed for $url: $e');
  }
  if (!ok && context.mounted) {
    showTopBanner(context, l10n.parksWebsiteOpenFailed);
  }
}

/// One park: where it is and who runs it, a map of every course line, and
/// its courses shortest first, each with its shape, climb and this season's
/// record. Mobile mirror of web `/parks/[region]/[park]`.
class ParkScreen extends StatefulWidget {
  final ApiClient? api;
  final ParkListing listing;

  const ParkScreen({super.key, required this.api, required this.listing});

  @override
  State<ParkScreen> createState() => _ParkScreenState();
}

class _ParkScreenState extends State<ParkScreen> {
  List<ParkCourseListing> _courses = const [];
  bool _loading = true;
  bool _error = false;
  Map<String, ParkCourseRecord> _records = const {};
  bool _recordsFailed = false;

  @override
  void initState() {
    super.initState();
    _load();
    _loadRecords();
  }

  Future<void> _load() async {
    final api = widget.api;
    if (api == null) {
      setState(() {
        _error = true;
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final courses = await api
          .fetchParkCourses(widget.listing.park.id)
          .timeout(kBackendLoadTimeout);
      if (!mounted) return;
      setState(() {
        _courses = sortedParkCourses(courses);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = true;
        _loading = false;
      });
    }
  }

  Future<void> _loadRecords() async {
    // The board behind the records refuses an anonymous caller, so a
    // signed-out reader gets the courses without the line, not a failure.
    final api = widget.api;
    if (api == null || api.userId == null) return;
    setState(() => _recordsFailed = false);
    try {
      final records =
          await api.fetchParkCourseRecords().timeout(kBackendLoadTimeout);
      if (mounted) setState(() => _records = records);
    } catch (e) {
      debugPrint('park page: course records read failed: $e');
      if (mounted) setState(() => _recordsFailed = true);
    }
  }

  void _open(ParkCourseListing c) => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ParkCourseScreen(
            api: widget.api,
            listing: widget.listing,
            course: c,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final park = widget.listing.park;
    final website = park.websiteUrl;
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final signedIn = widget.api?.userId != null;
    final darkBasemap = currentBasemapIsDark(context);
    return Scaffold(
      appBar: AppBar(title: Text(park.name)),
      body: _loading
          ? ListView(
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                ListSkeleton.section(label: l10n.parksLoading, rows: 3),
              ],
            )
          : _error
          ? ErrorState(message: l10n.parksLoadFailed, onRetry: _load)
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                contentColumn(
                  context,
                  maxWidth: 960,
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        key: const Key('park-header-meta'),
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        children: [
                          Text(
                            '${regionName(park.regionCode)} · '
                            '${agencyLabel(l10n, park.agency)}',
                            style: muted,
                          ),
                          if (website != null &&
                              website.startsWith('https://'))
                            TextButton.icon(
                              key: const Key('park-website'),
                              onPressed: () =>
                                  _openParkWebsite(context, website),
                              icon: const Icon(Icons.open_in_new, size: 18),
                              label: Text(l10n.parksWebsite),
                            ),
                        ],
                      ),
                      if (park.description != null &&
                          park.description!.trim().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(park.description!),
                      ],
                      const SizedBox(height: 16),
                      if (_courses.isEmpty)
                        Text(l10n.parksNoCourses)
                      else ...[
                        ParkOverviewMap(
                          key: const Key('park-overview-map'),
                          lines: [
                            for (final c in _courses)
                              ApiClient.globalSegmentGeometry(c.segment),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 20, bottom: 8),
                          child: Semantics(
                            header: true,
                            child: Text(
                              l10n.parksCourseCount(_courses.length),
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                        ),
                        if (_recordsFailed)
                          Padding(
                            key: const Key('park-records-failed'),
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 8,
                              children: [
                                Text(l10n.racesAnyTimeRecordsFailed),
                                OutlinedButton.icon(
                                  onPressed: _loadRecords,
                                  icon: const Icon(Icons.refresh),
                                  label: Text(l10n.parksRetry),
                                ),
                              ],
                            ),
                          ),
                        for (var i = 0; i < _courses.length; i++)
                          _ParkCourseCard(
                            key: ValueKey(
                              'park-course-${_courses[i].course.id}',
                            ),
                            course: _courses[i],
                            colour: parkCourseLineColour(
                              i,
                              darkBasemap: darkBasemap,
                            ),
                            recordLine: signedIn && !_recordsFailed
                                ? _recordLine(
                                    l10n,
                                    _records[_courses[i].course.id],
                                  )
                                : null,
                            onTap: () => _open(_courses[i]),
                          ),
                      ],
                      const SizedBox(height: 24),
                      _NotAffiliatedNote(
                        key: const Key('park-not-affiliated'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _ParkCourseCard extends StatelessWidget {
  final ParkCourseListing course;
  final Color colour;
  final String? recordLine;
  final VoidCallback onTap;

  const _ParkCourseCard({
    super.key,
    required this.course,
    required this.colour,
    required this.recordLine,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final segment = course.segment;
    final geometry = ApiClient.globalSegmentGeometry(segment);
    final pills = courseFactPills(context, course);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: MergeSemantics(
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (geometry.length >= 2) ...[
                  SizedBox(
                    width: 88,
                    child: AspectRatio(
                      aspectRatio: 4 / 3,
                      child: TrackPreview(points: geometry),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          ExcludeSemantics(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: colour,
                                shape: BoxShape.circle,
                              ),
                              child: const SizedBox.square(dimension: 10),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              segment.name,
                              style: theme.textTheme.titleSmall,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            courseDistanceForPref(segment.distanceM),
                            key: ValueKey(
                              'park-course-distance-${course.course.id}',
                            ),
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          ...pills,
                        ],
                      ),
                      if (recordLine != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          recordLine!,
                          key: ValueKey(
                            'park-course-record-${course.course.id}',
                          ),
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NotAffiliatedNote extends StatelessWidget {
  const _NotAffiliatedNote({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      AppLocalizations.of(context).parksNotAffiliated,
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

enum ParkBoardKind { fastest, completions }

/// One park course: stats, map with its legend, the elevation profile, one
/// credit line, the notices, the actions and the fastest / most-completions
/// boards for this season or all time. Mobile mirror of web
/// `/parks/[region]/[park]/[course]`.
class ParkCourseScreen extends StatefulWidget {
  final ApiClient? api;
  final ParkListing listing;
  final ParkCourseListing course;

  const ParkCourseScreen({
    super.key,
    required this.api,
    required this.listing,
    required this.course,
  });

  @override
  State<ParkCourseScreen> createState() => _ParkCourseScreenState();
}

class _ParkCourseScreenState extends State<ParkCourseScreen> {
  ParkBoardKind _kind = ParkBoardKind.fastest;
  bool _allTime = false;
  String? _gender;
  String? _ageBand;
  List<GlobalSegmentLeaderboardEntry>? _fastest;
  List<GlobalSegmentCompletionsEntry>? _completions;
  bool _boardFailed = false;

  /// Whether nobody has a time on this course at all, in any season. Null
  /// until known. While true the board is an invitation and its controls stay
  /// hidden, since there is nothing for them to sort or filter.
  bool? _neverRun;

  int? get _season => _allTime ? null : widget.listing.season;

  bool get _defaultSelection =>
      _kind == ParkBoardKind.fastest &&
      !_allTime &&
      _gender == null &&
      _ageBand == null;

  @override
  void initState() {
    super.initState();
    _refreshBoard();
  }

  Future<void> _refreshBoard() async {
    final api = widget.api;
    if (api == null || api.userId == null) return;
    setState(() {
      _fastest = null;
      _completions = null;
      _boardFailed = false;
    });
    final segmentId = widget.course.segment.id;
    try {
      if (_kind == ParkBoardKind.fastest) {
        final board = await api
            .fetchGlobalSegmentLeaderboard(
              segmentId,
              gender: _gender,
              ageBand: _ageBand,
              season: _season,
            )
            .timeout(kBackendLoadTimeout);
        if (!mounted) return;
        setState(() {
          _fastest = board;
          if (board.isNotEmpty) _neverRun = false;
        });
        if (board.isEmpty && _defaultSelection && _neverRun == null) {
          await _checkNeverRun();
        }
      } else {
        final board = await api
            .fetchGlobalSegmentCompletions(segmentId, season: _season)
            .timeout(kBackendLoadTimeout);
        if (!mounted) return;
        setState(() => _completions = board);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _boardFailed = true);
    }
  }

  /// An empty board this season can still have times from earlier ones; the
  /// all-time completions board says whether anyone has ever run the course.
  /// A failed check keeps the controls, which still work.
  Future<void> _checkNeverRun() async {
    final api = widget.api;
    if (api == null) return;
    try {
      final all = await api
          .fetchGlobalSegmentCompletions(
            widget.course.segment.id,
            season: null,
            limit: 1,
          )
          .timeout(kBackendLoadTimeout);
      if (mounted) setState(() => _neverRun = all.isEmpty);
    } catch (e) {
      debugPrint('park course: all-time check failed: $e');
      if (mounted) setState(() => _neverRun = false);
    }
  }

  /// Shares the course line as GPX with its checkpoints and the geometry
  /// credit, which has to travel with the file (OpenStreetMap's licence asks
  /// for it on the exported work).
  Future<void> _shareGpx(BuildContext anchor) async {
    final l10n = AppLocalizations.of(context);
    final course = widget.course.course;
    final segment = widget.course.segment;
    final park = widget.listing.park;
    final guide = parseRouteGuide(course.routeGuide);
    try {
      final gpx = parkCourseGpx(
        name: segment.name,
        waypoints: [
          for (final w in ApiClient.globalSegmentGeometry(segment))
            (lat: w.lat, lng: w.lng, ele: w.elevationMetres),
        ],
        checkpoints: parseCourseCheckpoints(course.checkpoints),
        attribution: courseAttribution(
          course.geometrySource,
          parkName: park.name,
          parkWebsiteUrl: park.websiteUrl,
        ),
        guide: guide == null
            ? null
            : (guide: guide, checkedAt: _isoDay(course.routeGuideCheckedAt)),
      );
      final safe = segment.name
          .replaceAll(RegExp(r'[^a-zA-Z0-9-_ ]'), '')
          .replaceAll(RegExp(r'\s+'), '_');
      final tmp = await getTemporaryDirectory();
      final file = File('${tmp.path}/${safe.isEmpty ? 'course' : safe}.gpx');
      await file.writeAsString(gpx);
      if (!anchor.mounted) return;
      await shareFilesFrom(
        anchor,
        files: [XFile(file.path, mimeType: 'application/gpx+xml')],
        text: segment.name,
      );
    } catch (e) {
      debugPrint('park course share GPX failed: $e');
      if (mounted) {
        showTopBanner(
          context,
          l10n.routeDetailShareFailed('GPX', friendlyError(l10n, e)),
        );
      }
    }
  }

  void _navigate(ApiClient api, String routeId) => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PublicRouteScreen(api: api, routeId: routeId),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final course = widget.course.course;
    final segment = widget.course.segment;
    final park = widget.listing.park;
    final geometry = ApiClient.globalSegmentGeometry(segment);
    final checkpoints =
        parseCourseCheckpoints(course.checkpoints) ?? const <CourseCheckpoint>[];
    final elevation = segment.elevationM;
    final difficulty = courseDifficultyLabel(l10n, course.difficulty);
    final pills = courseFactPills(context, widget.course, includeClimb: false);
    final description = segment.description?.trim();
    final guide = parseRouteGuide(course.routeGuide);
    final api = widget.api;
    final routeId = course.routeId;
    final open = course.status != 'closed';
    final canNavigate = api != null && routeId != null && open;
    final canShare = geometry.length >= 2 && open;
    return Scaffold(
      appBar: AppBar(
        title: Text(segment.name),
        actions: [
          IconButton(
            key: const Key('park-course-help'),
            icon: const Icon(Icons.help_outline),
            tooltip: l10n.infoTipReadGuide,
            onPressed: () => openGuide(context, 'park-courses'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          contentColumn(
            context,
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${park.name} · ${regionName(park.regionCode)}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (pills.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, runSpacing: 4, children: pills),
                ],
                if (course.status == 'closed') ...[
                  const SizedBox(height: 12),
                  Card(
                    key: const Key('park-course-closed'),
                    color: theme.colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        l10n.parksClosedBanner,
                        style: TextStyle(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                StatGrid(
                  cells: [
                    StatTile.medium(
                      label: l10n.parksStatDistance,
                      value: courseDistanceForPref(segment.distanceM),
                    ),
                    if (elevation != null && elevation > 0)
                      StatTile.medium(
                        label: l10n.parksStatElevation,
                        value: formatElevationForPref(elevation),
                      ),
                    StatTile.medium(
                      label: l10n.parksStatSurface,
                      value: routeSurfaceLabel(l10n, segment.surface),
                    ),
                    if (difficulty != null)
                      StatTile.medium(
                        label: l10n.parksStatDifficulty,
                        value: difficulty,
                      ),
                  ],
                ),
                if (course.status != 'open' &&
                    course.statusNote != null &&
                    course.statusNote!.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(course.statusNote!),
                ],
                if (description != null && description.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(description, key: const Key('park-course-description')),
                ],
                if (geometry.length >= 2) ...[
                  const SizedBox(height: 16),
                  ParkCourseMap(
                    key: const Key('park-course-map'),
                    line: geometry,
                    checkpoints: checkpoints,
                  ),
                  const SizedBox(height: 8),
                  ParkCourseMapLegend(
                    line: geometry,
                    checkpointCount: checkpoints.length,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    courseCredit(l10n, course),
                    key: const Key('park-course-attribution'),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (elevationSeries(geometry) != null) ...[
                  const SizedBox(height: 20),
                  Semantics(
                    header: true,
                    child: Text(
                      l10n.parksElevationProfile,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ElevationChart(
                    key: const Key('park-course-elevation'),
                    track: geometry,
                    theme: theme,
                    unit: activeDistanceUnit,
                  ),
                ],
                if (guide != null) ...[
                  const SizedBox(height: 20),
                  _CourseRouteGuide(
                    guide: guide,
                    checkedAt: course.routeGuideCheckedAt,
                  ),
                ],
                const SizedBox(height: 20),
                _CourseNotices(long: isLongCourse(segment.distanceM)),
                if (canNavigate || canShare) ...[
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      if (canNavigate)
                        FilledButton.icon(
                          key: const Key('park-course-navigate'),
                          onPressed: () => _navigate(api, routeId),
                          icon: const Icon(Icons.navigation_outlined),
                          label: Text(l10n.parksNavigate),
                        ),
                      if (canShare)
                        Builder(
                          builder: (anchor) => canNavigate
                              ? OutlinedButton.icon(
                                  key: const Key('park-course-share-gpx'),
                                  onPressed: () => _shareGpx(anchor),
                                  icon: const Icon(Icons.ios_share),
                                  label: Text(l10n.parksShareGpx),
                                )
                              : FilledButton.icon(
                                  key: const Key('park-course-share-gpx'),
                                  onPressed: () => _shareGpx(anchor),
                                  icon: const Icon(Icons.ios_share),
                                  label: Text(l10n.parksShareGpx),
                                ),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 24),
                _buildBoards(context, l10n),
                if (api != null) ...[
                  const SizedBox(height: 24),
                  // At the foot of the page, away from Navigate: it is for the
                  // rare runner or land manager with a problem (decisions § 2449).
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      key: const Key('park-course-report'),
                      onPressed: () => showParkCourseReportSheet(
                        context,
                        api: api,
                        courseId: course.id,
                        courseName: segment.name,
                      ),
                      icon: const Icon(Icons.flag_outlined),
                      label: Text(l10n.parkCourseReportAction),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBoards(BuildContext context, AppLocalizations l10n) {
    final api = widget.api;
    if (api == null || api.userId == null) {
      return SizedBox(
        height: 220,
        child: SignInRequiredState(
          api: api,
          message: l10n.parksSignInForBoards,
          onSignedIn: _refreshBoard,
        ),
      );
    }
    final theme = Theme.of(context);
    if (_neverRun == true && !_boardFailed) {
      return EmptyState(
        key: const Key('park-board-invitation'),
        icon: Icons.emoji_events_outlined,
        title: l10n.parksBoardEmptyTitle,
        body: l10n.parksBoardEmptyBody,
      );
    }
    final settledEmptyDefault = _defaultSelection &&
        !_boardFailed &&
        _fastest != null &&
        _fastest!.isEmpty &&
        _neverRun == null;
    if (settledEmptyDefault) {
      return Text(
        l10n.segmentsPanelLeaderboardLoading,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }
    return Column(
      key: const Key('park-board-controls'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ChoiceChipRow<ParkBoardKind>(
          key: const Key('park-board-kind'),
          options: [
            ChoiceChipOption(
              value: ParkBoardKind.fastest,
              label: l10n.parksBoardFastest,
            ),
            ChoiceChipOption(
              value: ParkBoardKind.completions,
              label: l10n.parksBoardCompletions,
            ),
          ],
          selected: _kind,
          onChanged: (k) {
            setState(() => _kind = k);
            _refreshBoard();
          },
        ),
        const SizedBox(height: 8),
        ChoiceChipRow<bool>(
          key: const Key('park-board-season'),
          options: [
            ChoiceChipOption(
              value: false,
              label: l10n.parksSeasonThisYear(widget.listing.season),
            ),
            ChoiceChipOption(value: true, label: l10n.parksSeasonAllTime),
          ],
          selected: _allTime,
          onChanged: (allTime) {
            setState(() => _allTime = allTime);
            _refreshBoard();
          },
        ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: () => showHeadToHeadSheet(
              context,
              api: api,
              kind: 'global_segment',
              targetId: widget.course.segment.id,
            ),
            icon: const Icon(Icons.people_outline, size: 18),
            label: Text(l10n.headToHeadCompare),
          ),
        ),
        if (_kind == ParkBoardKind.fastest)
          Wrap(
            spacing: 8,
            children: [
              DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: _gender,
                  isDense: true,
                  hint: Text(l10n.segmentsPanelAllGenders),
                  items: [
                    DropdownMenuItem(
                      value: null,
                      child: Text(l10n.segmentsPanelAllGenders),
                    ),
                    DropdownMenuItem(
                      value: 'male',
                      child: Text(l10n.segmentsPanelGenderMen),
                    ),
                    DropdownMenuItem(
                      value: 'female',
                      child: Text(l10n.segmentsPanelGenderWomen),
                    ),
                  ],
                  onChanged: (v) {
                    setState(() => _gender = v);
                    _refreshBoard();
                  },
                ),
              ),
              DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: _ageBand,
                  isDense: true,
                  hint: Text(l10n.segmentsPanelAllAges),
                  items: [
                    DropdownMenuItem(
                      value: null,
                      child: Text(l10n.segmentsPanelAllAges),
                    ),
                    for (final b in kSegmentAgeBands)
                      DropdownMenuItem(value: b, child: Text(b)),
                  ],
                  onChanged: (v) {
                    setState(() => _ageBand = v);
                    _refreshBoard();
                  },
                ),
              ),
            ],
          ),
        const SizedBox(height: 8),
        if (_kind == ParkBoardKind.fastest && !_boardFailed)
          OldMatchNote(api: api, segment: widget.course.segment),
        ..._boardBody(theme, l10n, api.userId),
      ],
    );
  }

  List<Widget> _boardBody(
    ThemeData theme,
    AppLocalizations l10n,
    String? viewerId,
  ) {
    if (_boardFailed) {
      return [
        ErrorState(message: l10n.parksBoardFailed, onRetry: _refreshBoard),
      ];
    }
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    if (_kind == ParkBoardKind.fastest) {
      final board = _fastest;
      if (board == null) {
        return [Text(l10n.segmentsPanelLeaderboardLoading, style: muted)];
      }
      if (board.isEmpty) return [Text(l10n.parksNoEfforts, style: muted)];
      return [
        for (final e in board)
          _ParkBoardRow(
            rank: e.rank,
            athlete: e.athlete,
            value: formatEffortTime(e.effort.timeSeconds),
            isViewer: e.effort.userId == viewerId,
          ),
      ];
    }
    final board = _completions;
    if (board == null) {
      return [Text(l10n.segmentsPanelLeaderboardLoading, style: muted)];
    }
    if (board.isEmpty) return [Text(l10n.parksNoEfforts, style: muted)];
    return [
      for (final e in board)
        _ParkBoardRow(
          rank: e.rank,
          athlete: e.athlete,
          value: l10n.parksCompletionDays(e.completions),
          isViewer: e.athlete.id == viewerId,
        ),
    ];
  }
}

/// `route_guide_checked_at` as the `YYYY-MM-DD` it is stored as.
String? _isoDay(DateTime? d) => d == null
    ? null
    : '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';

/// A course's route guide (#1344): its steps as a numbered list in the
/// reader's language and unit, under a note saying whether a person has
/// walked it at the park yet. Mirrors web's `ParkCourseRouteGuide`.
class _CourseRouteGuide extends StatelessWidget {
  final RouteGuide guide;
  final DateTime? checkedAt;
  const _CourseRouteGuide({required this.guide, required this.checkedAt});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tag = localeToTag(Localizations.localeOf(context));
    final fmt = GuideFormat(
      message: (key, params) => guideLineMessage(l10n, key, params),
      distance: formatDistanceForPref,
      short: formatElevationForPref,
    );
    final lines = [
      for (final l in routeGuideLines(guide)) formatGuideLine(l, fmt),
    ];
    final checked = checkedAt;
    final gettingThere = guide.gettingThere;
    return Column(
      key: const Key('park-course-guide'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(l10n.parkGuideTitle, style: theme.textTheme.titleMedium),
        ),
        const SizedBox(height: 8),
        if (checked != null)
          Text(
            l10n.parkGuideChecked(formatDateMed(
                DateTime(checked.year, checked.month, checked.day), tag)),
            key: const Key('park-course-guide-checked'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          )
        else
          Container(
            key: const Key('park-course-guide-pending'),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              border: BorderDirectional(
                start: BorderSide(
                  color: AppSemanticColors.of(context).warning,
                  width: 4,
                ),
              ),
            ),
            child: Text(l10n.parkGuidePending,
                style: theme.textTheme.bodyMedium),
          ),
        if (gettingThere != null) ...[
          const SizedBox(height: 12),
          Semantics(
            header: true,
            child: Text(l10n.parkGuideGettingThere,
                style: theme.textTheme.titleSmall),
          ),
          const SizedBox(height: 4),
          Text(gettingThere, key: const Key('park-course-guide-getting-there')),
        ],
        const SizedBox(height: 12),
        Column(
          key: const Key('park-course-guide-steps'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < lines.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${i + 1}.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        )),
                    const SizedBox(width: 8),
                    Expanded(child: Text(lines[i])),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// The course page's one notices callout: the safety rules first, the
/// long-course warning when it applies, then the not-affiliated note.
class _CourseNotices extends StatelessWidget {
  final bool long;
  const _CourseNotices({required this.long});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    Widget row(Key key, IconData icon, String text, TextStyle? style) => Row(
          key: key,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: scheme.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: style)),
          ],
        );
    return Card(
      key: const Key('park-course-notices'),
      color: scheme.surfaceContainerHighest,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            row(
              const Key('park-course-safety'),
              Icons.health_and_safety_outlined,
              l10n.parksSafetyNotice,
              theme.textTheme.bodyMedium,
            ),
            if (long) ...[
              const SizedBox(height: 10),
              row(
                const Key('park-course-long'),
                Icons.schedule,
                l10n.parksLongCourseNotice,
                theme.textTheme.bodyMedium,
              ),
            ],
            const SizedBox(height: 10),
            row(
              const Key('park-course-not-affiliated'),
              Icons.info_outline,
              l10n.parksNotAffiliated,
              theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ParkBoardRow extends StatelessWidget {
  final int rank;
  final PublicProfile athlete;
  final String value;
  final bool isViewer;

  const _ParkBoardRow({
    required this.rank,
    required this.athlete,
    required this.value,
    required this.isViewer,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: isViewer
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          TextLane(
            width: 32,
            child: Text(
              '#$rank',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          IdentityAvatar(
            seed: athlete.id,
            name: athlete.displayName,
            size: 24,
            imageUrl: athlete.avatarUrl,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              athlete.displayName ?? l10n.segmentsPanelRunnerFallback,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: isViewer ? FontWeight.w700 : null,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (isViewer) ...[
            Text(
              l10n.navYou,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

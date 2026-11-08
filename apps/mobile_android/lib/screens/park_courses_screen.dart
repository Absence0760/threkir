import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ui_kit/ui_kit.dart'
    show
        ChoiceChipOption,
        ChoiceChipRow,
        IdentityAvatar,
        ListSkeleton,
        StatGrid,
        StatTile;

import '../auth_error.dart';
import '../backend_timeout.dart';
import '../l10n/gen/app_localizations.dart';
import '../park_courses.dart';
import '../preferences.dart';
import '../route_surface_label.dart';
import '../share_sheet.dart';
import '../widgets/error_state.dart';
import 'help_screen.dart' show openGuide;
import '../widgets/head_to_head_card.dart' show showHeadToHeadSheet;
import '../widgets/sign_in_required_state.dart';
import '../widgets/top_banner.dart';
import '../widgets/track_preview.dart';

/// Park courses (issue #1313, decisions § 2383): parks by region. Mobile
/// mirror of web `/parks`. The catalogue is world-readable, so this works
/// signed out; only the boards on [ParkCourseScreen] need an account.
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

  @override
  void initState() {
    super.initState();
    _load();
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final groups = groupParksByRegion<ParkListing>(
      _parks,
      regionCodeOf: (p) => p.park.regionCode,
      nameOf: (p) => p.park.name,
    );
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
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                Text(
                  l10n.parksIntro,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                if (_parks.isEmpty)
                  Text(l10n.parksEmpty, key: const Key('parks-empty')),
                for (final group in groups) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 4),
                    child: Text(
                      regionName(group.regionCode),
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  for (final listing in group.parks)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.park_outlined),
                        title: Text(listing.park.name),
                        subtitle: Text(agencyLabel(l10n, listing.park.agency)),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                ParkScreen(api: widget.api, listing: listing),
                          ),
                        ),
                      ),
                    ),
                ],
              ],
            ),
    );
  }
}

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

/// One park and its courses. Mobile mirror of web `/parks/[region]/[park]`.
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

  @override
  void initState() {
    super.initState();
    _load();
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
        _courses = courses;
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final park = widget.listing.park;
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
                Text(
                  '${regionName(park.regionCode)} · ${agencyLabel(l10n, park.agency)}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (park.description != null &&
                    park.description!.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(park.description!),
                ],
                const SizedBox(height: 16),
                if (_courses.isEmpty) Text(l10n.parksNoCourses),
                for (final c in _courses)
                  Card(
                    child: ListTile(
                      title: Text(c.segment.name),
                      subtitle: Text(
                        '${formatDistanceForPref(c.segment.distanceM)} · '
                        '${courseShapeLabel(l10n, c.course.courseShape)}',
                      ),
                      trailing: c.course.status == 'open'
                          ? const Icon(Icons.chevron_right)
                          : Chip(
                              label: Text(
                                courseStatusLabel(l10n, c.course.status),
                              ),
                            ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ParkCourseScreen(
                            api: widget.api,
                            listing: widget.listing,
                            course: c,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

enum ParkBoardKind { fastest, completions }

/// One park course: map, stats, safety notice, attribution and the fastest /
/// most-completions boards for this season or all time. Mobile mirror of web
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

  int? get _season => _allTime ? null : widget.listing.season;

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
        setState(() => _fastest = board);
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

  /// Shares the course line as GPX with its checkpoints and the geometry
  /// credit, which has to travel with the file (OpenStreetMap's licence asks
  /// for it on the exported work).
  Future<void> _shareGpx(BuildContext anchor) async {
    final l10n = AppLocalizations.of(context);
    final course = widget.course.course;
    final segment = widget.course.segment;
    final park = widget.listing.park;
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final course = widget.course.course;
    final segment = widget.course.segment;
    final park = widget.listing.park;
    final geometry = ApiClient.globalSegmentGeometry(segment);
    final elevation = segment.elevationM;
    final difficulty = courseDifficultyLabel(l10n, course.difficulty);
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
          Text(
            '${park.name} · ${regionName(park.regionCode)}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (course.status == 'closed') ...[
            const SizedBox(height: 12),
            Card(
              key: const Key('park-course-closed'),
              color: theme.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  l10n.parksClosedBanner,
                  style: TextStyle(color: theme.colorScheme.onErrorContainer),
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          StatGrid(
            cells: [
              StatTile.medium(
                label: l10n.parksStatDistance,
                value: formatDistanceForPref(segment.distanceM),
              ),
              if (elevation != null && elevation > 0)
                StatTile.medium(
                  label: l10n.parksStatElevation,
                  value: formatElevationForPref(elevation),
                ),
              StatTile.medium(
                label: l10n.parksStatShape,
                value: courseShapeLabel(l10n, course.courseShape),
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
          if (course.status != 'open') ...[
            const SizedBox(height: 8),
            Text(
              [
                courseStatusLabel(l10n, course.status),
                if (course.statusNote != null &&
                    course.statusNote!.trim().isNotEmpty)
                  course.statusNote!,
              ].join(': '),
            ),
          ],
          if (geometry.length >= 2) ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                // TrackPreview fills whatever it is given, and a ListView
                // gives an unbounded height.
                aspectRatio: 2.4,
                child: TrackPreview(points: geometry),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              geometryAttribution(l10n, course.geometrySource),
              key: const Key('park-course-attribution'),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            key: const Key('park-course-safety'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.parksSafetyNotice,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
          if (geometry.length >= 2 && course.status != 'closed') ...[
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Builder(
                builder: (anchor) => OutlinedButton.icon(
                  key: const Key('park-course-share-gpx'),
                  onPressed: () => _shareGpx(anchor),
                  icon: const Icon(Icons.ios_share),
                  label: Text(l10n.parksShareGpx),
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          _buildBoards(context, l10n),
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
    return Column(
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
          SizedBox(
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

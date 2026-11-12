import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart'
    show
        ActiveFilter,
        AppInsets,
        AppSearchField,
        AppSemanticColors,
        AppSpace,
        AsyncView,
        EmptyState,
        FilterBar,
        HubTabBody,
        IdentityAvatar,
        ListSkeleton,
        LoadingState,
        SkeletonBlock,
        StatGrid,
        StatTile,
        showFilterSheet;

import '../backend_timeout.dart';
import '../catalogue_browse.dart';
import '../fab_clearance.dart';
import '../fitness_surface_requests.dart';
import '../l10n/gen/app_localizations.dart';
import '../preferences.dart';
import '../race_service.dart';
import '../route_surface_label.dart';
import '../widgets/error_state.dart';
import '../widgets/help_button.dart';
import 'park_courses_screen.dart';
import 'races_screen.dart';
import '../widgets/head_to_head_card.dart' show showHeadToHeadSheet;
import '../widgets/sign_in_required_state.dart';
import '../widgets/track_preview.dart';
import '../widgets/loading_skeletons.dart';
import '../widgets/old_match_note.dart';

/// Browse list for the curated famous-segment catalogue (decisions §233).
/// Mobile mirror of web `/segments`: search with accent folding, region and
/// surface filters, four sorts — all shaped by the `catalogue_browse.dart`
/// parity pair over the whole fetched catalogue, so a keystroke costs no
/// round-trip.
///
/// The catalogue is world-readable, so this screen works signed out — unlike
/// the leaderboard on [GlobalSegmentDetailScreen].
class GlobalSegmentsScreen extends StatefulWidget {
  final ApiClient? api;

  const GlobalSegmentsScreen({super.key, this.api});

  @override
  State<GlobalSegmentsScreen> createState() => _GlobalSegmentsScreenState();
}

class _GlobalSegmentsScreenState extends State<GlobalSegmentsScreen> {
  List<GlobalSegmentRow> _segments = const [];
  bool _loading = true;
  bool _error = false;

  String _query = '';
  String? _region;
  String? _surface;
  CatalogueSort _sort = CatalogueSort.name;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
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
      final segments =
          await api.fetchGlobalSegments().timeout(kBackendLoadTimeout);
      if (!mounted) return;
      setState(() {
        _segments = segments;
        _loading = false;
      });
    } catch (_) {
      // Surfaced rather than degraded to an empty list: "the catalogue is
      // empty" and "the fetch failed" are different claims, and only one of
      // them is worth offering a retry for.
      if (!mounted) return;
      setState(() {
        _error = true;
        _loading = false;
      });
    }
  }

  void _reset() {
    _search.clear();
    setState(() {
      _query = '';
      _region = null;
      _surface = null;
      _sort = CatalogueSort.name;
    });
  }

  void _open(String segmentId) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) =>
          GlobalSegmentDetailScreen(api: widget.api, segmentId: segmentId),
    ));
  }

  static String _sortLabel(AppLocalizations l10n, CatalogueSort sort) =>
      switch (sort) {
        CatalogueSort.name => l10n.segmentCatalogueSortName,
        CatalogueSort.shortest => l10n.segmentCatalogueSortShortest,
        CatalogueSort.longest => l10n.segmentCatalogueSortLongest,
        CatalogueSort.climb => l10n.segmentCatalogueSortClimb,
      };

  /// Park courses live in Races & courses (decisions § 2436), so this opens
  /// that tab on its Courses view rather than pushing a copy of the park
  /// index over the hub (decisions § 2437, § 2480).
  void _openParks() => openFitnessSurface(
        context,
        FitnessTab.races,
        racesShow: RacesShow.courses,
        fallback: () => RacesScreen(
          service: RaceService(),
          api: widget.api,
          initialShow: RacesShow.courses,
        ),
      );

  List<CatalogueSegment> get _catalogue => [
        for (final s in _segments)
          CatalogueSegment(
            id: s.id,
            name: s.name,
            surface: s.surface,
            region: s.region,
            distanceM: s.distanceM,
            elevationM: s.elevationM,
          ),
      ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final catalogue = _catalogue;
    return HubTabBody(
      // The tab's own name: "Famous segments" under a tab reading "Segments"
      // was two names for one place (issue #1374 report 2).
      title: l10n.runSurfaceTabSegments,
      actions: [
        IconButton(
          key: const Key('segments-parks-link'),
          tooltip: l10n.parksBrowseLink,
          icon: const Icon(Icons.park_outlined),
          onPressed: _openParks,
        ),
      ],
      filters: catalogue.isEmpty ? null : _filterBar(l10n, catalogue),
      onRefresh: _load,
      body: AsyncView<List<CatalogueSegment>>(
        loading: _loading,
        error: _error ? true : null,
        data: catalogue,
        isEmpty: (c) => c.isEmpty,
        loadingState: LoadingState.list(label: l10n.segmentsPanelLoading),
        errorBuilder: (_, _) => AppErrorState(
          message: l10n.segmentCatalogueLoadFailed,
          onRetry: _load,
        ),
        empty: EmptyState(
          icon: Icons.terrain,
          title: l10n.segmentCatalogueEmpty,
          ctaLabel: l10n.parksBrowseLink,
          ctaIcon: Icons.park_outlined,
          onCta: _openParks,
        ),
        builder: (context, c) => _buildCatalogue(context, l10n, c),
      ),
    );
  }

  /// Search, then Filters for region, surface and sort, whose non-default
  /// values show as removable chips. A one-value choice filters nothing, so a
  /// group with one value is left out of the sheet.
  FilterBar _filterBar(AppLocalizations l10n, List<CatalogueSegment> catalogue) {
    ActiveFilter active(String label, VoidCallback onRemove) => ActiveFilter(
          label: label,
          onRemove: onRemove,
          removeTooltip: l10n.filterBarRemoveFilter(label),
        );
    final filters = [
      if (_region case final r?) active(r, () => setState(() => _region = null)),
      if (_surface case final s?)
        active(routeSurfaceLabel(l10n, s), () => setState(() => _surface = null)),
      if (_sort != CatalogueSort.name)
        active(_sortLabel(l10n, _sort),
            () => setState(() => _sort = CatalogueSort.name)),
    ];
    return FilterBar(
      key: const Key('segments-filter-bar'),
      search: AppSearchField(
        controller: _search,
        hint: l10n.segmentCatalogueSearchHint,
        clearTooltip: l10n.commonClearSearch,
        onChanged: (v) => setState(() => _query = v),
      ),
      activeFilters: filters,
      filtersLabel: l10n.filterBarFilters,
      filtersSemanticLabel:
          filters.isEmpty ? null : l10n.filterBarFiltersCount(filters.length),
      activeFilterCount: filters.length,
      onOpenFilters: () => _openFilters(l10n, catalogue),
    );
  }

  Future<void> _openFilters(
      AppLocalizations l10n, List<CatalogueSegment> catalogue) {
    final regions = catalogueRegions(catalogue);
    final surfaces = catalogueSurfaces(catalogue);
    return showFilterSheet(
      context: context,
      title: l10n.filterBarFilters,
      doneLabel: l10n.filterBarDone,
      resetLabel: l10n.segmentsPanelResetFilters,
      onReset: _reset,
      builder: (sheetContext, setSheet) {
        final theme = Theme.of(sheetContext);
        Widget group<T>(String heading, List<(T, String)> options, T selected,
                ValueChanged<T> onPick) =>
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(heading, style: theme.textTheme.titleSmall),
                  const SizedBox(height: AppSpace.sm),
                  Semantics(
                    container: true,
                    label: heading,
                    child: Wrap(
                      spacing: AppSpace.sm,
                      children: [
                        for (final (value, label) in options)
                          ChoiceChip(
                            label: Text(label),
                            selected: value == selected,
                            onSelected: (_) {
                              setState(() => onPick(value));
                              setSheet(() {});
                            },
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (regions.length > 1)
              group<String?>(
                l10n.filterBarRegion,
                [
                  (null, l10n.segmentCatalogueAllRegions),
                  for (final r in regions) (r, r),
                ],
                _region,
                (v) => _region = v,
              ),
            if (surfaces.length > 1)
              group<String?>(
                l10n.filterBarSurface,
                [
                  (null, l10n.segmentCatalogueAllSurfaces),
                  for (final s in surfaces) (s, routeSurfaceLabel(l10n, s)),
                ],
                _surface,
                (v) => _surface = v,
              ),
            group<CatalogueSort>(
              l10n.filterBarSort,
              [for (final s in CatalogueSort.values) (s, _sortLabel(l10n, s))],
              _sort,
              (v) => _sort = v,
            ),
          ],
        );
      },
    );
  }

  Widget _buildCatalogue(BuildContext context, AppLocalizations l10n,
      List<CatalogueSegment> catalogue) {
    final theme = Theme.of(context);
    final shown = sortCatalogue(
      filterCatalogue(
        catalogue,
        query: _query,
        region: _region,
        surface: _surface,
      ),
      _sort,
    );
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(AppInsets.gutter, AppSpace.sm,
          AppInsets.gutter, fabScrollClearance(context)),
      children: [
        Text(
          l10n.segmentCatalogueIntro,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpace.smPlus),
        // One live region whose CONTENTS swap rather than one per branch: a
        // status node that is removed when the result set empties announces
        // nothing on the transition that most needs announcing.
        Semantics(
          liveRegion: true,
          child: shown.isEmpty
              ? EmptyState(
                  icon: Icons.filter_alt_off,
                  title: l10n.segmentCatalogueNoMatches,
                  ctaLabel: l10n.segmentsPanelResetFilters,
                  ctaIcon: Icons.close,
                  onCta: _reset,
                )
              : Text(
                  l10n.segmentCatalogueCount(shown.length),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
        ),
        const SizedBox(height: AppSpace.sm),
        for (final segment in shown) ...[
          _CatalogueCard(segment: segment, onTap: () => _open(segment.id)),
          const SizedBox(height: AppSpace.sm),
        ],
      ],
    );
  }
}

class _CatalogueCard extends StatelessWidget {
  final CatalogueSegment segment;
  final VoidCallback onTap;

  const _CatalogueCard({required this.segment, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final elevation = segment.elevationM;
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        onTap: onTap,
        title: Text(segment.name, style: theme.textTheme.titleMedium),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (segment.region != null && segment.region!.trim().isNotEmpty)
                Text(segment.region!),
              const SizedBox(height: 4),
              Text(
                [
                  formatDistanceForPref((segment.distanceM ?? 0).toDouble()),
                  if (elevation != null && elevation > 0)
                    formatElevationForPref(elevation.toDouble()),
                  routeSurfaceLabel(l10n, segment.surface),
                ].join(' · '),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

/// One catalogue segment: its curated geometry, key stats, description, and the
/// block-guarded leaderboard with the same gender / age-band tiers the
/// route-segment panel offers. Mobile mirror of web `/segments/[id]`.
class GlobalSegmentDetailScreen extends StatefulWidget {
  final ApiClient? api;
  final String segmentId;

  const GlobalSegmentDetailScreen({
    super.key,
    required this.api,
    required this.segmentId,
  });

  @override
  State<GlobalSegmentDetailScreen> createState() =>
      _GlobalSegmentDetailScreenState();
}

class _GlobalSegmentDetailScreenState extends State<GlobalSegmentDetailScreen> {
  GlobalSegmentRow? _segment;
  bool _loading = true;
  bool _loadFailed = false;

  // A null board is the loading state, so a rejected fetch that left it null
  // would read as "still loading" forever. The failure carries its own flag.
  List<GlobalSegmentLeaderboardEntry>? _board;
  bool _boardFailed = false;
  String? _gender;
  String? _ageBand;

  /// The park course built on this segment, if any: the screen links to its
  /// course page, and shows its source credit, which lives in the course's
  /// own column rather than the description (decisions § 2438). Null until
  /// read, and when the read fails: both are auxiliary on this screen.
  ({ParkListing park, ParkCourseListing course})? _parkCourse;

  String? get _courseCredit {
    final credit = _parkCourse?.course.course.attribution?.trim();
    return credit == null || credit.isEmpty ? null : credit;
  }

  @override
  void initState() {
    super.initState();
    _loadSegment();
    _loadParkCourse();
  }

  Future<void> _loadParkCourse() async {
    final api = widget.api;
    if (api == null) return;
    try {
      final found = await api
          .fetchParkCourseForSegment(widget.segmentId)
          .timeout(kBackendLoadTimeout);
      if (!mounted || found == null) return;
      setState(() => _parkCourse = found);
    } catch (e) {
      debugPrint('fetchParkCourseForSegment failed: $e');
    }
  }

  void _openParkCourse(({ParkListing park, ParkCourseListing course}) pc) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ParkCourseScreen(
            api: widget.api,
            listing: pc.park,
            course: pc.course,
          ),
        ),
      );

  Future<void> _loadSegment() async {
    final api = widget.api;
    if (api == null) {
      setState(() {
        _loadFailed = true;
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final segment = await api
          .fetchGlobalSegment(widget.segmentId)
          .timeout(kBackendLoadTimeout);
      if (!mounted) return;
      setState(() {
        _segment = segment;
        _loading = false;
      });
      if (segment != null) await _refreshBoard();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadFailed = true;
        _loading = false;
      });
    }
  }

  Future<void> _refreshBoard() async {
    final api = widget.api;
    // `global_segment_leaderboard` raises 42501 for an anonymous caller, so a
    // signed-out viewer gets the sign-in state rather than an error with a
    // retry that could never succeed.
    if (api == null || api.userId == null) return;
    setState(() {
      _board = null;
      _boardFailed = false;
    });
    try {
      final board = await api
          .fetchGlobalSegmentLeaderboard(
            widget.segmentId,
            gender: _gender,
            ageBand: _ageBand,
          )
          .timeout(kBackendLoadTimeout);
      if (!mounted) return;
      setState(() => _board = board);
    } catch (_) {
      if (!mounted) return;
      setState(() => _boardFailed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final segment = _segment;
    return Scaffold(
      appBar: AppBar(
        title: Text(segment?.name ?? l10n.segmentCatalogueTitle),
        actions: const [HelpButton(routes: ['/segments/[id]'])],
      ),
      body: _loading
          ? ListView(
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                const SkeletonStatStrip(cells: 3),
                const SizedBox(height: 16),
                const SkeletonBlock(height: 160),
                const SizedBox(height: 16),
                ListSkeleton.section(
                  label: l10n.segmentsPanelLoading,
                  rows: 5,
                ),
              ],
            )
          : _loadFailed
              ? AppErrorState(
                  message: l10n.segmentCatalogueDetailFailedTitle,
                  onRetry: _loadSegment,
                )
              : segment == null
                  ? EmptyState(
                      icon: Icons.search_off,
                      title: l10n.segmentCatalogueNotFoundTitle,
                      body: l10n.segmentCatalogueNotFoundBody,
                    )
                  : _buildDetail(context, l10n, segment),
    );
  }

  Widget _buildDetail(
    BuildContext context,
    AppLocalizations l10n,
    GlobalSegmentRow segment,
  ) {
    final theme = Theme.of(context);
    // The catalogue geometry is public curated data, NOT any athlete's GPS
    // track, so it renders directly — there is no owner whose privacy
    // zones could apply, and nothing for `fetchClippedTrackForRun` to
    // protect.
    final geometry = ApiClient.globalSegmentGeometry(segment);
    final elevation = segment.elevationM;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        if (segment.region != null && segment.region!.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Icon(Icons.place,
                    size: 16, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    segment.region!,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
        StatGrid(
          cells: [
            StatTile.medium(
              label: l10n.segmentCatalogueStatDistance,
              value: formatDistanceForPref(segment.distanceM),
            ),
            if (elevation != null && elevation > 0)
              StatTile.medium(
                label: l10n.segmentCatalogueStatElevation,
                value: formatElevationForPref(elevation),
              ),
            StatTile.medium(
              label: l10n.segmentCatalogueStatSurface,
              value: routeSurfaceLabel(l10n, segment.surface),
            ),
          ],
        ),
        if (segment.description != null &&
            segment.description!.trim().isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(segment.description!, style: theme.textTheme.bodyMedium),
        ],
        if (_parkCourse case final pc?) ...[
          const SizedBox(height: 8),
          Card(
            key: const Key('segment-park-course-link'),
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.park_outlined),
              title: Text(l10n.segmentCatalogueParkCourseLink(pc.park.park.name)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openParkCourse(pc),
            ),
          ),
        ],
        if (_courseCredit case final credit?) ...[
          const SizedBox(height: 8),
          Text(
            credit,
            key: const Key('segment-course-credit'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
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
        ],
        const SizedBox(height: 24),
        Text(
          l10n.segmentCatalogueLeaderboard,
          style: theme.textTheme.titleSmall,
        ),
        if (widget.api case final api? when api.userId != null)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: const Key('global-segment-head-to-head-open'),
              onPressed: () => showHeadToHeadSheet(
                context,
                api: api,
                kind: 'global_segment',
                targetId: segment.id,
              ),
              icon: const Icon(Icons.people_outline, size: 18),
              label: Text(l10n.headToHeadCompare),
            ),
          ),
        const SizedBox(height: 8),
        _buildBoard(context, l10n),
      ],
    );
  }

  Widget _buildBoard(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final api = widget.api;
    if (api == null || api.userId == null) {
      return SizedBox(
        height: 220,
        child: SignInRequiredState(api: api, onSignedIn: _refreshBoard),
      );
    }
    final filtered = _gender != null || _ageBand != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
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
            if (filtered)
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _gender = null;
                    _ageBand = null;
                  });
                  _refreshBoard();
                },
                icon: const Icon(Icons.close, size: 16),
                label: Text(l10n.segmentsPanelResetFilters),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (_segment case final segment?)
          OldMatchNote(api: api, segment: segment),
        if (_boardFailed)
          AppErrorState(
            message: l10n.segmentsPanelLeaderboardError,
            onRetry: _refreshBoard,
          )
        else if (_board == null)
          Text(
            l10n.segmentsPanelLeaderboardLoading,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          )
        else if (_board!.isEmpty)
          Text(
            filtered
                ? l10n.segmentsPanelLeaderboardEmptyFiltered
                : l10n.segmentsPanelLeaderboardEmpty,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          )
        else
          ..._boardRows(context, l10n, api.userId),
      ],
    );
  }

  List<Widget> _boardRows(
    BuildContext context,
    AppLocalizations l10n,
    String? viewerId,
  ) {
    final board = _board!;
    final label = crownLabel(_gender, _ageBand);
    final leader = board.first;
    final viewerHoldsCrown = leader.rank == 1 &&
        viewerId != null &&
        leader.effort.userId == viewerId;
    return [
      if (viewerHoldsCrown)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              Icon(Icons.emoji_events,
                  size: 18, color: AppSemanticColors.of(context).crown),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.segmentsPanelCrownBanner(label),
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      for (final entry in board)
        _BoardRow(entry: entry, viewerId: viewerId, crownLabel: label),
    ];
  }
}

class _BoardRow extends StatelessWidget {
  final GlobalSegmentLeaderboardEntry entry;
  final String? viewerId;
  final String crownLabel;

  const _BoardRow({
    required this.entry,
    required this.viewerId,
    required this.crownLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final isViewer = viewerId != null && entry.effort.userId == viewerId;
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
            child: entry.rank == 1
                ? Tooltip(
                    message: crownLabel,
                    child: Icon(
                      Icons.emoji_events,
                      size: 20,
                      color: AppSemanticColors.of(context).crown,
                    ),
                  )
                : Text(
                    '#${entry.rank}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
          ),
          IdentityAvatar(
            seed: entry.athlete.id,
            name: entry.athlete.displayName,
            size: 24,
            imageUrl: entry.athlete.avatarUrl,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              entry.athlete.displayName ?? l10n.segmentsPanelRunnerFallback,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: isViewer ? FontWeight.w700 : null),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // The viewer tint is barely distinguishable from a neighbouring row,
          // so the label and the weight are the cue — as on the route-segment
          // leaderboard.
          if (isViewer) ...[
            const SizedBox(width: 6),
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
            formatEffortTime(entry.effort.timeSeconds),
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

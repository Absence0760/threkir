import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' as cm;
import 'package:core_models/core_models.dart' show DistanceUnit;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' show MapController;
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:ui_kit/ui_kit.dart'
    show
        ActiveFilter,
        AppInsets,
        AppSearchField,
        AppSpace,
        EmptyState,
        FilterBar,
        HubTabBody,
        ListCard,
        MapFirstPage,
        MapFirstSheet,
        StatusPill,
        StatusPillSize,
        showFilterSheet;

import '../fab_clearance.dart';
import '../l10n/gen/app_localizations.dart';
import '../local_route_store.dart';
import '../official_distance.dart';
import '../preferences.dart';
import '../quiet_location.dart';
import '../routes_views.dart';
import '../route_surface_label.dart';
import '../auth_error.dart';
import '../backend_timeout.dart';
import '../widgets/error_state.dart';
import '../park_course_routes.dart';
import '../widgets/explore_routes_map.dart';
import '../widgets/route_track_preview.dart';
import 'public_route_screen.dart';
import 'route_detail_screen.dart';
import '../widgets/top_banner.dart';

enum _ExploreMode { search, nearMe }

enum _DistanceFilter { any, short, medium, long, ultra }

enum _SurfaceFilter { any, road, trail, mixed }

/// Public routes: Routes → Explore on its Routes chip (issue #1374, owner
/// decision 1), headed by the discovery maps the Routes tab hands it.
///
/// Map-first (issue #1374): the public routes in view are pins on a
/// full-bleed map, and the search results are the list in its sheet, headed
/// by the discovery maps. A search, with Near me as the quick chip (which also
/// moves the map to the runner), and distance, surface, sort, Featured and
/// tags in the Filters sheet. Mounted on its own (a test) it is a page titled
/// Explore Routes.
class ExploreRoutesScreen extends StatefulWidget {
  final ApiClient? apiClient;
  final LocalRouteStore routeStore;
  final Preferences preferences;

  /// The Routes tab's view row and Explore chips. Null on its own.
  final RoutesExploreChrome? chrome;

  /// The discovery maps, heading the list in the sheet.
  final Widget? maps;

  /// Test seam for the "Near me" fix. Production callers leave it null and
  /// get [locateForBrowse].
  final Future<Position> Function()? locateFn;

  const ExploreRoutesScreen({
    super.key,
    this.apiClient,
    required this.routeStore,
    required this.preferences,
    this.chrome,
    this.maps,
    this.locateFn,
  });

  @override
  State<ExploreRoutesScreen> createState() => _ExploreRoutesScreenState();
}

class _ExploreRoutesScreenState extends State<ExploreRoutesScreen> {
  final _searchController = TextEditingController();
  final _map = MapController();

  List<cm.Route> _results = [];
  late final ParkCourseRouteLookup _parkCourses = ParkCourseRouteLookup((
    ids,
  ) async {
    final api = widget.apiClient;
    if (api == null) return <String>{};
    return api.fetchParkCourseRouteIds(ids);
  });
  bool _loading = false;
  bool _hasMore = true;
  // The search the shown results came from, and the cursor for its next
  // page. Load more continues THAT search: the cursor is a position in one
  // sort's order and means nothing under another, and text typed since but not
  // submitted must not splice a different result set onto this one.
  Future<cm.KeysetPage<cm.Route>> Function(List<Object?>? after)? _activeSearch;
  List<Object?>? _resultsNext;
  String? _error;

  _DistanceFilter _distanceFilter = _DistanceFilter.any;
  _SurfaceFilter _surfaceFilter = _SurfaceFilter.any;
  _ExploreMode _mode = _ExploreMode.search;
  final Set<String> _selectedTags = {};
  bool _featuredOnly = false;
  String _sort = 'popular';
  List<String> _popularTags = const [];
  Set<String> _bookmarkedIds = const {};
  final Set<String> _bookmarkBusy = {};

  static const _pageSize = 30;

  @override
  void initState() {
    super.initState();
    // Defer the first search to after the first frame: the signed-out
    // early-return reads AppLocalizations.of(context), which isn't
    // available synchronously during initState.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _search();
    });
    _loadPopularTags();
    _loadBookmarkedIds();
  }

  /// Ids the viewer has bookmarked, for the row icons. A failure leaves every
  /// icon unfilled rather than claiming a state nothing confirmed.
  Future<void> _loadBookmarkedIds() async {
    final api = widget.apiClient;
    if (api == null || api.userId == null) return;
    try {
      final saved = await api.fetchBookmarkedRoutes(limit: 1000);
      if (mounted) setState(() => _bookmarkedIds = {for (final r in saved) r.id});
    } catch (e) {
      debugPrint('fetchBookmarkedRoutes failed: $e');
    }
  }

  Future<void> _loadPopularTags() async {
    final api = widget.apiClient;
    if (api == null) return;
    try {
      final tags = await api.fetchPopularRouteTags();
      if (mounted) setState(() => _popularTags = tags);
    } catch (e) {
      debugPrint('fetchPopularRouteTags failed: $e');
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _map.dispose();
    _parkCourses.dispose();
    super.dispose();
  }

  void _checkParkCourses() => unawaited(
    _parkCourses.check(_results.where((r) => r.official).map((r) => r.id)),
  );

  /// The sheet's list asks for the next page as it nears its end.
  bool _onScroll(ScrollNotification n) {
    if (n.metrics.axis == Axis.vertical &&
        n.metrics.pixels >= n.metrics.maxScrollExtent - 200 &&
        !_loading &&
        _hasMore) {
      _loadMore();
    }
    return false;
  }

  /// Near me moves the map to the runner too, so the pins and the list
  /// answer the same question. A map that has not laid out yet stays put.
  void _moveMapTo(Position pos) {
    try {
      _map.move(LatLng(pos.latitude, pos.longitude), 12);
    } catch (e) {
      debugPrint('ExploreRoutesScreen: map not ready to move: $e');
    }
  }

  void _openPin(cm.DiscoverableRoutePin pin) {
    final api = widget.apiClient;
    if (api == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PublicRouteScreen(api: api, routeId: pin.id),
      ),
    );
  }

  Future<void> _search() async {
    final api = widget.apiClient;
    if (api == null || api.userId == null) {
      setState(() =>
          _error = AppLocalizations.of(context).exploreRoutesSignInRequired);
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _results = [];
      _hasMore = true;
      _activeSearch = null;
      _resultsNext = null;
    });

    final text = _searchController.text.trim();
    final query = text.isEmpty ? null : text;
    final minDistanceM = _minDistance;
    final maxDistanceM = _maxDistance;
    final surface = _surfaceValue;
    final tags = _selectedTags.isEmpty ? null : _selectedTags.toList();
    final featuredOnly = _featuredOnly;
    final sort = _sort;
    Future<cm.KeysetPage<cm.Route>> read(List<Object?>? after) =>
        api.searchPublicRoutes(
          query: query,
          minDistanceM: minDistanceM,
          maxDistanceM: maxDistanceM,
          surface: surface,
          tags: tags,
          featuredOnly: featuredOnly,
          sort: sort,
          limit: _pageSize,
          after: after,
        );

    try {
      final page = await read(null).timeout(kBackendLoadTimeout);
      if (!mounted) return;
      setState(() {
        _results = page.rows;
        _resultsNext = page.next;
        _activeSearch = read;
        _hasMore = page.next != null;
        _loading = false;
      });
      _checkParkCourses();
    } on TimeoutException catch (e) {
      debugPrint('ExploreRoutesScreen._search timed out: $e');
      if (!mounted) return;
      setState(() {
        _error = AppLocalizations.of(context).exploreRoutesTimeout;
        _loading = false;
      });
    } catch (e, s) {
      debugPrint('ExploreRoutesScreen._search failed: $e\n$s');
      if (!mounted) return;
      setState(() {
        _error = AppLocalizations.of(context).exploreRoutesSearchFailed;
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    final read = _activeSearch;
    final after = _resultsNext;
    if (read == null || after == null || _loading || !_hasMore) return;

    setState(() => _loading = true);
    try {
      final page = await read(after);
      if (!mounted) return;
      setState(() {
        _results = cm.appendPage(_results, page.rows, (r) => r.id);
        _resultsNext = page.next;
        _hasMore = page.next != null;
        _loading = false;
      });
      _checkParkCourses();
    } catch (e, s) {
      debugPrint('ExploreRoutesScreen._loadMore failed: $e\n$s');
      if (mounted) {
        setState(() {
          _loading = false;
          _hasMore = false;
        });
        showTopBanner(context,
            AppLocalizations.of(context).exploreRoutesLoadMoreFailed);
      }
    }
  }

  Future<void> _searchNearby() async {
    final api = widget.apiClient;
    if (api == null || api.userId == null) {
      setState(() =>
          _error = AppLocalizations.of(context).exploreRoutesSignInRequired);
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _results = [];
      _hasMore = false;
      _activeSearch = null;
      _resultsNext = null;
    });

    try {
      final Position pos;
      try {
        pos = await (widget.locateFn ?? locateForBrowse)();
      } on PermissionDeniedException {
        if (mounted) {
          setState(() {
            _error = AppLocalizations.of(context)
                .exploreRoutesLocationPermissionRequired;
            _loading = false;
          });
        }
        return;
      } catch (e) {
        // Caught here, not below: a fix that never arrives is a
        // TimeoutException too, and the outer catch would call it a
        // backend timeout.
        debugPrint('ExploreRoutesScreen._searchNearby locate failed: $e');
        if (mounted) {
          final l10n = AppLocalizations.of(context);
          setState(() {
            _error = l10n.exploreRoutesNearbyLocationUnavailable(
                browseLocateErrorText(l10n, e));
            _loading = false;
          });
        }
        return;
      }

      _moveMapTo(pos);
      final results = await api.nearbyPublicRoutes(
        lat: pos.latitude,
        lng: pos.longitude,
        radiusM: 50000,
        limit: 50,
      ).timeout(kBackendLoadTimeout);
      if (!mounted) return;
      setState(() {
        _results = results;
        _loading = false;
      });
      _checkParkCourses();
    } on TimeoutException catch (e) {
      debugPrint('ExploreRoutesScreen._searchNearby timed out: $e');
      if (!mounted) return;
      setState(() {
        _error = AppLocalizations.of(context).exploreRoutesTimeout;
        _loading = false;
      });
    } catch (e, s) {
      debugPrint('ExploreRoutesScreen._searchNearby failed: $e\n$s');
      if (!mounted) return;
      setState(() {
        _error = AppLocalizations.of(context).exploreRoutesNearbyFailed;
        _loading = false;
      });
    }
  }

  static const _metresPerMile = 1609.344;

  // Thresholds in metres — adapt to the user's unit so the buckets feel
  // natural in both km and miles.
  List<double> get _thresholds => widget.preferences.useMiles
      ? [3 * _metresPerMile, 6 * _metresPerMile, 13 * _metresPerMile]
      : [5000, 10000, 21000];

  double? get _minDistance {
    final t = _thresholds;
    switch (_distanceFilter) {
      case _DistanceFilter.any:
      case _DistanceFilter.short:
        return null;
      case _DistanceFilter.medium:
        return t[0];
      case _DistanceFilter.long:
        return t[1];
      case _DistanceFilter.ultra:
        return t[2];
    }
  }

  double? get _maxDistance {
    final t = _thresholds;
    switch (_distanceFilter) {
      case _DistanceFilter.any:
        return null;
      case _DistanceFilter.short:
        return t[0];
      case _DistanceFilter.medium:
        return t[1];
      case _DistanceFilter.long:
        return t[2];
      case _DistanceFilter.ultra:
        return null;
    }
  }

  String? get _surfaceValue {
    switch (_surfaceFilter) {
      case _SurfaceFilter.any:
        return null;
      case _SurfaceFilter.road:
        return 'road';
      case _SurfaceFilter.trail:
        return 'trail';
      case _SurfaceFilter.mixed:
        return 'mixed';
    }
  }

  /// Saving a public route to the library is a `saved_routes` reference, not
  /// a private copy (decisions § 30), and a second tap removes it — as on web
  /// and on the route detail screen. This used to clone the route into the
  /// local store and never rebuild the row, so the bookmark stayed unfilled
  /// after a save and could not be undone from here.
  ///
  /// The icon flips before the request so the tap visibly lands, and flips
  /// back if it fails. A tap while that row's request is in flight is
  /// dropped, so a double tap cannot save and then unsave.
  Future<void> _toggleBookmark(cm.Route route) async {
    final api = widget.apiClient;
    if (api == null || api.userId == null) return;
    if (_bookmarkBusy.contains(route.id)) return;
    final l10n = AppLocalizations.of(context);
    final wasSaved = _bookmarkedIds.contains(route.id);
    setState(() {
      _bookmarkBusy.add(route.id);
      _bookmarkedIds = wasSaved
          ? ({..._bookmarkedIds}..remove(route.id))
          : {..._bookmarkedIds, route.id};
    });
    try {
      if (wasSaved) {
        await api.unbookmarkRoute(route.id);
      } else {
        await api.bookmarkRoute(route.id);
      }
      if (!mounted) return;
      showTopBanner(
        context,
        wasSaved
            ? l10n.exploreRoutesRemoved(route.name)
            : l10n.exploreRoutesSaved(route.name),
      );
    } catch (e) {
      debugPrint('explore bookmark toggle failed: $e');
      if (!mounted) return;
      setState(() {
        _bookmarkedIds = wasSaved
            ? {..._bookmarkedIds, route.id}
            : ({..._bookmarkedIds}..remove(route.id));
      });
      showTopBanner(
        context,
        l10n.routeDetailBookmarkFailed(friendlyError(l10n, e)),
      );
    } finally {
      if (mounted) setState(() => _bookmarkBusy.remove(route.id));
    }
  }

  void _setNearMe(bool on) {
    setState(() => _mode = on ? _ExploreMode.nearMe : _ExploreMode.search);
    on ? _searchNearby() : _search();
  }

  /// Applies a filter change, which reruns the search.
  void _apply(VoidCallback change) {
    setState(change);
    _search();
  }

  Map<_DistanceFilter, String> _distanceLabels(AppLocalizations l10n) {
    final mi = widget.preferences.useMiles;
    return {
      _DistanceFilter.any: l10n.exploreRoutesDistanceAny,
      _DistanceFilter.short:
          mi ? l10n.exploreRoutesDistanceUnderMi : l10n.exploreRoutesDistanceUnderKm,
      _DistanceFilter.medium:
          mi ? l10n.exploreRoutesDistanceMidMi : l10n.exploreRoutesDistanceMidKm,
      _DistanceFilter.long:
          mi ? l10n.exploreRoutesDistanceLongMi : l10n.exploreRoutesDistanceLongKm,
      _DistanceFilter.ultra:
          mi ? l10n.exploreRoutesDistanceUltraMi : l10n.exploreRoutesDistanceUltraKm,
    };
  }

  Map<_SurfaceFilter, String> _surfaceLabels(AppLocalizations l10n) => {
        _SurfaceFilter.any: l10n.exploreRoutesSurfaceAny,
        _SurfaceFilter.road: l10n.exploreRoutesSurfaceRoad,
        _SurfaceFilter.trail: l10n.exploreRoutesSurfaceTrail,
        _SurfaceFilter.mixed: l10n.exploreRoutesSurfaceMixed,
      };

  Map<String, String> _sortLabels(AppLocalizations l10n) => {
        'popular': l10n.exploreRoutesSortMostRun,
        'newest': l10n.exploreRoutesSortNewest,
        'featured': l10n.exploreRoutesSortFeatured,
      };

  /// Search and the Near me chip, after the Routes · Segments chips when the
  /// Routes tab hosts this. Near me searches around a location fix rather
  /// than by text and filters, so it hides both while it is on.
  FilterBar _filterBar(AppLocalizations l10n) {
    final nearMe = _mode == _ExploreMode.nearMe;
    ActiveFilter active(String label, VoidCallback onRemove) => ActiveFilter(
          label: label,
          onRemove: onRemove,
          removeTooltip: l10n.filterBarRemoveFilter(label),
        );
    final filters = nearMe
        ? const <ActiveFilter>[]
        : [
            if (_distanceFilter != _DistanceFilter.any)
              active(_distanceLabels(l10n)[_distanceFilter]!,
                  () => _apply(() => _distanceFilter = _DistanceFilter.any)),
            if (_surfaceFilter != _SurfaceFilter.any)
              active(_surfaceLabels(l10n)[_surfaceFilter]!,
                  () => _apply(() => _surfaceFilter = _SurfaceFilter.any)),
            if (_sort != 'popular')
              active(_sortLabels(l10n)[_sort] ?? l10n.exploreRoutesSort,
                  () => _apply(() => _sort = 'popular')),
            if (_featuredOnly)
              active(l10n.exploreRoutesFeatured,
                  () => _apply(() => _featuredOnly = false)),
            for (final t in _selectedTags)
              active(t, () => _apply(() => _selectedTags.remove(t))),
          ];
    return FilterBar(
      key: const ValueKey('explore-routes-filter-bar'),
      search: nearMe
          ? null
          : AppSearchField(
              controller: _searchController,
              hint: l10n.exploreRoutesSearchHint,
              clearTooltip: l10n.commonClearSearch,
              onChanged: (v) {
                if (v.isEmpty) _search();
              },
              onSubmitted: (_) => _search(),
            ),
      chips: [
        ...?widget.chrome?.chips,
        FilterChip(
          avatar: const Icon(Icons.near_me, size: 18),
          label: Text(l10n.exploreRoutesModeNearMe),
          selected: nearMe,
          showCheckmark: false,
          onSelected: _setNearMe,
        ),
      ],
      activeFilters: filters,
      filtersLabel: nearMe ? null : l10n.filterBarFilters,
      filtersSemanticLabel:
          filters.isEmpty ? null : l10n.filterBarFiltersCount(filters.length),
      activeFilterCount: filters.length,
      onOpenFilters: nearMe ? null : () => _openFilters(l10n),
    );
  }

  Future<void> _openFilters(AppLocalizations l10n) {
    return showFilterSheet(
      context: context,
      title: l10n.filterBarFilters,
      doneLabel: l10n.filterBarDone,
      builder: (sheetContext, setSheet) {
        final theme = Theme.of(sheetContext);
        Widget group(String heading, List<Widget> chips) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(heading, style: theme.textTheme.titleSmall),
                  const SizedBox(height: AppSpace.sm),
                  // semantics-children: a group name, read once before the controls inside it
                  Semantics(
                    container: true,
                    label: heading,
                    child: Wrap(
                      spacing: AppSpace.sm,
                      runSpacing: AppSpace.xs,
                      children: chips,
                    ),
                  ),
                ],
              ),
            );
        Widget pick<T>(T value, T selected, String label, ValueChanged<T> on) =>
            ChoiceChip(
              label: Text(label),
              selected: value == selected,
              onSelected: (_) {
                _apply(() => on(value));
                setSheet(() {});
              },
            );
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            group(l10n.filterBarDistance, [
              for (final e in _distanceLabels(l10n).entries)
                pick(e.key, _distanceFilter, e.value,
                    (v) => _distanceFilter = v),
            ]),
            group(l10n.filterBarSurface, [
              for (final e in _surfaceLabels(l10n).entries)
                pick(e.key, _surfaceFilter, e.value,
                    (v) => _surfaceFilter = v),
            ]),
            group(l10n.filterBarSort, [
              for (final e in _sortLabels(l10n).entries)
                pick(e.key, _sort, e.value, (v) => _sort = v),
            ]),
            group(l10n.exploreRoutesFeatured, [
              FilterChip(
                avatar: const Icon(Icons.star_border, size: 18),
                label: Text(l10n.exploreRoutesFeatured),
                selected: _featuredOnly,
                onSelected: (v) {
                  _apply(() => _featuredOnly = v);
                  setSheet(() {});
                },
              ),
              for (final t in _popularTags)
                FilterChip(
                  label: Text(t),
                  selected: _selectedTags.contains(t),
                  onSelected: (v) {
                    _apply(() => v ? _selectedTags.add(t) : _selectedTags.remove(t));
                    setSheet(() {});
                  },
                ),
            ]),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final unit = widget.preferences.unit;
    final bar = _filterBar(l10n);
    return HubTabBody(
      title: l10n.exploreRoutesTitle,
      filters: widget.chrome?.above(bar) ?? bar,
      onRefresh: _mode == _ExploreMode.nearMe ? _searchNearby : _search,
      // The map keeps the drags that start on it and the Fitness hub swipes
      // from the controls and the sheet, so Explore is a map inside the
      // hub's pages rather than a pushed screen (conventions § Mobile
      // map-first pages).
      body: MapFirstPage(
        map: ExploreRoutesMap(
          api: widget.apiClient,
          controller: _map,
          onOpen: _openPin,
        ),
        attribution: ExploreRoutesMap.credit(context),
        bottomClearance: DockedFabInset.of(context),
        sheet: MapFirstSheet(
          initialSize: 0.55,
          minSize: 0.2,
          maxSize: 0.85,
          onScroll: _onScroll,
          slivers: [
            if (widget.maps case final maps?) SliverToBoxAdapter(child: maps),
            ..._bodySlivers(theme, unit),
          ],
        ),
      ),
    );
  }

  List<Widget> _bodySlivers(ThemeData theme, DistanceUnit unit) {
    final l10n = AppLocalizations.of(context);
    if (_error != null) {
      return [
        SliverToBoxAdapter(
          child: AppErrorState(
            message: _error!,
            onRetry: _mode == _ExploreMode.nearMe ? _searchNearby : _search,
          ),
        ),
      ];
    }

    if (_results.isEmpty && !_loading) {
      return [
        SliverToBoxAdapter(
          child: EmptyState(
            icon: Icons.explore,
            title: _searchController.text.isEmpty
                ? l10n.exploreRoutesEmptyNoPublic
                : l10n.exploreRoutesEmptyNoMatch,
            body: l10n.exploreRoutesEmptyBody,
          ),
        ),
      ];
    }

    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(
            AppInsets.gutter, AppSpace.sm, AppInsets.gutter, 0),
        sliver: SliverList.builder(
          itemCount: _results.length + (_loading ? 1 : 0),
          itemBuilder: (context, index) {
            if (index >= _results.length) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              );
            }

            final route = _results[index];

            return _RouteCard(
              parkCourses: _parkCourses,
              route: route,
              unit: unit,
              theme: theme,
              saved: _bookmarkedIds.contains(route.id),
              onTap: () async {
                await Navigator.push<void>(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => RouteDetailScreen(
                      route: route,
                      routeStore: widget.routeStore,
                      preferences: widget.preferences,
                      apiClient: widget.apiClient,
                    ),
                  ),
                );
                // The detail screen carries its own bookmark toggle.
                _loadBookmarkedIds();
              },
              onToggleBookmark: () => _toggleBookmark(route),
            );
          },
        ),
      ),
    ];
  }
}

class _RouteCard extends StatelessWidget {
  final cm.Route route;
  final DistanceUnit unit;
  final ThemeData theme;
  final bool saved;
  final VoidCallback onTap;
  final VoidCallback onToggleBookmark;
  final ParkCourseRouteLookup parkCourses;

  const _RouteCard({
    required this.route,
    required this.parkCourses,
    required this.unit,
    required this.theme,
    required this.saved,
    required this.onTap,
    required this.onToggleBookmark,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListCard.row(
      dense: true,
      onTap: onTap,
      leadingWidth: 80,
      leading: SizedBox(
        height: 48,
        // Explore is community-public routes — every row is by a non-owner.
        // RouteTrackPreview's owner branch short-circuits to raw waypoints
        // in the rare case of viewing your own published route.
        child: route.waypoints.length >= 2
            ? RouteTrackPreview(
                routeId: route.id,
                waypoints: route.waypoints,
                ownerUserId: route.userId,
                api: ApiClient(),
              )
            : Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _surfaceIcon(route.surface),
                  color: theme.colorScheme.secondary,
                ),
              ),
      ),
      title: route.name,
      badge: route.official || route.featured
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (route.official)
                  OfficialRouteBadge(routeId: route.id, lookup: parkCourses),
                if (route.featured)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(start: 6),
                    child: Icon(
                      Icons.star,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                  ),
              ],
            )
          : null,
      meta: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              _tag(
                  Icons.straighten,
                  UnitFormat.distance(
                      routeDisplayDistanceM(
                          route.distanceMetres, route.officialDistanceMetres),
                      unit)),
              if (route.elevationGainMetres > 0)
                _tag(Icons.trending_up,
                    UnitFormat.elevation(route.elevationGainMetres, unit)),
              if (route.surface != null)
                _tag(_surfaceIcon(route.surface),
                    routeSurfaceLabel(l10n, route.surface!)),
              if (route.runCount > 0)
                _tag(Icons.directions_run, '${route.runCount}'),
            ],
          ),
          if (route.tags.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final t in route.tags.take(4))
                  StatusPill(
                    label: t,
                    foreground: theme.colorScheme.onSurfaceVariant,
                    fill: theme.colorScheme.surfaceContainerHighest,
                    size: StatusPillSize.compact,
                  ),
              ],
            ),
          ],
        ],
      ),
      trailing: IconButton(
        icon: Icon(
          saved ? Icons.bookmark : Icons.bookmark_border,
          color: saved ? theme.colorScheme.primary : theme.colorScheme.outline,
        ),
        tooltip: saved
            ? l10n.exploreRoutesRemoveFromLibrary
            : l10n.exploreRoutesSaveToLibrary,
        onPressed: onToggleBookmark,
      ),
    );
  }

  Widget _tag(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: theme.colorScheme.outline),
        const SizedBox(width: 3),
        // Flexible: at 2x text on a 320 dp phone the card's text column is
        // about 110 dp, and a distance on one line overflowed it.
        Flexible(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  static IconData _surfaceIcon(String? surface) {
    switch (surface) {
      case 'trail':
        return Icons.terrain;
      case 'mixed':
        return Icons.alt_route;
      default:
        return Icons.route;
    }
  }
}

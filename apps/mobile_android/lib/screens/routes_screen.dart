import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' as cm;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ui_kit/ui_kit.dart'
    show
        ActiveFilter,
        AppInsets,
        AppSearchField,
        AppSemanticColors,
        AppSpace,
        EmptyState,
        FilterBar,
        HubSelection,
        HubTabBody,
        PrimaryAction,
        SelectionHint,
        showFilterSheet;

import '../widgets/grisnir_moments.dart';
import '../auth_error.dart';
import '../catalogue_browse.dart' show compareFoldedNames, fold;
import '../l10n/gen/app_localizations.dart';
import '../fab_clearance.dart';
import '../local_route_store.dart';
import '../local_run_store.dart';
import '../official_distance.dart';
import '../preferences.dart';
import '../route_file_import.dart';
import '../social_service.dart';
import '../backend_timeout.dart';
import '../widgets/error_state.dart';
import '../widgets/route_track_preview.dart';
import 'explore_routes_screen.dart';
import 'routes_heatmap_screen.dart';
import 'route_builder_screen.dart';
import 'route_detail_screen.dart';
import 'run_heatmap_screen.dart';
import '../widgets/top_banner.dart';

/// Page size for the cloud fetch + visible-list window. Same value as
/// runs_screen — `docs/architecture/conventions.md § Pagination` makes consistency
/// across surfaces a load-bearing rule.
const int _kRoutesPageSize = 20;

/// SharedPreferences key for the persisted filter blob (search /
/// surface / distance / sort / starredOnly). Matches the web app's
/// localStorage key so the convention is the same on every surface.
const String _kRoutesFiltersKey = 'routes_filters_v1';

enum _RouteSort { newest, longest, shortest, mostRun, az }

enum _DistanceBucket { any, lt5, t5to10, t10to20, gt20 }

enum _SurfaceFilter { any, road, trail, mixed }

/// True when the Load-more button should render at the bottom of the
/// routes list — either the merged local+bookmark superset has more
/// rows beyond `visibleCount`, or the cloud might have older owned
/// routes. Pure helper kept top-level so unit tests can assert the
/// boundary conditions without mounting the screen. Mirrors
/// `shouldShowRunsLoadMore` in runs_screen.dart.
@visibleForTesting
bool shouldShowRoutesLoadMore({
  required int visibleCount,
  required int totalCount,
  required bool remoteHasMore,
  required bool apiSignedIn,
}) {
  if (visibleCount < totalCount) return true;
  return remoteHasMore && apiSignedIn;
}

/// Route library: imported and synced routes.
class RoutesScreen extends StatefulWidget {
  final ApiClient? apiClient;
  final LocalRouteStore routeStore;
  /// Only forwarded to [RunHeatmapScreen], whose tracks come from the
  /// local store as well as the server (issue #239).
  final LocalRunStore? runStore;
  final Preferences preferences;
  /// Optional social service. Threaded into [RouteBuilderScreen] so
  /// the SaveRouteDialog can show a "Save to" picker populated with
  /// the user's clubs. When null, the picker is hidden and saved
  /// routes go to the user's personal library (existing behaviour).
  final SocialService? social;
  const RoutesScreen({
    super.key,
    this.apiClient,
    required this.routeStore,
    this.runStore,
    required this.preferences,
    this.social,
  });

  @override
  State<RoutesScreen> createState() => RoutesScreenState();
}

class RoutesScreenState extends State<RoutesScreen> {
  bool _syncing = false;
  /// Set while one of the two FABs has its one-shot surface open — the builder
  /// route or the file picker. Both disable: a second tap during the push
  /// transition stacked a duplicate builder, so saving in the top one popped
  /// onto an empty second one and read as a discarded save.
  bool _fabBusy = false;
  // Set when the initial remote fetch fails or times out. Only surfaced as a
  // full ErrorState when there are no cached routes to fall back on — a stale
  // cache still renders, with the failure shown as a banner instead.
  bool _fetchError = false;
  List<cm.Route> _bookmarks = const [];

  /// How many merged rows the list reveals. Resets to one page when
  /// the filter state changes so a narrowed view starts at page 1.
  int _visibleCount = _kRoutesPageSize;
  bool _loadingMore = false;
  bool _remoteHasMore = true;

  /// The cursor after the last route the server returned — the server's own
  /// values, so a `created_at` keeps its microseconds and the next page starts
  /// exactly after it. Null until the first page lands, which makes a load
  /// more before then read the first page.
  List<Object?>? _remoteNext;

  // Filter state — mirrors the web `/routes` toolbar. The
  // post-filter list feeds the visible-window paging.
  String _search = '';
  final _searchCtl = TextEditingController();
  _SurfaceFilter _surfaceFilter = _SurfaceFilter.any;
  _DistanceBucket _distanceFilter = _DistanceBucket.any;
  _RouteSort _sort = _RouteSort.newest;
  bool _starredOnly = false;

  bool _selecting = false;
  final Set<String> _selected = <String>{};
  bool _deleting = false;

  /// One-shot: the cursor-paged owned fetch only has the first page in
  /// memory, so a client-side `is_starred` filter would only ever surface
  /// the starred routes that happen to sit on page 1. When the Starred
  /// filter is engaged we pull the user's full starred set server-side
  /// once so every starred route is present, not just the first page's.
  bool _starredLoaded = false;

  @override
  void initState() {
    super.initState();
    widget.routeStore.addListener(_onChange);
    widget.preferences.addListener(_onChange);
    _fetchRemoteRoutes();
    _fetchBookmarks();
    _hydrateFilters();
  }

  @override
  void dispose() {
    widget.routeStore.removeListener(_onChange);
    widget.preferences.removeListener(_onChange);
    _searchCtl.dispose();
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  /// Pull every starred route the user owns (server-side `is_starred`
  /// filter) so the Starred toggle isn't limited to whatever starred
  /// routes happened to be on the first cursor page. Idempotent.
  Future<void> _ensureStarredLoaded() async {
    if (_starredLoaded) return;
    final api = widget.apiClient;
    if (api == null || api.userId == null) return;
    try {
      final starred = await api
          .getRoutes(starredOnly: true, limit: 500)
          .timeout(kBackendLoadTimeout);
      await widget.routeStore.saveBatch(starred.rows);
      _starredLoaded = true;
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('fetch starred routes failed: $e');
    }
  }

  Future<void> _fetchBookmarks() async {
    final api = widget.apiClient;
    if (api == null || api.userId == null) return;
    try {
      final marks =
          await api.fetchBookmarkedRoutes().timeout(kBackendLoadTimeout);
      if (!mounted) return;
      setState(() => _bookmarks = marks);
    } catch (e) {
      // The owned list still renders; the bookmarks already shown stay.
      debugPrint('Fetch bookmarked routes failed: $e');
      if (mounted) {
        showTopBanner(
            context, AppLocalizations.of(context).routesBookmarksLoadFailed);
      }
    }
  }

  Future<void> _fetchRemoteRoutes() async {
    final api = widget.apiClient;
    if (api == null || api.userId == null) return;
    setState(() {
      _syncing = true;
      _fetchError = false;
    });
    try {
      // Initial sync pulls only the first page — older routes flow in
      // through Load more. Cap mirrors `_kRoutesPageSize` so a returning
      // user sees the same shape as the web `/routes` first paint.
      final page = await api
          .getRoutes(limit: _kRoutesPageSize)
          .timeout(kBackendLoadTimeout);
      await widget.routeStore.saveBatch(page.rows);
      if (!mounted) return;
      setState(() {
        _remoteNext = page.next;
        _remoteHasMore = page.next != null;
      });
    } catch (e) {
      debugPrint('Fetch routes failed: $e');
      if (mounted) {
        setState(() => _fetchError = true);
        showTopBanner(
            context, AppLocalizations.of(context).routesSyncFailedOffline);
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  /// Reveal the next page. Same two-layer shape as runs_screen: bump
  /// the local visibility window first, only hit the cloud once we've
  /// shown everything cached.
  Future<void> _loadMore() async {
    if (_loadingMore) return;
    final owned = widget.routeStore.routes;
    final ownedIds = {for (final r in owned) r.id};
    final mergedCount =
        owned.length + _bookmarks.where((b) => !ownedIds.contains(b.id)).length;

    if (_visibleCount < mergedCount) {
      setState(() => _visibleCount += _kRoutesPageSize);
      // After revealing locally, opportunistically fetch the next cloud
      // page if we just hit the bottom and the cloud might have more.
      if (_visibleCount >= mergedCount && _remoteHasMore) {
        await _fetchOlderFromRemote();
      }
      return;
    }

    if (_remoteHasMore) {
      await _fetchOlderFromRemote();
    }
  }

  Future<void> _fetchOlderFromRemote() async {
    final api = widget.apiClient;
    if (api == null || api.userId == null) {
      if (mounted) setState(() => _remoteHasMore = false);
      return;
    }

    setState(() => _loadingMore = true);
    try {
      // The cursor is the last row the SERVER returned, not the store's last
      // route: the store keeps insertion order and also holds the starred
      // routes `_ensureStarredLoaded` pulled from anywhere in the history, so
      // its last row can sit pages past where this list has read, and a
      // `created_at` round-tripped through DateTime loses the server's
      // microseconds.
      final page = await api
          .getRoutes(
            limit: _kRoutesPageSize,
            after: _remoteNext,
          )
          .timeout(kBackendLoadTimeout);
      await widget.routeStore.saveBatch(page.rows);
      if (!mounted) return;
      setState(() {
        _remoteNext = page.next;
        _remoteHasMore = page.next != null;
        _visibleCount += _kRoutesPageSize;
      });
    } catch (e) {
      debugPrint('Load more routes failed: $e');
      if (mounted) {
        showTopBanner(
            context, AppLocalizations.of(context).routesLoadMoreFailed);
      }
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  /// Restore filter state from SharedPreferences. Best-effort — a
  /// malformed blob is ignored and defaults stand. Mirrors the web
  /// app's runs/routes hydration shape.
  Future<void> _hydrateFilters() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_kRoutesFiltersKey);
      if (raw == null || !mounted) return;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final search = j['search'];
      final surface = j['surface'];
      final distance = j['distance'];
      final sort = j['sort'];
      final starred = j['starredOnly'];
      setState(() {
        if (search is String) {
          _search = search;
          _searchCtl.text = search;
        }
        if (surface is String) {
          _surfaceFilter = _SurfaceFilter.values.firstWhere(
            (e) => e.name == surface,
            orElse: () => _SurfaceFilter.any,
          );
        }
        if (distance is String) {
          _distanceFilter = _DistanceBucket.values.firstWhere(
            (e) => e.name == distance,
            orElse: () => _DistanceBucket.any,
          );
        }
        if (sort is String) {
          _sort = _RouteSort.values.firstWhere(
            (e) => e.name == sort,
            orElse: () => _sort,
          );
        }
        if (starred is bool) _starredOnly = starred;
        // Reset paging — the filtered list might be smaller.
        _visibleCount = _kRoutesPageSize;
      });
      // Restored into the Starred view → make sure the full starred set
      // is loaded, not just whatever sits on the first cursor page.
      if (_starredOnly) _ensureStarredLoaded();
    } catch (_) {
      // Corrupt blob; leave defaults.
    }
  }

  void _persistFilters() {
    SharedPreferences.getInstance().then((p) {
      p.setString(
        _kRoutesFiltersKey,
        jsonEncode({
          'search': _search,
          'surface': _surfaceFilter.name,
          'distance': _distanceFilter.name,
          'sort': _sort.name,
          'starredOnly': _starredOnly,
        }),
      );
    }).catchError((Object _) {
      // L4 best-effort — never escalate.
    });
  }

  bool _filtersActive() =>
      _search.trim().isNotEmpty ||
      _surfaceFilter != _SurfaceFilter.any ||
      _distanceFilter != _DistanceBucket.any ||
      _starredOnly;

  /// Snapshot of route IDs that LocalRouteStore considers synced
  /// (cloud-confirmed via the SyncService drain). Used by the list
  /// renderer to flip the "Will sync" badge on locally-built routes
  /// that haven't yet been pushed.
  Set<String> _syncedOwnedIds() {
    // unsyncedRoutes is the source of truth; flip it to the synced
    // set by diffing against everything the local store knows about.
    final unsyncedIds = {
      for (final r in widget.routeStore.unsyncedRoutes) r.id,
    };
    return {
      for (final r in widget.routeStore.routes)
        if (!unsyncedIds.contains(r.id)) r.id,
    };
  }


  void _clearFilters() {
    _searchCtl.clear();
    setState(() {
      _search = '';
      _surfaceFilter = _SurfaceFilter.any;
      _distanceFilter = _DistanceBucket.any;
      _starredOnly = false;
      _visibleCount = _kRoutesPageSize;
    });
    _persistFilters();
  }

  static bool _inDistanceBucket(double meters, _DistanceBucket b) {
    final km = meters / 1000;
    switch (b) {
      case _DistanceBucket.any:
        return true;
      case _DistanceBucket.lt5:
        return km < 5;
      case _DistanceBucket.t5to10:
        return km >= 5 && km < 10;
      case _DistanceBucket.t10to20:
        return km >= 10 && km < 20;
      case _DistanceBucket.gt20:
        return km >= 20;
    }
  }

  /// Apply the current filter + sort to the merged owned + bookmarks
  /// list. Pure pass over the input — no setState, no I/O.
  List<cm.Route> _filteredAndSorted(List<cm.Route> all) {
    // Folded on BOTH sides of the comparison, never `toLowerCase`. The two
    // runtimes' own lower-case answers differ at 466 code points, and the one
    // reachable in Latin text is U+0130: this side's simple mapping turns
    // `İstanbul Loop` into `istanbul loop`, while a browser emits `i` plus a
    // combining dot and does NOT match `istanbul`. So the same route was
    // findable by typing `istanbul` here and not on the web (decisions
    // § 1337). Folding also strips the accent, which is what lets `zurich`
    // reach `Zürich Loop` from a keyboard without one.
    final q = fold(_search.trim());
    Iterable<cm.Route> stream = all;
    if (_starredOnly) stream = stream.where((r) => r.isStarred);
    if (_surfaceFilter != _SurfaceFilter.any) {
      stream = stream.where((r) => r.surface == _surfaceFilter.name);
    }
    if (_distanceFilter != _DistanceBucket.any) {
      stream = stream
          .where((r) => _inDistanceBucket(_shownM(r), _distanceFilter));
    }
    if (q.isNotEmpty) {
      stream = stream.where((r) => fold(r.name).contains(q));
    }
    final out = stream.toList();
    switch (_sort) {
      case _RouteSort.newest:
        out.sort((a, b) {
          final ax = a.createdAt;
          final bx = b.createdAt;
          if (ax == null && bx == null) return 0;
          if (ax == null) return 1;
          if (bx == null) return -1;
          return bx.compareTo(ax);
        });
      case _RouteSort.longest:
        out.sort((a, b) => _shownM(b).compareTo(_shownM(a)));
      case _RouteSort.shortest:
        out.sort((a, b) => _shownM(a).compareTo(_shownM(b)));
      case _RouteSort.mostRun:
        out.sort((a, b) => b.runCount.compareTo(a.runCount));
      case _RouteSort.az:
        out.sort((a, b) => compareFoldedNames(a.name, a.id, b.name, b.id));
    }
    return out;
  }

  // ── Selection mode ────────────────────────────────────────────────
  //
  // Mirrors the runs_screen pattern: long-press a route to enter
  // selection, tap to add/remove, then bulk-delete. The selection state is
  // an inline banner at the top of the body rather than a replacement
  // AppBar, so the `embedded: true` path stays viable for a host that owns
  // the chrome — replacing a host's AppBar would mean plumbing selection
  // state up into it.

  void _enterSelection(String firstId) {
    setState(() {
      _selecting = true;
      _selected
        ..clear()
        ..add(firstId);
    });
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
        if (_selected.isEmpty) _selecting = false;
      } else {
        _selected.add(id);
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selecting = false;
      _selected.clear();
    });
  }

  void _selectAllOwnedVisible(List<cm.Route> visible, Set<String> ownedIds) {
    setState(() {
      _selected
        ..clear()
        ..addAll(visible.where((r) => ownedIds.contains(r.id)).map((r) => r.id));
    });
  }

  Future<void> _deleteSelected() async {
    final count = _selected.length;
    if (count == 0) return;
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.routesDeleteConfirmTitle(count)),
        content: Text(l10n.routesDeleteConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.routeBuilderCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppSemanticColors.of(ctx).danger,
              foregroundColor: AppSemanticColors.of(ctx).onDanger,
            ),
            child: Text(l10n.routeDetailDelete),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (!mounted) return;
    setState(() => _deleting = true);
    final ids = Set<String>.from(_selected);
    final failedIds = <String>{};
    final refusedIds = <String>{};
    final api = widget.apiClient;
    if (api != null && api.userId != null) {
      for (final id in ids) {
        try {
          await api.deleteRoute(id);
        } on RouteDeleteRefusedException {
          // Terminal: queueing it would retry a delete the server refuses
          // forever. The local copy stays, and the banner counts it failed.
          refusedIds.add(id);
        } catch (e) {
          debugPrint('deleteRoute failed for $id: $e');
          failedIds.add(id);
        }
      }
    }
    final ok2 = ids.difference(failedIds).difference(refusedIds);
    if (ok2.isNotEmpty) await widget.routeStore.deleteMany(ok2);
    if (failedIds.isNotEmpty) {
      // Queue the failed ids for retry so a partial-delete failure
      // isn't abandoned — SyncService drains this on its usual triggers
      // (foreground, connectivity-on, startup). Stamped with the
      // current user so a sign-out → other-user sign-in cycle doesn't
      // drain User A's pending deletes under User B's session. See
      // `docs/architecture/decisions.md § 67` for the owner-tag design.
      await widget.routeStore.markManyPendingRemoteDelete(
        failedIds,
        ownerUserId: api?.userId,
      );
    }
    if (!mounted) return;
    setState(() {
      _selecting = false;
      _selected.clear();
      _deleting = false;
    });
    if (failedIds.isNotEmpty || refusedIds.isNotEmpty) {
      showTopBanner(
        context,
        l10n.routesDeletePartial(ok2.length, failedIds.length + refusedIds.length),
      );
    } else {
      showTopBanner(
        context,
        l10n.routesDeleteDone(count),
      );
    }
  }

  HubSelection _selectionBar({
    required List<cm.Route> visible,
    required Set<String> ownedIds,
  }) {
    final l10n = AppLocalizations.of(context);
    final ownedVisibleIds =
        visible.where((r) => ownedIds.contains(r.id)).map((r) => r.id).toSet();
    final allSelected = ownedVisibleIds.isNotEmpty &&
        ownedVisibleIds.difference(_selected).isEmpty;
    return HubSelection(
      title: l10n.routesSelectionTitle(_selected.length),
      closeTooltip: l10n.routeBuilderCancel,
      onClose: _deleting ? null : _clearSelection,
      actions: [
        IconButton(
          icon: Icon(allSelected ? Icons.deselect : Icons.select_all),
          tooltip: allSelected
              ? l10n.historyClearSelectionTooltip
              : l10n.historySelectAllTooltip,
          onPressed: _deleting
              ? null
              : (allSelected
                  ? () => setState(() => _selected.clear())
                  : () => _selectAllOwnedVisible(visible, ownedIds)),
        ),
        IconButton(
          icon: _deleting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.delete_outline),
          tooltip: l10n.historyDeleteTooltip,
          onPressed:
              (_selected.isEmpty || _deleting) ? null : _deleteSelected,
        ),
      ],
    );
  }

  Future<void> _toggleStar(cm.Route route) async {
    final next = !route.isStarred;
    // BUG FIX: previous version omitted `clubId` and `description`
    // from the constructor, so toggling a star on a route that was
    // transferred to a club / had a description set silently wiped
    // both. User reported "starring a route doesn't work anymore"
    // — same incident, two visible symptoms (star fails to persist
    // visually if the wiped fields trigger an unrelated rebuild,
    // OR the description vanishes after a star tap).
    final updated = cm.Route(
      id: route.id,
      userId: route.userId,
      name: route.name,
      waypoints: route.waypoints,
      distanceMetres: route.distanceMetres,
      officialDistanceMetres: route.officialDistanceMetres,
      elevationGainMetres: route.elevationGainMetres,
      isPublic: route.isPublic,
      createdAt: route.createdAt,
      surface: route.surface,
      tags: route.tags,
      featured: route.featured,
      runCount: route.runCount,
      isStarred: next,
      clubId: route.clubId,
      description: route.description,
    );
    // Offline-tolerant flow (mirrors `_togglePublic` on the route
    // detail screen): write the local store first so the toggle is
    // durable across signed-out / network-down paths. SyncService
    // drains the unsynced state on the next cycle.
    await widget.routeStore.save(updated);
    if (!mounted) return;
    setState(() {});
    final api = widget.apiClient;
    if (api == null || api.userId == null) {
      // Signed-out — local-only is correct; the next sync push
      // carries the new isStarred flag.
      return;
    }
    try {
      await api.setRouteStar(route.id, next);
    } catch (e) {
      debugPrint('routes star update failed: $e');
      // Cloud failed — revert local + surface.
      await widget.routeStore.save(route);
      if (mounted) {
        setState(() {});
        showTopBanner(
            context, AppLocalizations.of(context).routesStarUpdateFailed(friendlyError(AppLocalizations.of(context), e)));
      }
    }
  }

  Future<void> _importFile() async {
    if (_fabBusy) return;
    setState(() => _fabBusy = true);
    try {
      await pickAndImportRouteFile(context, widget.routeStore);
    } finally {
      if (mounted) setState(() => _fabBusy = false);
    }
  }

  Future<void> _openBuilder() async {
    final api = widget.apiClient;
    if (api == null || _fabBusy) return;
    setState(() => _fabBusy = true);
    try {
      final created = await Navigator.of(context).push<cm.Route>(
        MaterialPageRoute(
          builder: (_) => RouteBuilderScreen(
            apiClient: api,
            routeStore: widget.routeStore,
            social: widget.social,
          ),
        ),
      );
      if (created != null && mounted) {
        showTopBanner(
            context, AppLocalizations.of(context).routesSaved(created.name));
      }
    } finally {
      if (mounted) setState(() => _fabBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final unit = widget.preferences.unit;
    final owned = widget.routeStore.routes;
    final ownedIds = {for (final r in owned) r.id};
    final mergedRoutes = <cm.Route>[
      ...owned,
      ..._bookmarks.where((b) => !ownedIds.contains(b.id)),
    ];
    // Filter pass first; pagination is computed against the filtered
    // list (a search of "trail" with 30 matches still pages 20 at a
    // time rather than locking the whole library to the screen).
    final filtered = _filteredAndSorted(mergedRoutes);
    final routes = filtered.length <= _visibleCount
        ? filtered
        : filtered.sublist(0, _visibleCount);
    final showLoadMore = shouldShowRoutesLoadMore(
      visibleCount: _visibleCount,
      totalCount: filtered.length,
      remoteHasMore: _remoteHasMore,
      apiSignedIn: widget.apiClient?.userId != null,
    );
    final emptyAfterFilter =
        mergedRoutes.isNotEmpty && filtered.isEmpty;

    final body = mergedRoutes.isEmpty && _fetchError && !_syncing
        ? AppErrorState(
            message: l10n.routesLoadErrorRetry,
            onRetry: _fetchRemoteRoutes,
          )
        : mergedRoutes.isEmpty
          // Names both ways in: the body copy says Build and Import, and the
          // button is whichever the hub's FAB is.
          ? EmptyState(
              icon: Icons.route,
              illustration: grisnirWaitingOrNull(),
              title: l10n.routesEmptyTitle,
              body: l10n.routesEmptyBody,
              ctaLabel: widget.apiClient == null
                  ? l10n.routesImport
                  : l10n.routesBuild,
              ctaIcon: widget.apiClient == null
                  ? Icons.upload_file
                  : Icons.add_location_alt,
              onCta: widget.apiClient == null ? _importFile : _openBuilder,
            )
          : ListView.builder(
              // Clears the Build FAB and the navigation bar, so the last
              // route's star button can scroll out from under both.
              padding: EdgeInsets.fromLTRB(AppInsets.gutter, AppSpace.sm,
                  AppInsets.gutter, fabScrollClearance(context)),
              itemCount: 1 +
                  (emptyAfterFilter ? 1 : routes.length) +
                  (showLoadMore && !emptyAfterFilter ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _discoverStrip(theme, l10n, inList: true),
                      _countRow(theme, l10n,
                          visible: routes.length, total: mergedRoutes.length),
                      // Long-press is the only way into multi-select, so it
                      // needs saying. Suppressed once selecting (the app bar
                      // has taken over the surface) and when nothing on
                      // screen is selectable — only OWNED routes are.
                      if (!_selecting &&
                          routes.any((r) => ownedIds.contains(r.id)))
                        SelectionHint(label: l10n.routesSelectionHint),
                    ],
                  );
                }
                if (emptyAfterFilter && index == 1) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 48),
                    child: Column(
                      children: [
                        Icon(Icons.filter_alt_off,
                            size: 48, color: theme.colorScheme.outline),
                        const SizedBox(height: 12),
                        Text(
                          l10n.routesNoMatch,
                          style: theme.textTheme.bodyLarge,
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _clearFilters,
                          child: Text(l10n.routesClearFilters),
                        ),
                      ],
                    ),
                  );
                }
                final routeIndex = index - 1;
                if (showLoadMore && routeIndex == routes.length) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: _loadingMore
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : OutlinedButton.icon(
                              onPressed: _loadMore,
                              icon: const Icon(Icons.expand_more),
                              label: Text(l10n.routesLoadMore(_kRoutesPageSize)),
                            ),
                    ),
                  );
                }
                final route = routes[routeIndex];
                final isOwned = ownedIds.contains(route.id);
                // Locally-built routes (created via the in-app
                // builder while offline / before the next sync
                // cycle) carry a "Will sync" badge so the user sees
                // their status at a glance. Only OWNED routes can
                // be unsynced — bookmarked rows are server-pulled.
                final isUnsynced = isOwned &&
                    !ownedIds.intersection(_syncedOwnedIds()).contains(route.id);
                final isOfflinePinned =
                    widget.routeStore.isOfflinePinned(route.id);
                final isSelected = _selected.contains(route.id);
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  color: isSelected
                      ? theme.colorScheme.primaryContainer
                      : null,
                  child: ListTile(
                    onLongPress: isOwned && !_selecting
                        ? () => _enterSelection(route.id)
                        : null,
                    // No contentPadding override — use ListTile's
                    // default so the row height matches the History
                    // tab's run-card exactly. Pre-fix, the routes
                    // card was visibly taller than the runs card
                    // because of (a) custom padding, (b) a two-row
                    // subtitle Column with badge chips below. Both
                    // are gone; the badges that matter move into
                    // trailing icons (cloud-upload + bookmark) or
                    // a tiny title-prefix glyph (public globe).
                    leading: route.waypoints.length >= 2 && widget.apiClient != null
                        ? SizedBox(
                            // Match the History tab's run-row leading
                            // (`runs_screen.dart:_kLeadingWidth = 72`,
                            // height: 40). Pinned in source so both
                            // list pages feel like a single design
                            // system.
                            width: 72,
                            height: 40,
                            // Bookmarked rows are owned by other users — must
                            // route through clip_route_for_viewer for non-owner
                            // viewers (decisions §33). Owner branch in
                            // RouteTrackPreview short-circuits to the raw row
                            // waypoints, so owned rows still render directly.
                            child: RouteTrackPreview(
                              routeId: route.id,
                              waypoints: route.waypoints,
                              ownerUserId: route.userId,
                              api: widget.apiClient!,
                            ),
                          )
                        : SizedBox(
                            width: 56,
                            height: 40,
                            child: CircleAvatar(
                              backgroundColor:
                                  theme.colorScheme.secondaryContainer,
                              child: Icon(
                                isOwned ? Icons.route : Icons.bookmark,
                                color: theme.colorScheme.secondary,
                              ),
                            ),
                          ),
                    // Title row mirrors runs' `Row(activity icon +
                    // distance)` shape — a small glyph + the name,
                    // single line. Public routes get a globe glyph
                    // so the visibility state stays visible without
                    // adding a second subtitle row.
                    title: Row(
                      children: [
                        if (route.isPublic) ...[
                          Icon(
                            Icons.public,
                            size: 16,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 6),
                        ],
                        Flexible(
                          child: Text(
                            route.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    // Same shape as runs' `$date  •  $dur`. Distance +
                    // elevation is the route equivalent; each figure stays
                    // glued to its unit when a raised text scale wraps it.
                    subtitle: Text(routeStatsLine(route, unit)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Bookmark glyph for routes the viewer
                        // saved from someone else (not their own).
                        // Mirrors the runs-row's `isUnsynced` icon
                        // pattern — small inline glyph that flags
                        // ownership without adding a subtitle row.
                        if (!isOwned) ...[
                          Icon(
                            Icons.bookmark_outline,
                            size: 16,
                            color: theme.colorScheme.outline,
                          ),
                          const SizedBox(width: 4),
                        ],
                        // Will-sync indicator for locally-built
                        // routes that haven't been pushed to the
                        // cloud yet. Same affordance the runs list
                        // uses for `isUnsynced` (cloud_off there;
                        // cloud_upload_outlined here because the
                        // semantic is "queued to upload" rather than
                        // "couldn't be uploaded").
                        if (isUnsynced) ...[
                          Tooltip(
                            message: l10n.routesQueuedToSync,
                            child: Icon(
                              Icons.cloud_upload_outlined,
                              size: 16,
                              color: theme.colorScheme.tertiary,
                            ),
                          ),
                          const SizedBox(width: 4),
                        ],
                        if (isOfflinePinned) ...[
                          Tooltip(
                            message: l10n.routesSavedForOffline,
                            child: Icon(
                              Icons.download_done,
                              size: 16,
                              color: AppSemanticColors.of(context).success,
                            ),
                          ),
                          const SizedBox(width: 4),
                        ],
                        if (isOwned)
                          IconButton(
                            icon: Icon(
                              route.isStarred ? Icons.star : Icons.star_border,
                              color: route.isStarred
                                  ? AppSemanticColors.of(context).crown
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                            tooltip: route.isStarred
                                ? l10n.routesUnstarRoute
                                : l10n.routesStarForWatch,
                            onPressed: () => _toggleStar(route),
                          ),
                      ],
                    ),
                    onTap: () async {
                      if (_selecting) {
                        if (!isOwned) return;
                        _toggleSelection(route.id);
                        return;
                      }
                      await Navigator.push<void>(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => RouteDetailScreen(
                            route: route,
                            routeStore: widget.routeStore,
                            preferences: widget.preferences,
                            apiClient: widget.apiClient,
                            isOwner: isOwned,
                          ),
                        ),
                      );
                      // Refresh bookmarks so unbookmarks made on the
                      // detail screen flow back into the list.
                      _fetchBookmarks();
                    },
                  ),
                );
              },
            );

    // The "Discover" strip (Public routes / Routes heatmap / Run heatmap) is
    // the single home of every map/discovery entry point: icon-only actions
    // proved undiscoverable (field reports for both heatmaps). With routes on
    // screen it heads the list and scrolls away with it; over the empty and
    // error states it stays put.
    return HubTabBody(
      title: l10n.fitnessRunsRoutes,
      actions: _routeActions(l10n),
      primary: _primaryAction(l10n),
      filters: mergedRoutes.isEmpty ? null : _filterBar(theme, l10n),
      selection: _selecting
          ? _selectionBar(visible: routes, ownedIds: ownedIds)
          : null,
      banner:
          mergedRoutes.isEmpty ? _discoverStrip(theme, l10n, inList: false) : null,
      // The list never refreshed on its own: a stale cache stayed stale with
      // no way to ask again (issue #1374 FS-5).
      onRefresh: _refresh,
      body: body,
    );
  }

  Future<void> _refresh() =>
      Future.wait([_fetchRemoteRoutes(), _fetchBookmarks()]);

  void _setSurface(_SurfaceFilter v) {
    setState(() {
      _surfaceFilter = v;
      _visibleCount = _kRoutesPageSize;
    });
    _persistFilters();
  }

  void _setDistance(_DistanceBucket v) {
    setState(() {
      _distanceFilter = v;
      _visibleCount = _kRoutesPageSize;
    });
    _persistFilters();
  }

  void _setSort(_RouteSort v) {
    setState(() {
      _sort = v;
      _visibleCount = _kRoutesPageSize;
    });
    _persistFilters();
  }

  void _toggleStarredOnly() {
    final turningOn = !_starredOnly;
    setState(() {
      _starredOnly = turningOn;
      _visibleCount = _kRoutesPageSize;
    });
    _persistFilters();
    if (turningOn) _ensureStarredLoaded();
  }

  /// Search, the Starred chip (the most-toggled filter), and Filters for
  /// surface, distance and sort, whose non-default values show as removable
  /// chips on the same line. Mirrors the web `/routes` toolbar's set.
  FilterBar _filterBar(ThemeData theme, AppLocalizations l10n) {
    ActiveFilter active(String label, VoidCallback onRemove) => ActiveFilter(
          label: label,
          onRemove: onRemove,
          removeTooltip: l10n.filterBarRemoveFilter(label),
        );
    final filters = [
      if (_surfaceFilter != _SurfaceFilter.any)
        active(_surfaceLabel(l10n, _surfaceFilter),
            () => _setSurface(_SurfaceFilter.any)),
      if (_distanceFilter != _DistanceBucket.any)
        active(_distanceLabel(l10n, _distanceFilter),
            () => _setDistance(_DistanceBucket.any)),
      if (_sort != _RouteSort.newest)
        active(_sortLabel(l10n, _sort), () => _setSort(_RouteSort.newest)),
    ];
    return FilterBar(
      key: const ValueKey('routes-filter-bar'),
      search: AppSearchField(
        controller: _searchCtl,
        hint: l10n.routesSearchHint,
        clearTooltip: l10n.routesClearSearch,
        onChanged: (v) {
          setState(() {
            _search = v;
            _visibleCount = _kRoutesPageSize;
          });
          _persistFilters();
        },
      ),
      chips: [
        FilterChip(
          label: Text(l10n.routesStarred),
          avatar: Icon(
            _starredOnly ? Icons.star : Icons.star_border,
            size: 18,
            color: _starredOnly
                ? AppSemanticColors.of(context).crown
                : theme.colorScheme.onSurfaceVariant,
          ),
          selected: _starredOnly,
          onSelected: (_) => _toggleStarredOnly(),
        ),
      ],
      activeFilters: filters,
      filtersLabel: l10n.filterBarFilters,
      filtersSemanticLabel:
          filters.isEmpty ? null : l10n.filterBarFiltersCount(filters.length),
      activeFilterCount: filters.length,
      onOpenFilters: _openFilters,
    );
  }

  Future<void> _openFilters() {
    final l10n = AppLocalizations.of(context);
    return showFilterSheet(
      context: context,
      title: l10n.filterBarFilters,
      doneLabel: l10n.filterBarDone,
      builder: (sheetContext, setSheet) {
        final theme = Theme.of(sheetContext);
        Widget group<T>(String heading, List<T> values, T selected,
                String Function(T) label, ValueChanged<T> onPick) =>
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
                        for (final v in values)
                          ChoiceChip(
                            label: Text(label(v)),
                            selected: v == selected,
                            onSelected: (_) {
                              onPick(v);
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
            group(l10n.filterBarSurface, _SurfaceFilter.values,
                _surfaceFilter, (v) => _surfaceLabel(l10n, v), _setSurface),
            group(l10n.filterBarDistance, _DistanceBucket.values,
                _distanceFilter, (v) => _distanceLabel(l10n, v), _setDistance),
            group(l10n.filterBarSort, _RouteSort.values, _sort,
                (v) => _sortLabel(l10n, v), _setSort),
          ],
        );
      },
    );
  }

  /// "Showing n of m" under the Discover strip, with Clear filters while any
  /// filter or search narrows the list.
  Widget _countRow(ThemeData theme, AppLocalizations l10n,
          {required int visible, required int total}) =>
      Padding(
        padding: const EdgeInsets.only(top: AppSpace.sm, bottom: AppSpace.xs),
        child: Row(
          children: [
            Expanded(
              child: Text(
                l10n.routesCountMeta(visible, total),
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (_filtersActive())
              TextButton(
                onPressed: _clearFilters,
                child: Text(l10n.routesClearFilters),
              ),
          ],
        ),
      );

  /// The "Discover" strip: the labelled discovery entry points — Public
  /// routes, the community routes heatmap (discoverable-route + club pins)
  /// and the user's own run heatmap — as one row of equal tiles, icon over
  /// label.
  ///
  /// One row at every width and text scale. As chips that wrapped, the three
  /// stacked into three full-width pills on a phone at a raised text scale and
  /// pushed the list half a screen down; as a sideways scroll they gave no edge
  /// cue and "Run heatmap" was never seen (decisions § 1954). A tile's label
  /// takes a second line instead. Each stays labelled, because icon-only AppBar
  /// actions proved undiscoverable for both heatmaps. "Discover" names the
  /// strip for assistive tech rather than spending a row.
  Widget _discoverStrip(ThemeData theme, AppLocalizations l10n,
      {required bool inList}) {
    final api = widget.apiClient;
    final tiles = <Widget>[
      _DiscoverTile(
        icon: Icons.explore,
        label: l10n.routesPublicRoutes,
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ExploreRoutesScreen(
              apiClient: widget.apiClient,
              routeStore: widget.routeStore,
              preferences: widget.preferences,
            ),
          ),
        ),
      ),
      if (api != null) ...[
        // The two heatmaps sit side by side, so both labels carry their
        // qualifier ("Routes" = community discoverable-route + club pins;
        // "Run" = the user's own tracks) — a bare "Heatmap" next to a
        // sibling heatmap says nothing.
        _DiscoverTile(
          icon: Icons.local_fire_department,
          label: l10n.routesHeatmapTooltip,
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => RoutesHeatmapScreen(api: api),
            ),
          ),
        ),
        _DiscoverTile(
          icon: Icons.person_pin_circle_outlined,
          label: l10n.runHeatmapTooltip,
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => RunHeatmapScreen(
                api: api,
                runStore: widget.runStore,
              ),
            ),
          ),
        ),
      ],
    ];

    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: l10n.routesDiscover,
      child: Padding(
        // In the list the ListView's own 16 dp gutter applies.
        padding: inList
            ? EdgeInsets.zero
            : const EdgeInsets.fromLTRB(16, 4, 16, 0),
        child: IntrinsicHeight(
          child: Row(
            key: const ValueKey('routes-discover-strip'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < tiles.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(child: tiles[i]),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Import (when Build is the primary action) and the cloud sync, at the
  /// end of the control row.
  List<Widget> _routeActions(AppLocalizations l10n) => [
        if (widget.apiClient != null)
          IconButton(
            key: const ValueKey('routes-import-action'),
            icon: const Icon(Icons.upload_file),
            tooltip: l10n.routesImport,
            onPressed: _fabBusy ? null : _importFile,
          ),
        if (_syncing)
          const SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else if (widget.apiClient?.userId != null)
          IconButton(
            icon: const Icon(Icons.cloud_download),
            tooltip: l10n.routesSyncFromCloud,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            onPressed: _fetchRemoteRoutes,
          ),
      ];

  /// Build, with Import among the actions. Without an api client there is
  /// nothing to build against, so Import is the primary action.
  PrimaryAction _primaryAction(AppLocalizations l10n) => widget.apiClient ==
          null
      ? PrimaryAction(
          label: l10n.routesImport,
          icon: Icons.upload_file,
          onPressed: _fabBusy ? null : _importFile,
        )
      : PrimaryAction(
          label: l10n.routesBuild,
          icon: Icons.add_location_alt,
          onPressed: _fabBusy ? null : _openBuilder,
        );
}

/// One Discover entry: a labelled, outlined tile whose label may take a
/// second line, so three fit one row on a narrow phone at a raised scale.
class _DiscoverTile extends StatelessWidget {
  const _DiscoverTile({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        minimumSize: const Size(0, kMinInteractiveDimension),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

double _shownM(cm.Route r) =>
    routeDisplayDistanceM(r.distanceMetres, r.officialDistanceMetres);

/// A route card's stats line, "26.48 mi  •  751 ft ↑", in the reader's unit.
///
/// Every space inside a figure is non-breaking, so a raised text scale wraps
/// the line between the two figures and never between a number and its unit.
@visibleForTesting
String routeStatsLine(cm.Route route, cm.DistanceUnit unit) {
  String glued(String s) => s.replaceAll(' ', '\u00A0');
  return '${glued(UnitFormat.distance(_shownM(route), unit))}'
      '  •  ${glued('${UnitFormat.elevation(route.elevationGainMetres, unit)} ↑')}';
}

String _surfaceLabel(AppLocalizations l10n, _SurfaceFilter v) => switch (v) {
      _SurfaceFilter.any => l10n.routesSurfaceAny,
      _SurfaceFilter.road => l10n.routesSurfaceRoad,
      _SurfaceFilter.trail => l10n.routesSurfaceTrail,
      _SurfaceFilter.mixed => l10n.routesSurfaceMixed,
    };

// Distance-bucket labels stay raw — the km/mi thresholds are numeric
// formatting owned by Epic C, not UI copy.
String _distanceLabel(AppLocalizations l10n, _DistanceBucket v) => switch (v) {
      _DistanceBucket.any => l10n.routesDistanceAny,
      _DistanceBucket.lt5 => '< 5 km',
      _DistanceBucket.t5to10 => '5–10 km',
      _DistanceBucket.t10to20 => '10–20 km',
      _DistanceBucket.gt20 => '20+ km',
    };

String _sortLabel(AppLocalizations l10n, _RouteSort v) => switch (v) {
      _RouteSort.newest => l10n.routesSortNewest,
      _RouteSort.longest => l10n.routesSortLongest,
      _RouteSort.shortest => l10n.routesSortShortest,
      _RouteSort.mostRun => l10n.routesSortMostRun,
      _RouteSort.az => l10n.routesSortAlpha,
    };

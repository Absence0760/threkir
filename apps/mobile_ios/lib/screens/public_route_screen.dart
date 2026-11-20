import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' as cm;
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart'
    show AppBarAction, DetailHero, DetailPage, StatGrid, StatTile;

import '../auth_error.dart';
import '../l10n/gen/app_localizations.dart';
import '../detail_map_height.dart';
import '../fab_clearance.dart';
import '../main.dart' show pendingStartRunWithRoute;
import '../official_distance.dart';
import '../preferences.dart';
import '../widgets/error_state.dart';
import '../widgets/live_run_map.dart';
import '../widgets/route_conditions.dart';
import '../widgets/route_photos.dart';
import '../widgets/segments_panel.dart';
import '../widgets/shared_with_you_chip.dart';
import '../widgets/top_banner.dart';
import '../widgets/loading_skeletons.dart';

/// Build the route a public / shared route starts a run against — carrying
/// the CLIPPED display waypoints the viewer is allowed to see, never the
/// source route's full trace (which may run through the owner's privacy
/// zones). Shared with a park course's Run this course, and unit-testable
/// without the map-bearing screen.
cm.Route publicRouteStartTarget(cm.Route source, List<cm.Waypoint> clipped) {
  return cm.Route(
    id: source.id,
    name: source.name,
    waypoints: clipped,
    distanceMetres: source.distanceMetres,
    officialDistanceMetres: source.officialDistanceMetres,
    userId: source.userId,
    elevationGainMetres: source.elevationGainMetres,
    isPublic: source.isPublic,
    surface: source.surface,
  );
}

/// A route as [viewer] may see it: the row, and the waypoints to draw and to
/// run against. The owner gets the full line; anyone else gets it through
/// `clipRouteForViewer`, which checks visibility server-side and cuts out the
/// owner's privacy zones (decisions §33). Shared by this screen and a park
/// course's Run this course, so both start a run on the same line.
Future<({cm.Route? route, List<cm.Waypoint> waypoints, bool isOwner})>
    loadViewableRoute(ApiClient api, String routeId) async {
  final fetched = await api.fetchRouteById(routeId);
  final route = fetched.route;
  if (route == null) {
    return (route: null, waypoints: const <cm.Waypoint>[], isOwner: false);
  }
  // Anon (`api.userId == null`) is a non-owner, so a signed-out viewer also
  // gets the clipped line. Three explicit branches, not an
  // `(isOwner || waypoints.isEmpty)` short-circuit: a later change that fills
  // `route.waypoints` for non-owners on the empty branch must not bypass
  // `clipRouteForViewer` (audit:privacy-zones 2026-05-25). It fails closed,
  // returning [] on an outage, so a blip draws an empty line rather than the
  // owner's start or finish.
  final viewerId = api.userId;
  final ownerId = fetched.ownerId;
  final isOwner = viewerId != null && ownerId != null && viewerId == ownerId;
  final List<cm.Waypoint> waypoints;
  if (isOwner) {
    waypoints = route.waypoints;
  } else if (route.waypoints.isEmpty) {
    waypoints = const [];
  } else {
    waypoints = await api.clipRouteForViewer(routeId);
  }
  return (route: route, waypoints: waypoints, isOwner: isOwner);
}

/// Read-only non-owner view of a single route. Mirrors the web
/// `/share/route/[id]` route for a public route, and the non-owner branch of
/// `/routes/[id]` for a club route or one shared with the viewer through its
/// owner's followers level or a named-person grant (decisions § 1874).
/// Anything else falls through to a "not available" empty state via RLS.
class PublicRouteScreen extends StatefulWidget {
  final ApiClient api;
  final String routeId;

  const PublicRouteScreen({
    super.key,
    required this.api,
    required this.routeId,
  });

  @override
  State<PublicRouteScreen> createState() => _PublicRouteScreenState();
}

class _PublicRouteScreenState extends State<PublicRouteScreen> {
  bool _loading = true;
  Object? _loadError;
  cm.Route? _route;
  List<cm.Waypoint> _waypoints = const [];
  bool _isOwner = false;
  bool? _bookmarked;
  bool _bookmarkBusy = false;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final viewable = await loadViewableRoute(widget.api, widget.routeId);
      final route = viewable.route;
      final waypoints = viewable.waypoints;
      final isOwner = viewable.isOwner;
      if (route == null) {
        if (!mounted) return;
        setState(() {
          _route = null;
          _waypoints = const [];
          _loading = false;
        });
        return;
      }
      if (!mounted) return;
      setState(() {
        _route = route;
        _waypoints = waypoints;
        _isOwner = isOwner;
        _loading = false;
      });
      // A non-owner viewer can save (bookmark) the route to their library —
      // load the current bookmark state (best-effort) so the AppBar action
      // reflects reality on first paint.
      if (!isOwner && widget.api.userId != null) _loadBookmarkState();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e;
        _loading = false;
      });
    }
  }

  Future<void> _loadBookmarkState() async {
    try {
      final saved = await widget.api.isRouteBookmarked(widget.routeId);
      if (!mounted) return;
      setState(() => _bookmarked = saved);
    } catch (e) {
      debugPrint('public route isRouteBookmarked failed: $e');
    }
  }

  Future<void> _toggleBookmark() async {
    if (_bookmarkBusy || widget.api.userId == null) return;
    final l10n = AppLocalizations.of(context);
    final before = _bookmarked ?? false;
    setState(() {
      _bookmarkBusy = true;
      _bookmarked = !before;
    });
    try {
      if (before) {
        await widget.api.unbookmarkRoute(widget.routeId);
      } else {
        await widget.api.bookmarkRoute(widget.routeId);
      }
    } catch (e) {
      debugPrint('public route bookmark failed: $e');
      if (!mounted) return;
      setState(() => _bookmarked = before);
      showTopBanner(
          context, l10n.routeDetailBookmarkFailed(friendlyError(l10n, e)));
    } finally {
      if (mounted) setState(() => _bookmarkBusy = false);
    }
  }

  void _startRun(cm.Route route) {
    // Hand off through the global notifier — HomeScreen switches to the
    // recorder with the route preselected and pops back to the shell, so a
    // follower who opened a shared / public route can run it without owning
    // it. Carry the CLIPPED display waypoints (never the owner's full trace).
    pendingStartRunWithRoute.value = publicRouteStartTarget(route, _waypoints);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final route = _route;
    final canStartRun = route != null && _waypoints.length >= 2;
    // Save (bookmark) is offered to a signed-in viewer who doesn't own the
    // route — owners already have it, signed-out viewers can't have a
    // library. Starting a run needs no sign-in (offline recording is fine).
    final canBookmark =
        route != null && !_isOwner && widget.api.userId != null;
    return DetailPage(
      title: route?.name ?? l10n.publicRouteFallbackTitle,
      actions: [
        if (canBookmark)
          AppBarAction(
            icon: Icon(
              (_bookmarked ?? false) ? Icons.bookmark : Icons.bookmark_border,
            ),
            label: (_bookmarked ?? false)
                ? l10n.routeDetailRemoveBookmark
                : l10n.routeDetailBookmarkRoute,
            onPressed: _bookmarkBusy ? null : _toggleBookmark,
          ),
      ],
      floatingActionButtonLocation: pageFabLocation(context),
      floatingActionButton: canStartRun
          ? FloatingActionButton.extended(
              heroTag: 'public_route_start_run',
              onPressed: () => _startRun(route),
              icon: const Icon(Icons.play_arrow),
              label: Text(
                l10n.routeDetailStartRun,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            )
          : null,
      body: _loading
          ? MapDetailSkeleton(label: l10n.commonLoading)
          : _loadError != null
              ? AppErrorState(
                  message: l10n.publicRouteLoadError, onRetry: _load)
              : _route == null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          l10n.publicRouteUnavailable,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, viewport) =>
                          _buildBody(theme, _route!, viewport.maxHeight),
                    ),
    );
  }

  Widget _buildBody(ThemeData theme, cm.Route route, double viewportHeight) {
    final l10n = AppLocalizations.of(context);
    // Web's derivation: neither the viewer's, public, nor a club route, so it
    // can only have come through `shared_routes`.
    final sharedWithMe = !_isOwner && !route.isPublic && route.clubId == null;
    return ListView(
      controller: _scrollController,
      children: [
        SizedBox(
          height: detailMapHeight(viewportHeight),
          child: LiveRunMap(
            track: const [],
            plannedRoute: _waypoints,
            followRunner: false,
          ),
        ),
        DetailHero(
          title: route.name,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        ),
        if (sharedWithMe)
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: SharedWithYouChip(),
            ),
          ),
        if (route.description != null && route.description!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Text(
              route.description!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: StatGrid(
            cells: [
              StatTile.large(
                label: route.officialDistanceMetres != null
                    ? l10n.routeDetailStatOfficialDistance
                    : l10n.publicRouteStatDistance,
                value: UnitFormat.distanceValue(
                    routeDisplayDistanceM(
                        route.distanceMetres, route.officialDistanceMetres),
                    activeDistanceUnit),
                unit: UnitFormat.distanceLabel(activeDistanceUnit),
              ),
              if (route.officialDistanceMetres != null)
                StatTile.large(
                  label: l10n.routeDetailStatMeasured,
                  value: UnitFormat.distanceValue(
                      route.distanceMetres, activeDistanceUnit),
                  unit: UnitFormat.distanceLabel(activeDistanceUnit),
                ),
              StatTile.large(
                label: l10n.publicRouteStatElevation,
                value: UnitFormat.elevationValue(
                    route.elevationGainMetres, activeDistanceUnit),
                unit: UnitFormat.elevationLabel(activeDistanceUnit),
              ),
              if (_waypoints.isNotEmpty)
                StatTile.large(
                  label: l10n.publicRouteStatWaypoints,
                  value: '${_waypoints.length}',
                ),
            ],
          ),
        ),
        if (widget.api.userId != null)
          SegmentsPanel(
            api: widget.api,
            routeId: route.id,
            routeDistanceM: route.distanceMetres,
            canCreate: false,
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: RoutePhotos(
            api: widget.api,
            routeId: route.id,
            routeOwnerId: route.userId,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: RouteConditions(
            api: widget.api,
            routeId: route.id,
            routeOwnerId: route.userId,
          ),
        ),
        SizedBox(height: fabScrollClearance(context)),
      ],
    );
  }
}


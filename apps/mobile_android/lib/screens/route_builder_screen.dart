import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' as cm;
import 'package:core_models/core_models.dart' show DistanceUnit;
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:ui_kit/ui_kit.dart'
    show
        AppMotion,
        AppSemanticColors,
        ChoiceChipOption,
        ChoiceChipRow,
        ListCard,
        MapFirstPage,
        SheetScaffold,
        syncMotionLoop;
import 'package:uuid/uuid.dart';

import '../auth_error.dart';
import '../elevation.dart';
import '../geocoding.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../l10n/number_format.dart';
import '../local_route_store.dart';
import '../preferences.dart';
import '../quiet_location.dart';
import '../rate_limit_errors.dart';
import '../rate_limit_message.dart';
import '../route_art.dart';
import '../route_loop.dart';
import '../route_overlap.dart';
import '../routing.dart';
import '../social_service.dart';
import '../run_stats.dart' show haversineMetres;
import '../typed_decimal.dart';
import '../widgets/app_bar_actions.dart';
import '../widgets/confirm_destructive.dart';
import '../widgets/confirm_discard.dart';
import '../widgets/live_run_map.dart'
    show
        basemapTileLayer,
        basemapVoidColour,
        currentBasemapIsDark,
        currentTileUrl,
        mapDraftLine,
        mapOverlapLine,
        solidMapLine;
import '../widgets/map_attribution.dart';
import '../widgets/snap_to_start.dart';
import '../widgets/top_banner.dart';
import '../widgets/place_search_panel.dart';

/// Full-screen in-app route builder. Phase 3 "In-app route builder
/// (free)" — the mobile counterpart of `apps/web/src/lib/components/
/// RouteBuilder.svelte`.
///
/// Shipped features:
/// - tap-to-place waypoints, OSRM-snapped (foot / car) or straight
/// - long-press a waypoint to drag-reshape — pan to move, release to
///   commit + re-fetch the snapped polyline
/// - tap near the start (when 3+ waypoints placed) snaps the loop closed
///   and shows a pulsing halo on the start marker as the affordance
/// - "Locate me" FAB centers on the user's current GPS position
/// - place-name search in the AppBar — debounced MapTiler geocoding,
///   tap a result to fly the camera there
/// - elevation gain in the status pill, sampled at up to 100 points per
///   re-route via Open-Meteo
/// - out-and-back overlap is rendered as a purple over-stroke on the
///   retraced sections
/// - undo / clear / save (name + public toggle → ApiClient.saveRoute
///   + LocalRouteStore.save, then pops with the new route)
///
/// Pure helpers (`routing.dart`, `elevation.dart`, `geocoding.dart`,
/// `route_overlap.dart`, `widgets/snap_to_start.dart`) are unit-tested
/// in isolation; this screen is the integration glue.
class RouteBuilderScreen extends StatefulWidget {
  final ApiClient apiClient;
  final LocalRouteStore routeStore;
  final LatLng? initialCenter;

  /// Optional social service for fetching the user's clubs. When
  /// provided, the SaveRouteDialog renders a "Save to" picker so a
  /// route can be created against a club library directly. Mirrors
  /// web's `?club=<id>` URL parameter on `/routes/new` plus a
  /// dropdown — mobile lacks an equivalent URL surface, so the
  /// picker is the universal entry point regardless of where the
  /// builder was launched from.
  final SocialService? social;

  /// Optional pre-selected club. When non-null, the SaveRouteDialog
  /// opens with this club already chosen in the "Save to" picker —
  /// the equivalent of landing on `/routes/new?club=<id>` on web.
  /// The user can still switch to Personal or a different club from
  /// the picker; nothing is locked.
  final String? initialClubId;

  /// Test seams — production passes null and each helper uses its
  /// dart:io fetcher / OS geolocator default.
  final OsrmFetcher? osrmFetcher;
  final ElevationFetcher? elevationFetcher;
  final GeocodingFetcher? geocodingFetcher;
  final Future<void> Function(cm.Route route)? saveRouteFn;
  final Future<Position> Function()? locateFn;

  /// Test seam for the fixes the builder centres on when it opens. Production
  /// passes null and reads [quietPositionFixes], which never prompts.
  @visibleForTesting
  final Stream<Position> Function()? initialFixesFn;

  /// Test seam — when non-null, [_loadClubs] reads from this instead
  /// of calling into [social]. Lets widget tests drive the dialog's
  /// club picker without booting a real SocialService / Supabase.
  final Future<List<RouteClubChoice>> Function()? clubChoicesLoader;

  /// Test seam — overrides [isOsrmSnapAvailable] so a widget test can
  /// exercise the degraded (no road-snapping) path without a release
  /// build. Production passes null.
  @visibleForTesting
  final bool? snapAvailableOverride;

  const RouteBuilderScreen({
    super.key,
    required this.apiClient,
    required this.routeStore,
    this.initialCenter,
    this.social,
    this.initialClubId,
    this.osrmFetcher,
    this.elevationFetcher,
    this.geocodingFetcher,
    this.saveRouteFn,
    this.locateFn,
    this.initialFixesFn,
    this.clubChoicesLoader,
    this.snapAvailableOverride,
  });

  @override
  State<RouteBuilderScreen> createState() => _RouteBuilderScreenState();
}

class _RouteBuilderScreenState extends State<RouteBuilderScreen> {
  final MapController _map = MapController();

  // Where the camera opens, decided once before the first frame so the map
  // never shows one place and then jumps to another it already knew about.
  late final ({LatLng centre, double zoom}) _opening = _openingCamera();

  // Set by anything that puts the camera where the runner wants it — a pan,
  // a search result, the Locate button, a placed waypoint — after which a
  // late on-open fix must not drag it away.
  bool _cameraClaimed = false;
  bool _mapReady = false;
  LatLng? _pendingFix;
  StreamSubscription<Position>? _openingFixes;

  // Waypoint + polyline state.
  final List<cm.Waypoint> _waypoints = [];
  List<cm.Waypoint> _polyline = const [];
  double _distanceM = 0;
  double _elevationGainM = 0;
  List<OverlapSpan> _overlapSpans = const [];

  // Draw mode (route art, decisions § 2263): a drag on the map draws a
  // shape that is matched to roads and paths instead of panning.
  bool _drawing = false;
  final List<LatLng> _stroke = [];
  Offset? _lastStrokeOffset;

  /// The score of the last drawing matched, kept until the route stops
  /// being that drawing.
  ArtFidelity? _artFidelity;

  // Mode toggle + in-flight flags.
  RouteBuilderMode _mode = RouteBuilderMode.trail;
  bool _routing = false;
  bool _saving = false;

  /// Whether OSRM road-snapping is available in this build. `false` on
  /// a release build with no `OSRM_URL` (the privacy guard forbids the
  /// uncontracted public demo). When false the builder degrades to
  /// straight-line placement so a map tap always drops a pin, instead
  /// of the prod guard throwing out of `snapToRoad` / `fetchRouteThrough`
  /// and silently swallowing the tap (the "trail/road taps do nothing"
  /// bug). Evaluated once — the dotenv value is stable at runtime.
  late final bool _snapAvailable =
      widget.snapAvailableOverride ?? isOsrmSnapAvailable();

  /// Latches after the "snapping unavailable" disclosure shows once.
  bool _snapUnavailableNoted = false;

  /// Placement + routing behave as a straight line whenever the user
  /// picked Straight OR road-snapping is unavailable in this build.
  bool get _effectiveStraight =>
      _mode == RouteBuilderMode.straight || !_snapAvailable;

  /// Disclose — once — that road-snapping is unavailable, so the user
  /// understands why trail/road pins land exactly where tapped and the
  /// line runs straight between them. No-op when snapping works, when
  /// already disclosed, or in a plain Straight-mode session.
  void _maybeNoteSnapUnavailable() {
    if (_snapAvailable ||
        _snapUnavailableNoted ||
        _mode == RouteBuilderMode.straight) {
      return;
    }
    _snapUnavailableNoted = true;
    if (!mounted) return;
    showTopBanner(
      context,
      AppLocalizations.of(context).routeBuilderSnapUnavailable,
    );
  }

  /// Monotonic counter incremented on every `_rerouteThrough` entry.
  /// Each routing pass captures `_routeGeneration` at start, threads
  /// it into `fetchRouteThrough` as a cancellation gate, and drops
  /// its result if the gate fires (which happens whenever the user
  /// places another pin, drags a marker, or hits clear / undo
  /// before the previous routing pass completes). Mirrors web's
  /// `routeVersion` counter on RouteBuilder.svelte.
  int _routeGeneration = 0;

  /// Reused across re-routes so re-snapping after a new pin only fetches
  /// the one new segment, not every prior one. See [RouteSegmentCache].
  final RouteSegmentCache _segmentCache = RouteSegmentCache();

  // Drag state. When the user long-presses a marker, we enter drag
  // mode; subsequent map taps move that waypoint until the user taps
  // the marker again or hits the cancel chip.
  int? _dragIndex;

  // Place search.
  final TextEditingController _searchCtl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  List<PlaceResult> _searchResults = const [];
  // Held apart from an empty result set so the dropdown can say the
  // search FAILED rather than claim the place does not exist.
  bool _searchUnavailable = false;

  /// True while the search TextField is focused — the keyboard is
  /// up. We hide the bottom mode toggle in this state so it doesn't
  /// overlap the search-results dropdown, and condense the AppBar
  /// actions into an overflow menu so the search field gets the
  /// full title width.
  bool _searchFocused = false;
  Timer? _searchDebounce;
  bool _searchOpen = false;

  // Club picker state for the SaveRouteDialog. Loaded in initState so
  // by the time the user finishes building + taps Save the list is
  // already there. Failure is silent — no clubs simply hides the
  // picker, matching the no-SocialService case.
  List<RouteClubChoice> _clubChoices = const [];

  @override
  void initState() {
    super.initState();
    _loadClubs();
    if (widget.initialCenter == null) _centreOnRunner();
    _searchFocus.addListener(() {
      if (!mounted) return;
      setState(() => _searchFocused = _searchFocus.hasFocus);
    });
    // The builder opens in Trail mode; if this build can't snap
    // (release with no OSRM_URL), tell the user up front rather than
    // letting them wonder why pins don't follow roads. Post-frame so
    // the Overlay showTopBanner needs is mounted.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeNoteSnapUnavailable();
    });
  }

  Future<void> _loadClubs() async {
    final loader = widget.clubChoicesLoader ?? _defaultClubsLoader;
    final social = widget.social;
    if (loader == _defaultClubsLoader && social == null) return;
    try {
      final choices = await loader();
      if (!mounted || choices.isEmpty) return;
      setState(() => _clubChoices = choices);
    } catch (e) {
      debugPrint('RouteBuilder._loadClubs failed: $e');
    }
  }

  Future<List<RouteClubChoice>> _defaultClubsLoader() async {
    final social = widget.social;
    if (social == null) return const [];
    final clubs = await social.fetchMyClubs();
    // Only clubs the user is actively a member of can hold routes.
    // Pending memberships and non-member viewers are excluded server-
    // side via RLS, but we filter here too for snappier UX (no
    // dropdown entries that would error on save).
    return [
      for (final c in clubs)
        if (c.isMember && c.viewerStatus == 'active')
          RouteClubChoice(id: c.row.id, name: c.row.name),
    ];
  }

  @override
  void dispose() {
    _openingFixes?.cancel();
    _searchDebounce?.cancel();
    _searchCtl.dispose();
    _searchFocus.dispose();
    _map.dispose();
    super.dispose();
  }

  String get _maptilerKey => dotenv.env['MAPTILER_KEY'] ?? '';

  /// Delegate to the shared `currentTileUrl` helper so the route
  /// builder honours `TILE_URL_TEMPLATE` (local Protomaps dev) the
  /// same way every other mobile map surface does — see
  /// `live_run_map.dart` for the helper, which falls back to OSM
  /// tiles when neither MAPTILER_KEY nor TILE_URL_TEMPLATE is set.
  String get _tileUrl => currentTileUrl(context);

  OsrmProfile get _osrmProfile =>
      _mode == RouteBuilderMode.road ? OsrmProfile.car : OsrmProfile.foot;

  /// Run OSRM through every waypoint + update derived fields
  /// (polyline / distance / elevation / overlap). Pure side-effect
  /// audit/accessibility — WCAG 4.1.3 (Status Messages). Pin
  /// placement / undo / clear / loop-close mutate the route silently
  /// from a screen-reader's view: the distance + waypoint count live
  /// in a `_StatusPill` that updates via `setState` without focus, so
  /// TalkBack never reads the change. `SemanticsService.announce`
  /// pushes a one-shot live-region message. Best-effort: a platform
  /// throw must not break the builder — wrap in try / catch (mirrors
  /// `run_screen._announceA11yState`).
  void _announceA11yState(String message) {
    try {
      SemanticsService.announce(message, TextDirection.ltr);
    } catch (e) {
      debugPrint('SemanticsService.announce failed: $e');
    }
  }

  /// Spoken summary of the current route after a mutation settles —
  /// "3 points, 2.40 km" / "Route cleared".
  void _announceRouteState() {
    final l10n = AppLocalizations.of(context);
    if (_waypoints.isEmpty) {
      _announceA11yState(l10n.routeBuilderRouteCleared);
      return;
    }
    final n = _waypoints.length;
    _announceA11yState(
      l10n.routeBuilderPointsSummary(n, formatDistanceForPref(_distanceM)),
    );
  }

  /// helper called from every mutator (_onMapTap, _undo, drag commit,
  /// snap-to-start close).
  Future<void> _rerouteThrough(List<cm.Waypoint> waypoints) async {
    // Any edit means the route is no longer the drawing that was scored.
    _artFidelity = null;
    _stroke.clear();
    if (_effectiveStraight) {
      setState(() {
        _waypoints
          ..clear()
          ..addAll(waypoints);
        _polyline = List<cm.Waypoint>.from(waypoints);
        _distanceM = straightLineDistance(waypoints);
        _overlapSpans = const [];
      });
      _announceRouteState();
      unawaited(_refreshElevation());
      return;
    }
    if (waypoints.length < 2) {
      setState(() {
        _waypoints
          ..clear()
          ..addAll(waypoints);
        _polyline = const [];
        _distanceM = 0;
        _elevationGainM = 0;
        _overlapSpans = const [];
      });
      _announceRouteState();
      return;
    }
    // Bump the generation on entry; the captured snapshot is the
    // version this pass owns. Any newer pass during our awaits will
    // increment _routeGeneration, the `cancelled` gate will fire,
    // and we'll drop the result on the way back.
    final myGen = ++_routeGeneration;
    setState(() => _routing = true);
    try {
      final routed = await fetchRouteThrough(
        waypoints,
        profile: _osrmProfile,
        fetcher: widget.osrmFetcher,
        cancelled: () => myGen != _routeGeneration,
        cache: _segmentCache,
      );
      if (!mounted) return;
      if (routed.wasCancelled) {
        // A newer pass has started — DON'T touch _polyline /
        // _distanceM / _routing. The newer pass owns those now.
        return;
      }
      setState(() {
        _waypoints
          ..clear()
          ..addAll(waypoints);
        _polyline = routed.coordinates;
        _distanceM = routed.distanceMetres;
        _overlapSpans = detectOverlapSpans(routed.coordinates);
        _routing = false;
      });
      _announceRouteState();
      // Web-parity soft warning: per-segment routing means a
      // single unreachable waypoint falls back to a straight line
      // for that segment but the rest of the polyline stays
      // road-accurate. Surface the partial-success state so the
      // user knows to drag the bad pin.
      if (routed.hadFallbacks && routed.totalSegments > 0) {
        final failed = routed.totalSegments - routed.okSegments;
        showTopBanner(
          context,
          failed == routed.totalSegments
              ? AppLocalizations.of(context).routeBuilderRouteFailedStraightLines
              : AppLocalizations.of(context).routeBuilderSegmentsFailed(failed),
        );
      }
      unawaited(_refreshElevation());
    } catch (e) {
      debugPrint('route builder routing failed: $e');
      if (!mounted) return;
      // Don't surface stale errors from cancelled passes — only the
      // current generation owns the user-visible banner.
      if (myGen != _routeGeneration) return;
      setState(() => _routing = false);
      showTopBanner(
          context, AppLocalizations.of(context).routeBuilderRoutingFailed(friendlyError(AppLocalizations.of(context), e)));
    }
  }

  /// Sample the current polyline and look up open-meteo elevations.
  /// Fire-and-forget — runs after the polyline updates so the user
  /// sees the line + distance immediately and elevation fills in on
  /// the network round-trip (~300 ms). L4 best-effort: a failure just
  /// leaves the gain reading at 0.
  Future<void> _refreshElevation() async {
    if (_polyline.length < 2) {
      if (mounted) setState(() => _elevationGainM = 0);
      return;
    }
    final sample = sampleCoordinates(_polyline);
    try {
      final elevations = await fetchElevations(
        sample,
        // The user is actively drawing this route (OS location granted +
        // an explicit in-app action), which is the consent for the
        // Open-Meteo elevation enrichment (audit/third-party-data-flows).
        consented: true,
        fetcher: widget.elevationFetcher,
      );
      final gain = calculateElevationGain(elevations);
      if (!mounted) return;
      setState(() => _elevationGainM = gain);
    } catch (e) {
      debugPrint('elevation fetch failed: $e');
    }
  }

  Future<void> _onMapTap(TapPosition _, LatLng latLng) async {
    _cameraClaimed = true;
    // Don't gate on `_routing` — the cancellation system in
    // `_rerouteThrough` (gen-counter + `cancelled` gate threaded
    // into fetchRouteThrough) handles overlapping passes correctly,
    // and gating the tap here would make rapid pin placement feel
    // sticky on a slow OSRM call. Still gate on `_saving` because
    // the save-dialog flow shouldn't be racing pin placements.
    if (_saving) return;
    _maybeNoteSnapUnavailable();
    final tapWaypoint =
        cm.Waypoint(lat: latLng.latitude, lng: latLng.longitude);

    // Drag-to-reshape: a marker is currently selected, this tap moves
    // it to the tap point + re-routes.
    if (_dragIndex != null) {
      final idx = _dragIndex!;
      _dragIndex = null;
      final moved = _effectiveStraight
          ? tapWaypoint
          : await snapToRoad(
              tapWaypoint,
              profile: _osrmProfile,
              fetcher: widget.osrmFetcher,
            );
      // Reject a drag that lands within 5 m of any OTHER existing
      // waypoint — the OSRM segment between them would be a
      // zero-length back-and-forth, distorting the polyline and
      // the distance / elevation readouts. Surface the rejection
      // so the user knows the drag didn't take and can retry.
      if (isTooCloseToOtherWaypoints(
        candidate: moved,
        existing: _waypoints,
        excludeIndex: idx,
      )) {
        if (!mounted) return;
        showTopBanner(
          context,
          AppLocalizations.of(context).routeBuilderTooCloseToPin,
        );
        return;
      }
      final next = List<cm.Waypoint>.from(_waypoints);
      next[idx] = moved;
      await _rerouteThrough(next);
      return;
    }

    // Snap-to-start: close the loop instead of placing a stub-end
    // waypoint right next to the start marker. Runs BEFORE the
    // close-to-existing check below — closing the loop on the
    // start is a deliberate UX affordance, not a degenerate
    // placement.
    if (shouldSnapToStart(
      tap: tapWaypoint,
      existingWaypoints: _waypoints,
    )) {
      final next = [..._waypoints, _waypoints.first];
      await _rerouteThrough(next);
      return;
    }

    final next = _effectiveStraight
        ? tapWaypoint
        : await snapToRoad(
            tapWaypoint,
            profile: _osrmProfile,
            fetcher: widget.osrmFetcher,
          );
    // Reject the placement when the new pin (post-snap) would
    // duplicate or near-duplicate an existing one. This catches:
    //   - fat-finger double-taps on the same spot
    //   - a tap visually distinct from the prior pin that
    //     `snapToRoad` pulled onto the same road segment
    // Either way the user's intended action would produce a
    // zero-length OSRM segment that breaks the polyline.
    if (isTooCloseToOtherWaypoints(
      candidate: next,
      existing: _waypoints,
    )) {
      if (!mounted) return;
      showTopBanner(
        context,
        AppLocalizations.of(context).routeBuilderPinAlreadyThere,
      );
      return;
    }
    await _rerouteThrough([..._waypoints, next]);
  }

  Future<void> _undo() async {
    if (_routing || _saving || _waypoints.isEmpty) return;
    final next = _waypoints.sublist(0, _waypoints.length - 1);
    // If the user was dragging the to-be-removed last waypoint,
    // cancel the drag — otherwise `_dragIndex` points at a stale
    // index and the status pill shows "Tap to move point N" for a
    // marker that no longer exists.
    if (_dragIndex == _waypoints.length - 1) {
      setState(() => _dragIndex = null);
    }
    await _rerouteThrough(next);
  }

  /// Remove the currently-dragged waypoint and re-route through the
  /// rest. Surfaced via the trash button in the status pill when a
  /// marker is "lifted" (drag mode active).
  ///
  /// Pre-fix, the only way to remove a specific interior waypoint
  /// was to Undo back to it (losing every later placement) and redo
  /// the rest of the route. With this affordance you can lift the
  /// stray waypoint and delete it in two taps without disturbing
  /// anything else.
  Future<void> _deleteSelectedWaypoint() async {
    if (_saving) return;
    final idx = _dragIndex;
    if (idx == null) return;
    setState(() => _dragIndex = null);
    final next = List<cm.Waypoint>.from(_waypoints)..removeAt(idx);
    await _rerouteThrough(next);
  }

  /// Bottom-sheet list of every waypoint — reorder via drag handle or
  /// delete per row, no map gestures needed. The pins stay the pointer
  /// path (long-press + tap-to-move needs precise pointer work); this
  /// is the accessible / precision alternative, mirroring the web
  /// builder's sidebar waypoint list.
  Future<void> _openWaypointList() async {
    if (_waypoints.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => WaypointListSheet(
        waypoints: List.of(_waypoints),
        onApply: (next) {
          if (_saving) return;
          // A list edit shifts indices — a lifted pin's _dragIndex
          // would point at the wrong waypoint afterwards.
          if (_dragIndex != null) setState(() => _dragIndex = null);
          unawaited(_rerouteThrough(next));
        },
        announce: _announceA11yState,
      ),
    );
  }

  /// Generate a loop by target distance. Ports web's iterative
  /// bisection approach (`apps/web/src/lib/components/
  /// RouteBuilder.svelte:generateLoop`) — the previous mobile
  /// implementation was a single-shot generate-and-hope, which
  /// often produced routes 20-40 % off-target. The user reported
  /// "the generate loop logic is not good, can you copy what the
  /// web app does."
  ///
  /// Algorithm (mirrors web exactly):
  ///   1. Generate radial scaffolding from `centre` with the
  ///      default scale factor + a deterministic per-call radial
  ///      seed.
  ///   2. Route through; measure actual distance.
  ///   3. If within ±15 % of target → done.
  ///   4. Otherwise bisect the scale range and try again. Up to
  ///      4 attempts total.
  ///   5. Track the BEST attempt (closest to target) and keep
  ///      whichever ended closest — OSRM's response is non-
  ///      monotonic in twisty grids and the final attempt isn't
  ///      always the best.
  Future<void> _generateLoop() async {
    if (_routing || _saving) return;
    final centre = _map.camera.center;
    final unit = activeDistanceUnit;
    final picked = await _pickLoopDistance(unit);
    if (picked == null || !mounted) return;
    if (!isValidTargetDistance(picked)) {
      showTopBanner(
          context, AppLocalizations.of(context).routeBuilderTargetTooLong);
      return;
    }

    // Per-call deterministic radial seed so subsequent iterations
    // all share the same starting orientation — bisecting scale
    // with a re-randomised pattern would chase noise.
    final radialSeed =
        DateTime.now().millisecondsSinceEpoch / 1000 % 6.28;
    var scaleFactor = kDefaultScaleFactor;
    var scaleRange = initScaleRange();
    const maxAttempts = 4;

    // Track best attempt across iterations.
    List<cm.Waypoint>? bestWaypoints;
    List<cm.Waypoint>? bestPolyline;
    var bestDistance = double.infinity;
    var bestDelta = double.infinity;

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final seeds = generateLoopWaypoints(
        start: centre,
        targetDistanceMetres: picked,
        scaleFactor: scaleFactor,
        radialSeedRad: radialSeed,
      );
      final next = seeds
          .map((p) => cm.Waypoint(lat: p.latitude, lng: p.longitude))
          .toList();
      // Route through the scaffolding. _rerouteThrough cancels any
      // in-flight previous attempt via the generation counter so
      // concurrent attempts are safe.
      await _rerouteThrough(next);
      if (!mounted) return;
      // Measure actual distance from the resulting polyline.
      final actual = _distanceM;
      if (actual <= 0) break;
      final delta = (picked - actual).abs();
      if (delta < bestDelta) {
        bestDelta = delta;
        bestDistance = actual;
        bestWaypoints = List.of(_waypoints);
        bestPolyline = List.of(_polyline);
      }
      if (isWithinAcceptBand(
        targetDistanceMetres: picked,
        actualDistanceMetres: actual,
      )) {
        break;
      }
      final advised = bisectScale(
        range: scaleRange,
        currentScale: scaleFactor,
        targetDistanceMetres: picked,
        actualDistanceMetres: actual,
      );
      scaleFactor = advised.scale;
      scaleRange = advised.range;
    }

    // If the final attempt drifted away from the best one,
    // restore the best. Mirrors web's post-loop fallback. Local
    // copies so flow analysis can narrow the nullables inside
    // the setState closure.
    final bw = bestWaypoints;
    final bp = bestPolyline;
    if (bw != null && bp != null) {
      final currentDelta = (picked - _distanceM).abs();
      if (bestDelta < currentDelta) {
        setState(() {
          _waypoints
            ..clear()
            ..addAll(bw);
          _polyline = bp;
          _distanceM = bestDistance;
          _overlapSpans = detectOverlapSpans(bp);
        });
        unawaited(_refreshElevation());
      }
    }
  }

  /// Prompt the user for a target distance. Returns metres, or null
  /// if cancelled. The unit picker renders in the user's preferred
  /// unit (km / mi) and converts to metres on confirm.
  Future<double?> _pickLoopDistance(DistanceUnit unit) async {
    // Delegated to a StatefulWidget so the TextEditingController is
    // owned by a state object — its lifecycle is framework-managed
    // (init in initState, freed in dispose). Pre-fix the controller
    // was constructed inline in the dialog builder and disposed
    // manually AFTER `await showDialog` returned; that ordering
    // tripped Flutter's `_dependents.isEmpty` assertion when the
    // user tapped Generate (the controller still had a dangling
    // listener from the popped TextField's deferred disposal).
    return showDialog<double>(
      context: context,
      builder: (ctx) => _GenerateLoopDialog(unit: unit),
    );
  }

  Future<void> _clear() async {
    if (_routing || _saving) return;
    // Confirm before discarding a route the user has actually started — Undo
    // only steps back one waypoint, so a stray Clear tap is total work loss.
    if (_waypoints.length >= 2) {
      final l = AppLocalizations.of(context);
      final ok = await confirmDestructive(
        context,
        title: l.routeBuilderClearConfirmTitle,
        body: l.routeBuilderClearConfirmBody,
        confirmLabel: l.routeBuilderClear,
        cancelLabel: l.routeBuilderCancel,
      );
      if (!ok) return;
    }
    if (!mounted) return;
    _segmentCache.clear();
    _routeGeneration++;
    setState(() {
      _artFidelity = null;
      _stroke.clear();
      _waypoints.clear();
      _polyline = const [];
      _distanceM = 0;
      _elevationGainM = 0;
      _overlapSpans = const [];
      _dragIndex = null;
    });
  }

  Future<void> _save() async {
    if (_polyline.length < 2) {
      showTopBanner(
          context, AppLocalizations.of(context).routeBuilderSaveNeedTwo);
      return;
    }
    final result = await showDialog<SaveDialogResult>(
      context: context,
      builder: (_) => SaveRouteDialog(
        clubChoices: _clubChoices,
        initialClubId: widget.initialClubId,
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _saving = true);
    final route = cm.Route(
      id: const Uuid().v4(),
      // Stamp the signed-in user's id when available so route-detail
      // / share / kudos surfaces that branch on owner-vs-viewer can
      // recognise the freshly-built route as "mine" before the cloud
      // round-trip stamps it server-side. Falls back to '' for
      // signed-out builds (the route still saves locally; the detail
      // screen's empty-ownerId branch picks it up).
      userId: widget.apiClient.userId ?? '',
      name: result.name,
      waypoints: _polyline,
      distanceMetres: _distanceM,
      elevationGainMetres: _elevationGainM,
      isPublic: result.isPublic,
      surface: _surfaceFor(_mode),
      description: result.description,
      clubId: result.clubId,
    );
    // Local-first save. The route lands on disk (unsynced) BEFORE we
    // attempt the cloud push, so a signed-out / offline / Supabase-
    // init-failed state can never lose the route the user just spent
    // a few minutes building. SyncService drains unsynced routes on
    // the next connectivity flap / app foreground / manual Sync chip.
    await widget.routeStore.save(route);

    final cloudSave = widget.saveRouteFn ?? widget.apiClient.saveRoute;
    try {
      await cloudSave(route);
      await widget.routeStore.markRouteSynced(route.id);
      if (!mounted) return;
      Navigator.of(context).pop<cm.Route>(route);
    } catch (e) {
      // Local copy is already on disk — surface a non-blocking note
      // so the user knows it'll sync later, then proceed as if the
      // save succeeded. Beats yelling about a sign-in / network
      // issue at someone who just wants to capture the route they
      // built.
      if (!mounted) return;
      showTopBanner(
        context,
        AppLocalizations.of(context)
            .routeBuilderSavedLocally(formatSaveRouteError(e, context)),
      );
      Navigator.of(context).pop<cm.Route>(route);
    }
  }

  /// The opening camera when the caller names no centre: the start of the
  /// runner's most recent route, else the whole world (the same fallback
  /// web's `RouteBuilder.svelte` uses). Never a fixed city: the builder
  /// opened on London for everyone, and Generate loop, which builds around
  /// the camera centre, then built the loop there.
  ({LatLng centre, double zoom}) _openingCamera() {
    final given = widget.initialCenter;
    if (given != null) return (centre: given, zoom: 14);
    try {
      cm.Route? latest;
      for (final r in widget.routeStore.routes) {
        if (r.waypoints.isEmpty) continue;
        final at = r.createdAt;
        if (latest == null ||
            (at != null &&
                (latest.createdAt == null || at.isAfter(latest.createdAt!)))) {
          latest = r;
        }
      }
      if (latest != null) {
        final w = latest.waypoints.first;
        return (centre: LatLng(w.lat, w.lng), zoom: 14);
      }
    } catch (e) {
      debugPrint('route builder: no recent route to open on: $e');
    }
    return (centre: const LatLng(20, 0), zoom: 2);
  }

  /// Follows the quiet on-open fixes (last known, then fresh) until the
  /// runner takes the camera. Never prompts: the Locate button is the place
  /// that asks.
  void _centreOnRunner() {
    try {
      final fixes = (widget.initialFixesFn ?? quietPositionFixes)();
      _openingFixes = fixes.listen(
        (pos) {
          if (!mounted || _cameraClaimed) return;
          final fix = LatLng(pos.latitude, pos.longitude);
          if (_mapReady) {
            _map.move(fix, 15);
          } else {
            _pendingFix = fix;
          }
        },
        onError: (Object e) =>
            debugPrint('route builder opening fix failed: $e'),
        cancelOnError: true,
      );
    } catch (e) {
      debugPrint('route builder opening fix unavailable: $e');
    }
  }

  void _onMapReady() {
    _mapReady = true;
    final fix = _pendingFix;
    _pendingFix = null;
    if (fix != null && !_cameraClaimed) _map.move(fix, 15);
  }

  Future<void> _locate() async {
    if (_routing || _saving) return;
    _cameraClaimed = true;
    try {
      final pos = widget.locateFn != null
          ? await widget.locateFn!()
          : await locateForBrowse();
      if (!mounted) return;
      _map.move(LatLng(pos.latitude, pos.longitude), 15);
    } catch (e) {
      debugPrint('route builder location unavailable: $e');
      if (!mounted) return;
      showTopBanner(context,
          AppLocalizations.of(context).routeBuilderLocationUnavailable(browseLocateErrorText(AppLocalizations.of(context), e)));
    }
  }

  Future<void> _onSearchChanged(String query) async {
    _searchDebounce?.cancel();
    if (query.trim().length < 2) {
      setState(() {
        _searchResults = const [];
        _searchUnavailable = false;
        _searchOpen = false;
      });
      return;
    }
    _searchDebounce =
        Timer(const Duration(milliseconds: 300), () => _runPlaceSearch(query));
  }

  Future<void> _runPlaceSearch(String query) async {
    final outcome = await searchPlaces(
      query,
      apiKey: _maptilerKey,
      fetcher: widget.geocodingFetcher,
    );
    if (!mounted) return;
    setState(() {
      _searchResults = outcome.results;
      _searchUnavailable = outcome.isUnavailable;
      // Open on an empty result set too: a provider that matched nothing
      // must say so rather than leave the runner staring at a map that
      // did not react.
      _searchOpen = true;
    });
  }

  void _onSearchResultTap(PlaceResult result) {
    _cameraClaimed = true;
    _map.move(LatLng(result.lat, result.lng), 15);
    FocusManager.instance.primaryFocus?.unfocus();
    _searchCtl.clear();
    setState(() {
      _searchResults = const [];
      _searchUnavailable = false;
      _searchOpen = false;
    });
  }

  void _toggleDragOn(int index) {
    if (_saving) return;
    setState(() => _dragIndex = _dragIndex == index ? null : index);
  }

  /// Tap on a marker while a different marker is in drag mode →
  /// move the dragged marker to that marker's exact position.
  /// Skips the 5 m dedupe (the user deliberately chose to place the
  /// dragged marker on top of the tapped one — it's explicit
  /// intent, not a fat-finger accident).
  Future<void> _placeOverMarker(int tappedIndex) async {
    if (_saving) return;
    final draggedIdx = _dragIndex;
    if (draggedIdx == null || draggedIdx == tappedIndex) return;
    // Snapshot the tapped marker's position BEFORE clearing the
    // drag index, then build the new waypoints list with the
    // dragged marker relocated. The 5 m dedupe is intentionally
    // skipped — see method kdoc.
    final target = _waypoints[tappedIndex];
    setState(() => _dragIndex = null);
    final next = List<cm.Waypoint>.from(_waypoints);
    next[draggedIdx] = target;
    await _rerouteThrough(next);
  }

  void _toggleDrawing() {
    setState(() {
      _drawing = !_drawing;
      _dragIndex = null;
    });
  }

  void _onStrokeStart(DragStartDetails d) {
    if (_routing || _saving) return;
    _cameraClaimed = true;
    setState(() {
      _stroke
        ..clear()
        ..add(_map.camera.screenOffsetToLatLng(d.localPosition));
      _lastStrokeOffset = d.localPosition;
    });
  }

  void _onStrokeUpdate(DragUpdateDetails d) {
    final last = _lastStrokeOffset;
    if (last == null) return;
    // A slow drag would otherwise pile up a point per frame.
    if ((d.localPosition - last).distance < 3) return;
    setState(() {
      _stroke.add(_map.camera.screenOffsetToLatLng(d.localPosition));
      _lastStrokeOffset = d.localPosition;
    });
  }

  void _onStrokeEnd(DragEndDetails _) {
    if (_lastStrokeOffset == null) return;
    _lastStrokeOffset = null;
    unawaited(matchDrawing([
      for (final p in _stroke) [p.longitude, p.latitude],
    ]));
  }

  /// Match a drawn stroke (`[lng, lat]` points) to roads and paths, and
  /// adopt it as the route only when it stays close to the drawing. The
  /// drawing stays on the map either way so the runner can compare it with
  /// what the roads allow. Mirrors web's `matchDrawing` in
  /// `RouteBuilder.svelte`.
  @visibleForTesting
  Future<void> matchDrawing(List<List<double>> raw) async {
    final l10n = AppLocalizations.of(context);
    final prepared = prepareStroke(raw);
    if (!prepared.ok) {
      showTopBanner(context, switch (prepared.rejection!) {
        StrokeRejection.tooShort => l10n.routeBuilderDrawTooShort,
        StrokeRejection.tooLong => l10n.routeBuilderDrawTooLong,
        StrokeRejection.tooComplex => l10n.routeBuilderDrawTooComplex,
      });
      return;
    }
    if (!_snapAvailable) {
      showTopBanner(context, l10n.routeBuilderDrawUnavailable);
      return;
    }
    final myGen = ++_routeGeneration;
    final profile = _osrmProfile;
    setState(() {
      _routing = true;
      _artFidelity = null;
      _dragIndex = null;
      _waypoints.clear();
      _polyline = const [];
      _distanceM = 0;
      _elevationGainM = 0;
      _overlapSpans = const [];
    });
    try {
      final parts = <List<List<double>>>[];
      for (final batch in planRouteBatches(prepared.points.length)) {
        final result = await fetchRouteArtBatch(
          prepared.points.sublist(batch.start, batch.end + 1),
          profile: profile,
          fetcher: widget.osrmFetcher,
          cancelled: () => myGen != _routeGeneration,
        );
        if (!mounted || myGen != _routeGeneration) return;
        if (!result.ok) {
          setState(() => _routing = false);
          showTopBanner(
            context,
            result.failure == RouteArtBatchFailure.noRoads
                ? l10n.routeBuilderDrawNoRoads
                : l10n.routeBuilderDrawUnavailable,
          );
          return;
        }
        parts.add(result.line);
      }
      final matched = stitchPolylines(parts);
      final fidelity = drawingFidelity(prepared.points, matched);
      if (fidelity == null || fidelity.score < kRouteArtMinScore) {
        setState(() {
          _routing = false;
          _artFidelity = fidelity;
        });
        showTopBanner(
          context,
          l10n.routeBuilderDrawPoorMatch(fidelity?.score ?? 0),
        );
        return;
      }
      final anchors = artAnchorIndices(matched);
      final pins = [
        for (final i in anchors) cm.Waypoint(lat: matched[i][1], lng: matched[i][0]),
      ];
      // Seed the cache with the matched pieces between pins, so dragging one
      // pin re-routes only its two neighbouring pieces and the rest of the
      // drawing survives.
      final slices = sliceAtAnchors(matched, anchors);
      for (var j = 0; j < slices.length; j++) {
        _segmentCache.seed(
          pins[j],
          pins[j + 1],
          profile,
          [for (final p in slices[j]) cm.Waypoint(lat: p[1], lng: p[0])],
          polylineLengthM(slices[j]),
        );
      }
      final line = [
        for (final p in matched) cm.Waypoint(lat: p[1], lng: p[0]),
      ];
      setState(() {
        _waypoints
          ..clear()
          ..addAll(pins);
        _polyline = line;
        _distanceM = polylineLengthM(matched);
        _overlapSpans = detectOverlapSpans(line);
        _routing = false;
        _artFidelity = fidelity;
      });
      _announceA11yState(l10n.routeBuilderDrawMatch(fidelity.score));
      unawaited(_refreshElevation());
    } catch (e) {
      debugPrint('route builder drawing match failed: $e');
      if (!mounted || myGen != _routeGeneration) return;
      setState(() => _routing = false);
      showTopBanner(context, l10n.routeBuilderDrawUnavailable);
    }
  }

  void _onModeChanged(RouteBuilderMode mode) {
    setState(() => _mode = mode);
    // The polyline's shape depends on the OSRM profile, so a placed route
    // re-routes through its existing waypoints.
    if (_waypoints.length >= 2) {
      unawaited(_rerouteThrough(List.of(_waypoints)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final darkBasemap = currentBasemapIsDark(context);
    final waypointLatLngs = [
      for (final w in _waypoints) LatLng(w.lat, w.lng),
    ];
    final polylineLatLngs = [
      for (final w in _polyline) LatLng(w.lat, w.lng),
    ];
    final overlapLatLngs = _polyline.length >= 2
        ? overlapLatLngsFor(_polyline, _overlapSpans)
        : const <List<LatLng>>[];

    final canUndo = _waypoints.isNotEmpty && !_routing && !_saving;
    final canClear = _waypoints.isNotEmpty && !_routing && !_saving;
    final canGenerate = !_routing && !_saving;
    final canSave = _polyline.length >= 2 && !_routing && !_saving;
    // The list stays usable while routing — _rerouteThrough's
    // generation counter cancels a stale in-flight pass, same as
    // placing another pin mid-route.
    final canListPoints = _waypoints.isNotEmpty && !_saving;
    final scaffold = MapFirstPage(
      appBar: AppBar(
        title: TextField(
          controller: _searchCtl,
          focusNode: _searchFocus,
          onChanged: _onSearchChanged,
          decoration: InputDecoration(
            hintText: l10n.routeBuilderSearchHint,
            border: InputBorder.none,
            prefixIcon: const Icon(Icons.search, size: 20),
          ),
          style: theme.textTheme.bodyLarge,
        ),
        // Ordered by how often a builder reaches for them, so Undo is the one
        // icon that keeps a slot and the rest fold into the overflow. All four
        // used to be toolbar icons, which left the search field a few dp on a
        // 360 dp phone. While the field has focus Undo folds too, so the query
        // being typed gets the width.
        actions: [
          AppBarActions(
            maxVisible: _searchFocused ? 1 : 2,
            actions: [
              AppBarAction(
                icon: const Icon(Icons.undo),
                label: l10n.routeBuilderUndo,
                onPressed: canUndo ? _undo : null,
              ),
              AppBarAction(
                icon: const Icon(Icons.all_inclusive),
                label: l10n.routeBuilderGenerateLoop,
                onPressed: canGenerate ? _generateLoop : null,
              ),
              AppBarAction(
                icon: const Icon(Icons.format_list_numbered),
                label: l10n.routeBuilderPointList,
                onPressed: canListPoints ? _openWaypointList : null,
              ),
              AppBarAction(
                icon: const Icon(Icons.delete_outline),
                label: l10n.routeBuilderClear,
                onPressed: canClear ? _clear : null,
                destructive: true,
              ),
            ],
          ),
          TextButton(
            onPressed: canSave ? _save : null,
            child:
                Text(_saving ? l10n.routeBuilderSaving : l10n.routeBuilderSave),
          ),
        ],
      ),
      // Draw mode takes the drag gestures off the map: one finger draws, and
      // turning the mode off brings panning back.
      map: Stack(
        fit: StackFit.expand,
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              backgroundColor: basemapVoidColour(darkBasemap: darkBasemap),
              initialCenter: _opening.centre,
              initialZoom: _opening.zoom,
              minZoom: 3,
              maxZoom: 22,
              onTap: _onMapTap,
              onMapReady: _onMapReady,
              onPositionChanged: (_, hasGesture) {
                if (hasGesture) _cameraClaimed = true;
              },
            ),
            children: [
              basemapTileLayer(
                urlTemplate: _tileUrl,
                maxNativeZoom: 19,
                maxZoom: 22,
              ),
              if (_stroke.length >= 2)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: List.of(_stroke),
                      strokeWidth: 3,
                      color: theme.colorScheme.tertiary,
                      pattern: StrokePattern.dashed(segments: const [8, 6]),
                    ),
                  ],
                ),
              if (polylineLatLngs.length >= 2)
                PolylineLayer(
                  key: const ValueKey('builder-draft-line'),
                  polylines: solidMapLine(
                    polylineLatLngs,
                    mapDraftLine(darkBasemap: darkBasemap),
                  ),
                ),
              if (overlapLatLngs.isNotEmpty)
                PolylineLayer(
                  key: const ValueKey('builder-overlap-line'),
                  polylines: [
                    for (final span in overlapLatLngs)
                      if (span.length >= 2)
                        ...solidMapLine(
                          span,
                          mapOverlapLine(darkBasemap: darkBasemap),
                        ),
                  ],
                ),
              // Waypoint pins. Long-press toggles drag mode for that
              // waypoint; the next map tap moves it.
              if (waypointLatLngs.isNotEmpty)
                MarkerLayer(
                  markers: [
                    for (var i = 0; i < waypointLatLngs.length; i++)
                      Marker(
                        point: waypointLatLngs[i],
                        // Bigger marker hit-box + tap-area for the
                        // marker that's currently being dragged —
                        // makes it obvious where the "lifted" pin is
                        // and easier to tap to drop / cancel.
                        width: _dragIndex == i ? 56 : 36,
                        height: _dragIndex == i ? 56 : 36,
                        child: GestureDetector(
                          // Long-press = pick up this marker (or drop
                          // it if it's already picked up).
                          onLongPress: () => _toggleDragOn(i),
                          // Tap behaviour depends on drag state:
                          //   - no drag active → no-op (clean map
                          //     gestures stay in charge)
                          //   - this marker is dragged → tap drops it
                          //     (cancel-drag affordance)
                          //   - a DIFFERENT marker is dragged → tap
                          //     places the dragged marker at this
                          //     marker's exact position ("place over
                          //     another marker" — the user's
                          //     described intent)
                          onTap: _dragIndex == null
                              ? null
                              : _dragIndex == i
                                  ? () => _toggleDragOn(i)
                                  : () => _placeOverMarker(i),
                          child: _WaypointPin(
                            index: i,
                            total: waypointLatLngs.length,
                            isStart: i == 0,
                            isEnd: i == waypointLatLngs.length - 1 && i > 0,
                            isDragging: _dragIndex == i,
                            pulseStart: i == 0 &&
                                _waypoints.length >= 3 &&
                                _dragIndex == null,
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          ),
          if (_drawing)
            Positioned.fill(
              child: GestureDetector(
                key: const Key('route-builder-draw-surface'),
                behavior: HitTestBehavior.opaque,
                onPanStart: _onStrokeStart,
                onPanUpdate: _onStrokeUpdate,
                onPanEnd: _onStrokeEnd,
              ),
            ),
        ],
      ),
      overlays: [
        // Distance + elevation gain + spinner.
        Padding(
          padding: const EdgeInsets.all(12),
          child: _StatusPill(
            distanceM: _distanceM,
            elevationGainM: _elevationGainM,
            routing: _routing,
            saving: _saving,
            waypointCount: _waypoints.length,
            mode: _mode,
            dragIndex: _dragIndex,
            onCancelDrag: () => setState(() => _dragIndex = null),
            onDeleteDragged: _deleteSelectedWaypoint,
          ),
        ),
        // Search results hang from the app bar, over the status pill.
        if (_searchOpen)
          Material(
            elevation: 4,
            child: PlaceSearchPanel(
              results: _searchResults,
              unavailable: _searchUnavailable,
              onSelect: _onSearchResultTap,
              onRetry: () => _runPlaceSearch(_searchCtl.text),
            ),
          ),
      ],
      // The mode selector shares a row with Locate me, so it cannot grow into
      // it, and the template stands the row and the credit on the system
      // nav bar at any text scale. The selector hides while the search field
      // has focus: the results dropdown hangs from the app bar and the
      // selector used to cover its lower rows.
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_drawing || _artFidelity != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _DrawStatusCard(
                drawing: _drawing,
                fidelity: _artFidelity,
              ),
            ),
          Row(
            children: [
              Expanded(
                child: _searchFocused
                    ? const SizedBox.shrink()
                    : Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: _ModeToggle(
                          mode: _mode,
                          onChanged:
                              _routing || _saving ? null : _onModeChanged,
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              IconButton.filledTonal(
                key: const Key('route-builder-draw-toggle'),
                tooltip: l10n.routeBuilderDrawShape,
                isSelected: _drawing,
                icon: const Icon(Icons.gesture),
                selectedIcon: const Icon(Icons.edit_off),
                onPressed: _routing || _saving ? null : _toggleDrawing,
              ),
              const SizedBox(width: 12),
              FloatingActionButton(
                heroTag: 'route_builder_locate_fab',
                tooltip: l10n.routeBuilderLocateMe,
                onPressed: _routing || _saving ? null : _locate,
                child: const Icon(Icons.my_location),
              ),
            ],
          ),
        ],
      ),
      attribution: MapAttribution(darkBasemap: darkBasemap),
    );
    // Any placed waypoint is unsaved work (Save pops directly after
    // persisting, which bypasses the guard).
    return DiscardGuard(
      isDirty: () => _waypoints.isNotEmpty,
      child: scaffold,
    );
  }
}

/// Available routing profiles surfaced to the user. Maps to
/// [OsrmProfile] for road/trail and bypasses OSRM for straight.
enum RouteBuilderMode { trail, road, straight }

String _modeLabel(AppLocalizations l10n, RouteBuilderMode m) => switch (m) {
      RouteBuilderMode.trail => l10n.routeBuilderModeTrail,
      RouteBuilderMode.road => l10n.routeBuilderModeRoad,
      RouteBuilderMode.straight => l10n.routeBuilderModeStraight,
    };

/// Format the user-visible message for a saveRoute failure. Pure
/// function — extracted so the catch branch in `_save` stays a
/// one-liner and the rate-limit / generic split is unit-testable
/// without driving the full widget tree.
///
/// Behaviour:
///   - PostgrestException with the rate-limit signature (P0001 +
///     migration 20260907_001 message) becomes the localized "wait
///     N minutes" sentence from the ARB catalogue.
///   - LateInitializationError (Supabase SDK's `late client` field
///     read before init) or a StateError carrying the "bootstrap"
///     signature from [ApiClient] surface as the offline-mode
///     message. This catches the case where Supabase init failed
///     silently in `main.dart` and a call slipped past the null-guard
///     on `apiClient` (defence in depth — the primary fix is to
///     leave `api == null` so the user can't reach this path at all).
///   - Anything else falls through to the classified friendly copy;
///     the raw detail (RLS denials, FK violations, network errors)
///     stays in debugPrint only.
String formatSaveRouteError(Object e, [BuildContext? context]) {
  if (e is PostgrestException) {
    final info = parseRateLimitError(code: e.code, message: e.message);
    if (info != null) {
      // Looked up off the English catalogue when the caller has no
      // context (only the unit tests do) rather than re-spelling the
      // sentence here — a hardcoded copy of a translated string is
      // exactly what § 744 removed.
      return rateLimitMessage(
        context != null
            ? AppLocalizations.of(context)
            : lookupAppLocalizations(const Locale('en')),
        info,
      );
    }
  }
  // `LateInitializationError` is not a public type in dart:core — the
  // SDK throws a private subclass of `Error` whose `toString()` begins
  // with the literal `"LateInitializationError:"`. Match on the string
  // signature rather than `is`. Pair with the StateError signature
  // from `ApiClient`'s bootstrap guard so both error sites surface the
  // same friendly copy.
  if ((e is Error && e.toString().startsWith('LateInitializationError')) ||
      (e is StateError &&
          e.message.contains('Supabase.initialize'))) {
    return context != null
        ? AppLocalizations.of(context).routeBuilderServerUnreachable
        : "Can't reach the server. Sign in or check your connection and try again.";
  }
  debugPrint('route builder save failed: $e');
  return context != null
      ? AppLocalizations.of(context)
          .routeBuilderSaveFailed(friendlyError(AppLocalizations.of(context), e))
      : 'Save failed. Please try again.';
}

String _surfaceFor(RouteBuilderMode mode) {
  return switch (mode) {
    RouteBuilderMode.trail => 'trail',
    RouteBuilderMode.road => 'road',
    RouteBuilderMode.straight => 'mixed',
  };
}

/// Sum great-circle distances between consecutive waypoints. Re-uses
/// the haversine helper from `run_stats`.
@visibleForTesting
double straightLineDistance(List<cm.Waypoint> points) {
  if (points.length < 2) return 0;
  var total = 0.0;
  for (var i = 1; i < points.length; i++) {
    total += haversineMetres(
      points[i - 1].lat,
      points[i - 1].lng,
      points[i].lat,
      points[i].lng,
    );
  }
  return total;
}

/// Slice the polyline into [LatLng] runs by overlap span — used to
/// draw the purple over-stroke on retraced sections. Public so the
/// widget test can assert the slicing without mounting the screen.
List<List<LatLng>> overlapLatLngsFor(
  List<cm.Waypoint> polyline,
  List<OverlapSpan> spans,
) {
  if (spans.isEmpty) return const [];
  final out = <List<LatLng>>[];
  for (final span in spans) {
    if (span.startIndex >= polyline.length) continue;
    final end = span.endIndex.clamp(0, polyline.length - 1);
    final slice = <LatLng>[
      for (var i = span.startIndex; i <= end; i++)
        LatLng(polyline[i].lat, polyline[i].lng),
    ];
    if (slice.length >= 2) out.add(slice);
  }
  return out;
}

class _StatusPill extends StatelessWidget {
  final double distanceM;
  final double elevationGainM;
  final bool routing;
  final bool saving;
  final int waypointCount;
  final RouteBuilderMode mode;
  final int? dragIndex;
  final VoidCallback onCancelDrag;
  final VoidCallback onDeleteDragged;

  const _StatusPill({
    required this.distanceM,
    required this.elevationGainM,
    required this.routing,
    required this.saving,
    required this.waypointCount,
    required this.mode,
    required this.dragIndex,
    required this.onCancelDrag,
    required this.onDeleteDragged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    String label;
    if (dragIndex != null) {
      // Pinning the affordance hierarchy: PRIMARY action is move,
      // SECONDARY is delete, TERTIARY is cancel. The label leads with
      // "Tap anywhere" because that's the move gesture; the two
      // icons cover the other two intents.
      label = l10n.routeBuilderTapToMovePoint(dragIndex! + 1);
    } else if (waypointCount == 0) {
      // Surface the current routing mode in the empty hint so flipping
      // Trail / Road / Straight gives immediate visual feedback even
      // before the user places two waypoints (otherwise the mode
      // toggle looks dead until there's a polyline to reshape).
      label = l10n.routeBuilderEmptyHint(_modeLabel(l10n, mode));
    } else if (waypointCount == 1) {
      // One waypoint placed — same rationale: show the mode so the
      // user can compose the toggle + next tap with confidence.
      label = l10n.routeBuilderOnePointHint(_modeLabel(l10n, mode));
    } else {
      final km = formatFixed(distanceM / 1000, 2, activeLocaleTag);
      label = elevationGainM > 0
          ? l10n.routeBuilderStatusGain(
              '$km km', elevationGainM.round(), waypointCount)
          : l10n.routeBuilderStatusNoGain('$km km', waypointCount);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        children: [
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          if (dragIndex != null) ...[
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              tooltip: l10n.routeBuilderDeletePoint(dragIndex! + 1),
              color: theme.colorScheme.error,
              onPressed: onDeleteDragged,
              constraints:
                  const BoxConstraints(minWidth: 48, minHeight: 48),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              tooltip: l10n.routeBuilderCancelDrag,
              onPressed: onCancelDrag,
              constraints:
                  const BoxConstraints(minWidth: 48, minHeight: 48),
            ),
          ] else if (routing || saving) ...[
            const SizedBox(width: 8),
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ],
      ),
    );
  }
}

/// Bottom-sheet listing every waypoint as a reorderable row — the
/// accessible alternative to the map-only pin gestures. Reordering
/// (explicit drag handle, so TalkBack exposes a semantics action) or
/// deleting a row applies immediately through [onApply]; the sheet
/// keeps its own ordered copy so back-to-back edits don't wait on the
/// parent's OSRM re-route. Each mutation is narrated via [announce]
/// (WCAG 4.1.3 — mirrors the screen's `_announceA11yState` pattern).
class WaypointListSheet extends StatefulWidget {
  const WaypointListSheet({
    super.key,
    required this.waypoints,
    required this.onApply,
    required this.announce,
  });

  final List<cm.Waypoint> waypoints;
  final ValueChanged<List<cm.Waypoint>> onApply;
  final ValueChanged<String> announce;

  @override
  State<WaypointListSheet> createState() => _WaypointListSheetState();
}

class _WaypointListSheetState extends State<WaypointListSheet> {
  late final List<cm.Waypoint> _items = List.of(widget.waypoints);
  // Row identity for ReorderableListView keys. Coordinates can't key
  // the rows — a closed loop carries the same lat/lng at both ends.
  late final List<int> _ids =
      List.generate(widget.waypoints.length, (i) => i);

  void _onReorder(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1;
    if (newIndex == oldIndex) return;
    setState(() {
      _items.insert(newIndex, _items.removeAt(oldIndex));
      _ids.insert(newIndex, _ids.removeAt(oldIndex));
    });
    widget.onApply(List.of(_items));
    widget.announce(
      AppLocalizations.of(context)
          .routeBuilderPointMovedTo(oldIndex + 1, newIndex + 1),
    );
  }

  void _removeAt(int index) {
    setState(() {
      _items.removeAt(index);
      _ids.removeAt(index);
    });
    widget.onApply(List.of(_items));
    widget.announce(
      AppLocalizations.of(context).routeBuilderPointRemoved(index + 1),
    );
    if (_items.isEmpty) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    // The list rows bring their own 16 dp inset, so the sheet adds none
    // beside them; SheetScaffold still lifts the list off the nav bar.
    return SheetScaffold(
      padding: const EdgeInsets.only(bottom: 16),
      title: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text(l10n.routeBuilderPointList),
      ),
      scrollBody: false,
      body: ReorderableListView.builder(
        shrinkWrap: true,
        buildDefaultDragHandles: false,
        itemCount: _items.length,
        onReorder: _onReorder,
        itemBuilder: (context, i) {
          final w = _items[i];
          final tag = i == 0
              ? l10n.routeBuilderPointStart
              : (i == _items.length - 1 && i > 0
                  ? l10n.routeBuilderPointEnd
                  : null);
          return ListTile(
            key: ValueKey(_ids[i]),
            leading: CircleAvatar(
              radius: 14,
              child: Text('${i + 1}'),
            ),
            title: Text(
              '${w.lat.toStringAsFixed(5)}, ${w.lng.toStringAsFixed(5)}',
              style: theme.textTheme.bodyMedium,
            ),
            subtitle: tag == null ? null : Text(tag),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: l10n.routeBuilderDeletePoint(i + 1),
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _removeAt(i),
                ),
                ReorderableDragStartListener(
                  index: i,
                  child: Semantics(
                    excludeSemantics: true,
                    label: l10n.routeBuilderReorderPoint(i + 1),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(Icons.drag_handle),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Generate-Loop dialog. Owns its own TextEditingController via a
/// proper State object so the controller's lifecycle is bound to
/// the dialog widget tree — `dispose()` runs when the dialog
/// unmounts (after the pop animation completes), which is what
/// Flutter's ChangeNotifier disposal contract expects.
class _GenerateLoopDialog extends StatefulWidget {
  final DistanceUnit unit;
  const _GenerateLoopDialog({required this.unit});

  @override
  State<_GenerateLoopDialog> createState() => _GenerateLoopDialogState();
}

class _GenerateLoopDialogState extends State<_GenerateLoopDialog> {
  late final TextEditingController _ctl = TextEditingController(
    text: widget.unit == DistanceUnit.mi ? '3' : '5',
  );

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _submit() {
    final v = parseTypedDecimal(_ctl.text);
    if (v == null || v <= 0) {
      Navigator.pop(context);
      return;
    }
    final metres = widget.unit == DistanceUnit.mi
        ? v * 1609.344
        : v * 1000;
    Navigator.pop(context, metres);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final label = widget.unit == DistanceUnit.mi ? 'mi' : 'km';
    return AlertDialog(
      title: Text(l10n.routeBuilderGenerateLoop),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.routeBuilderLoopDialogBody,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          // semantics-children: names a field that shows no label or hint of its own
          Semantics(
            label: l10n.routeBuilderLoopDialogBody,
            child: TextField(
              controller: _ctl,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(suffixText: label),
              onSubmitted: (_) => _submit(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.routeBuilderCancel),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(l10n.routeBuilderGenerate),
        ),
      ],
    );
  }
}

class _ModeToggle extends StatelessWidget {
  final RouteBuilderMode mode;
  final ValueChanged<RouteBuilderMode>? onChanged;

  const _ModeToggle({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(4),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.dividerColor),
      ),
      // The earlier field report here — "the text wraps to the next line for
      // Road and Straight items" — was the segmented control dividing the map
      // overlay's width three ways. `maxLines: 1` + a fade stopped the wrap
      // and started losing characters instead: Spanish "Sendero" got 36.7 px
      // of the 52.5 it needs at 320 dp / 1.0x. Chips are sized by their own
      // labels, so neither happens. The chips then reflowed onto a second run
      // at 1.3x, which on a floating map overlay is a half-empty pill grown
      // into the Locate FAB. A segmented track scrolls as one block rather
      // than splitting across rows (conventions.md, "Content whose axis is
      // its information may scroll itself"); the unbounded width lays the
      // chips out as one run.
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ChoiceChipRow<RouteBuilderMode>(
          options: [
            ChoiceChipOption(
              value: RouteBuilderMode.trail,
              label: l10n.routeBuilderModeTrail,
              icon: Icons.terrain,
            ),
            ChoiceChipOption(
              value: RouteBuilderMode.road,
              label: l10n.routeBuilderModeRoad,
              icon: Icons.directions_car_outlined,
            ),
            ChoiceChipOption(
              value: RouteBuilderMode.straight,
              label: l10n.routeBuilderModeStraight,
              icon: Icons.straighten,
            ),
          ],
          selected: mode,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

/// What Draw mode is doing: the hint while drawing, then the last
/// drawing's score and verdict. Text wraps rather than truncates, so it
/// stays whole at large OS text scales.
class _DrawStatusCard extends StatelessWidget {
  const _DrawStatusCard({required this.drawing, required this.fidelity});

  final bool drawing;
  final ArtFidelity? fidelity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final f = fidelity;
    final verdict = f == null
        ? null
        : switch (f.verdict) {
            FidelityVerdict.close => l10n.routeBuilderDrawMatchClose,
            FidelityVerdict.rough => l10n.routeBuilderDrawMatchRough,
            FidelityVerdict.poor => l10n.routeBuilderDrawMatchPoor,
          };
    return ListCard(
      key: const Key('route-builder-draw-status'),
      margin: EdgeInsets.zero,
      dense: true,
      child: Row(
          children: [
            Icon(
              f == null ? Icons.gesture : Icons.auto_awesome,
              size: 20,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: f == null
                  ? Text(l10n.routeBuilderDrawHint,
                      style: theme.textTheme.bodyMedium)
                  : Text(
                      '${l10n.routeBuilderDrawMatch(f.score)} · $verdict',
                      style: theme.textTheme.bodyMedium,
                    ),
            ),
          ],
        ),
    );
  }
}

/// Waypoint pin. Renders a small numbered circle (green start, red
/// end, blue intermediate). The start pin shows a pulsing halo when
/// the route is long enough to close as a loop — visual cue for
/// snap-to-start. While the user is dragging this waypoint, the pin
/// switches to an amber outline.
/// The fill and the glyph colour of a route-builder waypoint pin, from the
/// AA-tuned semantic pairs, so the index or glyph reads on every pin (#1374
/// A11Y-7). Material's green / red / amber / blueGrey under white measured
/// 2.78 / 3.68 / 1.63 / 4.37:1. Start and end also differ by glyph, not by
/// colour alone.
@visibleForTesting
({Color fill, Color on}) waypointPinColors(
  ThemeData theme, {
  required bool isStart,
  required bool isEnd,
  required bool isDragging,
}) {
  final semantic = AppSemanticColors.ofTheme(theme);
  if (isDragging) return (fill: semantic.warning, on: semantic.onWarning);
  if (isStart) return (fill: semantic.success, on: semantic.onSuccess);
  if (isEnd) return (fill: semantic.danger, on: semantic.onDanger);
  return (
    fill: theme.colorScheme.inverseSurface,
    on: theme.colorScheme.onInverseSurface,
  );
}

class _WaypointPin extends StatefulWidget {
  final int index;
  final int total;
  final bool isStart;
  final bool isEnd;
  final bool isDragging;
  final bool pulseStart;

  const _WaypointPin({
    required this.index,
    required this.total,
    required this.isStart,
    required this.isEnd,
    required this.isDragging,
    required this.pulseStart,
  });

  @override
  State<_WaypointPin> createState() => _WaypointPinState();
}

class _WaypointPinState extends State<_WaypointPin>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(duration: AppMotion.pulse, vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    syncMotionLoop(context, _pulse);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = waypointPinColors(
      Theme.of(context),
      isStart: widget.isStart,
      isEnd: widget.isEnd,
      isDragging: widget.isDragging,
    );
    final color = colors.fill;
    // Drag mode bumps the pin from 22→32 dp + adds a coloured
    // shadow so it visibly "lifts" off the map. Without this the
    // only sign you'd entered drag mode was a colour shift the
    // user might not notice.
    final size = widget.isDragging ? 32.0 : 22.0;
    final pin = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: widget.isDragging
            ? [
                BoxShadow(
                  color: color,
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
      alignment: Alignment.center,
      // Start and end carry a glyph, so they differ by shape as well as
      // colour; the pins between carry their number.
      child: widget.isStart || widget.isEnd
          ? Icon(
              widget.isStart ? Icons.play_arrow : Icons.sports_score,
              size: widget.isDragging ? 18 : 14,
              color: colors.on,
            )
          : Text(
              '${widget.index + 1}',
              style: TextStyle(
                color: colors.on,
                fontWeight: FontWeight.bold,
                fontSize: widget.isDragging ? 14 : 11,
              ),
            ),
    );
    final n = widget.index + 1;
    final pinLabel = widget.isStart
        ? l10n.routeBuilderWaypointStart(n, widget.total)
        : widget.isEnd
            ? l10n.routeBuilderWaypointEnd(n, widget.total)
            : l10n.routeBuilderWaypoint(n, widget.total);
    // Two pulsing-halo paths: the start-pin "snap to close loop"
    // affordance (existing) and the new "drag in progress" affordance.
    // Either reuses the same `_pulse` controller so the animation
    // stays coordinated when both ever overlap (shouldn't, because
    // pulseStart gates on `_dragIndex == null`).
    final shouldPulse = widget.pulseStart || widget.isDragging;
    if (!shouldPulse) {
      return Semantics(label: pinLabel, excludeSemantics: true, child: pin);
    }
    final ringColor = color;
    final pulsing = AnimatedBuilder(
      animation: _pulse,
      builder: (_, child) {
        final t = _pulse.value;
        final ringScale = 1 + 0.7 * t;
        final ringOpacity = (1 - t).clamp(0.0, 1.0);
        return SizedBox(
          width: widget.isDragging ? 56 : 36,
          height: widget.isDragging ? 56 : 36,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Transform.scale(
                scale: ringScale,
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: ringColor.withValues(alpha: 0.30 * ringOpacity),
                  ),
                ),
              ),
              child!,
            ],
          ),
        );
      },
      child: pin,
    );
    return Semantics(label: pinLabel, excludeSemantics: true, child: pulsing);
  }
}

/// One option in the SaveRouteDialog's "Save to" picker. Kept tiny
/// and screen-local so the dialog doesn't take a dependency on
/// `SocialService` / `ClubView` — the caller does the membership
/// lookup and hands in a flat list.
@visibleForTesting
class RouteClubChoice {
  final String id;
  final String name;
  const RouteClubChoice({required this.id, required this.name});
}

/// Result popped by [SaveRouteDialog]. Promoted alongside the dialog so
/// widget tests can pattern-match on the returned shape.
@visibleForTesting
class SaveDialogResult {
  final String name;
  final bool isPublic;
  final String? description;

  /// The club this route is being saved to, or null for "Personal".
  /// Mirrors web's `?club=<id>` URL parameter on `/routes/new`.
  final String? clubId;

  const SaveDialogResult({
    required this.name,
    required this.isPublic,
    this.description,
    this.clubId,
  });
}

/// Save-route modal. Promoted from file-private so the widget test
/// can pump it in isolation rather than mounting the whole builder
/// (which would need a working MapLibre/OSRM/elevation stack).
///
/// When the caller passes a non-empty [clubChoices], the dialog
/// renders a "Save to" dropdown that lets the user choose between
/// Personal (the default) and any club they're a member of. The
/// picker is hidden entirely when the list is empty so users who
/// aren't in any clubs see the same lean dialog as before.
@visibleForTesting
class SaveRouteDialog extends StatefulWidget {
  final List<RouteClubChoice> clubChoices;

  /// Pre-selected club id. Defaults to null (Personal). When the
  /// caller (e.g. the club-detail "Build route" CTA) wants the
  /// picker to open already pointing at a specific club, it passes
  /// that club's id here. The user can still change it.
  final String? initialClubId;

  const SaveRouteDialog({
    super.key,
    this.clubChoices = const [],
    this.initialClubId,
  });
  @override
  State<SaveRouteDialog> createState() => _SaveRouteDialogState();
}

class _SaveRouteDialogState extends State<SaveRouteDialog> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  bool _isPublic = false;
  late String? _clubId;

  @override
  void initState() {
    super.initState();
    // Seed the picker default from the caller's `initialClubId`, but
    // only if it matches one of the available choices — otherwise
    // fall back to Personal so a stale / wrong id can't put the
    // picker into a non-selectable state.
    final candidate = widget.initialClubId;
    final valid = candidate != null &&
        widget.clubChoices.any((c) => c.id == candidate);
    _clubId = valid ? candidate : null;
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hasClubs = widget.clubChoices.isNotEmpty;
    return AlertDialog(
      title: Text(l10n.routeBuilderSaveDialogTitle),
      // SingleChildScrollView so the Make public toggle isn't clipped
      // behind the Save / Cancel actions on short screens (or when
      // the keyboard opens). Without it, AlertDialog overflows its
      // content area under the actions strip.
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: InputDecoration(
                labelText: l10n.routeBuilderNameLabel,
                hintText: l10n.routeBuilderNameHint,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _description,
              decoration: InputDecoration(
                labelText: l10n.routeBuilderDescriptionLabel,
                hintText: l10n.routeBuilderDescriptionHint,
              ),
              maxLines: 3,
            ),
            if (hasClubs) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String?>(
                key: const Key('save-route-dialog-club-picker'),
                initialValue: _clubId,
                decoration: InputDecoration(
                  labelText: l10n.routeBuilderSaveToLabel,
                ),
                items: <DropdownMenuItem<String?>>[
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text(l10n.routeBuilderSaveToPersonal),
                  ),
                  for (final c in widget.clubChoices)
                    DropdownMenuItem<String?>(
                      value: c.id,
                      child: Text(c.name),
                    ),
                ],
                onChanged: (v) => setState(() => _clubId = v),
              ),
            ],
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.routeBuilderMakePublic),
              subtitle: Text(l10n.routeBuilderMakePublicSubtitle),
              value: _isPublic,
              onChanged: (v) => setState(() => _isPublic = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.routeBuilderCancel),
        ),
        FilledButton(
          onPressed: () {
            final trimmed = _name.text.trim();
            if (trimmed.isEmpty) return;
            final desc = _description.text.trim();
            Navigator.of(context).pop(SaveDialogResult(
              name: trimmed,
              isPublic: _isPublic,
              description: desc.isEmpty ? null : desc,
              clubId: _clubId,
            ));
          },
          child: Text(l10n.routeBuilderSave),
        ),
      ],
    );
  }
}

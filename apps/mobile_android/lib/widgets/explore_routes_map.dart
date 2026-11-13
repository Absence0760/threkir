import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' as cm;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../heatmap_clustering.dart';
import '../l10n/gen/app_localizations.dart';
import '../quiet_location.dart';
import 'live_run_map.dart'
    show basemapTileLayer, basemapVoidColour, currentBasemapIsDark, currentTileUrl;
import 'map_attribution.dart';

/// The map behind Routes → Explore (issue #1374): the public routes in view,
/// as clustered start pins, from the same `discoverable_routes_in_bbox` read
/// the routes heatmap uses, which places each pin server-side (a non-owner
/// never receives a route's raw line here).
///
/// It refetches as the camera settles, opens on the world and moves to the
/// runner once a quiet fix arrives (never prompting), unless they have
/// already moved the map. A pin opens its route through [onOpen]; a cluster
/// zooms in on itself.
class ExploreRoutesMap extends StatefulWidget {
  const ExploreRoutesMap({
    super.key,
    required this.api,
    required this.controller,
    required this.onOpen,
    this.quietFixes = quietPositionFixes,
  });

  final ApiClient? api;

  /// Owned by the screen, which moves it when Near me finds the runner.
  final MapController controller;

  final void Function(cm.DiscoverableRoutePin pin) onOpen;

  /// Test seam; production centres on [quietPositionFixes].
  final Stream<Position> Function() quietFixes;

  /// This map's credit, for the page to float above its sheet, where the
  /// map's own bottom edge is covered.
  static Widget credit(BuildContext context) =>
      MapAttribution(darkBasemap: currentBasemapIsDark(context));

  @override
  State<ExploreRoutesMap> createState() => _ExploreRoutesMapState();
}

class _ExploreRoutesMapState extends State<ExploreRoutesMap> {
  static const _clusterRadiusPx = 44.0;
  static const _openZoom = 12.0;

  List<cm.DiscoverableRoutePin> _pins = const [];
  Timer? _debounce;
  StreamSubscription<Position>? _fixes;
  LatLng? _pendingFix;
  bool _ready = false;
  bool _moved = false;
  int _generation = 0;

  /// The last read of the routes in view failed. Shown on the map with
  /// Retry, never as an empty map (issue #1374 FS-10).
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _fixes = widget.quietFixes().listen((pos) {
      final at = LatLng(pos.latitude, pos.longitude);
      if (_moved || !mounted) return;
      if (_ready) {
        widget.controller.move(at, _openZoom);
      } else {
        _pendingFix = at;
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _fixes?.cancel();
    super.dispose();
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _refresh);
  }

  Future<void> _refresh() async {
    final api = widget.api;
    if (!_ready || api == null) return;
    final bounds = widget.controller.camera.visibleBounds;
    final generation = ++_generation;
    try {
      final pins = await api.fetchDiscoverableRoutesInBbox(
        minLng: bounds.west,
        minLat: bounds.south,
        maxLng: bounds.east,
        maxLat: bounds.north,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _pins = pins;
        _failed = false;
      });
    } catch (e) {
      // L4: the pins are auxiliary to the list in the sheet, so a failed read
      // keeps the pins already shown and says so on the map.
      debugPrint('explore map routes read failed: ${safeErrorLabel(e)}');
      if (!mounted || generation != _generation) return;
      setState(() => _failed = true);
    }
  }

  void _zoomInto(PinCluster<cm.DiscoverableRoutePin> c) {
    final camera = widget.controller.camera;
    widget.controller.move(LatLng(c.lat, c.lng), camera.zoom + 2);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final darkBasemap = currentBasemapIsDark(context);
    return FlutterMap(
      key: const ValueKey('explore-routes-map'),
      mapController: widget.controller,
      options: MapOptions(
        backgroundColor: basemapVoidColour(darkBasemap: darkBasemap),
        initialCenter: const LatLng(20, 0),
        initialZoom: 2,
        minZoom: 2,
        onMapReady: () {
          _ready = true;
          final fix = _pendingFix;
          if (fix != null && !_moved) widget.controller.move(fix, _openZoom);
          _refresh();
        },
        onPositionChanged: (_, hasGesture) {
          if (hasGesture) _moved = true;
          _schedule();
        },
      ),
      children: [
        basemapTileLayer(urlTemplate: currentTileUrl(context)),
        Builder(builder: (context) {
          final camera = MapCamera.of(context);
          final clusters = clusterPins<cm.DiscoverableRoutePin>(
            items: _pins,
            latOf: (p) => p.lat,
            lngOf: (p) => p.lng,
            project: (lat, lng) {
              final o = camera.latLngToScreenOffset(LatLng(lat, lng));
              return (x: o.dx, y: o.dy);
            },
            radiusPx: _clusterRadiusPx,
          );
          return MarkerLayer(
            markers: [
              for (final c in clusters)
                Marker(
                  point: LatLng(c.lat, c.lng),
                  width: 48,
                  height: 48,
                  child: c.isCluster
                      ? Semantics(
                          excludeSemantics: true,
                          onTap: () => _zoomInto(c),
                          button: true,
                          label: l10n.heatmapRouteCount(c.count),
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _zoomInto(c),
                            child: _Dot(
                              size: 32,
                              color: theme.colorScheme.primary,
                              // Scales down rather than spill out of the
                              // dot at a large text size.
                              child: FittedBox(
                                child: Padding(
                                  padding: const EdgeInsets.all(4),
                                  child: Text(
                                    '${c.count}',
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(
                                            color:
                                                theme.colorScheme.onPrimary),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        )
                      // semantics-children: the child draws no text, and keeps its own tap
                      : Semantics(
                          button: true,
                          label: c.first.name,
                          child: GestureDetector(
                            key: ValueKey('explore-pin-${c.first.id}'),
                            behavior: HitTestBehavior.opaque,
                            onTap: () => widget.onOpen(c.first),
                            child: _Dot(
                              size: 18,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                ),
            ],
          );
        }),
        if (_failed)
          Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: ActionChip(
                key: const Key('explore-map-load-failed'),
                avatar: const Icon(Icons.refresh, size: 18),
                label: Text(l10n.heatmapLoadFailed),
                onPressed: _refresh,
              ),
            ),
          ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.size, required this.color, this.child});

  final double size;
  final Color color;
  final Widget? child;

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
                color: Theme.of(context).colorScheme.surface, width: 2),
          ),
          child: child,
        ),
      );
}

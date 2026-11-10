import 'dart:math' as math;

import 'package:core_models/core_models.dart' show Waypoint;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:ui_kit/ui_kit.dart' show AppSemanticColors, ChartPalette;

import '../l10n/gen/app_localizations.dart';
import '../park_courses.dart' show CourseCheckpoint;
import '../run_stats.dart' show haversineMetres;
import 'live_run_map.dart'
    show
        basemapTileLayer,
        basemapVoidColour,
        chevronInk,
        chevronOutline,
        currentBasemapIsDark,
        currentTileUrl,
        mapOverlayOutline,
        mapTrackLine,
        solidMapLine;
import 'map_attribution.dart';
import 'track_decorations.dart' show computeChevrons;

/// A course whose first and last points sit this close together starts and
/// finishes in one place, so the map draws one marker for both.
const double kParkCourseSharedEndM = 60;

/// Starts closer together than this share one start marker on the park map.
const double kParkStartMergeM = 60;

/// How many direction chevrons a course line carries, spread along its length.
const int kParkCourseChevrons = 6;

/// The colour of a park's [index]th course line, as the park map draws it and
/// the course list's swatch repeats it. Keyed on the basemap, as the start and
/// finish colours are, because the line is drawn over tiles.
Color parkCourseLineColour(int index, {required bool darkBasemap}) {
  final kinds = (darkBasemap ? ChartPalette.dark : ChartPalette.light).kinds;
  return kinds[index % kinds.length];
}

AppSemanticColors _endPalette(bool darkBasemap) =>
    darkBasemap ? AppSemanticColors.dark : AppSemanticColors.light;

LatLng _ll(Waypoint w) => LatLng(w.lat, w.lng);

/// Whether [line] starts and finishes in the same place.
bool courseEndsShared(List<Waypoint> line) =>
    line.length >= 2 &&
    haversineMetres(
          line.first.lat,
          line.first.lng,
          line.last.lat,
          line.last.lng,
        ) <=
        kParkCourseSharedEndM;

double _lineMetres(List<LatLng> pts) {
  var total = 0.0;
  for (var i = 1; i < pts.length; i++) {
    total += haversineMetres(
      pts[i - 1].latitude,
      pts[i - 1].longitude,
      pts[i].latitude,
      pts[i].longitude,
    );
  }
  return total;
}

class _EndMarker extends StatelessWidget {
  final IconData icon;
  final Color fill;
  final Color ink;
  final Color ring;

  const _EndMarker({
    required this.icon,
    required this.fill,
    required this.ink,
    required this.ring,
  });

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: fill,
          shape: BoxShape.circle,
          border: Border.all(color: ring, width: 2),
        ),
        child: Center(child: Icon(icon, size: 14, color: ink)),
      );
}

class _CheckpointMarker extends StatelessWidget {
  final int number;
  final Color fill;
  final Color ink;

  const _CheckpointMarker({
    required this.number,
    required this.fill,
    required this.ink,
  });

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context)
        .textTheme
        .labelSmall
        ?.copyWith(color: ink, fontWeight: FontWeight.w700);
    return DecoratedBox(
      decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text('$number', style: style),
        ),
      ),
    );
  }
}

class _Chevron extends StatelessWidget {
  final double angle;
  const _Chevron(this.angle);

  @override
  Widget build(BuildContext context) => Transform.rotate(
        angle: angle,
        child: const Icon(
          Icons.play_arrow,
          size: 16,
          color: chevronInk,
          shadows: chevronOutline,
        ),
      );
}

/// One park course on a basemap: its line, the direction it is run in, the
/// start and finish (one marker when they share a place) and its numbered
/// checkpoints. Pair it with [ParkCourseMapLegend], which names each mark.
/// Static, because it sits inside the course page's scroll view.
class ParkCourseMap extends StatelessWidget {
  final List<Waypoint> line;
  final List<CourseCheckpoint> checkpoints;
  final double aspectRatio;

  const ParkCourseMap({
    super.key,
    required this.line,
    this.checkpoints = const [],
    this.aspectRatio = 1.5,
  });

  @override
  Widget build(BuildContext context) {
    if (line.length < 2) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final darkBasemap = currentBasemapIsDark(context);
    final ends = _endPalette(darkBasemap);
    final ring = mapOverlayOutline(darkBasemap: darkBasemap);
    final pts = [for (final w in line) _ll(w)];
    final shared = courseEndsShared(line);
    final step = math.max(_lineMetres(pts) / kParkCourseChevrons, 25.0);
    final chevrons = computeChevrons(pts, stepMetres: step);
    return Semantics(
      container: true,
      label: l10n.parksMapCourseLabel(checkpoints.length),
      child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(
            aspectRatio: aspectRatio,
            child: FlutterMap(
              options: MapOptions(
                backgroundColor: basemapVoidColour(darkBasemap: darkBasemap),
                initialCameraFit: CameraFit.coordinates(
                  coordinates: pts,
                  padding: const EdgeInsets.all(28),
                  maxZoom: 17,
                ),
                interactionOptions:
                    const InteractionOptions(flags: InteractiveFlag.none),
              ),
              children: [
                basemapTileLayer(urlTemplate: currentTileUrl(context)),
                PolylineLayer(
                  key: const ValueKey('park-course-line'),
                  polylines:
                      solidMapLine(pts, mapTrackLine(darkBasemap: darkBasemap)),
                ),
                MarkerLayer(
                  key: const ValueKey('park-course-chevrons'),
                  markers: [
                    for (final c in chevrons)
                      Marker(
                        point: c.position,
                        width: 18,
                        height: 18,
                        child: _Chevron(c.angleRadians),
                      ),
                  ],
                ),
                MarkerLayer(
                  key: const ValueKey('park-course-checkpoints'),
                  markers: [
                    for (var i = 0; i < checkpoints.length; i++)
                      Marker(
                        point: LatLng(checkpoints[i].lat, checkpoints[i].lng),
                        width: 22,
                        height: 22,
                        child: _CheckpointMarker(
                          number: i + 1,
                          fill: ring,
                          ink: basemapVoidColour(darkBasemap: darkBasemap),
                        ),
                      ),
                  ],
                ),
                MarkerLayer(
                  key: const ValueKey('park-course-ends'),
                  markers: [
                    if (!shared)
                      Marker(
                        point: pts.last,
                        width: 24,
                        height: 24,
                        child: _EndMarker(
                          icon: Icons.flag,
                          fill: ends.danger,
                          ink: ends.onDanger,
                          ring: ring,
                        ),
                      ),
                    Marker(
                      point: pts.first,
                      width: 24,
                      height: 24,
                      child: _EndMarker(
                        icon: shared ? Icons.flag : Icons.play_arrow,
                        fill: ends.success,
                        ink: ends.onSuccess,
                        ring: ring,
                      ),
                    ),
                  ],
                ),
                MapAttribution(darkBasemap: darkBasemap),
              ],
            ),
          ),
      ),
    );
  }
}

/// The key under a [ParkCourseMap]: one row per kind of mark the map draws,
/// each read by a screen reader as its own item.
class ParkCourseMapLegend extends StatelessWidget {
  final List<Waypoint> line;
  final int checkpointCount;

  const ParkCourseMapLegend({
    super.key,
    required this.line,
    required this.checkpointCount,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final darkBasemap = currentBasemapIsDark(context);
    final ends = _endPalette(darkBasemap);
    final ring = mapOverlayOutline(darkBasemap: darkBasemap);
    final shared = courseEndsShared(line);
    Widget item(Key key, Widget mark, String label) => MergeSemantics(
          key: key,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ExcludeSemantics(
                child: SizedBox.square(dimension: 22, child: mark),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(label, style: Theme.of(context).textTheme.bodySmall),
              ),
            ],
          ),
        );
    return Semantics(
      container: true,
      label: l10n.parksLegendTitle,
      child: Wrap(
        key: const Key('park-course-legend'),
        spacing: 16,
        runSpacing: 8,
        children: [
          if (shared)
            item(
              const Key('park-course-legend-start-finish'),
              _EndMarker(
                icon: Icons.flag,
                fill: ends.success,
                ink: ends.onSuccess,
                ring: ring,
              ),
              l10n.parksLegendStartFinish,
            )
          else ...[
            item(
              const Key('park-course-legend-start'),
              _EndMarker(
                icon: Icons.play_arrow,
                fill: ends.success,
                ink: ends.onSuccess,
                ring: ring,
              ),
              l10n.parksLegendStart,
            ),
            item(
              const Key('park-course-legend-finish'),
              _EndMarker(
                icon: Icons.flag,
                fill: ends.danger,
                ink: ends.onDanger,
                ring: ring,
              ),
              l10n.parksLegendFinish,
            ),
          ],
          if (checkpointCount > 0)
            item(
              const Key('park-course-legend-checkpoints'),
              _CheckpointMarker(
                number: 1,
                fill: ring,
                ink: basemapVoidColour(darkBasemap: darkBasemap),
              ),
              l10n.parksLegendCheckpoints,
            ),
          item(
            const Key('park-course-legend-direction'),
            const Center(child: _Chevron(0)),
            l10n.parksLegendDirection,
          ),
        ],
      ),
    );
  }
}

/// Every course line in one park over a basemap, each in its own colour
/// ([parkCourseLineColour], in the order given), with a start marker at each
/// distinct start. Static, for the park page header and the parks index card.
class ParkOverviewMap extends StatelessWidget {
  final List<List<Waypoint>> lines;
  final double aspectRatio;
  final bool showStarts;

  const ParkOverviewMap({
    super.key,
    required this.lines,
    this.aspectRatio = 1.6,
    this.showStarts = true,
  });

  @override
  Widget build(BuildContext context) {
    final drawn = [
      for (final l in lines)
        if (l.length >= 2) l,
    ];
    if (drawn.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final darkBasemap = currentBasemapIsDark(context);
    final ends = _endPalette(darkBasemap);
    final ring = mapOverlayOutline(darkBasemap: darkBasemap);
    final starts = <Waypoint>[];
    for (final l in drawn) {
      final s = l.first;
      final near = starts.any((o) =>
          haversineMetres(o.lat, o.lng, s.lat, s.lng) <= kParkStartMergeM);
      if (!near) starts.add(s);
    }
    final all = [
      for (final l in drawn)
        for (final w in l) _ll(w),
    ];
    return Semantics(
      container: true,
      label: l10n.parksMapParkLabel(drawn.length),
      child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(
            aspectRatio: aspectRatio,
            child: FlutterMap(
              options: MapOptions(
                backgroundColor: basemapVoidColour(darkBasemap: darkBasemap),
                initialCameraFit: CameraFit.coordinates(
                  coordinates: all,
                  padding: const EdgeInsets.all(20),
                  maxZoom: 16,
                ),
                interactionOptions:
                    const InteractionOptions(flags: InteractiveFlag.none),
              ),
              children: [
                basemapTileLayer(urlTemplate: currentTileUrl(context)),
                PolylineLayer(
                  key: const ValueKey('park-overview-lines'),
                  polylines: [
                    for (var i = drawn.length - 1; i >= 0; i--)
                      ...solidMapLine(
                        [for (final w in drawn[i]) _ll(w)],
                        parkCourseLineColour(i, darkBasemap: darkBasemap),
                      ),
                  ],
                ),
                if (showStarts)
                  MarkerLayer(
                    key: const ValueKey('park-overview-starts'),
                    markers: [
                      for (final s in starts)
                        Marker(
                          point: _ll(s),
                          width: 24,
                          height: 24,
                          child: _EndMarker(
                            icon: Icons.play_arrow,
                            fill: ends.success,
                            ink: ends.onSuccess,
                            ring: ring,
                          ),
                        ),
                    ],
                  ),
                MapAttribution(darkBasemap: darkBasemap),
              ],
            ),
          ),
      ),
    );
  }
}

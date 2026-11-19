import 'dart:math' as math;

import 'package:core_models/core_models.dart' show GlobalSegmentRow, Waypoint;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:ui_kit/ui_kit.dart' show AppSemanticColors, ChartPalette;

import '../course_gates.dart';
import '../course_jump.dart';
import '../gate_crossing.dart' show Gate;
import '../l10n/gen/app_localizations.dart';
import '../park_courses.dart' show CourseCheckpoint, checkpointMarks;
import '../run_stats.dart' show haversineMetres;
import 'live_run_map.dart'
    show
        basemapTileLayer,
        basemapVoidColour,
        chevronInk,
        chevronOutline,
        currentBasemapIsDark,
        currentTileUrl,
        mapFinishZoneColour,
        mapOverlayOutline,
        mapStartZoneColour,
        mapBoxInk,
        mapTrackLine,
        mapZoneFillOpacity,
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

/// A course's start and finish lines as a page draws them: the segment's
/// stored lines, the ones the matcher times, or null unless both are whole
/// (decisions § 2582). Twin of web's `courseBoxGates` (`course_map.ts`).
({Gate start, Gate finish})? courseBoxGates(GlobalSegmentRow segment) {
  Gate? gate(double? lat, double? lng, double? bearing, double? halfWidth) {
    if (lat == null ||
        lng == null ||
        bearing == null ||
        halfWidth == null ||
        !lat.isFinite ||
        !lng.isFinite ||
        !bearing.isFinite ||
        !halfWidth.isFinite) {
      return null;
    }
    return Gate(lat: lat, lng: lng, bearingDeg: bearing, halfWidthM: halfWidth);
  }

  final start = gate(segment.startGateLat, segment.startGateLng,
      segment.startGateBearingDeg, segment.startGateHalfWidthM);
  final finish = gate(segment.endGateLat, segment.endGateLng,
      segment.endGateBearingDeg, segment.endGateHalfWidthM);
  if (start == null || finish == null) return null;
  return (start: start, finish: finish);
}

/// The one sentence a course page gives a runner (decisions § 2582): start
/// recording in the green box and follow the arrows to the red one (round the
/// loop [laps] times on a lapped course). Where the start and finish share a
/// spot, a loop or an out-and-back, it is one start box, left and come back
/// to, by way of the Turn around mark when the course marks one. Twin of
/// web's `courseBoxInstruction`.
String courseBoxInstruction(
  AppLocalizations l10n,
  ({Gate start, Gate finish}) g, {
  required bool hasTurn,
  int? laps,
}) {
  final n = laps != null && laps > 0 ? laps : 1;
  if (gateBoxParts(g.start, g.finish).layout == GateBoxLayout.shared) {
    return hasTurn ? l10n.parksBoxesOutAndBack : l10n.parksBoxesShared(n);
  }
  return l10n.parksBoxesApart(n);
}

LatLng _gp(GatePoint p) => LatLng(p.lat, p.lng);

/// The start and finish boxes over a course map (decisions § 2582), from
/// [gateBoxParts]: a translucent fill with a full-strength outline, the
/// timing line (solid for the start, chequered for the finish and for the one
/// start-coloured box a start and finish at one spot share), and a flag with
/// the box's name at a fixed size, so the boxes read first at the
/// whole-course zoom. Twin of web's `addCourseGateBoxLayers` and its markers.
List<Widget> courseGateBoxLayers({
  required Gate start,
  required Gate finish,
  required bool darkBasemap,
  required String startLabel,
  required String finishLabel,
  required String bothLabel,
  required double centreLng,
}) {
  final boxes = gateBoxParts(start, finish);

  final casing = mapOverlayOutline(darkBasemap: darkBasemap);
  Color colourOf(GateWhich? w) => w == GateWhich.finish
      ? mapFinishZoneColour(darkBasemap: darkBasemap)
      : mapStartZoneColour(darkBasemap: darkBasemap);
  final edges = <Polyline>[];
  for (final p in boxes.parts) {
    final pts = [_gp(p.line.$1), _gp(p.line.$2)];
    edges
      ..add(Polyline(points: pts, strokeWidth: 8, color: casing))
      ..add(Polyline(points: pts, strokeWidth: 5, color: colourOf(p.which)));
    if (p.which != GateWhich.start) {
      // The chequered finish: light squares over the edge's own colour.
      edges.add(Polyline(
        points: pts,
        strokeWidth: 5,
        color: Colors.white,
        pattern: StrokePattern.dashed(segments: const [5, 5]),
      ));
    }
  }
  return [
    PolygonLayer(
      key: const ValueKey('park-course-boxes'),
      polygons: [
        for (final p in boxes.parts)
          Polygon(
            points: [for (final q in p.box) _gp(q)],
            color: colourOf(p.which).withValues(alpha: mapZoneFillOpacity),
            borderColor: colourOf(p.which),
            borderStrokeWidth: 2,
          ),
      ],
    ),
    PolylineLayer(
        key: const ValueKey('park-course-box-edges'), polylines: edges),
    MarkerLayer(
      key: const ValueKey('park-course-box-markers'),
      markers: [
        for (final mk in boxes.markers)
          Marker(
            point: _gp(mk.at),
            width: 190,
            height: 34,
            alignment: mk.at.lng <= centreLng
                ? Alignment.centerRight
                : Alignment.centerLeft,
            child: Align(
              alignment: mk.at.lng <= centreLng
                  ? Alignment.centerLeft
                  : Alignment.centerRight,
              child: _BoxMarker(
                key: ValueKey('park-course-box-${mk.which?.name ?? 'both'}'),
                which: mk.which,
                label: switch (mk.which) {
                  GateWhich.start => startLabel,
                  GateWhich.finish => finishLabel,
                  null => bothLabel,
                },
                darkBasemap: darkBasemap,
              ),
            ),
          ),
      ],
    ),
  ];
}

/// A box's name tag, filled with the box's colour so it is the green or red
/// box at the whole-course zoom: a flag for the start, a chequered flag for
/// the finish, both flags (in the start colour, like the box) for a box they
/// share. The map's key
/// and the page's sentence name the boxes for a screen reader, so the tag is
/// excluded. Twin of web's box tags in `RunMap`.
class _BoxMarker extends StatelessWidget {
  final GateWhich? which;
  final String label;
  final bool darkBasemap;
  const _BoxMarker({
    super.key,
    required this.which,
    required this.label,
    required this.darkBasemap,
  });

  @override
  Widget build(BuildContext context) {
    final ink = mapBoxInk(darkBasemap: darkBasemap);
    // The tag has a fixed box on the map, so its text scales only so far.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: ExcludeSemantics(
        child: DecoratedBox(
          // A pill on the map, not a card: a stadium shape.
          decoration: ShapeDecoration(
            color: which == GateWhich.finish
                ? mapFinishZoneColour(darkBasemap: darkBasemap)
                : mapStartZoneColour(darkBasemap: darkBasemap),
            shape: StadiumBorder(
              side: BorderSide(
                width: 2,
                color: mapOverlayOutline(darkBasemap: darkBasemap),
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 2, 10, 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (which != GateWhich.finish)
                  Icon(Icons.flag_outlined, size: 18, color: ink),
                if (which != GateWhich.start)
                  Icon(Icons.sports_score, size: 18, color: ink),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .labelLarge
                        ?.copyWith(color: ink, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
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
  /// The numbers it stands for: one, or several checkpoints close enough to
  /// share a marker ([checkpointMarks]).
  final String number;
  final Color fill;
  final Color ink;

  const _CheckpointMarker({
    super.key,
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
    // A numbered dot on the map, widened to a stadium when two checkpoints
    // share it; not a status pill.
    return DecoratedBox(
      decoration: ShapeDecoration(color: fill, shape: const StadiumBorder()),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(number, style: style),
        ),
      ),
    );
  }
}

/// An out-and-back's turn: a U-turn and its name, on the label halo, where
/// the course's last checkpoint is. The key and the page's sentence name it
/// for a screen reader, so the marker is excluded.
class _TurnMarker extends StatelessWidget {
  final String label;
  final bool darkBasemap;
  const _TurnMarker({
    super.key,
    required this.label,
    required this.darkBasemap,
  });

  @override
  Widget build(BuildContext context) {
    final ink = mapOverlayOutline(darkBasemap: darkBasemap);
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: ExcludeSemantics(
      child: DecoratedBox(
        // A pill on the map, not a card: a stadium shape.
        decoration: ShapeDecoration(
          color: basemapVoidColour(darkBasemap: darkBasemap),
          shape: StadiumBorder(side: BorderSide(width: 2, color: ink)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 2, 10, 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.u_turn_left, size: 18, color: ink),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .labelLarge
                      ?.copyWith(color: ink, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
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
/// It does not pan or pinch, because it sits inside the course page's scroll
/// view; the buttons under it take it to the start, the finish (one button
/// where they share a box) and back to the whole course ([courseJumps]).
class ParkCourseMap extends StatefulWidget {
  final List<Waypoint> line;
  final List<CourseCheckpoint> checkpoints;
  final double aspectRatio;

  /// `park_courses.course_shape`: an out-and-back's last checkpoint is drawn
  /// as its turn.
  final String? shape;

  /// The stored start and finish lines, drawn as boxes in place of the
  /// start and finish pins; null draws the pins ([courseBoxGates]).
  final ({Gate start, Gate finish})? zones;

  const ParkCourseMap({
    super.key,
    required this.line,
    this.checkpoints = const [],
    this.aspectRatio = 1.5,
    this.shape,
    this.zones,
  });

  @override
  State<ParkCourseMap> createState() => ParkCourseMapState();
}

class ParkCourseMapState extends State<ParkCourseMap>
    with SingleTickerProviderStateMixin {
  final MapController _map = MapController();
  late final AnimationController _move;

  /// Where the camera is: what a widget test reads after a jump.
  @visibleForTesting
  MapCamera get camera => _map.camera;

  @override
  void initState() {
    super.initState();
    _move = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
  }

  @override
  void dispose() {
    _move.dispose();
    _map.dispose();
    super.dispose();
  }

  /// Fit the camera to [jump]'s bounds, never closer than [kCourseJumpMaxZoom]
  /// on a start or finish, and as the map opens on the whole course. Eased,
  /// or a jump when the reader has asked for less motion.
  void _jumpTo(CourseJump jump) {
    final b = jump.bounds;
    final fit = CameraFit.bounds(
      bounds: LatLngBounds(LatLng(b.south, b.west), LatLng(b.north, b.east)),
      padding: const EdgeInsets.all(28),
      maxZoom:
          jump.target == CourseJumpTarget.course ? 17 : kCourseJumpMaxZoom,
    );
    _move.stop();
    if (MediaQuery.disableAnimationsOf(context)) {
      _map.fitCamera(fit);
      return;
    }
    final from = _map.camera;
    final to = fit.fit(from);
    final curve = CurvedAnimation(parent: _move, curve: Curves.easeInOut);
    void step() {
      final t = curve.value;
      _map.move(
        LatLng(
          from.center.latitude + (to.center.latitude - from.center.latitude) * t,
          from.center.longitude +
              (to.center.longitude - from.center.longitude) * t,
        ),
        from.zoom + (to.zoom - from.zoom) * t,
      );
    }

    _move.addListener(step);
    _move.forward(from: 0).whenCompleteOrCancel(() {
      _move.removeListener(step);
      curve.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    final line = widget.line;
    final checkpoints = widget.checkpoints;
    final zones = widget.zones;
    if (line.length < 2) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final darkBasemap = currentBasemapIsDark(context);
    final ends = _endPalette(darkBasemap);
    final ring = mapOverlayOutline(darkBasemap: darkBasemap);
    final pts = [for (final w in line) _ll(w)];
    final shared = courseEndsShared(line);
    final step = math.max(_lineMetres(pts) / kParkCourseChevrons, 25.0);
    final chevrons = computeChevrons(pts, stepMetres: step);
    final marks = checkpointMarks(
      checkpoints: [for (final c in checkpoints) (lat: c.lat, lng: c.lng)],
      line: [for (final w in line) (lat: w.lat, lng: w.lng)],
      shape: widget.shape,
    );
    final jumps = courseJumps(
      gates: zones,
      line: [for (final w in line) GatePoint(w.lat, w.lng)],
      endsShared: shared,
    );
    // semantics-children: the map's credit line keeps its own node
    final map = Semantics(
      container: true,
      label: l10n.parksMapCourseLabel(checkpoints.length),
      child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(
            aspectRatio: widget.aspectRatio,
            child: FlutterMap(
              mapController: _map,
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
                    for (final k in marks)
                      if (k.isTurn)
                        Marker(
                          point: LatLng(k.lat, k.lng),
                          width: 160,
                          height: 32,
                          child: Center(
                            child: _TurnMarker(
                              key: const ValueKey('park-course-turnaround'),
                              label: l10n.parksTurnAround,
                              darkBasemap: darkBasemap,
                            ),
                          ),
                        )
                      else
                        Marker(
                          point: LatLng(k.lat, k.lng),
                          width: 14.0 + 8 * k.numbers.join(',').length,
                          height: 22,
                          child: _CheckpointMarker(
                            key: ValueKey(
                                'park-course-checkpoint-${k.numbers.join('-')}'),
                            number: k.numbers.join(', '),
                            fill: ring,
                            ink: basemapVoidColour(darkBasemap: darkBasemap),
                          ),
                        ),
                  ],
                ),
                // The boxes take the start and finish pins' place.
                if (zones case final z?)
                  ...courseGateBoxLayers(
                    start: z.start,
                    finish: z.finish,
                    darkBasemap: darkBasemap,
                    startLabel: l10n.parksLegendStart,
                    finishLabel: l10n.parksLegendFinish,
                    bothLabel: l10n.parksLegendStartFinish,
                    centreLng: (pts.map((p) => p.longitude).reduce(math.min) +
                            pts.map((p) => p.longitude).reduce(math.max)) /
                        2,
                  )
                else
                  MarkerLayer(
                    key: const ValueKey('park-course-ends'),
                    markers: [
                      if (!shared)
                        Marker(
                          point: pts.last,
                          width: 24,
                          height: 24,
                          child: _EndMarker(
                            icon: Icons.flag_outlined,
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
                          icon: shared ? Icons.flag_outlined : Icons.play_arrow,
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
    if (jumps.isEmpty) return map;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        map,
        const SizedBox(height: 8),
        _CourseJumpButtons(
          jumps: jumps,
          darkBasemap: darkBasemap,
          onJump: _jumpTo,
        ),
      ],
    );
  }
}

/// The row of buttons under a [ParkCourseMap]: a caption, then Start and
/// Finish (or one Start and finish) and Whole course, each an icon and a
/// word. The start and finish icons sit on their boxes' colours, as the boxes
/// on the map do; the word carries the meaning.
class _CourseJumpButtons extends StatelessWidget {
  const _CourseJumpButtons({
    required this.jumps,
    required this.darkBasemap,
    required this.onJump,
  });

  final List<CourseJump> jumps;
  final bool darkBasemap;
  final void Function(CourseJump) onJump;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    String label(CourseJumpTarget t) => switch (t) {
          CourseJumpTarget.start => l10n.parksLegendStart,
          CourseJumpTarget.finish => l10n.parksLegendFinish,
          CourseJumpTarget.startFinish => l10n.parksLegendStartFinish,
          CourseJumpTarget.course => l10n.parksMapJumpCourse,
        };
    Widget icon(CourseJumpTarget t) {
      final glyph = switch (t) {
        CourseJumpTarget.start => Icons.play_arrow,
        CourseJumpTarget.finish ||
        CourseJumpTarget.startFinish =>
          Icons.flag_outlined,
        CourseJumpTarget.course => Icons.route,
      };
      final fill = switch (t) {
        CourseJumpTarget.start ||
        CourseJumpTarget.startFinish =>
          mapStartZoneColour(darkBasemap: darkBasemap),
        CourseJumpTarget.finish =>
          mapFinishZoneColour(darkBasemap: darkBasemap),
        CourseJumpTarget.course => null,
      };
      if (fill == null) return const Icon(Icons.route, size: 20);
      return DecoratedBox(
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Icon(glyph,
              size: 18, color: mapBoxInk(darkBasemap: darkBasemap)),
        ),
      );
    }

    return Semantics(
      container: true,
      label: l10n.parksMapJumpLabel,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ExcludeSemantics(
            child: Text(
              l10n.parksMapJumpLabel,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          for (final j in jumps)
            OutlinedButton.icon(
              key: ValueKey('park-course-jump-${j.target.name}'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(48, 48),
              ),
              onPressed: () => onJump(j),
              icon: icon(j.target),
              label: Text(label(j.target)),
            ),
        ],
      ),
    );
  }
}

/// The key under a [ParkCourseMap]: one row per kind of mark the map draws,
/// each read by a screen reader as its own item.
class ParkCourseMapLegend extends StatelessWidget {
  final List<Waypoint> line;

  /// How many numbered checkpoint markers the map draws.
  final int checkpointCount;

  /// Whether the map marks an out-and-back's turn.
  final bool hasTurn;

  /// The lines the map draws as boxes, so the key names the boxes in place
  /// of the pins; null for none.
  final ({Gate start, Gate finish})? zones;

  const ParkCourseMapLegend({
    super.key,
    required this.line,
    required this.checkpointCount,
    this.hasTurn = false,
    this.zones,
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
    // semantics-children: a group name, read once before the controls inside it
    return Semantics(
      container: true,
      label: l10n.parksLegendTitle,
      child: Wrap(
        key: const Key('park-course-legend'),
        spacing: 16,
        runSpacing: 8,
        children: [
          // The boxes replace the pins on the map, so the key names the boxes.
          if (zones case final z?)
            if (gateBoxParts(z.start, z.finish).layout == GateBoxLayout.shared)
              item(
                const Key('park-course-legend-start-finish-box'),
                _BoxSwatch(darkBasemap: darkBasemap, which: null),
                l10n.parksLegendStartFinish,
              )
            else ...[
              item(
                const Key('park-course-legend-start-box'),
                _BoxSwatch(darkBasemap: darkBasemap, which: GateWhich.start),
                l10n.parksLegendStart,
              ),
              item(
                const Key('park-course-legend-finish-box'),
                _BoxSwatch(darkBasemap: darkBasemap, which: GateWhich.finish),
                l10n.parksLegendFinish,
              ),
            ]
          else if (shared)
            item(
              const Key('park-course-legend-start-finish'),
              _EndMarker(
                icon: Icons.flag_outlined,
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
                icon: Icons.flag_outlined,
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
                number: '1',
                fill: ring,
                ink: basemapVoidColour(darkBasemap: darkBasemap),
              ),
              l10n.parksLegendCheckpoints,
            ),
          if (hasTurn)
            item(
              const Key('park-course-legend-turnaround'),
              Center(
                child: Icon(Icons.u_turn_left,
                    size: 18, color: mapOverlayOutline(darkBasemap: darkBasemap)),
              ),
              l10n.parksLegendTurnAround,
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

/// A box as the map draws it, for the key: the fill, its outline and its
/// cased timing line, solid for the start, chequered for the finish, and for
/// a box the start and finish share ([which] null) the start colour with a
/// chequered line across its middle.
class _BoxSwatch extends StatelessWidget {
  final bool darkBasemap;
  final GateWhich? which;
  const _BoxSwatch({required this.darkBasemap, required this.which});

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _BoxSwatchPainter(
      colour: which == GateWhich.finish
          ? mapFinishZoneColour(darkBasemap: darkBasemap)
          : mapStartZoneColour(darkBasemap: darkBasemap),
      chequered: which != GateWhich.start,
      centred: which == null,
      casing: mapOverlayOutline(darkBasemap: darkBasemap),
    ),
  );
}

class _BoxSwatchPainter extends CustomPainter {
  final Color colour;
  final bool chequered;
  final bool centred;
  final Color casing;
  const _BoxSwatchPainter({
    required this.colour,
    required this.chequered,
    required this.centred,
    required this.casing,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final top = size.height * 0.2;
    final bottom = size.height * 0.8;
    final edge = centred ? (top + bottom) / 2 : top;
    final band = Rect.fromLTRB(0, top, size.width, bottom);
    canvas
      ..drawRect(
        band,
        Paint()..color = colour.withValues(alpha: mapZoneFillOpacity),
      )
      ..drawRect(
        band,
        Paint()
          ..color = colour
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      )
      ..drawLine(
        Offset(band.left, edge),
        Offset(band.right, edge),
        Paint()
          ..color = casing
          ..strokeWidth = 4,
      )
      ..drawLine(
        Offset(band.left, edge),
        Offset(band.right, edge),
        Paint()
          ..color = colour
          ..strokeWidth = 2.5,
      );
    if (chequered) {
      final white = Paint()
        ..color = Colors.white
        ..strokeWidth = 2.5;
      for (var x = band.left + 2.5; x < band.right; x += 5) {
        canvas.drawLine(
          Offset(x, edge),
          Offset((x + 2.5).clamp(0, band.right), edge),
          white,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_BoxSwatchPainter old) =>
      old.colour != colour ||
      old.chequered != chequered ||
      old.centred != centred ||
      old.casing != casing;
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
    // semantics-children: the map's credit line keeps its own node
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

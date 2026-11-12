import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:ui_kit/ui_kit.dart' show AppSemanticColors;

import '../course_gates.dart' show CourseGate, gateArrowTip, gateLineEnds, offsetPoint, GatePoint;
import '../l10n/gen/app_localizations.dart';
import 'live_run_map.dart'
    show basemapTileLayer, basemapVoidColour, currentBasemapIsDark, currentTileUrl;
import 'map_attribution.dart';

/// The semantic palette that reads against the basemap under the lines: the
/// dark set's lighter success / danger on a dark basemap, the light set's
/// deeper ones on a light basemap. Keyed on the basemap, not the app theme,
/// because the lines are drawn over tiles (as web's `mapStartColour` /
/// `mapFinishColour` are), and the extension's pairs are the measured ones.
AppSemanticColors _gatePalette(bool darkBasemap) =>
    darkBasemap ? AppSemanticColors.dark : AppSemanticColors.light;

/// The start line's colour: the palette's success green.
Color mapStartColour({required bool darkBasemap}) =>
    _gatePalette(darkBasemap).success;

/// The finish line's colour: the palette's danger red.
Color mapFinishColour({required bool darkBasemap}) =>
    _gatePalette(darkBasemap).danger;

LatLng _ll(GatePoint p) => LatLng(p.lat, p.lng);

/// The start line (green) and the finish line with its direction arrow, one
/// keyed layer per line so a test can find each. Empty for a course with no
/// lines. Shared by [CourseLinesMap] and the race screen's live map.
List<Widget> courseGateLayers({
  required CourseGate? start,
  required CourseGate? finish,
  required bool darkBasemap,
}) {
  List<Polyline> lineOf(CourseGate g, Color color) {
    final (left, right) = gateLineEnds(g);
    final centre = GatePoint(g.lat, g.lng);
    final tip = gateArrowTip(g);
    final barb = (g.halfWidthM * 0.4).clamp(4.0, 12.0);
    final arrow = [
      _ll(centre),
      _ll(tip),
    ];
    final head = [
      _ll(offsetPoint(tip, g.bearingDeg + 150, barb)),
      _ll(tip),
      _ll(offsetPoint(tip, g.bearingDeg - 150, barb)),
    ];
    Polyline stroke(List<LatLng> pts, double w, Color c) => Polyline(
          points: pts,
          strokeWidth: w,
          color: c,
          strokeCap: StrokeCap.round,
          strokeJoin: StrokeJoin.round,
        );
    const casing = Color(0x8C0B0A14);
    return [
      stroke([_ll(left), _ll(right)], 9, casing),
      stroke(arrow, 7, casing),
      stroke(head, 7, casing),
      stroke([_ll(left), _ll(right)], 5, color),
      stroke(arrow, 3, color),
      stroke(head, 3, color),
    ];
  }

  return [
    if (start != null)
      PolylineLayer(
        key: const ValueKey('course-gate-start'),
        polylines: lineOf(start, mapStartColour(darkBasemap: darkBasemap)),
      ),
    if (finish != null)
      PolylineLayer(
        key: const ValueKey('course-gate-finish'),
        polylines: lineOf(finish, mapFinishColour(darkBasemap: darkBasemap)),
      ),
  ];
}

/// A compact, non-interactive map of one course's start and finish lines.
/// It draws the lines only, never the route: a racer reads the course row,
/// not a route they may not own (decisions § 1845).
class CourseLinesMap extends StatelessWidget {
  const CourseLinesMap({
    super.key,
    required this.start,
    required this.finish,
    this.height = 160,
  });

  final CourseGate? start;
  final CourseGate? finish;
  final double height;

  @override
  Widget build(BuildContext context) {
    final gates = [?start, ?finish];
    if (gates.isEmpty) return const SizedBox.shrink();
    final darkBasemap = currentBasemapIsDark(context);
    final points = <LatLng>[
      for (final g in gates) ...[
        _ll(gateLineEnds(g).$1),
        _ll(gateLineEnds(g).$2),
        _ll(gateArrowTip(g)),
      ],
    ];
    final l10n = AppLocalizations.of(context);
    return Semantics(
      label: start != null && finish != null
          ? l10n.eventCourseLinesMapBoth
          : start != null
              ? l10n.eventCourseLinesMapStart
              : l10n.eventCourseLinesMapFinish,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: height,
          child: FlutterMap(
            options: MapOptions(
              backgroundColor: basemapVoidColour(darkBasemap: darkBasemap),
              initialCameraFit: CameraFit.coordinates(
                coordinates: points,
                padding: const EdgeInsets.all(28),
                maxZoom: 18,
              ),
              interactionOptions:
                  const InteractionOptions(flags: InteractiveFlag.none),
            ),
            children: [
              basemapTileLayer(urlTemplate: currentTileUrl(context)),
              ...courseGateLayers(
                  start: start, finish: finish, darkBasemap: darkBasemap),
              MapAttribution(darkBasemap: darkBasemap),
            ],
          ),
        ),
      ),
    );
  }
}

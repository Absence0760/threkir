import 'dart:math' as math;

import 'package:core_models/core_models.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart' show ChartPalette;

import '../elevation_profile.dart';
import '../preferences.dart' show UnitFormat;
import '../run_stats.dart' show haversineMetres;

/// Interactive elevation chart. Drag or tap to read distance, elevation and,
/// on a timed track, pace at any point along it. Shared by run detail and the
/// park course page, which hands it an untimed course line. One smoothed line over one gradient
/// fill, plotted against distance on a y-axis at least
/// [elevationMinSpanM] tall, so a flat run looks flat.
class ElevationChart extends StatefulWidget {
  final List<Waypoint> track;
  final ThemeData theme;
  final DistanceUnit unit;
  /// Linked-cursor: fires with the track-index currently under the
  /// pointer (null on touch release). Lets `run_detail_screen` paint
  /// the matching marker on `LiveRunMap` — Nike/Strava-style brushing.
  final ValueChanged<int?>? onHoverIdx;
  const ElevationChart({
    super.key,
    required this.track,
    required this.theme,
    required this.unit,
    this.onHoverIdx,
  });

  @override
  State<ElevationChart> createState() => _ElevationChartState();
}

/// The chart's derived series, computed once per track rather than per
/// frame of a drag.
class _ElevationProfile {
  final List<double> smoothed;
  final double dataMin;
  final double dataMax;
  final ({double lo, double hi}) domain;
  const _ElevationProfile(this.smoothed, this.dataMin, this.dataMax, this.domain);
}

class _ElevationChartState extends State<ElevationChart> {
  static const double _chartHeight = 140;
  static const double _minGutter = 40;

  /// Wide enough for the longer of the two gutter labels in the runner's
  /// unit: "8,848 m" fits the old fixed 40 px, "5,577 ft" does not.
  double _gutter = _minGutter;

  int? _touchIdx;
  int? _lastEmittedIdx;
  late List<double> _cum;
  late bool _timed;
  _ElevationProfile? _profile;

  @override
  void initState() {
    super.initState();
    _derive();
  }

  @override
  void didUpdateWidget(covariant ElevationChart old) {
    super.didUpdateWidget(old);
    if (!identical(old.track, widget.track)) _derive();
  }

  void _derive() {
    _cum = cumulativeMetres(widget.track);
    _timed = widget.track.any((w) => w.timestamp != null);
    final series = elevationSeries(widget.track);
    if (series == null) {
      _profile = null;
      return;
    }
    final smoothed = smoothElevation(series, _cum);
    var lo = smoothed.first, hi = smoothed.first;
    for (final v in smoothed) {
      if (v < lo) lo = v;
      if (v > hi) hi = v;
    }
    _profile = _ElevationProfile(smoothed, lo, hi, elevationDomain(lo, hi));
  }

  void _emitHover() {
    if (widget.onHoverIdx == null) return;
    if (_touchIdx != _lastEmittedIdx) {
      _lastEmittedIdx = _touchIdx;
      widget.onHoverIdx!(_touchIdx);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    if (profile == null) return const SizedBox.shrink();
    final theme = widget.theme;
    final labelStyle = theme.textTheme.labelSmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final total = _cum.isEmpty ? 0.0 : _cum.last;
    final textScaler = MediaQuery.textScalerOf(context);
    var widest = 0.0;
    for (final ele in [profile.dataMin, profile.dataMax]) {
      final tp = TextPainter(
        text: TextSpan(
          text: UnitFormat.elevation(ele, widget.unit),
          style: theme.textTheme.labelSmall,
        ),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
      )..layout();
      if (tp.width > widest) widest = tp.width;
    }
    _gutter = math.max(_minGutter, (widest + 8).ceilToDouble());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: textScaler.scale(20),
          child: _touchIdx != null ? _buildCrosshairLabel() : null,
        ),
        SizedBox(
          height: _chartHeight,
          child: GestureDetector(
            onPanStart: (d) => _onTouch(d.localPosition),
            onPanUpdate: (d) => _onTouch(d.localPosition),
            onPanEnd: (_) => _clearTouch(),
            onTapDown: (d) => _onTouch(d.localPosition),
            onTapUp: (_) => _clearTouch(),
            onTapCancel: _clearTouch,
            child: CustomPaint(
              painter: _ElevationPainter(
                smoothed: profile.smoothed,
                cumulativeM: _cum,
                dataMin: profile.dataMin,
                dataMax: profile.dataMax,
                domain: profile.domain,
                theme: theme,
                gutter: _gutter,
                unit: widget.unit,
                textScaler: textScaler,
                touchIdx: _touchIdx,
              ),
              size: const Size(double.infinity, _chartHeight),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.only(left: _gutter, top: 4),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            children: [
              Text(UnitFormat.distance(0, widget.unit), style: labelStyle),
              Text(UnitFormat.distance(total, widget.unit), style: labelStyle),
            ],
          ),
        ),
      ],
    );
  }

  void _clearTouch() {
    setState(() => _touchIdx = null);
    _emitHover();
  }

  void _onTouch(Offset local) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || _cum.length < 2) return;
    final plotWidth = box.size.width - _gutter;
    if (plotWidth <= 0) return;
    final frac = ((local.dx - _gutter) / plotWidth).clamp(0.0, 1.0);
    final target = frac * _cum.last;
    var lo = 0, hi = _cum.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_cum[mid] < target) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    setState(() => _touchIdx = lo);
    _emitHover();
  }

  Widget _buildCrosshairLabel() {
    final idx = _touchIdx!;
    final ele = _profile?.smoothed[idx];
    final cumDist = _cum[idx];

    // Local pace: compute from a ~200m window around this point.
    String paceStr = '--';
    if (idx >= 2 && idx < widget.track.length - 1) {
      final windowStart = (idx - 5).clamp(0, widget.track.length - 1);
      final windowEnd = (idx + 5).clamp(0, widget.track.length - 1);
      final a = widget.track[windowStart];
      final b = widget.track[windowEnd];
      if (a.timestamp != null && b.timestamp != null) {
        double segDist = 0;
        for (var i = windowStart + 1; i <= windowEnd; i++) {
          segDist += haversineMetres(
            widget.track[i - 1].lineLat, widget.track[i - 1].lineLng,
            widget.track[i].lineLat, widget.track[i].lineLng,
          );
        }
        if (segDist > 10) {
          final dtSec =
              b.timestamp!.difference(a.timestamp!).inMilliseconds / 1000.0;
          if (dtSec > 0) {
            final secPerKm = dtSec / segDist * 1000;
            paceStr = UnitFormat.pace(secPerKm, widget.unit);
          }
        }
      }
    }

    final theme = widget.theme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            UnitFormat.distance(cumDist, widget.unit),
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 16),
          if (ele != null)
            Text(
              UnitFormat.elevation(ele, widget.unit),
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          if (_timed) ...[
            const SizedBox(width: 16),
            Text(
              '$paceStr ${UnitFormat.paceLabel(widget.unit)}',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The elevations the elevation chart labels in its gutter: the data's
/// rounded low and high, or a single label at the rounded middle when those
/// two would sit closer than [minGapPx] on a [plotHeight]-tall plot of
/// [domain]. A flat run's domain is padded to 36 m, so a 100-102 m run put
/// its two labels 7.8 px apart on the 140 px chart and painted them over
/// each other.
@visibleForTesting
List<double> elevationGutterLabels({
  required double dataMin,
  required double dataMax,
  required ({double lo, double hi}) domain,
  required double plotHeight,
  required double minGapPx,
}) {
  final lo = dataMin.roundToDouble();
  final hi = dataMax.roundToDouble();
  final range = domain.hi - domain.lo;
  final gapPx = (hi - lo).abs() / range * plotHeight;
  if (lo != hi && gapPx >= minGapPx) return [lo, hi];
  return [((dataMin + dataMax) / 2).roundToDouble()];
}

class _ElevationPainter extends CustomPainter {
  final List<double> smoothed;
  final List<double> cumulativeM;
  final double dataMin;
  final double dataMax;
  final ({double lo, double hi}) domain;
  final ThemeData theme;
  final double gutter;
  final DistanceUnit unit;
  final TextScaler textScaler;
  final int? touchIdx;

  _ElevationPainter({
    required this.smoothed,
    required this.cumulativeM,
    required this.dataMin,
    required this.dataMax,
    required this.domain,
    required this.theme,
    required this.gutter,
    required this.unit,
    required this.textScaler,
    this.touchIdx,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final n = smoothed.length;
    final total = cumulativeM.last;
    if (n < 2 || total <= 0) return;
    final plotLeft = gutter;
    final plotWidth = size.width - gutter;
    final range = domain.hi - domain.lo;
    double xAt(int i) => plotLeft + cumulativeM[i] / total * plotWidth;
    double yAt(double ele) => size.height - (ele - domain.lo) / range * size.height;

    final colour = ChartPalette.ofTheme(theme).series.first;
    final labelStyle = theme.textTheme.labelSmall!
        .copyWith(color: theme.colorScheme.onSurfaceVariant);
    // Gridlines and labels at the data's own low and high points, in the
    // gutter rather than on the plot, so neither ever sits on the line.
    final labelHeight = (TextPainter(
      text: TextSpan(text: '0 m', style: labelStyle),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    )..layout())
        .height;
    for (final ele in elevationGutterLabels(
      dataMin: dataMin,
      dataMax: dataMax,
      domain: domain,
      plotHeight: size.height,
      minGapPx: labelHeight,
    )) {
      final y = yAt(ele);
      canvas.drawLine(
        Offset(plotLeft, y),
        Offset(size.width, y),
        Paint()
          ..color = theme.dividerColor
          ..strokeWidth = 1,
      );
      final tp = TextPainter(
        text: TextSpan(
          text: UnitFormat.elevation(ele, unit),
          style: labelStyle,
        ),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
      )..layout(maxWidth: gutter - 4);
      tp.paint(canvas, Offset(gutter - 4 - tp.width, y - tp.height / 2));
    }

    final line = Path()..moveTo(xAt(0), yAt(smoothed[0]));
    for (var i = 1; i < n; i++) {
      line.lineTo(xAt(i), yAt(smoothed[i]));
    }
    final fill = Path.from(line)
      ..lineTo(xAt(n - 1), size.height)
      ..lineTo(xAt(0), size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            colour.withValues(alpha: 0.35),
            colour.withValues(alpha: 0.04),
          ],
        ).createShader(Rect.fromLTWH(plotLeft, 0, plotWidth, size.height)),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = colour
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );

    final idx = touchIdx;
    if (idx != null && idx >= 0 && idx < n) {
      final tx = xAt(idx);
      final ty = yAt(smoothed[idx]);
      canvas.drawLine(
        Offset(tx, 0),
        Offset(tx, size.height),
        Paint()
          ..color = theme.colorScheme.outline
          ..strokeWidth = 1,
      );
      canvas.drawCircle(Offset(tx, ty), 5, Paint()..color = colour);
      canvas.drawCircle(
        Offset(tx, ty),
        5,
        Paint()
          ..color = theme.colorScheme.surface
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ElevationPainter old) =>
      !identical(old.smoothed, smoothed) ||
      old.touchIdx != touchIdx ||
      old.gutter != gutter ||
      old.unit != unit ||
      old.textScaler != textScaler ||
      old.theme != theme;
}

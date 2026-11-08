import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:ui_kit/ui_kit.dart' show AppTheme;

import '../l10n/date_format.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../pr_card.dart';
import '../preferences.dart';
import '../privacy.dart';
import '../run_share_stats.dart';
import '../share_look.dart';
import '../share_placement.dart';
import 'plan_recap_card.dart' show planRecapBracketLabel;
import 'track_preview.dart' show projectTrack;

/// Every share image is laid out at a fixed logical size and rasterised up to
/// this many pixels across, so the PNG is the same whatever phone made it and
/// a story or feed post is never upscaled.
const double shareImageExportWidthPx = 1080;

/// The colours one [RunShareInk] draws with. Labels take [muted], numbers and
/// the route take [text]; [shadow] keeps both legible on whatever photo the
/// image lands on, and [halo] is the soft casing under the route line.
/// [accent] marks the one figure an occasion sticker singles out, such as the
/// fastest split: the coral on the white and black inks, white on the coral.
@immutable
class RunShareInkSpec {
  final Color text;
  final Color muted;
  final Color accent;
  final Color shadow;
  final Color halo;

  const RunShareInkSpec._({
    required this.text,
    required this.muted,
    required this.accent,
    required this.shadow,
    required this.halo,
  });

  static final _light = RunShareInkSpec._(
    text: Colors.white,
    muted: Colors.white.withValues(alpha: 0.85),
    accent: AppTheme.coral,
    shadow: Colors.black.withValues(alpha: 0.55),
    halo: Colors.black.withValues(alpha: 0.35),
  );
  static final _dark = RunShareInkSpec._(
    text: AppTheme.ink,
    muted: AppTheme.ink.withValues(alpha: 0.8),
    accent: AppTheme.coralDeep,
    shadow: Colors.white.withValues(alpha: 0.6),
    halo: Colors.white.withValues(alpha: 0.5),
  );
  static final _brand = RunShareInkSpec._(
    text: AppTheme.coral,
    muted: Colors.white.withValues(alpha: 0.9),
    accent: Colors.white,
    shadow: Colors.black.withValues(alpha: 0.6),
    halo: Colors.black.withValues(alpha: 0.4),
  );

  static RunShareInkSpec of(RunShareInk ink) => switch (ink) {
        RunShareInk.light => _light,
        RunShareInk.dark => _dark,
        RunShareInk.brand => _brand,
      };

  Color role(RunShareInkRole role) => switch (role) {
        RunShareInkRole.text => text,
        RunShareInkRole.muted => muted,
        RunShareInkRole.accent => accent,
      };

  List<Shadow> get shadows => [
        Shadow(color: shadow, blurRadius: 10, offset: const Offset(0, 1)),
      ];
}

/// The Threkir mark — the gradient tile and its white glyph — painted from the
/// geometry of `apps/web/static/logo-mark.svg` (glyph, gradient) with the
/// rounded tile `wordmark.svg` draws, so no share image depends on an asset
/// load finishing before the capture.
class ThrekirMarkPainter extends CustomPainter {
  const ThrekirMarkPainter();

  // logo-mark.svg's own units: a 1024 tile (rounded at 180, as wordmark.svg
  // rounds it), the glyph drawn at scale 7.6 about (54.5, 50).
  static const double _tile = 1024;
  static const double _corner = 180;
  static const double _glyphScale = 7.6;
  static const _gradient = [
    AppTheme.coralDeep,
    Color(0xFFA8426A),
    AppTheme.violet,
  ];

  static Offset _g(double x, double y) => Offset(
        _tile / 2 + _glyphScale * (x - 54.5),
        _tile / 2 + _glyphScale * (y - 50),
      );

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas.save();
    canvas.scale(size.shortestSide / _tile);
    const tile = Rect.fromLTWH(0, 0, _tile, _tile);
    canvas.drawRRect(
      RRect.fromRectAndRadius(tile, const Radius.circular(_corner)),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _gradient,
        ).createShader(tile),
    );
    final glyph = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Rect.fromPoints(_g(30, 10), _g(44, 90)))
      ..moveTo(_g(44, 29).dx, _g(44, 29).dy)
      ..lineTo(_g(58, 29).dx, _g(58, 29).dy)
      ..arcToPoint(_g(58, 71), radius: const Radius.circular(21 * _glyphScale))
      ..lineTo(_g(44, 71).dx, _g(44, 71).dy)
      ..close()
      ..moveTo(_g(44, 42).dx, _g(44, 42).dy)
      ..lineTo(_g(56, 42).dx, _g(56, 42).dy)
      ..arcToPoint(_g(56, 58), radius: const Radius.circular(8 * _glyphScale))
      ..lineTo(_g(44, 58).dx, _g(44, 58).dy)
      ..close();
    canvas.drawPath(glyph, Paint()..color = Colors.white);
    canvas.restore();
  }

  @override
  bool shouldRepaint(ThrekirMarkPainter oldDelegate) => false;
}

/// The Threkir signature every share image carries: the mark beside the
/// wordmark, in the image's ink.
class ThrekirShareBrand extends StatelessWidget {
  final Color color;
  final List<Shadow> shadows;
  final double markSize;

  const ThrekirShareBrand({
    super.key,
    required this.color,
    this.shadows = const [],
    this.markSize = 18,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox.square(
          dimension: markSize,
          child: const CustomPaint(painter: ThrekirMarkPainter()),
        ),
        SizedBox(width: markSize * 0.45),
        Text(
          l10n.shareCardBrandRun.toUpperCase(),
          maxLines: 1,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
                letterSpacing: 2.6,
                height: 1,
                shadows: shadows,
              ),
        ),
      ],
    );
  }
}

/// The clipped [runShareCardTrack] as an outline with no basemap: the line the
/// photo and sticker images draw. A soft [halo] keeps it legible on a busy
/// photo. Nothing is drawn under two points.
class RunRouteOutlinePainter extends CustomPainter {
  final List<Waypoint> points;
  final Color color;
  final Color halo;

  const RunRouteOutlinePainter(
    this.points, {
    this.color = Colors.white,
    this.halo = Colors.black26,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2 || size.isEmpty) return;
    final stroke = (size.shortestSide * 0.032).clamp(2.5, 7.0);
    final projected =
        projectTrack(points, size.width, size.height, pad: stroke * 2);
    if (projected.length < 2) return;
    final path = Path()..moveTo(projected.first.dx, projected.first.dy);
    for (var i = 1; i < projected.length; i++) {
      path.lineTo(projected[i].dx, projected[i].dy);
    }
    Paint line(double width, Color c) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = c;
    canvas.drawPath(
      path,
      line(stroke * 2.4, halo)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, stroke),
    );
    canvas.drawPath(path, line(stroke, color));
    canvas.drawCircle(projected.last, stroke * 1.3, Paint()..color = color);
  }

  @override
  bool shouldRepaint(RunRouteOutlinePainter oldDelegate) =>
      !identical(oldDelegate.points, points) ||
      oldDelegate.color != color ||
      oldDelegate.halo != halo;
}

/// One figure as the overlays print it: a small uppercase label over a large
/// value with its unit, each scaled down rather than clipped when a long value
/// or a long label meets a narrow column.
class _Figure extends StatelessWidget {
  final RunShareStat stat;
  final RunShareInkSpec ink;
  final TextStyle? valueStyle;
  final TextScaler valueScale;

  const _Figure(
    this.stat, {
    required this.ink,
    required this.valueStyle,
    this.valueScale = TextScaler.noScaling,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final unit = stat.unit;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            stat.label.toUpperCase(),
            maxLines: 1,
            style: text.labelMedium?.copyWith(
              color: ink.muted,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.6,
              shadows: ink.shadows,
            ),
          ),
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                stat.value,
                maxLines: 1,
                textScaler: valueScale,
                style: valueStyle?.copyWith(
                  color: ink.text,
                  fontWeight: FontWeight.w800,
                  height: 1.05,
                  letterSpacing: -0.5,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  shadows: ink.shadows,
                ),
              ),
              if (unit != null) ...[
                const SizedBox(width: 4),
                Text(
                  unit,
                  maxLines: 1,
                  style: text.titleSmall?.copyWith(
                    color: ink.muted,
                    fontWeight: FontWeight.w700,
                    shadows: ink.shadows,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// The stats, route and signature of one [RunStickerLayout], laid out at
/// [widthFor] logical pixels with no ground of its own: the photo style lays
/// it over a photo, the sticker style exports it on transparency.
class RunStickerContent extends StatelessWidget {
  final RunStickerLayout layout;
  final List<RunShareStat> stats;
  final List<Waypoint> track;
  final RunShareInkSpec ink;

  /// Whether the Threkir signature closes the content; off when the runner
  /// turned the mark off.
  final bool mark;

  const RunStickerContent({
    super.key,
    required this.layout,
    required this.stats,
    required this.track,
    required this.ink,
    this.mark = true,
  });

  /// The strip is a single line, so it is laid out wide; every other layout
  /// stacks and is portrait.
  static double widthFor(RunStickerLayout layout) =>
      layout == RunStickerLayout.strip ? 560 : 320;

  bool get _hasRoute => track.length >= 2;

  Widget _route(double size) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: RunRouteOutlinePainter(track, color: ink.text, halo: ink.halo),
        ),
      );

  Widget _row(List<RunShareStat> row, TextStyle? style) => Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final (i, stat) in row.indexed) ...[
            if (i > 0) const SizedBox(width: 12),
            Expanded(child: _Figure(stat, ink: ink, valueStyle: style)),
          ],
        ],
      );

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final brand = ThrekirShareBrand(color: ink.text, shadows: ink.shadows);
    final width = widthFor(layout);
    switch (layout) {
      case RunStickerLayout.stack:
        return SizedBox(
          width: width,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final stat in stats)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _Figure(
                    stat,
                    ink: ink,
                    valueStyle: text.displaySmall,
                    valueScale: const TextScaler.linear(1.25),
                  ),
                ),
              if (_hasRoute) ...[_route(150), const SizedBox(height: 16)],
              if (mark) brand,
            ],
          ),
        );
      case RunStickerLayout.route:
        return SizedBox(
          width: width,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_hasRoute) ...[_route(width * 0.82), const SizedBox(height: 14)],
              _row(stats, text.headlineMedium),
              const SizedBox(height: 16),
              if (mark) brand,
            ],
          ),
        );
      case RunStickerLayout.strip:
        return SizedBox(
          width: width,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  for (final (i, stat) in stats.indexed) ...[
                    if (i > 0)
                      Container(
                        width: 2,
                        height: 44,
                        margin: const EdgeInsets.symmetric(horizontal: 10),
                        color: ink.muted,
                      ),
                    Expanded(
                      child: _Figure(
                        stat,
                        ink: ink,
                        valueStyle: text.headlineMedium,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              if (mark) brand,
            ],
          ),
        );
      case RunStickerLayout.hero:
        final rest = stats.skip(1).toList();
        return SizedBox(
          width: width,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Figure(
                stats.first,
                ink: ink,
                valueStyle: text.displayLarge,
                valueScale: const TextScaler.linear(1.6),
              ),
              if (rest.isNotEmpty) ...[
                const SizedBox(height: 10),
                _row(rest, text.titleLarge),
              ],
              const SizedBox(height: 16),
              if (mark) brand,
            ],
          ),
        );
    }
  }
}


/// Which of an ink's colours a line of an occasion sticker takes.
enum RunShareInkRole { text, muted, accent }

/// The type step one line of an occasion sticker is set at: [label] the
/// small uppercase kicker, up to [hero] for a streak's day count. Web's
/// `OccasionStep`.
enum OccasionStep { label, title, headline, display, hero }

/// One centred line of an occasion sticker. [maxLines] above 1 wraps; a
/// single line scales down rather than overflowing the width.
@immutable
class OccasionLine {
  final String text;
  final OccasionStep step;
  final RunShareInkRole ink;
  final int maxLines;

  const OccasionLine(this.text, this.step, this.ink, {this.maxLines = 1});
}

/// One table row of the splits sticker: the split's number and its pace,
/// already formatted.
@immutable
class SplitsStickerEntry {
  final String label;
  final String pace;
  final SplitsStickerRow row;

  const SplitsStickerEntry(this.label, this.pace, this.row);
}

/// What an occasion sticker draws, web's `StickerBody` less its stats arm
/// (which [RunStickerContent] draws): a stack of lines over an optional route
/// — a record, a streak day, a race, a badge, or the route alone — or the
/// run's splits.
sealed class RunOccasionBody {
  const RunOccasionBody();
}

class OccasionLinesBody extends RunOccasionBody {
  final List<OccasionLine> lines;

  /// The route's size, or 0 for none.
  final double route;

  const OccasionLinesBody(this.lines, {this.route = 0});
}

class SplitsStickerBody extends RunOccasionBody {
  final String heading;
  final List<SplitsStickerEntry> entries;

  const SplitsStickerBody(this.heading, this.entries);
}

/// The occasion stickers' layout constants, twins of web's in
/// run_sticker_canvas.ts. The splits cut-overs are derived from these and
/// [SplitsStickerBudget], never written down.
abstract final class OccasionLayout {
  static const double width = 320;
  static const double lineGap = 6;
  static const double route = 110;
  static const double routeSticker = width * 0.82;
  static const double splitRowH = 30;
  static const double splitHeadingH = 16;
  static const double splitHeadingGap = 10;
  static const double splitBrandGap = 12;
  static const double splitBarsH = 120;
  static const double splitBarMin = 0.2;
  static const double splitSingleW = 220;
  static const double splitColumnGap = 20;
  static const double brandMark = 18;

  /// Everything on a splits sticker that is not a row: the padding, the
  /// heading, the signature and their gaps.
  static const double splitsChrome = RunStickerShareCard._pad * 2 +
      splitHeadingH +
      splitHeadingGap +
      splitBrandGap +
      brandMark;

  /// Rows one column holds, for rows set at [rowTextPx].
  static int splitsCapacity(double rowTextPx) =>
      splitsColumnCapacity(rowTextPx, splitRowH, splitsChrome);
}

/// A personal record: what it is, the bracket in the accent, the time, and how
/// much it beat the old one by.
OccasionLinesBody prStickerBody({
  required String headline,
  required String distance,
  required String time,
  String? improvement,
  required bool hasRoute,
}) =>
    OccasionLinesBody([
      OccasionLine(headline, OccasionStep.label, RunShareInkRole.muted),
      OccasionLine(distance, OccasionStep.headline, RunShareInkRole.accent),
      OccasionLine(time, OccasionStep.display, RunShareInkRole.text),
      if (improvement != null)
        OccasionLine(improvement, OccasionStep.title, RunShareInkRole.text),
    ], route: hasRoute ? OccasionLayout.route : 0);

/// A day of a streak: the day count huge, between what it is and what it
/// means.
OccasionLinesBody streakStickerBody({
  required String kicker,
  required String days,
  required String caption,
}) =>
    OccasionLinesBody([
      OccasionLine(kicker, OccasionStep.label, RunShareInkRole.muted),
      OccasionLine(days, OccasionStep.hero, RunShareInkRole.text),
      OccasionLine(caption, OccasionStep.title, RunShareInkRole.accent),
    ]);

/// A race finish: with an official time, the time is the hero under the
/// race; without one, the word Finisher is.
OccasionLinesBody raceStickerBody({
  required String name,
  required String finisher,
  String? time,
  required bool hasRoute,
}) =>
    OccasionLinesBody(
      time != null
          ? [
              OccasionLine(finisher, OccasionStep.label, RunShareInkRole.muted),
              OccasionLine(name, OccasionStep.headline, RunShareInkRole.text,
                  maxLines: 2),
              OccasionLine(time, OccasionStep.display, RunShareInkRole.accent),
            ]
          : [
              OccasionLine(name, OccasionStep.headline, RunShareInkRole.text,
                  maxLines: 2),
              OccasionLine(
                  finisher, OccasionStep.display, RunShareInkRole.accent),
            ],
      route: hasRoute ? OccasionLayout.route : 0,
    );

/// A park course time: what it is, the course and its park, the time in the
/// accent, and the season place when the run holds one.
OccasionLinesBody courseStickerBody({
  required String kicker,
  required String name,
  required String park,
  required String time,
  String? rank,
  required bool hasRoute,
}) =>
    OccasionLinesBody(
      [
        OccasionLine(kicker, OccasionStep.label, RunShareInkRole.muted),
        OccasionLine(name, OccasionStep.headline, RunShareInkRole.text,
            maxLines: 2),
        OccasionLine(park, OccasionStep.title, RunShareInkRole.muted),
        OccasionLine(time, OccasionStep.display, RunShareInkRole.accent),
        if (rank != null)
          OccasionLine(rank, OccasionStep.title, RunShareInkRole.text),
      ],
      route: hasRoute ? OccasionLayout.route : 0,
    );

/// A badge the run earned: its name, and its tier in the accent.
OccasionLinesBody badgeStickerBody({
  required String kicker,
  required String name,
  required String tier,
}) =>
    OccasionLinesBody([
      OccasionLine(kicker, OccasionStep.label, RunShareInkRole.muted),
      OccasionLine(name, OccasionStep.headline, RunShareInkRole.text,
          maxLines: 2),
      OccasionLine(tier, OccasionStep.label, RunShareInkRole.accent),
    ]);

OccasionLinesBody routeStickerBody() =>
    const OccasionLinesBody([], route: OccasionLayout.routeSticker);

/// An occasion sticker's content and signature, [OccasionLayout.width] wide
/// with no ground of its own: the twin of web's `layoutBodyContent` for every
/// body but stats.
class RunOccasionContent extends StatelessWidget {
  final RunOccasionBody body;
  final List<Waypoint> track;
  final RunShareInkSpec ink;
  final bool mark;

  const RunOccasionContent({
    super.key,
    required this.body,
    required this.track,
    required this.ink,
    this.mark = true,
  });

  TextStyle? _style(TextTheme text, OccasionStep step) => switch (step) {
        OccasionStep.label => text.labelMedium
            ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 1.6),
        OccasionStep.title =>
          text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        OccasionStep.headline =>
          text.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
        OccasionStep.display => text.displayLarge?.copyWith(
            fontWeight: FontWeight.w800, letterSpacing: -0.5, height: 1.05),
        OccasionStep.hero => text.displayLarge?.copyWith(
            fontWeight: FontWeight.w800, letterSpacing: -1, height: 1),
      };

  TextScaler _scale(OccasionStep step) => switch (step) {
        OccasionStep.display => const TextScaler.linear(1.25),
        OccasionStep.hero => const TextScaler.linear(1.8),
        _ => TextScaler.noScaling,
      };

  Widget _line(TextTheme text, OccasionLine line) {
    final style = _style(text, line.step)?.copyWith(
      color: ink.role(line.ink),
      fontFeatures: const [FontFeature.tabularFigures()],
      shadows: ink.shadows,
    );
    final value =
        line.step == OccasionStep.label ? line.text.toUpperCase() : line.text;
    if (line.maxLines > 1) {
      return Text(
        value,
        maxLines: line.maxLines,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        textScaler: _scale(line.step),
        style: style,
      );
    }
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(value,
          maxLines: 1, textScaler: _scale(line.step), style: style),
    );
  }

  Widget _route(double size) => SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter:
              RunRouteOutlinePainter(track, color: ink.text, halo: ink.halo),
        ),
      );

  Widget _lines(TextTheme text, OccasionLinesBody b) {
    final route = track.length >= 2 ? b.route : 0.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, line) in b.lines.indexed) ...[
          if (i > 0) const SizedBox(height: OccasionLayout.lineGap),
          _line(text, line),
        ],
        if (route > 0) ...[
          if (b.lines.isNotEmpty) const SizedBox(height: 18),
          _route(route),
        ],
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _rows(TextTheme text, List<SplitsStickerEntry> entries, int fastest,
      double width) {
    final rowStyle = text.titleLarge?.copyWith(
      fontWeight: FontWeight.w800,
      fontFeatures: const [FontFeature.tabularFigures()],
      shadows: ink.shadows,
      height: 1,
    );
    return SizedBox(
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, e) in entries.indexed)
            SizedBox(
              height: OccasionLayout.splitRowH,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: SizedBox(
                  width: width,
                  child: Row(
                    children: [
                      Text(
                        e.label,
                        maxLines: 1,
                        style: rowStyle?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: i == fastest ? ink.accent : ink.muted,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        e.pace,
                        maxLines: 1,
                        style: rowStyle?.copyWith(
                          color: i == fastest ? ink.accent : ink.text,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _splits(TextTheme text, SplitsStickerBody b) {
    final rowText = text.titleLarge?.fontSize ?? 22;
    final rows = [for (final e in b.entries) e.row];
    final fastest = fastestStickerSplit(rows);
    final form = splitsStickerForm(
        b.entries.length, OccasionLayout.splitsCapacity(rowText));
    final Widget table = switch (form) {
      SplitsStickerForm.single =>
        _rows(text, b.entries, fastest, OccasionLayout.splitSingleW),
      SplitsStickerForm.paired => () {
          final perColumn = (b.entries.length / 2).ceil();
          const colW =
              (OccasionLayout.width - OccasionLayout.splitColumnGap) / 2;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _rows(text, b.entries.sublist(0, perColumn), fastest, colW),
              const SizedBox(width: OccasionLayout.splitColumnGap),
              _rows(text, b.entries.sublist(perColumn), fastest - perColumn,
                  colW),
            ],
          );
        }(),
      SplitsStickerForm.bars => SizedBox(
          width: OccasionLayout.width,
          height: OccasionLayout.splitBarsH,
          child: CustomPaint(
            painter: SplitBarsPainter(
              rows: rows,
              fastest: fastest,
              average: averageStickerPace(rows),
              ink: ink,
            ),
          ),
        ),
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: OccasionLayout.splitHeadingH,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              b.heading.toUpperCase(),
              maxLines: 1,
              style: text.labelMedium?.copyWith(
                color: ink.muted,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.6,
                height: 1,
                shadows: ink.shadows,
              ),
            ),
          ),
        ),
        const SizedBox(height: OccasionLayout.splitHeadingGap),
        table,
        const SizedBox(height: OccasionLayout.splitBrandGap),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = body;
    return SizedBox(
      width: OccasionLayout.width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          switch (b) {
            OccasionLinesBody() => _lines(text, b),
            SplitsStickerBody() => _splits(text, b),
          },
          if (mark)
            ThrekirShareBrand(
              color: ink.text,
              shadows: ink.shadows,
              markSize: OccasionLayout.brandMark,
            ),
        ],
      ),
    );
  }
}

/// One bar per split, height by speed so the faster split stands taller, the
/// fastest in the accent and a partial tail muted, over a line at the average
/// pace. Web's `bar` ops.
class SplitBarsPainter extends CustomPainter {
  final List<SplitsStickerRow> rows;
  final int fastest;
  final double? average;
  final RunShareInkSpec ink;

  const SplitBarsPainter({
    required this.rows,
    required this.fastest,
    required this.average,
    required this.ink,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (rows.isEmpty || size.isEmpty) return;
    final speeds = [
      for (final r in rows) r.paceSecPerKm > 0 ? 1 / r.paceSecPerKm : 0.0,
    ];
    final live = speeds.where((v) => v > 0);
    if (live.isEmpty) return;
    final lo = live.reduce((a, b) => a < b ? a : b);
    final hi = live.reduce((a, b) => a > b ? a : b);
    double frac(double v) => hi > lo
        ? OccasionLayout.splitBarMin +
            (1 - OccasionLayout.splitBarMin) * (v - lo) / (hi - lo)
        : 1;
    final gap = rows.length > 60 ? 1.0 : 2.0;
    final barW = (size.width - gap * (rows.length - 1)) / rows.length;
    final shadow = Paint()
      ..color = ink.shadow
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    for (var i = 0; i < rows.length; i++) {
      if (speeds[i] <= 0) continue;
      final h = size.height * frac(speeds[i]);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(i * (barW + gap), size.height - h, barW, h),
        Radius.circular((barW / 2).clamp(0, 3)),
      );
      canvas.drawRRect(rect, shadow);
      canvas.drawRRect(
        rect,
        Paint()
          ..color = i == fastest
              ? ink.accent
              : rows[i].partial
                  ? ink.muted
                  : ink.text,
      );
    }
    final avg = average;
    if (avg != null && avg > 0) {
      final y = size.height - size.height * frac(1 / avg);
      canvas.drawRect(
          Rect.fromLTWH(0, y - 0.75, size.width, 1.5), Paint()..color = ink.muted);
    }
  }

  @override
  bool shouldRepaint(SplitBarsPainter oldDelegate) =>
      !identical(oldDelegate.rows, rows) ||
      oldDelegate.fastest != fastest ||
      oldDelegate.average != average ||
      oldDelegate.ink != ink;
}

/// The run's stats as a sticker on a TRANSPARENT ground, cropped to its own
/// content, to be saved and laid onto a story or photo in another app.
class RunStickerShareCard extends StatelessWidget {
  final Run run;
  final Preferences preferences;
  final List<PrivacyZone> privacyZones;
  final RunShareLook look;

  /// The occasion sticker to draw in place of the stats; null draws the
  /// stats in the look's layout.
  final RunOccasionBody? occasion;

  const RunStickerShareCard({
    super.key,
    required this.run,
    required this.preferences,
    required this.privacyZones,
    this.look = const RunShareLook(),
    this.occasion,
  });

  /// The sticker's logical width, padding included: what the export scales to
  /// [shareImageExportWidthPx].
  static double canvasWidth(RunShareLook look, {bool occasion = false}) =>
      (occasion ? OccasionLayout.width : RunStickerContent.widthFor(look.layout)) +
      _pad * 2;

  static const double _pad = 16;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(_pad),
      child: runShareBodyContent(
        context,
        run: run,
        preferences: preferences,
        privacyZones: privacyZones,
        look: look,
        occasion: occasion,
      ),
    );
  }
}

/// The sticker content a look draws: [occasion] when there is one, the
/// stats in the look's layout otherwise. Shared by the sticker and the photo.
Widget runShareBodyContent(
  BuildContext context, {
  required Run run,
  required Preferences preferences,
  required List<PrivacyZone> privacyZones,
  required RunShareLook look,
  RunOccasionBody? occasion,
}) {
  final track = runShareCardTrack(run, privacyZones);
  final ink = RunShareInkSpec.of(look.ink);
  final body = occasion;
  if (body != null) {
    return RunOccasionContent(
        body: body, track: track, ink: ink, mark: look.mark);
  }
  return RunStickerContent(
    layout: look.layout,
    stats: runShareStats(AppLocalizations.of(context), run, preferences.unit,
        kinds: look.stats),
    track: track,
    ink: ink,
    mark: look.mark,
  );
}

/// Where [RunPhotoShareCard] last laid its title-and-stats block out: the
/// block's size at scale 1, the frame it must stay inside and its smallest
/// scale, which a move or resize gesture clamps against, and where it landed.
/// Written during layout; the sheet reads it when a gesture starts.
class SharePlacementProbe {
  Size? canvas;
  Size? block;
  Rect? frame;
  double minScale = SharePlacement.maxScale;
  PlacedShareBlock? placed;

  /// [placement] clamped to what the last layout allows, or [placement]
  /// itself before the card has been laid out.
  SharePlacement clamp(SharePlacement placement) {
    final c = canvas, b = block, f = frame;
    if (c == null || b == null || f == null) return placement;
    return placeShareBlock(placement, b, c, f, minScale).placement;
  }
}

/// The run's title, stats and route laid over the runner's own [photo],
/// cropped to fill a 4:5 post or a 9:16 story. A scrim on the side the stats
/// sit makes the ink legible on any photo. The title and stats are one block,
/// placed by the look's placement for this aspect: by default centred on the
/// frame's bottom edge, which on a story keeps it clear of the band the story
/// viewer's reply bar covers.
class RunPhotoShareCard extends StatelessWidget {
  final Run run;
  final Preferences preferences;
  final String title;
  final List<PrivacyZone> privacyZones;
  final ImageProvider photo;
  final RunShareLook look;

  /// Told where the block landed on every layout, for the sheet's gestures.
  final SharePlacementProbe? probe;

  /// The occasion sticker to lay over the photo in place of the stats.
  final RunOccasionBody? occasion;

  const RunPhotoShareCard({
    super.key,
    required this.run,
    required this.preferences,
    required this.title,
    required this.privacyZones,
    required this.photo,
    this.look = const RunShareLook(),
    this.probe,
    this.occasion,
  });

  static Size canvasFor(RunPhotoAspect aspect) => switch (aspect) {
        RunPhotoAspect.post => const Size(360, 450),
        RunPhotoAspect.story => const Size(360, 640),
      };

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final ink = RunShareInkSpec.of(look.ink);
    final size = canvasFor(look.aspect);
    final scrim =
        look.ink == RunShareInk.dark ? Colors.white : Colors.black;
    final titled = title.trim().isNotEmpty;
    return SizedBox.fromSize(
      size: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image(image: photo, fit: BoxFit.cover),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0.3, 1],
                colors: [
                  scrim.withValues(alpha: 0),
                  scrim.withValues(alpha: 0.7),
                ],
              ),
            ),
          ),
          _PlacedPhotoBlock(
            canvas: size,
            story: look.aspect == RunPhotoAspect.story,
            placement: look.placement,
            titleGap: titled ? 12 : 0,
            smallestTextPx: text.labelMedium?.fontSize ?? 12,
            probe: probe,
            children: [
              if (titled)
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: text.titleLarge?.copyWith(
                    color: ink.text,
                    fontWeight: FontWeight.w800,
                    shadows: ink.shadows,
                  ),
                )
              else
                const SizedBox.shrink(),
              runShareBodyContent(
                context,
                run: run,
                preferences: preferences,
                privacyZones: privacyZones,
                look: look,
                occasion: occasion,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Lays the title (first child) over the sticker content (second) as one
/// block, the way web's `layoutPhoto` does: the title at the frame's width,
/// the content fitted into the width and the height the title leaves, then
/// the whole block scaled and placed by [placement] with [placeShareBlock].
class _PlacedPhotoBlock extends MultiChildRenderObjectWidget {
  final Size canvas;
  final bool story;
  final SharePlacement placement;
  final double titleGap;
  final double smallestTextPx;
  final SharePlacementProbe? probe;

  const _PlacedPhotoBlock({
    required this.canvas,
    required this.story,
    required this.placement,
    required this.titleGap,
    required this.smallestTextPx,
    required this.probe,
    required super.children,
  });

  @override
  _RenderPlacedPhotoBlock createRenderObject(BuildContext context) =>
      _RenderPlacedPhotoBlock(this);

  @override
  void updateRenderObject(
          BuildContext context, _RenderPlacedPhotoBlock renderObject) =>
      renderObject.config = this;
}

class _PlacedParentData extends ContainerBoxParentData<RenderBox> {
  double scale = 1;
}

class _RenderPlacedPhotoBlock extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _PlacedParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _PlacedParentData> {
  _RenderPlacedPhotoBlock(this._config);

  _PlacedPhotoBlock _config;
  set config(_PlacedPhotoBlock value) {
    _config = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _PlacedParentData) {
      child.parentData = _PlacedParentData();
    }
  }

  @override
  void performLayout() {
    final c = _config;
    size = constraints.constrain(c.canvas);
    final frame = sharePlacementFrame(c.canvas, story: c.story);
    final title = firstChild!;
    final content = childAfter(title)!;
    title.layout(BoxConstraints.tightFor(width: frame.width),
        parentUsesSize: true);
    content.layout(const BoxConstraints(), parentUsesSize: true);
    final titleH = title.size.height;
    final natural = content.size;
    final availH = frame.height - titleH - c.titleGap;
    final contentScale = [
      1.0,
      frame.width / natural.width,
      availH / natural.height,
    ].reduce((a, b) => a < b ? a : b);
    final cw = natural.width * contentScale;
    final block = Size(frame.width, titleH + c.titleGap + natural.height * contentScale);
    final minScale = minSharePlacementScale(c.smallestTextPx * contentScale);
    final placed =
        placeShareBlock(c.placement, block, c.canvas, frame, minScale);
    final k = placed.scale;
    (title.parentData! as _PlacedParentData)
      ..offset = placed.rect.topLeft
      ..scale = k;
    (content.parentData! as _PlacedParentData)
      ..offset = placed.rect.topLeft +
          Offset((frame.width - cw) / 2 * k, (titleH + c.titleGap) * k)
      ..scale = contentScale * k;
    final probe = c.probe;
    if (probe != null) {
      probe
        ..canvas = c.canvas
        ..block = block
        ..frame = frame
        ..minScale = minScale
        ..placed = placed;
    }
  }

  Matrix4 _transformOf(RenderBox child) {
    final data = child.parentData! as _PlacedParentData;
    return Matrix4.translationValues(data.offset.dx, data.offset.dy, 0)
      ..scaleByDouble(data.scale, data.scale, 1, 1);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    var child = firstChild;
    while (child != null) {
      final c = child;
      context.pushTransform(
        needsCompositing,
        offset,
        _transformOf(c),
        (context, offset) => context.paintChild(c, offset),
      );
      child = childAfter(c);
    }
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.multiply(_transformOf(child));
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    var child = lastChild;
    while (child != null) {
      final c = child;
      final hit = result.addWithPaintTransform(
        transform: _transformOf(c),
        position: position,
        hitTest: (result, position) => c.hitTest(result, position: position),
      );
      if (hit) return true;
      child = childBefore(c);
    }
    return false;
  }
}

/// The ground each ink is drawn on for the PR card: the white and coral inks on
/// the night card, the dark ink on white paper — web's `PR_CARD_GROUNDS`.
Color prCardGround(RunShareInk ink) => switch (ink) {
      RunShareInk.light => AppTheme.night,
      RunShareInk.brand => AppTheme.night,
      RunShareInk.dark => Colors.white,
    };

/// One personal record on a solid ground, in the photo style's post (4:5) or
/// story (9:16) canvas: the headline, the bracket, the record time, how much
/// faster it was than the record it beat, the run's date, the clipped route
/// and the signature. Web's twin is `layoutPrCard` / `paintPrCard` in
/// apps/web/src/lib/share/pr_card_canvas.ts.
class RunPrShareCard extends StatelessWidget {
  final Run run;
  final PrCardEntry record;
  final List<PrivacyZone> privacyZones;
  final RunShareLook look;

  const RunPrShareCard({
    super.key,
    required this.run,
    required this.record,
    required this.privacyZones,
    this.look = const RunShareLook(),
  });

  /// The accent band across the top, in logical pixels.
  static const double band = 6;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final ink = RunShareInkSpec.of(look.ink);
    final size = RunPhotoShareCard.canvasFor(look.aspect);
    const pad = 28.0;
    final bottomInset =
        look.aspect == RunPhotoAspect.story ? size.height * 0.13 : pad;
    final distance = planRecapBracketLabel(l10n, record.distance);
    final improvement = formatPrImprovement(record);
    final previous = record.previousS;
    final detail = previous != null
        ? l10n.shareCardPrPrevious(
            formatShareDuration(Duration(seconds: previous)))
        : record.kind == PrCardKind.first
            ? l10n.shareCardPrFirst(distance)
            : null;
    final track = runShareCardTrack(run, privacyZones);

    Widget line(String s, TextStyle? style, Color color) => FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            s,
            maxLines: 1,
            textAlign: TextAlign.center,
            style: style?.copyWith(color: color, shadows: ink.shadows, height: 1.2),
          ),
        );

    return SizedBox.fromSize(
      size: size,
      child: ColoredBox(
        color: prCardGround(look.ink),
        child: Column(
          children: [
            Container(
              height: band,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppTheme.coralDeep, Color(0xFFA8426A), AppTheme.violet],
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(pad, pad, pad, bottomInset),
                child: Column(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          line(
                            (record.kind == PrCardKind.held
                                    ? l10n.shareCardPrHeld
                                    : l10n.shareCardPrHeadline)
                                .toUpperCase(),
                            text.labelLarge?.copyWith(
                                fontWeight: FontWeight.w800, letterSpacing: 2),
                            ink.muted,
                          ),
                          const SizedBox(height: 14),
                          line(
                            distance,
                            text.headlineMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                            ink.text,
                          ),
                          const SizedBox(height: 4),
                          line(
                            formatShareDuration(Duration(seconds: record.timeS)),
                            text.displayLarge?.copyWith(
                                fontSize: 84,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -1),
                            ink.text,
                          ),
                          const SizedBox(height: 10),
                          if (improvement != null) ...[
                            line(
                              l10n.shareCardPrFaster(improvement),
                              text.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w800),
                              ink.text,
                            ),
                            const SizedBox(height: 6),
                          ],
                          if (detail != null) ...[
                            line(
                              detail,
                              text.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                              ink.muted,
                            ),
                            const SizedBox(height: 6),
                          ],
                          line(
                            formatDateMed(run.startedAt, activeLocaleTag),
                            text.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                            ink.muted,
                          ),
                          // The route takes the room the lines leave, up to
                          // 110: a 4:5 post leaves less than that.
                          if (track.length >= 2) ...[
                            const SizedBox(height: 22),
                            Flexible(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                    maxWidth: 110, maxHeight: 110),
                                child: AspectRatio(
                                  aspectRatio: 1,
                                  child: CustomPaint(
                                    painter: RunRouteOutlinePainter(
                                      track,
                                      color: ink.text,
                                      halo: ink.halo,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    if (look.mark)
                      ThrekirShareBrand(color: ink.text, shadows: ink.shadows),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

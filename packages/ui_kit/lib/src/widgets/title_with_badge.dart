import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A title with a badge (a `StatusPill`, a glyph) set inline after its last
/// word: the badge wraps with that word, so it never stands alone on a line
/// under the title, and when the title is cut at [maxLines] the ellipsis
/// comes before the badge, which always shows.
///
/// A `Wrap` of the title and the badge dropped the badge onto a line of its
/// own whenever the title took two lines (issue #1374: the public-route globe
/// under "Pocahontas Lakeview Loop"), and a `WidgetSpan` in a `Text.rich`
/// loses the badge to the ellipsis on a long title.
///
/// It is a [Text] whose [data] is the title, so it is found, measured and
/// read as the title it is; the badge is a separate node after it. A cut
/// title always ends in an ellipsis, which [overflow] reports.
class TitleWithBadge extends Text {
  const TitleWithBadge(
    String super.data, {
    super.key,
    required this.badge,
    super.style,
    int super.maxLines = 2,
    this.gap = 8,
  }) : super(overflow: TextOverflow.ellipsis);

  final Widget badge;

  /// The space between the title's last word and the badge.
  final double gap;

  @override
  Widget build(BuildContext context) => _TitleWithBadge(
        text: data!,
        style: DefaultTextStyle.of(context).style.merge(style),
        maxLines: maxLines!,
        gap: gap,
        textDirection: textDirection ?? Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        locale: Localizations.maybeLocaleOf(context),
        badge: badge,
      );
}

class _TitleWithBadge extends SingleChildRenderObjectWidget {
  const _TitleWithBadge({
    required this.text,
    required this.style,
    required this.maxLines,
    required this.gap,
    required this.textDirection,
    required this.textScaler,
    required this.locale,
    required Widget badge,
  }) : super(child: badge);

  final String text;
  final TextStyle style;
  final int maxLines;
  final double gap;
  final TextDirection textDirection;
  final TextScaler textScaler;
  final Locale? locale;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderTitleWithBadge(
        text: text,
        style: style,
        maxLines: maxLines,
        gap: gap,
        textDirection: textDirection,
        textScaler: textScaler,
        locale: locale,
      );

  @override
  void updateRenderObject(
      BuildContext context, _RenderTitleWithBadge renderObject) {
    renderObject
      ..text = text
      ..style = style
      ..maxLines = maxLines
      ..gap = gap
      ..textDirection = textDirection
      ..textScaler = textScaler
      ..locale = locale;
  }
}

/// U+2060 WORD JOINER: no line break between the last word and the badge.
const _joiner = '⁠';
const _ellipsis = '…';

class _RenderTitleWithBadge extends RenderBox
    with RenderObjectWithChildMixin<RenderBox> {
  _RenderTitleWithBadge({
    required String text,
    required TextStyle style,
    required int maxLines,
    required double gap,
    required TextDirection textDirection,
    required TextScaler textScaler,
    required Locale? locale,
  })  : _text = text,
        _style = style,
        _maxLines = maxLines,
        _gap = gap,
        _textDirection = textDirection,
        _textScaler = textScaler,
        _locale = locale;

  String _text;
  set text(String v) {
    if (v == _text) return;
    _text = v;
    markNeedsLayout();
    markNeedsSemanticsUpdate();
  }

  TextStyle _style;
  set style(TextStyle v) {
    if (v == _style) return;
    _style = v;
    markNeedsLayout();
  }

  int _maxLines;
  set maxLines(int v) {
    if (v == _maxLines) return;
    _maxLines = v;
    markNeedsLayout();
  }

  double _gap;
  set gap(double v) {
    if (v == _gap) return;
    _gap = v;
    markNeedsLayout();
  }

  TextDirection _textDirection;
  set textDirection(TextDirection v) {
    if (v == _textDirection) return;
    _textDirection = v;
    markNeedsLayout();
    markNeedsSemanticsUpdate();
  }

  TextScaler _textScaler;
  set textScaler(TextScaler v) {
    if (v == _textScaler) return;
    _textScaler = v;
    markNeedsLayout();
  }

  Locale? _locale;
  set locale(Locale? v) {
    if (v == _locale) return;
    _locale = v;
    markNeedsLayout();
  }

  /// What [paint] draws; [_measure] answers dry layout and intrinsics, so a
  /// parent asking for a size never changes what is on screen.
  final TextPainter _painter = TextPainter();
  final TextPainter _measure = TextPainter();
  Offset _badgeOffset = Offset.zero;

  @override
  void dispose() {
    _painter.dispose();
    _measure.dispose();
    super.dispose();
  }

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! BoxParentData) child.parentData = BoxParentData();
  }

  TextSpan _span(String title) => TextSpan(
        style: _style,
        children: [
          TextSpan(text: '$title$_joiner'),
          const WidgetSpan(child: SizedBox.shrink()),
        ],
      );

  /// Lays [painter] out with [title] and a placeholder of [badge]'s size.
  int _layoutPainter(
      TextPainter painter, String title, Size badge, double maxWidth) {
    painter
      ..text = _span(title)
      ..textDirection = _textDirection
      ..textScaler = _textScaler
      ..locale = _locale
      ..maxLines = null
      ..setPlaceholderDimensions([
        PlaceholderDimensions(
          size: Size(badge.width + _gap, badge.height),
          alignment: PlaceholderAlignment.middle,
        ),
      ])
      ..layout(maxWidth: maxWidth);
    return painter.computeLineMetrics().length;
  }

  /// The longest prefix of the title, with an ellipsis, that keeps the title
  /// and the badge inside [_maxLines]. Leaves [painter] laid out with it.
  void _fit(TextPainter painter, Size badge, double maxWidth) {
    if (_layoutPainter(painter, _text, badge, maxWidth) <= _maxLines) return;
    final chars = _text.characters.toList();
    var lo = 0, hi = chars.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) ~/ 2;
      final candidate = '${chars.take(mid).join().trimRight()}$_ellipsis';
      if (_layoutPainter(painter, candidate, badge, maxWidth) <= _maxLines) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    _layoutPainter(painter, '${chars.take(lo).join().trimRight()}$_ellipsis',
        badge, maxWidth);
  }

  Size _badgeSize(BoxConstraints constraints, {required bool dry}) {
    final c = BoxConstraints(maxWidth: constraints.maxWidth);
    if (child == null) return Size.zero;
    if (dry) return child!.getDryLayout(c);
    child!.layout(c, parentUsesSize: true);
    return child!.size;
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final badge = _badgeSize(constraints, dry: true);
    _fit(_measure, badge, constraints.maxWidth);
    return constraints.constrain(Size(_measure.width, _measure.height));
  }

  @override
  void performLayout() {
    final badge = _badgeSize(constraints, dry: false);
    _fit(_painter, badge, constraints.maxWidth);
    final box = _painter.inlinePlaceholderBoxes?.firstOrNull;
    if (box != null && child != null) {
      final left = _textDirection == TextDirection.ltr ? box.left + _gap : box.left;
      _badgeOffset = Offset(
          left, box.top + (box.bottom - box.top - child!.size.height) / 2);
      (child!.parentData! as BoxParentData).offset = _badgeOffset;
    }
    size = constraints.constrain(Size(_painter.width, _painter.height));
  }

  @override
  double computeMinIntrinsicWidth(double height) {
    _measure
      ..text = TextSpan(text: _text, style: _style)
      ..textDirection = _textDirection
      ..textScaler = _textScaler
      ..maxLines = null
      ..setPlaceholderDimensions(null)
      ..layout();
    return math.max(_measure.minIntrinsicWidth,
        child?.getMinIntrinsicWidth(height) ?? 0);
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    _measure
      ..text = TextSpan(text: _text, style: _style)
      ..textDirection = _textDirection
      ..textScaler = _textScaler
      ..maxLines = null
      ..setPlaceholderDimensions(null)
      ..layout();
    return _measure.maxIntrinsicWidth +
        _gap +
        (child?.getMaxIntrinsicWidth(height) ?? 0);
  }

  @override
  double computeMinIntrinsicHeight(double width) =>
      getDryLayout(BoxConstraints(maxWidth: width)).height;

  @override
  double computeMaxIntrinsicHeight(double width) =>
      computeMinIntrinsicHeight(width);

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      _painter.computeDistanceToActualBaseline(baseline);

  @override
  void paint(PaintingContext context, Offset offset) {
    _painter.paint(context.canvas, offset);
    if (child case final child?) {
      context.paintChild(child, offset + _badgeOffset);
    }
  }

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final child = this.child;
    if (child == null) return false;
    return result.addWithPaintOffset(
      offset: _badgeOffset,
      position: position,
      hitTest: (result, transformed) =>
          child.hitTest(result, position: transformed),
    );
  }

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config
      ..label = _text
      ..textDirection = _textDirection;
  }
}

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'choice_chip_row.dart';
import 'edge_fade_scroll.dart';

/// A tab's views (Routes' Mine · Explore, Clubs' Browse · My clubs): one
/// outlined track of segments, exactly one selected, that switches what the
/// tab shows rather than filtering it. `FilterBar.views` takes one.
///
/// Not a `SegmentedButton`, which divides its width equally and then clips a
/// label that does not fit, with no ellipsis and no fade (decisions § 500).
/// The track always spans the row and its labels are centred: the segments
/// are equal while every label fits an equal share at the current width and
/// text scale, else each gets a share in proportion to its label (so every
/// label still fits), and only when the labels together are wider than the
/// row does each take its own width and the track scroll sideways with an
/// edge fade ([ViewSwitchLayout]). No label is ever cut.
///
/// Selection is the fill, a check before the label and the segment's
/// selected state for a screen reader, never the colour alone. Only the
/// selected segment draws the check, so an unselected label is centred in
/// its segment with no gap held for a glyph it does not have (the chip
/// version of this row left one beside "Explore").
class ViewSwitch<T> extends StatelessWidget {
  const ViewSwitch({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.label,
  }) : assert(options.length >= 2, 'a view switch needs two views');

  /// The views. An option's `icon` is not drawn: a segment is its label.
  final List<ChoiceChipOption<T>> options;
  final T selected;
  final ValueChanged<T> onChanged;

  /// Names the group for a screen reader, e.g. "Routes section".
  final String? label;

  static const double _checkSize = 18;
  static const double _checkGap = 6;
  static const double _hPad = 12;

  /// The width every segment needs for its label with the check beside it,
  /// so equal segments are only used when none of them would clip.
  static double segmentWidthFor(
      String text, TextStyle? style, TextScaler scaler) {
    final painter = TextPainter(
      // Measured at the selected weight, the wider of the two.
      text: TextSpan(
          text: text, style: style?.copyWith(fontWeight: FontWeight.w600)),
      textScaler: scaler,
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    final w = painter.width;
    painter.dispose();
    // 2 dp for the outline and a divider, so a measured fit never rounds
    // into an overflow.
    return w + _checkSize + _checkGap + 2 * _hPad + 2;
  }

  /// How segments needing [widths] share [available].
  static ViewSwitchLayout layoutFor(List<double> widths, double available) {
    if (!available.isFinite) return ViewSwitchLayout.scroll;
    final widest = widths.reduce(math.max);
    if (widths.length * widest <= available) return ViewSwitchLayout.equal;
    if (widths.fold<double>(0, (a, b) => a + b) <= available) {
      return ViewSwitchLayout.proportional;
    }
    return ViewSwitchLayout.scroll;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelLarge;
    final scaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(builder: (context, constraints) {
      final widths = [
        for (final o in options) segmentWidthFor(o.label, style, scaler),
      ];
      final layout = layoutFor(widths, constraints.maxWidth);
      final fills = layout != ViewSwitchLayout.scroll;
      final segments = [
        for (var i = 0; i < options.length; i++)
          _Segment(
            key: ValueKey('view-switch-segment-$i'),
            label: options[i].label,
            selected: options[i].value == selected,
            first: i == 0,
            last: i == options.length - 1,
            onTap: () => onChanged(options[i].value),
          ),
      ];
      Widget track = Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: DecoratedBox(
                decoration: ShapeDecoration(
                  shape: StadiumBorder(
                      side: BorderSide(color: theme.colorScheme.outline)),
                ),
              ),
            ),
          ),
          Row(
            mainAxisSize: fills ? MainAxisSize.max : MainAxisSize.min,
            children: [
              for (var i = 0; i < segments.length; i++)
                switch (layout) {
                  ViewSwitchLayout.equal => Expanded(child: segments[i]),
                  // Each share is its width over the total, at least what
                  // its label needs because the total fits.
                  ViewSwitchLayout.proportional => Expanded(
                      flex: (widths[i] * 10).round(), child: segments[i]),
                  ViewSwitchLayout.scroll => segments[i],
                },
            ],
          ),
        ],
      );
      if (!fills) {
        track = EdgeFadeScroll(
          key: const Key('view-switch-scroll'),
          child: track,
        );
      }
      // semantics-children: a group name, read once before the segments inside it
      return Semantics(
        key: const Key('view-switch'),
        container: true,
        explicitChildNodes: true,
        label: label,
        child: track,
      );
    });
  }
}

/// How a [ViewSwitch] shares its row.
enum ViewSwitchLayout {
  /// Equal segments: every label fits an equal share.
  equal,

  /// Full width, each segment in proportion to its label.
  proportional,

  /// Each segment its label's width, in a sideways scroll with an edge fade.
  scroll,
}

class _Segment extends StatelessWidget {
  const _Segment({
    super.key,
    required this.label,
    required this.selected,
    required this.first,
    required this.last,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool first;
  final bool last;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final radius = BorderRadiusDirectional.horizontal(
      start: first ? const Radius.circular(999) : Radius.zero,
      end: last ? const Radius.circular(999) : Radius.zero,
    ).resolve(Directionality.of(context));
    final fg = selected ? scheme.onSecondaryContainer : scheme.onSurface;
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: InkWell(
        onTap: onTap,
        customBorder: RoundedRectangleBorder(borderRadius: radius),
        child: ConstrainedBox(
          constraints:
              const BoxConstraints(minHeight: kMinInteractiveDimension),
          child: Padding(
            // The fill sits inside the outline, which is inset 4 dp top and
            // bottom so the drawn track is 40 dp in a 48 dp target.
            padding: EdgeInsets.fromLTRB(first ? 1 : 0, 5, last ? 1 : 0, 5),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: selected ? scheme.secondaryContainer : null,
                borderRadius: radius,
                border: last
                    ? null
                    : BorderDirectional(
                        end: BorderSide(color: scheme.outline)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: ViewSwitch._hPad, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (selected) ...[
                      Icon(Icons.check,
                          size: ViewSwitch._checkSize, color: fg),
                      const SizedBox(width: ViewSwitch._checkGap),
                    ],
                    Text(
                      label,
                      maxLines: 1,
                      softWrap: false,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: fg,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/spacing.dart';

/// Half the floating label's line at 1x: the part of an outlined field's
/// label that stands above the field's top edge.
const double _floatingLabelOverhang = 6;

/// A form's fields, one under another, with the one field gap between each.
///
/// An outlined field's floating label is centred on its top border, so half
/// of it stands above the field. Fields that touched drew each label over
/// the field above ("Half-width, m" on the bearing's border, issue #1374),
/// and forms that spaced their fields by hand used 0, 8, 12 or 16. Here the
/// gap is [AppInsets.fieldGap], grown with the OS text size once the
/// label's overhang would reach it, so a label never meets the field above.
///
/// A child is a field (`TextField`, `TextFormField`,
/// `DropdownButtonFormField`, `InputDecorator`), a [Row] of fields, or
/// anything else the form stacks between them (a hint, a switch). Children
/// stretch to the column's width. Put a section's heading outside the
/// column, above it. Two fields that share a row when there is room go in a
/// [FieldPair].
class FieldColumn extends StatelessWidget {
  const FieldColumn({super.key, required this.children});

  final List<Widget> children;

  /// The gap [FieldColumn] places between two fields under [textScaler].
  static double gapFor(TextScaler textScaler) => math.max(
        AppInsets.fieldGap,
        textScaler.scale(_floatingLabelOverhang) + AppSpace.xs,
      );

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: gapFor(MediaQuery.textScalerOf(context)),
        children: children,
      );
}

/// Two [TextField]s side by side when both labels fit at half the width, one
/// above the other when either does not.
///
/// A label is cut when the field is narrower than it: "Saturated fat (g)"
/// at half a 320 dp phone and 2x text showed "Saturated f…" (issue #1374).
/// The choice is made from the labels as they lay out under the reader's
/// text size and locale, so a pair that fits on a tablet keeps its row and
/// the same pair stacks on a narrow phone, with [FieldColumn]'s gap between
/// them. Each child's `decoration.labelText` is what is measured.
class FieldPair extends StatelessWidget {
  const FieldPair({super.key, required this.first, required this.second});

  final TextField first;
  final TextField second;

  /// The gap between the two fields when they share a row.
  static const double rowGap = AppSpace.sm;

  /// An outlined field's start and end content padding, which a resting
  /// label sits inside.
  static const double _labelInset = 24;

  /// Whether a field [width] wide shows [label] uncut.
  static bool labelFits(BuildContext context, String? label, double width) {
    if (label == null || label.isEmpty) return true;
    final theme = Theme.of(context);
    final style = (theme.textTheme.bodyLarge ?? const TextStyle())
        .merge(theme.inputDecorationTheme.labelStyle);
    final painter = TextPainter(
      text: TextSpan(text: label, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final fits = painter.width <= width - _labelInset;
    painter.dispose();
    return fits;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final half = (constraints.maxWidth - rowGap) / 2;
          final side = labelFits(context, first.decoration?.labelText, half) &&
              labelFits(context, second.decoration?.labelText, half);
          if (!side) return FieldColumn(children: [first, second]);
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: first),
              const SizedBox(width: rowGap),
              Expanded(child: second),
            ],
          );
        },
      );
}

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

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
/// column, above it.
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

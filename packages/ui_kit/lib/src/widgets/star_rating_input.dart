import 'package:flutter/material.dart';

/// A one-to-[count] star picker that fits whatever width it is given.
///
/// Five fixed 48 dp `IconButton`s need 240 dp, and an `AlertDialog`'s content
/// area is 192 dp on a 320 dp phone, so the fifth star was clipped out of
/// reach (issue #1374 TO-1). Each star takes an equal share of the row,
/// capped at [cellExtent]; the tap target keeps its full height and loses
/// width only when the row cannot hold full cells, which still clears WCAG
/// 2.5.8's 24 dp minimum down to a 120 dp row. It lays out with flex rather
/// than a `LayoutBuilder` because `AlertDialog` measures its content's
/// intrinsic width.
class StarRatingInput extends StatelessWidget {
  const StarRatingInput({
    super.key,
    required this.value,
    required this.onChanged,
    required this.starLabel,
    this.count = 5,
    this.color,
    this.cellExtent = 48,
    this.iconSize = 24,
  });

  final int value;
  final ValueChanged<int> onChanged;

  /// Already localized — `ui_kit` has no catalogue.
  final String Function(int star) starLabel;
  final int count;
  final Color? color;
  final double cellExtent;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final cell = Size(cellExtent, cellExtent);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(count, (i) {
        final star = i + 1;
        return Flexible(
          child: IconButton(
            tooltip: starLabel(star),
            isSelected: star <= value,
            padding: EdgeInsets.zero,
            iconSize: iconSize,
            style: ButtonStyle(
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              minimumSize: WidgetStatePropertyAll(cell),
              maximumSize: WidgetStatePropertyAll(cell),
            ),
            icon: Icon(Icons.star_border, color: color),
            selectedIcon: Icon(Icons.star, color: color),
            onPressed: () => onChanged(star),
          ),
        );
      }),
    );
  }
}

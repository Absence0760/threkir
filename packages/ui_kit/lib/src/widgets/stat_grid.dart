import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'stat_tile.dart';

/// Narrowest a [StatTile.small] cell may be at 1.0x text scale before its
/// value stops being readable. The widest secondary value a run produces is a paced one —
/// "10:24 /km", "1234 kcal" — needing roughly 64 dp at the 14 sp body size a
/// [StatTile.small] draws its value in, so 72 leaves the value whole and lets
/// only the label truncate. Scaled by the OS text scale, it is what [StatGrid]
/// divides the available width by to decide a column count. The larger tiers
/// carry their own floors, [kStatMediumCellMinWidth] and
/// [kStatLargeCellMinWidth].
const double kStatCellMinWidth = 72;

/// Lays stat cells on a column grid whose column *count* is derived from the
/// width a cell needs at the current text scale, rather than from how many
/// cells there happen to be.
///
/// A `Row` of `Expanded` stat cells divides its width by the cell count, so a
/// run carrying eight secondary stats gave each 40.0 dp on a 360 dp phone —
/// under every value it draws — and because a stat label ellipsises rather
/// than overflows, nothing threw and no test could see it (§502). Here eight
/// cells become two rows of four at 1.0x and four rows of two at 2.0x.
///
/// With four or fewer cells that all fit, the layout is exactly what a `Row`
/// of `Expanded` produced, so adopting it on an existing row changes nothing
/// at 1.0x. What it adds beyond the reflow is that every cell is *bounded*,
/// which is what a `StatTile`'s `BoxFit.scaleDown` needs in order to shrink a
/// long value instead of bursting its row.
///
/// The floor is the widest any cell asks for: a [StatTile] reports its own
/// tier's [StatTile.minCellWidth], so a hero row reflows at a width a dense
/// secondary row still fits in. A cell that wraps a tile in something else
/// cannot be read that way, which is what [minCellWidth] is for.
///
/// When the cells do not fit on one run, the column count is evened out over
/// the runs, so four hero cells that fit three to a row lay out two by two
/// rather than three and an orphan.
class StatGrid extends StatelessWidget {
  const StatGrid({super.key, required this.cells, this.minCellWidth});

  static const int _maxColumns = 4;

  final List<Widget> cells;

  /// The 1.0x floor for cells that are not themselves a [StatTile]; unset, such
  /// a cell asks for [kStatCellMinWidth].
  final double? minCellWidth;

  double get _minCellWidth {
    var widest = 0.0;
    for (final cell in cells) {
      widest = math.max(
        widest,
        cell is StatTile
            ? cell.minCellWidth
            : minCellWidth ?? kStatCellMinWidth,
      );
    }
    return widest;
  }

  /// Width of one cell when [available] is a real bound: the widest that lets
  /// as many cells as will fit share the row, floored so `columns` of them can
  /// never total more than [available] through floating-point drift and push
  /// the last onto its own run.
  static double _cellWidth(double available, double minWidth, int cellCount) {
    final fit =
        (available / minWidth).floor().clamp(1, math.min(_maxColumns, cellCount));
    final runs = (cellCount / fit).ceil();
    final columns = (cellCount / runs).ceil();
    return (available / columns).floorToDouble();
  }

  @override
  Widget build(BuildContext context) {
    if (cells.isEmpty) return const SizedBox.shrink();
    final minWidth = MediaQuery.textScalerOf(context).scale(_minCellWidth);
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth;
        // An unbounded width — a horizontal scroller, a `Row` child with no
        // `Expanded` — offers nothing to divide, and `Infinity.floor()` does
        // not degrade: it throws `UnsupportedError` out of `build`, taking the
        // whole screen rather than laying the grid out badly. Every cell still
        // has to be BOUNDED, which is what a `StatTile`'s `BoxFit.scaleDown`
        // needs, so each gets exactly the width one cell asks for.
        final width = available.isFinite
            ? _cellWidth(available, minWidth, cells.length)
            : minWidth;
        return Wrap(
          runSpacing: 12,
          children: [
            for (final cell in cells) SizedBox(width: width, child: cell),
          ],
        );
      },
    );
  }
}

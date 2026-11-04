import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart' show ListSkeleton, SkeletonBlock;

import '../detail_map_height.dart';

/// The loading frames for the screen shapes several detail screens share.
///
/// None of these is a new primitive: each is ui_kit's [ListSkeleton] and
/// [SkeletonBlock] composed into the layout the screen settles into, so the
/// arriving frame fills the blocks instead of re-laying the page out. A screen
/// whose shape is its own composes the primitives inline instead.

/// A hero map at [detailMapHeight], a stat strip, then section rows — the
/// public route, public run, live tracker and segment detail layout.
class MapDetailSkeleton extends StatelessWidget {
  final String label;
  final int statCells;
  final int rows;

  const MapDetailSkeleton({
    super.key,
    required this.label,
    this.statCells = 3,
    this.rows = 3,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, viewport) => ListView(
          physics: const NeverScrollableScrollPhysics(),
          children: [
            SkeletonBlock(
              height: detailMapHeight(viewport.maxHeight),
              radius: 0,
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: SkeletonStatStrip(cells: statCells),
            ),
            ListSkeleton.section(
              label: label,
              rows: rows,
              padding: const EdgeInsets.symmetric(horizontal: 20),
            ),
          ],
        ),
      );
}

/// A header band (avatar and title lines), the pinned tab strip, and the
/// first tab's rows — the club detail layout, and the same composition
/// `profile_screen` builds for its whole-profile load.
class TabbedDetailSkeleton extends StatelessWidget {
  final String label;

  const TabbedDetailSkeleton({super.key, required this.label});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListSkeleton.section(
            label: label,
            rows: 1,
            rowHeight: 80,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: SkeletonBlock(height: 32, radius: 8),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          Expanded(child: ListSkeleton(label: label)),
        ],
      );
}

/// A title band, an optional stat strip and a primary action, then section
/// rows — the plan, workout, event, challenge, race and meal detail layout:
/// prose and controls over a list, with no map.
class SectionedDetailSkeleton extends StatelessWidget {
  final String label;
  final int statCells;
  final bool hasAction;
  final int rows;
  final double rowHeight;
  final bool hasLeading;

  const SectionedDetailSkeleton({
    super.key,
    required this.label,
    this.statCells = 0,
    this.hasAction = false,
    this.rows = 4,
    this.rowHeight = 64,
    this.hasLeading = false,
  });

  @override
  Widget build(BuildContext context) => ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          const FractionallySizedBox(
            alignment: AlignmentDirectional.centerStart,
            widthFactor: 0.6,
            child: SkeletonBlock(height: 24, radius: 6),
          ),
          const SizedBox(height: 10),
          const FractionallySizedBox(
            alignment: AlignmentDirectional.centerStart,
            widthFactor: 0.4,
            child: SkeletonBlock(height: 14, radius: 4),
          ),
          if (statCells > 0) ...[
            const SizedBox(height: 20),
            SkeletonStatStrip(cells: statCells),
          ],
          if (hasAction) ...[
            const SizedBox(height: 20),
            const SkeletonBlock(height: 48, radius: 24),
          ],
          const SizedBox(height: 12),
          ListSkeleton.section(
            label: label,
            rows: rows,
            rowHeight: rowHeight,
            hasLeading: hasLeading,
          ),
        ],
      );
}

/// A row of [cells] stat-cell blocks, the shape a `StatGrid` settles into.
class SkeletonStatStrip extends StatelessWidget {
  final int cells;

  const SkeletonStatStrip({super.key, required this.cells});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          for (var i = 0; i < cells; i++) ...[
            if (i > 0) const SizedBox(width: 12),
            const Expanded(child: SkeletonBlock(height: 56)),
          ],
        ],
      );
}

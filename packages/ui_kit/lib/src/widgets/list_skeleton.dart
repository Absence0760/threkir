import 'package:flutter/material.dart';

import '../motion.dart';

/// Placeholder rows for a list surface that is still loading.
///
/// A centred spinner tells the user only that something is happening; it
/// occupies none of the space the list will, so arriving content lands as a
/// full-height jump. These blocks stand where the rows will stand, so the
/// swap is a fill rather than a re-layout.
///
/// [label] is the screen-reader announcement — ui_kit has no localisations of
/// its own, so the caller passes the translated string.
class ListSkeleton extends StatelessWidget {
  final int rows;
  final double rowHeight;
  final bool hasLeading;
  final EdgeInsetsGeometry padding;
  final String label;

  /// Lay the rows out at their intrinsic height rather than inside a
  /// viewport. See [ListSkeleton.section].
  final bool _intrinsic;

  const ListSkeleton({
    super.key,
    required this.label,
    this.rows = 5,
    this.rowHeight = 64,
    this.hasLeading = true,
    this.padding = const EdgeInsets.all(16),
  }) : _intrinsic = false;

  /// Placeholder rows for one *section* of an already-laid-out screen — a
  /// comment list inside a card, a picker inside a scrollable sheet.
  ///
  /// The default constructor's viewport requires a bounded height, so it
  /// cannot be used inside an outer scrollable; this variant occupies exactly
  /// the height its rows need and leaves scrolling to the host.
  const ListSkeleton.section({
    super.key,
    required this.label,
    this.rows = 3,
    this.rowHeight = 64,
    this.hasLeading = true,
    this.padding = const EdgeInsets.symmetric(vertical: 8),
  }) : _intrinsic = true;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      excludeSemantics: true,
      label: label,
      liveRegion: true,
      container: true,
      child: _SkeletonPulse(
        builder: (context, block) {
          Widget row(int i) => _SkeletonRow(
                color: block,
                height: rowHeight,
                hasLeading: hasLeading,
                // Stagger the bar widths so the stack reads as content in
                // waiting rather than as a rendered table.
                titleFactor: 0.44 + (i % 3) * 0.12,
              );
          if (_intrinsic) {
            return Padding(
              padding: padding,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < rows; i++) ...[
                    if (i > 0) const SizedBox(height: 10),
                    row(i),
                  ],
                ],
              ),
            );
          }
          return ListView.separated(
            padding: padding,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: rows,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (_, i) => row(i),
          );
        },
      ),
    );
  }
}

/// A plain placeholder rectangle for a part of a loading screen that has no
/// row rhythm — a map, a chart, a hero stat strip, a barcode.
///
/// Composed beside [ListSkeleton] into the shape the screen will settle into,
/// so the loaded frame fills the blocks rather than re-laying the page out.
/// Pulses on the same 900 ms cycle and holds the same reduced-motion pose as
/// the rows, so a composite reads as one surface.
///
/// [label] is optional because a composite announces once: give it to one
/// element (usually the [ListSkeleton]) and leave the blocks silent. A block
/// that stands alone takes the label itself.
class SkeletonBlock extends StatelessWidget {
  final double height;
  final double? width;
  final double radius;
  final String? label;

  const SkeletonBlock({
    super.key,
    required this.height,
    this.width,
    this.radius = 12,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    final block = _SkeletonPulse(
      builder: (context, color) => Container(
        width: width ?? double.infinity,
        height: height,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
    final label = this.label;
    if (label == null) return ExcludeSemantics(child: block);
    return Semantics(
      excludeSemantics: true,
      label: label,
      liveRegion: true,
      container: true,
      child: block,
    );
  }
}

/// The one skeleton pulse: a 900 ms reversing loop over the block alpha,
/// parked mid-cycle under reduced motion.
class _SkeletonPulse extends StatefulWidget {
  final Widget Function(BuildContext context, Color block) builder;

  const _SkeletonPulse({required this.builder});

  @override
  State<_SkeletonPulse> createState() => _SkeletonPulseState();
}

class _SkeletonPulseState extends State<_SkeletonPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    syncMotionLoop(context, _controller, restValue: 0.5, reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => widget.builder(
        context,
        onSurface.withValues(alpha: 0.05 + 0.06 * _controller.value),
      ),
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  final Color color;
  final double height;
  final bool hasLeading;
  final double titleFactor;

  const _SkeletonRow({
    required this.color,
    required this.height,
    required this.hasLeading,
    required this.titleFactor,
  });

  Widget _bar(double widthFactor, double barHeight) => FractionallySizedBox(
        alignment: AlignmentDirectional.centerStart,
        widthFactor: widthFactor,
        child: Container(
          height: barHeight,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final leadingSide = (height * 0.55).clamp(24.0, 48.0);
    return SizedBox(
      height: height,
      child: Row(
        children: [
          if (hasLeading) ...[
            Container(
              width: leadingSide,
              height: leadingSide,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _bar(titleFactor, 12),
                const SizedBox(height: 8),
                _bar(0.82, 10),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

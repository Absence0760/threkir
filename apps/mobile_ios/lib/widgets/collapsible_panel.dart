import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart' show AppMotion, reduceMotion;

import '../fab_clearance.dart';
import '../l10n/gen/app_localizations.dart';

/// A bottom-pinned panel with a drag handle that can be toggled between a
/// collapsed (minimal) state and an expanded (full) state.
///
/// Tap the handle to toggle. Flick the handle up to expand, down to collapse.
/// The panel provides its own glass-blur container and safe-area padding so
/// callers only supply the content for each state. It also clears a docked
/// FAB ([DockedFabInset]), which would otherwise cover its bottom row.
class CollapsiblePanel extends StatefulWidget {
  /// How far the handle's touch target reaches above the panel's visible
  /// top edge. The handle draws in a 28 dp strip, which clears WCAG's 24 dp
  /// but not Android's 48 dp, and growing the strip would grow the panel
  /// over the map; so the panel lays out this much transparent space above
  /// itself that belongs to the handle (issue #1374 A11Y-15). The run screen
  /// keeps its floating cards clear of it.
  static const double handleOverhang = 20;

  /// The visible handle strip; with [handleOverhang] it is a 48 dp target.
  static const double handleHeight = 28;

  final Widget expandedChild;
  final Widget collapsedChild;
  final bool initiallyExpanded;

  const CollapsiblePanel({
    super.key,
    required this.expandedChild,
    required this.collapsedChild,
    this.initiallyExpanded = true,
  });

  @override
  State<CollapsiblePanel> createState() => _CollapsiblePanelState();
}

class _CollapsiblePanelState extends State<CollapsiblePanel> {
  late bool _expanded = widget.initiallyExpanded;

  static const _flickVelocity = 200.0;

  void _toggle() => setState(() => _expanded = !_expanded);

  void _onVerticalDragEnd(DragEndDetails details) {
    final v = details.primaryVelocity ?? 0;
    if (v > _flickVelocity && _expanded) {
      setState(() => _expanded = false);
    } else if (v < -_flickVelocity && !_expanded) {
      setState(() => _expanded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomSafe = MediaQuery.of(context).padding.bottom;

    final l10n = AppLocalizations.of(context);
    // The handle's whole target: the transparent overhang above the panel
    // and the drawn strip at its top, one semantics node and one gesture.
    final handle = Semantics(
      label: _expanded ? l10n.runCollapseStatsPanel : l10n.runExpandStatsPanel,
      button: true,
      excludeSemantics: true,
      child: GestureDetector(
        key: const ValueKey('collapsible-panel-handle'),
        behavior: HitTestBehavior.opaque,
        onTap: _toggle,
        onVerticalDragEnd: _onVerticalDragEnd,
        child: const SizedBox(
          height: CollapsiblePanel.handleOverhang + CollapsiblePanel.handleHeight,
          width: double.infinity,
        ),
      ),
    );

    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.only(top: CollapsiblePanel.handleOverhang),
          child: _panel(context, theme, bottomSafe),
        ),
        Positioned(top: 0, left: 0, right: 0, child: handle),
      ],
    );
  }

  Widget _panel(BuildContext context, ThemeData theme, double bottomSafe) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withValues(alpha: 0.85),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drawn here; the handle's target is laid over it from above.
              SizedBox(
                height: CollapsiblePanel.handleHeight,
                child: Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.dividerColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
              // Reduce-motion skips the widget rather than passing it a zero
              // duration: `RenderAnimatedSize` completes a zero-duration
              // controller inside its own performLayout and asserts on
              // re-dirtying itself mid-layout. Web's global net has the same
              // shape for the same reason (0.01ms, not 0).
              if (reduceMotion(context))
                SizedBox(
                  width: double.infinity,
                  child:
                      _expanded ? widget.expandedChild : widget.collapsedChild,
                )
              else
                AnimatedCrossFade(
                  duration: AppMotion.brief,
                  sizeCurve: AppMotion.curveEmphasised,
                  alignment: Alignment.topCenter,
                  crossFadeState: _expanded
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  firstChild: SizedBox(
                    width: double.infinity,
                    child: widget.collapsedChild,
                  ),
                  secondChild: SizedBox(
                    width: double.infinity,
                    child: widget.expandedChild,
                  ),
                ),
              SizedBox(height: bottomSafe + DockedFabInset.of(context) + 12),
            ],
          ),
        ),
      ),
    );
  }
}

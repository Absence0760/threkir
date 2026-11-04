import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart' show AppMotion, motionDuration;

/// Tracks whether a screen's body heading has scrolled under its app bar.
///
/// A detail screen's toolbar actions leave a long name a few characters, so
/// the full name is a wrapping [ScrolledAwayHeading] in the body and the bar
/// only repeats it, through [ScrolledAwayTitle], once that heading is gone.
class ScrolledAwayTitleController {
  ScrolledAwayTitleController(this._scroll) {
    _scroll.addListener(_queueMeasure);
  }

  final ScrollController _scroll;
  final GlobalKey headingKey = GlobalKey();
  final ValueNotifier<bool> underBar = ValueNotifier(false);
  bool _queued = false;
  bool _disposed = false;

  // Measured after the frame: a scroll listener runs before the list has
  // laid out at the new offset, so measuring there reads the last frame.
  void _queueMeasure() {
    if (_queued) return;
    _queued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _queued = false;
      if (!_disposed) _measure();
    });
  }

  void _measure() {
    final context = headingKey.currentContext;
    final box = context?.findRenderObject() as RenderBox?;
    // A heading the list has already disposed is far above the bar.
    underBar.value = context == null || box == null || !box.attached
        ? _scroll.hasClients && _scroll.offset > 0
        : box.localToGlobal(Offset(0, box.size.height)).dy <=
            MediaQuery.paddingOf(context).top + kToolbarHeight;
  }

  void dispose() {
    _disposed = true;
    _scroll.removeListener(_queueMeasure);
    underBar.dispose();
  }
}

/// The app-bar title, shown only while [controller]'s heading is under the bar.
class ScrolledAwayTitle extends StatelessWidget {
  const ScrolledAwayTitle({
    super.key,
    required this.controller,
    required this.child,
  });

  final ScrolledAwayTitleController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: controller.underBar,
      builder: (context, under, child) => AnimatedOpacity(
        opacity: under ? 1 : 0,
        duration: motionDuration(context, AppMotion.brief),
        child: child,
      ),
      child: child,
    );
  }
}

/// The full, wrapping name heading in the body that [controller] measures.
class ScrolledAwayHeading extends StatelessWidget {
  const ScrolledAwayHeading({
    super.key,
    required this.controller,
    required this.text,
    this.padding = const EdgeInsets.fromLTRB(24, 16, 24, 0),
  });

  final ScrolledAwayTitleController controller;
  final String text;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: controller.headingKey,
      padding: padding,
      child: Semantics(
        header: true,
        child: Text(text, style: Theme.of(context).textTheme.headlineSmall),
      ),
    );
  }
}

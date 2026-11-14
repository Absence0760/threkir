import 'package:flutter/material.dart';

/// A sideways-scrolling line that fades out at an edge with more beyond it,
/// so a chip cut by the screen edge reads as "more this way" rather than a
/// hard cut (issue #1374: Plans' "Com…" with no hint). The end fades while
/// the line can still scroll towards it, the start once it has scrolled away
/// from its start, and neither when everything fits. Both follow the reading
/// direction.
///
/// The fade is a mask over the drawing only: a faded chip is still focusable,
/// still read by a screen reader, and scrolls fully into view.
class EdgeFadeScroll extends StatefulWidget {
  const EdgeFadeScroll({
    super.key,
    required this.child,
    this.scrollKey,
    this.fadeExtent = 32,
  });

  final Widget child;

  /// The key of the inner [SingleChildScrollView], for tests and hosts that
  /// look the scroller up.
  final Key? scrollKey;

  /// How far in from the edge the fade runs, in logical pixels.
  final double fadeExtent;

  @override
  State<EdgeFadeScroll> createState() => EdgeFadeScrollState();
}

class EdgeFadeScrollState extends State<EdgeFadeScroll> {
  final _controller = ScrollController();
  bool _start = false;
  bool _end = false;

  /// Whether the start edge is faded, for tests.
  @visibleForTesting
  bool get fadesStart => _start;

  /// Whether the end edge is faded, for tests.
  @visibleForTesting
  bool get fadesEnd => _end;

  /// Which edges fade for a scroll position: the start once it has left its
  /// start, the end while there is more to scroll to.
  static ({bool start, bool end}) fadesFor({
    required double pixels,
    required double min,
    required double max,
  }) =>
      (start: pixels > min + 0.5, end: pixels < max - 0.5);

  void _update() {
    if (!mounted || !_controller.hasClients) return;
    final p = _controller.position;
    if (!p.hasContentDimensions) return;
    final f = fadesFor(
        pixels: p.pixels, min: p.minScrollExtent, max: p.maxScrollExtent);
    if (f.start != _start || f.end != _end) {
      setState(() {
        _start = f.start;
        _end = f.end;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // A changed child can change the extent without a scroll; check after
    // every layout. setState only runs when an edge actually changes.
    WidgetsBinding.instance.addPostFrameCallback((_) => _update());
    final rtl = Directionality.of(context) == TextDirection.rtl;
    // The tree is the same with or without a fade, so turning one on never
    // rebuilds the scroller and loses its position.
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (_) {
        _update();
        return false;
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.depth == 0) _update();
          return false;
        },
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (rect) {
            final f = rect.width <= 0
                ? 0.0
                : (widget.fadeExtent / rect.width).clamp(0.0, 0.5);
            // Left and right in paint order; in RTL the start is the right.
            final left = rtl ? _end : _start;
            final right = rtl ? _start : _end;
            return LinearGradient(
              colors: [
                left ? Colors.transparent : Colors.black,
                Colors.black,
                Colors.black,
                right ? Colors.transparent : Colors.black,
              ],
              stops: [0, f, 1 - f, 1],
            ).createShader(rect);
          },
          child: SingleChildScrollView(
            key: widget.scrollKey,
            controller: _controller,
            scrollDirection: Axis.horizontal,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

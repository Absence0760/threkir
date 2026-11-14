import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart' show PinnedHeaderScope;

/// Top-anchored notification pill — the canonical replacement for
/// `ScaffoldMessenger.of(context).showSnackBar(...)` across the mobile
/// app. Material's floating SnackBar docks at the bottom and on the
/// recording screen overlapped the Pause / Stop / Lap controls; the
/// runner couldn't reach Stop without dismissing a snack first.
/// Anchoring at the top eliminates that overlap on every screen and
/// gives notifications a consistent shape app-wide.
///
/// Renders via [Overlay] so callers don't need to plumb a banner into
/// every screen's [Scaffold] body. The pill auto-positions just below
/// the header on screen — the lowest AppBar or pinned header (a root page's
/// title row, a hub's tab strip) that is showing — whichever context it is
/// said from; with no header on screen it sits under the view's status bar,
/// whatever SafeArea the caller lives in.
///
/// Single-banner semantics, mirroring SnackBar: a new call coalesces
/// the existing entry — there is never more than one banner on screen.

_TopBannerEntry? _current;

/// Hard ceiling on how long ANY banner can stay on screen, even when
/// a caller passes a custom [duration]. Acts as a defence against
/// a degenerate code path (e.g. a screen scheduling a banner with
/// `Duration.zero` or a forgotten-to-dismiss action handler) so the
/// user is never stuck looking at a stale notification.
const Duration kTopBannerMaxDuration = Duration(seconds: 6);

/// Show a transient top-anchored banner. Returns immediately.
///
/// [actionLabel] + [onAction] add a tappable button (e.g. the
/// "Settings" shortcut on the GPS-unavailable banner). Tapping the
/// action runs the callback AND dismisses the banner.
///
/// Auto-dismisses after [duration] (clamped to [kTopBannerMaxDuration]),
/// measured from the frame the pill first renders on rather than from this
/// call — an entry inserted into an Overlay that is torn down before the next
/// frame is never displayed, and so never starts a clock.
/// Also swipe-dismissible — drag horizontally to dismiss; matches
/// the canonical Material SnackBar gesture so users don't need to
/// learn a new affordance.
///
/// Caller must pass a [context] that's under the [Navigator] /
/// [Overlay] (any screen-level context works) or is the root
/// navigator's own context (`navigatorKey.currentContext`). When no Overlay is
/// reachable (e.g. very early app boot) the call is a no-op.
void showTopBanner(
  BuildContext context,
  String message, {
  String? actionLabel,
  VoidCallback? onAction,
  Duration duration = const Duration(seconds: 3),
}) {
  // Clamp to the hard ceiling so a caller can never wedge a banner
  // on screen indefinitely.
  final effective = duration > kTopBannerMaxDuration
      ? kTopBannerMaxDuration
      : duration;
  // The root navigator's own context sits above the Overlay it owns, so
  // `Overlay.maybeOf` misses it; `Navigator.maybeOf` recognises that
  // context as the navigator itself and hands back its overlay.
  final overlay = Overlay.maybeOf(context, rootOverlay: true) ??
      Navigator.maybeOf(context, rootNavigator: true)?.overlay;
  if (overlay == null) return;

  // Measured at show-time — the Overlay context is above the screen's
  // Scaffold, so the entry's own builder wouldn't see it. The status bar is
  // read from the view, not the caller: under a SafeArea or a Scaffold body
  // the caller's MediaQuery has had its top padding removed, which put the
  // pill under the notch on an AppBar-less screen.
  final view = View.maybeOf(context);
  final statusBar = view != null
      ? MediaQueryData.fromView(view).padding.top
      : MediaQuery.paddingOf(context).top;
  final headerBottom = _headerBottomFor(overlay);
  final topInset =
      (headerBottom > statusBar ? headerBottom : statusBar) + 12;

  _current?.dismiss();
  _current = null;

  late _TopBannerEntry tracker;
  late OverlayEntry entry;
  void detach() {
    if (_current == tracker) _current = null;
  }

  void dismiss() {
    detach();
    if (entry.mounted) entry.remove();
  }

  entry = OverlayEntry(
    builder: (ctx) => _TopBannerWidget(
      message: message,
      duration: effective,
      actionLabel: actionLabel,
      onAction: onAction == null
          ? null
          : () {
              dismiss();
              onAction.call();
            },
      onSwipeDismiss: dismiss,
      onExpired: dismiss,
      onDisposed: detach,
      topInset: topInset,
    ),
  );
  overlay.insert(entry);

  tracker = _TopBannerEntry(dismiss: dismiss);
  _current = tracker;
}

/// The bottom of the header on screen — the lowest app bar and the lowest
/// pinned header (a root page's title row, a hub's tab strip under it) — in
/// the overlay's coordinates, or 0 when nothing on screen has one.
///
/// It reads what is on screen, not what encloses the caller. A banner is
/// said from a tab of a shell, a screen State above its own Scaffold, a
/// sheet, the root navigator after the screen that started the work has
/// gone, or a service holding only the navigator's context; and the four
/// root pages stay alive in the shell, each with its own header, while only
/// one of them shows. Searching from the caller found a hidden tab's header,
/// or none, and the pill covered the visible page's title row (issue #1374).
/// So the whole overlay is searched, and a header counts only when it is
/// painted where the overlay can show it: a route under an opaque one is in
/// a `TickerMode` that is off, a kept-alive page the pager has moved away is
/// one its parent does not paint, and a page laid out beside the viewport is
/// outside the overlay's bounds. `TickerMode` alone is not enough, because a
/// pager keeps its kept-alive pages' tickers on.
double _headerBottomFor(OverlayState overlay) {
  final overlayBox = overlay.context.findRenderObject();
  if (overlayBox is! RenderBox || !overlayBox.hasSize) return 0;
  final bounds = Offset.zero & overlayBox.size;
  var bottom = 0.0;

  Rect? shown(BuildContext context) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    RenderObject child = box;
    for (var parent = child.parent; ; parent = child.parent) {
      if (parent == null || !parent.paintsChild(child)) return null;
      if (identical(parent, overlayBox)) break;
      child = parent;
    }
    final rect = MatrixUtils.transformRect(
        box.getTransformTo(overlayBox), Offset.zero & box.size);
    return rect.overlaps(bounds) ? rect : null;
  }

  void visit(Element element) {
    final widget = element.widget;
    if (widget is TickerMode && !widget.enabled) return;
    if (widget is Offstage && widget.offstage) return;
    if (element is StatefulElement && element.state is ScaffoldState) {
      final height = (element.state as ScaffoldState).appBarMaxHeight;
      final rect = height == null ? null : shown(element);
      if (rect != null && rect.top + height! > bottom) {
        bottom = rect.top + height;
      }
    } else if (widget is PinnedHeaderScope) {
      final header = widget.headerKey.currentContext;
      final rect = header == null ? null : shown(header);
      if (rect != null && rect.bottom > bottom) bottom = rect.bottom;
    }
    element.visitChildElements(visit);
  }

  overlay.context.visitChildElements(visit);
  return bottom;
}

/// Dismiss the currently visible banner, if any. Safe to call from
/// anywhere; no-op when nothing is shown.
void hideTopBanner() {
  _current?.dismiss();
  _current = null;
}

class _TopBannerEntry {
  final void Function() dismiss;
  _TopBannerEntry({required this.dismiss});
}

class _TopBannerWidget extends StatefulWidget {
  final String message;
  final Duration duration;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback onSwipeDismiss;
  final VoidCallback onExpired;
  final VoidCallback onDisposed;
  final double topInset;

  const _TopBannerWidget({
    required this.message,
    required this.duration,
    required this.topInset,
    required this.onSwipeDismiss,
    required this.onExpired,
    required this.onDisposed,
    this.actionLabel,
    this.onAction,
  });

  @override
  State<_TopBannerWidget> createState() => _TopBannerWidgetState();
}

class _TopBannerWidgetState extends State<_TopBannerWidget> {
  /// The display clock is the pill's own, armed when it first renders and
  /// cancelled when it goes away, because [showTopBanner] can only insert an
  /// [OverlayEntry] — the widget is not built until the next frame, and may
  /// never be. Armed from outside, the timer outlived a banner nobody saw and
  /// a banner whose tree was torn down; in a widget test that is the
  /// framework's `A Timer is still pending even after the widget tree was
  /// disposed`, raised from inside the test body before any `tearDown` runs,
  /// so no harness cleanup can reach it (decisions § 1195).
  Timer? _dismiss;

  @override
  void initState() {
    super.initState();
    _dismiss = Timer(widget.duration, widget.onExpired);
  }

  @override
  void dispose() {
    _dismiss?.cancel();
    widget.onDisposed();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: widget.topInset,
      left: 16,
      right: 16,
      // The Center wraps the Dismissible chain (not the reverse) so the
      // Dismissible sizes to the pill only. A Dismissible's hit-test
      // area is opaque and sized to its child, so wrapping the
      // full-width Center inside it made the whole top band absorb
      // pointer events and block taps to widgets underneath until the
      // banner dismissed. With Center on the outside, the empty band on
      // either side of the pill passes taps through.
      child: Center(
        // Dismissible — swipe in any direction to dismiss.
        // `DismissDirection.up` is the primary affordance the user
        // explicitly asked for (top-anchored banner reads as
        // "push me away upwards"). Horizontal also dismisses for
        // Material SnackBar gesture parity. The two are combined via
        // a wrapping Dismissible-on-Dismissible pattern because
        // DismissDirection is an enum that doesn't bitwise-OR.
        child: Dismissible(
          key: ValueKey('top_banner:up:${widget.message}'),
          direction: DismissDirection.up,
          onDismissed: (_) => widget.onSwipeDismiss(),
          child: Dismissible(
            key: ValueKey('top_banner:horiz:${widget.message}'),
            direction: DismissDirection.horizontal,
            onDismissed: (_) => widget.onSwipeDismiss(),
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: EdgeInsets.fromLTRB(
                  16,
                  6,
                  widget.actionLabel == null ? 16 : 6,
                  6,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surface
                      .withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(color: Colors.black26, blurRadius: 8),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // The text portion is IgnorePointer'd so a tap on the
                    // banner pill doesn't compete with whatever's
                    // underneath; only the explicit action button is
                    // interactive.
                    Flexible(
                      child: IgnorePointer(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          // liveRegion so TalkBack/VoiceOver announce the
                          // message when the banner appears. This primitive
                          // replaced Material's SnackBar, which auto-announced;
                          // without this a blind user gets no feedback on the
                          // failures (marker save failed, sync failed, …) that
                          // flow through here.
                          child: Semantics(
                            liveRegion: true,
                            child: Text(
                              widget.message,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (widget.actionLabel != null) ...[
                      const SizedBox(width: 8),
                      // A time-limited Undo / Retry: Material's 48 dp target,
                      // not the 28 dp shrink-wrapped one it had (#1374
                      // A11Y-15).
                      TextButton(
                        key: const Key('topBannerAction'),
                        onPressed: widget.onAction,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          tapTargetSize: MaterialTapTargetSize.padded,
                        ),
                        child: Text(
                          widget.actionLabel!,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
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

import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart' show motionScrollTo;

/// Stick-to-bottom for a chat log whose newest content arrives at the end.
///
/// New content follows the reader down only while they are within
/// [threshold] of the bottom. Scrolling up releases it, so a streaming reply
/// can be read from its start; reaching the bottom again, the
/// [JumpToLatestButton], or the runner's own turn (`force`) re-engages it.
/// Only an upward move releases, so the controller's own scroll down — an
/// animation still in flight included — can never switch it off.
class ChatStickToBottom {
  ChatStickToBottom(this.scroll, {this.threshold = 48}) {
    scroll.addListener(_onScroll);
  }

  final ScrollController scroll;
  final double threshold;

  /// True while content has arrived below a reader who scrolled away.
  final ValueNotifier<bool> showJump = ValueNotifier(false);

  bool _stick = true;
  ScrollPosition? _lastPosition;
  double? _lastPixels;

  bool get isFollowing => _stick;

  void _onScroll() {
    if (!scroll.hasClients) return;
    final p = scroll.position;
    // The coach swaps between an empty-state list and the message list on
    // one controller; a fresh position starts at 0 and must not read as the
    // reader scrolling up from where the old one stood.
    if (!identical(p, _lastPosition)) {
      _lastPosition = p;
      _lastPixels = null;
    }
    final atBottom = p.maxScrollExtent - p.pixels <= threshold;
    final movedUp = _lastPixels != null && p.pixels < _lastPixels!;
    _lastPixels = p.pixels;
    if (atBottom) {
      _stick = true;
      showJump.value = false;
    } else if (movedUp) {
      _stick = false;
    }
  }

  /// Scrolls to the newest content if the reader is following it, and
  /// otherwise raises [showJump]. [force] re-engages following first: the
  /// runner's own turn, a thread switch and the jump button use it.
  Future<void> scrollToBottom(
    BuildContext context, {
    bool force = false,
  }) async {
    if (force) {
      _stick = true;
      _lastPixels = null;
      showJump.value = false;
    }
    // Let the new content lay out so maxScrollExtent includes it.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (!context.mounted || !scroll.hasClients) return;
    if (!_stick) {
      showJump.value = true;
      return;
    }
    await motionScrollTo(context, scroll, scroll.position.maxScrollExtent);
  }

  void dispose() {
    scroll.removeListener(_onScroll);
    showJump.dispose();
  }
}

/// The "Jump to latest" pill shown over a chat log while [ChatStickToBottom]
/// has content waiting below the reader.
class JumpToLatestButton extends StatelessWidget {
  const JumpToLatestButton({
    super.key,
    required this.controller,
    required this.label,
  });

  final ChatStickToBottom controller;
  final String label;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: controller.showJump,
      builder: (context, show, _) {
        if (!show) return const SizedBox.shrink();
        return FilledButton.tonalIcon(
          onPressed: () => controller.scrollToBottom(context, force: true),
          icon: const Icon(Icons.arrow_downward, size: 18),
          label: Text(label),
        );
      },
    );
  }
}

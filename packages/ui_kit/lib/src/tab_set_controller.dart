import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TabController;
import 'package:flutter/scheduler.dart';

/// The [TabController] for a tab strip whose set of tabs can change while
/// the page is open, kept the same length as that set.
///
/// A `TabController`'s length is fixed when it is made, and nothing in
/// Flutter checks it against the strip until a debug-only assert after the
/// frame. When a tab left the set under a fixed-length controller — the
/// Notifications tab of your own profile when the session ended, the Gym and
/// Nutrition tabs of the Fitness hub when they were switched off — the strip
/// built a tab past its end: `RangeError (length)` thrown from `_TabBarState`
/// (Sentry THREKIR-CLIENT-A). Hold the tabs here and pass every change to
/// [update]; the strip and the pager read [controller] and [tabs], so they
/// cannot disagree.
///
/// On a change the controller is replaced, never resized (Flutter has no
/// resize). The tab being shown stays selected while it is still in the set,
/// including the tab a running tap animation is moving to; otherwise the
/// selection goes to the caller's fallback, or else to the nearest index
/// still in range. The replaced controller is disposed after the frame that
/// stops using it, so the strip and pager can still detach from a live one.
class TabSetController<T> {
  TabSetController({
    required TickerProvider vsync,
    required List<T> tabs,
    T? initial,
    this.onIndexChanged,
  })  : _vsync = vsync,
        _tabs = List.unmodifiable(tabs) {
    final index = initial == null ? -1 : _tabs.indexOf(initial);
    _controller = _build(index < 0 ? 0 : index);
  }

  final TickerProvider _vsync;

  /// Added to every controller this makes, and removed when it is replaced.
  final VoidCallback? onIndexChanged;

  List<T> _tabs;
  late TabController _controller;
  final List<TabController> _retired = [];
  bool _disposed = false;

  /// The controller for the current [tabs]; a new object after [update]
  /// changes the set, so read it at build time rather than caching it.
  TabController get controller => _controller;

  /// The tabs, in strip order.
  List<T> get tabs => _tabs;

  /// The tab showing, or the one a running animation is moving to.
  T get selected => _tabs[_controller.index];

  /// Selects [tab]. A tab that is not in the set is ignored rather than
  /// handed to the controller as index -1.
  void select(T tab, {bool animate = true}) {
    final index = _tabs.indexOf(tab);
    if (index < 0 || index == _controller.index) return;
    if (animate) {
      _controller.animateTo(index);
    } else {
      _controller.index = index;
    }
  }

  /// Adopts [next] as the set of tabs. Returns false, and changes nothing,
  /// when it is the set already held.
  ///
  /// Safe to call from `build`: it notifies no one. The caller rebuilds the
  /// strip with the new [controller] in the same pass.
  bool update(List<T> next, {T? fallback}) {
    if (listEquals(next, _tabs)) return false;
    var index = _tabs.isEmpty ? -1 : next.indexOf(selected);
    if (index < 0 && fallback != null) index = next.indexOf(fallback);
    if (index < 0) index = math.min(_controller.index, next.length - 1);
    _retire(_controller);
    _tabs = List.unmodifiable(next);
    _controller = _build(math.max(0, index));
    return true;
  }

  TabController _build(int index) {
    final controller = TabController(
      length: _tabs.length,
      vsync: _vsync,
      initialIndex: index,
    );
    final listener = onIndexChanged;
    if (listener != null) controller.addListener(listener);
    return controller;
  }

  void _retire(TabController old) {
    final listener = onIndexChanged;
    if (listener != null) old.removeListener(listener);
    _retired.add(old);
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_disposed) return;
      if (_retired.remove(old)) old.dispose();
    });
  }

  void dispose() {
    _disposed = true;
    final listener = onIndexChanged;
    if (listener != null) _controller.removeListener(listener);
    _controller.dispose();
    for (final old in _retired) {
      old.dispose();
    }
    _retired.clear();
  }
}

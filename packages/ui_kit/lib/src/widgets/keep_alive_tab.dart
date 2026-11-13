import 'package:flutter/widgets.dart';

/// Keeps a hub tab's page alive once it has been built. A `TabBarView` is a
/// `PageView` with no cache extent, so without this a page is disposed the
/// moment it scrolls out of view, and switching back re-runs its arrival
/// fetch and drops its search, filters and scroll position. Both hubs
/// (Fitness and Social) wrap each tab body in one.
///
/// The home shell's `_LazyKeepAliveTab` is a different widget: it also
/// defers building its child until first shown and rebuilds it on a key.
class KeepAliveTab extends StatefulWidget {
  const KeepAliveTab({super.key, required this.child});

  final Widget child;

  @override
  State<KeepAliveTab> createState() => _KeepAliveTabState();
}

class _KeepAliveTabState extends State<KeepAliveTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

import 'package:flutter/widgets.dart';

/// Keeps its child's State alive once it has been built, inside any lazily
/// built scrollable: a `TabBarView` (a `PageView` with no cache extent) or a
/// `ListView` past its cache extent would otherwise dispose the child the
/// moment it leaves view.
///
/// Both hubs (Fitness and Social) wrap each tab body in one, so switching
/// back does not re-run the tab's arrival fetch or drop its search, filters
/// and scroll position. The route and run detail screens wrap their map in
/// one, so scrolling past it does not tear down the FlutterMap and reload
/// every tile, and its pulse ticker pauses while it is off screen.
///
/// The home shell's `_LazyKeepAliveTab` is a different widget: it also
/// defers building its child until first shown and rebuilds it on a key.
class KeepAliveChild extends StatefulWidget {
  const KeepAliveChild({super.key, required this.child});

  final Widget child;

  @override
  State<KeepAliveChild> createState() => _KeepAliveChildState();
}

class _KeepAliveChildState extends State<KeepAliveChild>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

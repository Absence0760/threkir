import 'package:flutter/widgets.dart';

/// The Routes tab's views: Mine (the runner's own and saved routes), or
/// Explore on one of its two chips, Routes (public routes, with the discovery
/// maps at their head) or Segments (the segment catalogue).
///
/// The segment catalogue was a Fitness tab of its own until issue #1374
/// (owner decision 1) folded it into Routes, so one value names both the view
/// and Explore's chip, and a link can open Explore on either through the
/// shell's channel (`fitness_surface_requests.dart`).
enum RoutesShow {
  mine,
  routes,
  segments;

  bool get isExplore => this != RoutesShow.mine;
}

/// What the Routes tab hands each Explore body: the Mine · Explore row that
/// sits above the body's own controls, and the Routes · Segments chips that
/// lead the body's chip line. Null when the body is mounted on its own.
@immutable
class RoutesExploreChrome {
  const RoutesExploreChrome({required this.viewBar, required this.chips});

  final Widget viewBar;
  final List<Widget> chips;

  /// [controls] under the view row.
  Widget above(Widget controls) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [viewBar, controls],
      );
}

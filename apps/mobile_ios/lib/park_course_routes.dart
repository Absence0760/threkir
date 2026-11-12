import 'package:flutter/widgets.dart';

import 'widgets/official_badge.dart';

/// Which official routes are a park course's route, for the Official badge:
/// on a park course it must read "Official Threkir course", never just
/// "Official", or it reads as the park's own. Twin of the web
/// `ParkCourseRouteLookup`. A route is unknown until checked, so a surface
/// shows no badge rather than the short one while it waits; a failed read
/// marks the routes checked and not park courses, so a lost lookup never
/// hides the badge on every official route.
class ParkCourseRouteLookup extends ChangeNotifier {
  ParkCourseRouteLookup(this._fetch);

  final Future<Set<String>> Function(List<String> routeIds) _fetch;
  final Map<String, bool> _parkCourse = {};
  final Set<String> _inFlight = {};
  bool _disposed = false;

  bool known(String routeId) => _parkCourse.containsKey(routeId);

  bool isParkCourse(String routeId) => _parkCourse[routeId] == true;

  Future<void> check(Iterable<String> routeIds) async {
    final ids = routeIds
        .toSet()
        .where((id) => !_parkCourse.containsKey(id) && !_inFlight.contains(id))
        .toList();
    if (ids.isEmpty) return;
    _inFlight.addAll(ids);
    Set<String> found;
    try {
      found = await _fetch(ids);
    } catch (e) {
      debugPrint('park course route lookup failed: $e');
      found = const {};
    } finally {
      _inFlight.removeAll(ids);
    }
    if (_disposed) return;
    for (final id in ids) {
      _parkCourse[id] = found.contains(id);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// The Official badge on a route, reading "Official Threkir course" when the
/// route is a park course's. Nothing until [lookup] has checked the route.
class OfficialRouteBadge extends StatelessWidget {
  final String routeId;
  final ParkCourseRouteLookup lookup;
  final double size;

  const OfficialRouteBadge({
    super.key,
    required this.routeId,
    required this.lookup,
    this.size = 14,
  });

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: lookup,
        builder: (context, _) => lookup.known(routeId)
            ? OfficialBadge(
                size: size,
                parkCourse: lookup.isParkCourse(routeId),
              )
            : const SizedBox.shrink(),
      );
}

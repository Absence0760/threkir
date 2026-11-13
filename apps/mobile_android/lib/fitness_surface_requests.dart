import 'package:flutter/material.dart';

import 'routes_views.dart' show RoutesShow;
import 'screens/fitness_hub_screen.dart';
import 'screens/races_screen.dart' show RacesShow;

export 'routes_views.dart' show RoutesShow;
export 'screens/fitness_hub_screen.dart' show FitnessTab;
export 'screens/races_screen.dart' show RacesShow;

/// A parked request: the tab, and for a tab with views the view to open it on
/// (null leaves the tab's view as it is).
typedef FitnessSurfaceRequest = ({
  FitnessTab tab,
  RacesShow? racesShow,
  RoutesShow? routesShow,
});

/// The views of the Fitness hub's tabs that have more than one, held by the
/// shell beside the selected tab so a link can select a tab and its view
/// together, even before the hub (a lazy page) has been built.
class FitnessHubViews {
  /// Races & courses: All · Races · Courses.
  final races = ValueNotifier<RacesShow>(RacesShow.all);

  /// Routes: Mine, or Explore on its Routes or Segments chip.
  final routes = ValueNotifier<RoutesShow>(RoutesShow.mine);

  /// Moves each view [request] names; the views it leaves null stay put.
  void apply(FitnessSurfaceRequest request) {
    if (request.racesShow case final show?) races.value = show;
    if (request.routesShow case final show?) routes.value = show;
  }

  void dispose() {
    races.dispose();
    routes.dispose();
  }
}

/// A link elsewhere in the app asking for one of the Fitness hub's tabs.
///
/// Plans, Races & courses and Routes are tabs of the hub, not screens of
/// their own (decisions § 2437), and the segment catalogue is Routes' Explore
/// view on its Segments chip, so a link to one from a run's summary, the
/// Coach, Settings or a notification selects the tab and view rather than
/// pushing a second copy over the shell — a copy whose back arrow leads away
/// from the tab the runner meant. The caller holds none of the shell's state,
/// so it parks the request and `HomeScreen`, which does, drains it: it closes
/// whatever is pushed over the shell, selects the tab and view and shows the
/// hub.
///
/// Where no shell is listening (a screen mounted on its own, a widget test)
/// [openFitnessSurface] pushes the caller's fallback screen instead, so the
/// link still goes somewhere.
class FitnessSurfaceRequests extends ChangeNotifier {
  FitnessSurfaceRequest? _pending;

  /// Hands [tab] to the shell. False when nothing is listening, in which case
  /// the request is dropped and the caller has to get there itself.
  bool request(FitnessTab tab, {RacesShow? racesShow, RoutesShow? routesShow}) {
    if (!hasListeners) return false;
    _pending = (tab: tab, racesShow: racesShow, routesShow: routesShow);
    notifyListeners();
    return true;
  }

  /// The pending request, cleared as it is read so the same tab can be asked
  /// for twice in a row.
  FitnessSurfaceRequest? take() {
    final request = _pending;
    _pending = null;
    return request;
  }
}

final FitnessSurfaceRequests fitnessSurfaceRequests = FitnessSurfaceRequests();

/// Opens [tab] in the shell's Fitness hub, on [racesShow] when it is Races &
/// courses or [routesShow] when it is Routes, or pushes [fallback] where there
/// is no shell to open it in.
Future<void> openFitnessSurface(
  BuildContext context,
  FitnessTab tab, {
  RacesShow? racesShow,
  RoutesShow? routesShow,
  required Widget Function() fallback,
}) async {
  if (fitnessSurfaceRequests.request(tab,
      racesShow: racesShow, routesShow: routesShow)) {
    return;
  }
  await Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => fallback()));
}

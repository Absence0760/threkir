import 'package:flutter/material.dart';

import 'screens/fitness_hub_screen.dart';
import 'screens/races_screen.dart' show RacesShow;

export 'screens/fitness_hub_screen.dart' show FitnessTab;
export 'screens/races_screen.dart' show RacesShow;

/// A parked request: the tab, and for Races & courses the view to open it on
/// (null leaves the tab's view as it is).
typedef FitnessSurfaceRequest = ({FitnessTab tab, RacesShow? racesShow});

/// A link elsewhere in the app asking for one of the Fitness hub's tabs.
///
/// Plans, Races & courses, Routes and Segments are tabs of the hub, not
/// screens of their own (decisions § 2437), so a link to one from a run's
/// summary, the Coach, Settings or a notification selects the tab rather than
/// pushing a second copy over the shell — a copy whose back arrow leads away
/// from the tab the runner meant. The caller holds none of the shell's state,
/// so it parks the request and `HomeScreen`, which does, drains it: it closes
/// whatever is pushed over the shell, selects the tab and shows the hub.
///
/// Where no shell is listening (a screen mounted on its own, a widget test)
/// [openFitnessSurface] pushes the caller's fallback screen instead, so the
/// link still goes somewhere.
class FitnessSurfaceRequests extends ChangeNotifier {
  FitnessSurfaceRequest? _pending;

  /// Hands [tab] to the shell. False when nothing is listening, in which case
  /// the request is dropped and the caller has to get there itself.
  bool request(FitnessTab tab, {RacesShow? racesShow}) {
    if (!hasListeners) return false;
    _pending = (tab: tab, racesShow: racesShow);
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
/// courses, or pushes [fallback] where there is no shell to open it in.
Future<void> openFitnessSurface(
  BuildContext context,
  FitnessTab tab, {
  RacesShow? racesShow,
  required Widget Function() fallback,
}) async {
  if (fitnessSurfaceRequests.request(tab, racesShow: racesShow)) return;
  await Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => fallback()));
}

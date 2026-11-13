import 'package:flutter/material.dart';

import 'screens/social_screen.dart' show SocialTab;

export 'screens/social_screen.dart' show SocialTab;

/// A link elsewhere in the app asking for one of the Social hub's tabs.
///
/// Feed, Clubs, Events, Challenges and People are tabs of the hub, not
/// screens of their own, so a link to one from Home, a notification or
/// another screen selects the tab rather than pushing a second copy over the
/// shell, the copy whose back arrow leads away from the tab the person meant
/// (issue #1374; `fitness_surface_requests.dart` is the Fitness hub's twin).
/// The caller holds none of the shell's state, so it parks the request and
/// `HomeScreen`, which does, drains it: it returns to the shell (asking any
/// form above it to discard first), selects the tab and shows the hub.
///
/// Where no shell is listening (a screen mounted on its own, a widget test)
/// [openSocialSurface] pushes the caller's fallback screen instead, so the
/// link still goes somewhere.
class SocialSurfaceRequests extends ChangeNotifier {
  SocialTab? _pending;

  /// Hands [tab] to the shell. False when nothing is listening, in which case
  /// the request is dropped and the caller has to get there itself.
  bool request(SocialTab tab) {
    if (!hasListeners) return false;
    _pending = tab;
    notifyListeners();
    return true;
  }

  /// The pending request, cleared as it is read so the same tab can be asked
  /// for twice in a row.
  SocialTab? take() {
    final tab = _pending;
    _pending = null;
    return tab;
  }
}

final SocialSurfaceRequests socialSurfaceRequests = SocialSurfaceRequests();

/// Opens [tab] in the shell's Social hub, or pushes [fallback] where there is
/// no shell to open it in.
Future<void> openSocialSurface(
  BuildContext context,
  SocialTab tab, {
  required Widget Function() fallback,
}) async {
  if (socialSurfaceRequests.request(tab)) return;
  await Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => fallback()));
}

import 'package:flutter/foundation.dart';

import 'help_guides.dart';

/// Cross-screen handoff for "a guide link asked to open this surface".
///
/// The same shape as `pendingSettingsDestination` (decisions § 710): a guide
/// screen holds none of the dependencies the destination screens take, so it
/// parks the intent and `HomeScreen` — which holds all of them — drains it and
/// navigates.
final ValueNotifier<HelpDestination?> pendingHelpDestination =
    ValueNotifier<HelpDestination?>(null);

/// Ask the shell to open [destination]. The host clears the slot as it
/// navigates, so the same destination can be asked for twice in a row.
void openHelpDestination(HelpDestination destination) {
  pendingHelpDestination.value = destination;
}

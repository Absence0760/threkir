import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';
import '../screens/help_screen.dart';

/// The AppBar "?" that opens the guides about the screen it sits on.
///
/// [routes] are the web route ids the screen corresponds to — guides name
/// screens by those ids, and the lookup is web's `guidesForRoute`. One match
/// opens that guide directly; with none it opens the whole guide list, so the
/// button never leads nowhere.
class HelpButton extends StatelessWidget {
  const HelpButton({super.key, required this.routes, this.audience});

  final List<String> routes;

  /// Narrows to guides written for this reader (plus those for everyone).
  final String? audience;

  @override
  Widget build(BuildContext context) => IconButton(
    key: const Key('help-how-this-works'),
    icon: const Icon(Icons.help_outline),
    tooltip: AppLocalizations.of(context).helpHowThisWorks,
    onPressed: () => openHelpForRoutes(context, routes, audience: audience),
  );
}

import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart' show AppBarAction, ToolbarActions;

import '../l10n/gen/app_localizations.dart';

export 'package:ui_kit/ui_kit.dart' show AppBarAction;

/// ui_kit's [ToolbarActions] with the app's "More" tooltip, for a toolbar
/// that is not a `PushedPage` / `DetailPage` app bar (those place their
/// actions themselves).
class AppBarActions extends StatelessWidget {
  const AppBarActions({
    super.key,
    required this.actions,
    this.pinned = const [],
    this.maxVisible = 3,
  });

  final List<AppBarAction> actions;
  final List<Widget> pinned;
  final int maxVisible;

  @override
  Widget build(BuildContext context) => ToolbarActions(
        actions: actions,
        pinned: pinned,
        maxVisible: maxVisible,
        moreTooltip: AppLocalizations.of(context).commonMore,
      );
}

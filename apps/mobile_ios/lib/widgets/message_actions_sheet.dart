import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart' show AppSemanticColors, SheetScaffold;

import '../l10n/gen/app_localizations.dart';

/// The long-press options for one stored message, shared by a direct thread
/// and a group thread: React, Edit (inside the edit window) and Unsend on
/// your own, Report on someone else's. Resolves to `'react'`, `'edit'`,
/// `'unsend'` or `'report'`, or null when dismissed.
Future<String?> showMessageActionsSheet(
  BuildContext context, {
  required bool mine,
  required bool editable,
  required bool canReact,
}) {
  final l10n = AppLocalizations.of(context);
  return showModalBottomSheet<String>(
    context: context,
    useSafeArea: true,
    builder: (ctx) => SheetScaffold(
      padding: EdgeInsets.zero,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (canReact)
            ListTile(
              key: const ValueKey('message-action-react'),
              leading: const Icon(Icons.add_reaction_outlined),
              title: Text(l10n.messagesReact),
              onTap: () => Navigator.pop(ctx, 'react'),
            ),
          if (editable)
            ListTile(
              key: const ValueKey('message-action-edit'),
              leading: const Icon(Icons.edit_outlined),
              title: Text(l10n.messagesEdit),
              onTap: () => Navigator.pop(ctx, 'edit'),
            ),
          if (mine)
            ListTile(
              key: const ValueKey('message-action-unsend'),
              leading:
                  Icon(Icons.undo, color: AppSemanticColors.of(ctx).danger),
              title: Text(l10n.messagesUnsend),
              onTap: () => Navigator.pop(ctx, 'unsend'),
            )
          else
            ListTile(
              key: const ValueKey('message-action-report'),
              leading: const Icon(Icons.flag_outlined),
              title: Text(l10n.messagesReport),
              onTap: () => Navigator.pop(ctx, 'report'),
            ),
        ],
      ),
    ),
  );
}

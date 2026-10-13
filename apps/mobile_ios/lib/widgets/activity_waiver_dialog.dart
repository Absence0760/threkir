import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';

/// Ask for a club's activity-risk acknowledgement before joining it. The
/// accept button stays disabled until the box is ticked, so the database's
/// requirement (§ R7CLUBS-1) is met by an explicit act, not a reflex tap.
/// Resolves `true` only on accept; cancel and barrier dismiss resolve
/// `false`.
Future<bool> confirmActivityWaiver(BuildContext context) async {
  return await showDialog<bool>(
        context: context,
        builder: (_) => const _ActivityWaiverDialog(),
      ) ??
      false;
}

class _ActivityWaiverDialog extends StatefulWidget {
  const _ActivityWaiverDialog();

  @override
  State<_ActivityWaiverDialog> createState() => _ActivityWaiverDialogState();
}

class _ActivityWaiverDialogState extends State<_ActivityWaiverDialog> {
  bool _ack = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.clubWaiverTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.clubWaiverBody),
            const SizedBox(height: 12),
            CheckboxListTile(
              value: _ack,
              onChanged: (v) => setState(() => _ack = v ?? false),
              title: Text(l10n.clubWaiverAck),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: _ack ? () => Navigator.pop(context, true) : null,
          child: Text(l10n.clubWaiverAccept),
        ),
      ],
    );
  }
}

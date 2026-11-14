import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart' show SettingsAnchor;

import '../l10n/gen/app_localizations.dart';

/// A switch whose value comes from a server read, in three states: loading
/// (disabled, the value not yet known), failed (no switch at all, a retry
/// row in its place) and loaded. A failed read never shows a default as if it
/// were the saved choice (issue #1374 FS-6): for a privacy switch, OFF over an
/// account that is private is the one wrong answer.
class AsyncSwitchTile extends StatelessWidget {
  const AsyncSwitchTile({
    super.key,
    this.switchKey,
    required this.title,
    this.subtitle,
    required this.value,
    required this.failed,
    required this.saving,
    required this.onChanged,
    required this.onRetry,
    this.anchor,
  });

  final Key? switchKey;
  final String title;
  final String? subtitle;

  /// Null until the read answers.
  final bool? value;
  final bool failed;
  final bool saving;
  final ValueChanged<bool> onChanged;
  final VoidCallback onRetry;

  /// The row's [SettingsAnchor] id, as `ListRow.anchor`.
  final String? anchor;

  @override
  Widget build(BuildContext context) {
    final id = anchor;
    final row = _row(context);
    return id == null ? row : SettingsAnchor(id: id, label: title, child: row);
  }

  Widget _row(BuildContext context) {
    if (failed) {
      final theme = Theme.of(context);
      final l10n = AppLocalizations.of(context);
      return ListTile(
        title: Text(title),
        subtitle: Text(
          l10n.asyncSwitchLoadFailed,
          style: TextStyle(color: theme.colorScheme.error),
        ),
        trailing: Icon(Icons.refresh, semanticLabel: l10n.errorStateRetry),
        onTap: onRetry,
      );
    }
    final known = value;
    return SwitchListTile(
      key: switchKey,
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      value: known ?? false,
      onChanged: known == null || saving ? null : onChanged,
    );
  }
}

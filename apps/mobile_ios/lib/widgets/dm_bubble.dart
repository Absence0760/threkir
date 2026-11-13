import 'package:api_client/api_client.dart' show safeErrorLabel;
import 'package:core_models/core_models.dart' show DirectMessageRow;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LengthLimitingTextInputFormatter;
import 'package:ui_kit/ui_kit.dart';

import '../dm_send_error.dart';
import '../l10n/gen/app_localizations.dart';
import 'dm_message_text.dart';

/// `direct_messages.body` is capped at `length(btrim(body)) <= 4000` by its
/// CHECK (migration 20261026_001), the same ceiling web's composer sets.
const int kDirectMessageMaxLength = 4000;

/// One message bubble: the sender's own on the right in the primary colour,
/// anyone else's on the left. Shared by the 1:1 thread and the group thread
/// (decisions § 2468), so a message reads the same in both.
class DmBubble extends StatelessWidget {
  const DmBubble({
    super.key,
    required this.mine,
    required this.body,
    required this.time,
    this.attachment,
    this.sending = false,
    this.sendingLabel,
    this.unsentLabel,
    this.seenLabel,
    this.editedLabel,
    this.aiAssisted,
    this.onLongPress,
    this.longPressHint,
    this.onOpenLink,
    this.footer,
    this.senderName,
    this.avatar,
  });

  final bool mine;
  final String? body;
  final String time;
  final Widget? attachment;
  final bool sending;
  final String? sendingLabel;

  /// Set when the sender unsent the message; rendered in place of the body.
  final String? unsentLabel;

  /// "Seen" and the time, under the viewer's newest message the partner read.
  final String? seenLabel;

  /// "Edited", beside the time, once the sender edited the message.
  final String? editedLabel;

  /// The AI-assisted marker beside the time, on a message the coach wrote
  /// from an AI draft (issue #1215 Phase 4). [title] is what a screen reader
  /// announces in place of the short [label].
  final ({String label, String title})? aiAssisted;
  final VoidCallback? onLongPress;
  final String? longPressHint;
  final void Function(String href)? onOpenLink;

  /// Under the bubble: the message's reaction chips.
  final Widget? footer;

  /// In a group, the sender's name on top of someone else's message.
  final String? senderName;

  /// In a group, the sender's avatar beside someone else's message.
  final Widget? avatar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fg = mine ? scheme.onPrimary : scheme.onSurface;
    final bubble = Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.78,
      ),
      decoration: BoxDecoration(
        color: mine ? scheme.primary : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (senderName != null && !mine) ...[
            Text(
              senderName!,
              key: const ValueKey('dm-sender-name'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
          ],
          if (attachment != null) ...[
            attachment!,
            if (body != null) const SizedBox(height: 6),
          ],
          if (unsentLabel != null)
            Text(
              unsentLabel!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: fg.withValues(alpha: 0.8),
                fontStyle: FontStyle.italic,
              ),
            )
          else if (body != null)
            DmMessageText(
              body: body!,
              style: theme.textTheme.bodyMedium?.copyWith(color: fg),
              onOpenLink: onOpenLink,
            ),
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (sending) ...[
                Icon(Icons.schedule,
                    size: AppIconSize.dense, color: fg.withValues(alpha: 0.7)),
                const SizedBox(width: 4),
              ],
              Text(
                time,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: fg.withValues(alpha: 0.7)),
              ),
              if (aiAssisted != null) ...[
                const SizedBox(width: 6),
                Semantics(
                  key: const ValueKey('dm-ai-assisted'),
                  label: aiAssisted!.title,
                  excludeSemantics: true,
                  child: Tooltip(
                    message: aiAssisted!.title,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.auto_awesome,
                            size: AppIconSize.dense,
                            color: fg.withValues(alpha: 0.7)),
                        const SizedBox(width: 2),
                        Text(
                          aiAssisted!.label,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: fg.withValues(alpha: 0.7),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (editedLabel != null) ...[
                const SizedBox(width: 6),
                Text(
                  editedLabel!,
                  key: const ValueKey('dm-edited'),
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: fg.withValues(alpha: 0.7)),
                ),
              ],
            ],
          ),
        ],
      ),
    );
    final Widget content;
    if (sending) {
      // semantics-children: the sending status, then the message it qualifies
      content = Semantics(
        label: sendingLabel,
        child: Opacity(opacity: 0.6, child: bubble),
      );
    } else if (onLongPress != null) {
      content = Semantics(
        onLongPressHint: longPressHint,
        child: GestureDetector(onLongPress: onLongPress, child: bubble),
      );
    } else {
      content = bubble;
    }
    final aligned = Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: avatar == null || mine
          ? content
          : Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                avatar!,
                const SizedBox(width: 6),
                Flexible(child: content),
              ],
            ),
    );
    if (seenLabel == null && footer == null) return aligned;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        aligned,
        if (footer != null)
          Align(
            alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
            child: footer,
          ),
        if (seenLabel != null)
          Padding(
            padding: const EdgeInsets.only(right: 4, bottom: 2),
            child: Text(
              seenLabel!,
              key: const ValueKey('dm-seen'),
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
      ],
    );
  }
}

/// Edits one message in place: Save calls [save], closes with the stored row
/// on success, and on a refusal keeps the dialog and the typed text up with
/// the reason under the field.
class DmEditMessageDialog extends StatefulWidget {
  const DmEditMessageDialog({
    super.key,
    required this.initial,
    required this.save,
  });

  final String initial;
  final Future<DirectMessageRow> Function(String body) save;

  @override
  State<DmEditMessageDialog> createState() => _DmEditMessageDialogState();
}

class _DmEditMessageDialogState extends State<DmEditMessageDialog> {
  late final TextEditingController _text =
      TextEditingController(text: widget.initial);
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final body = _text.text.trim();
    if (body.isEmpty || _saving) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final row = await widget.save(body);
      if (mounted) Navigator.pop(context, row);
    } catch (e) {
      debugPrint('message edit failed: ${safeErrorLabel(e)}');
      if (mounted) {
        setState(() {
          _saving = false;
          _error = dmEditErrorMessage(l10n, e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.messagesEditTitle),
      content: TextField(
        key: const ValueKey('message-edit-field'),
        controller: _text,
        autofocus: true,
        minLines: 1,
        maxLines: 6,
        inputFormatters: [
          LengthLimitingTextInputFormatter(kDirectMessageMaxLength),
        ],
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: l10n.messagesEditTitle,
          errorText: _error,
          errorMaxLines: 3,
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: Text(l10n.commonCancel),
        ),
        TextButton(
          key: const ValueKey('message-edit-save'),
          onPressed: _saving || _text.text.trim().isEmpty ? null : _save,
          child: Text(l10n.messagesEditSave),
        ),
      ],
    );
  }
}

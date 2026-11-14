import 'package:api_client/api_client.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart' show EditorPage, EditorSave;

import '../group_errors.dart';
import '../group_messages.dart';
import '../l10n/gen/app_localizations.dart';
import '../widgets/confirm_discard.dart';
import '../widgets/group_people_picker.dart';
import '../widgets/top_banner.dart';

/// Create a group (issue #1365 slice 3, D1, D2): a title and at least two
/// people, who are invited, never added. The creator takes one of the 32
/// seats, so up to 31 can be invited. Pops with the new conversation's id;
/// the inbox opens the group. Mirrors web `GroupCreateDialog.svelte`.
class GroupCreateScreen extends StatefulWidget {
  const GroupCreateScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<GroupCreateScreen> createState() => _GroupCreateScreenState();
}

class _GroupCreateScreenState extends State<GroupCreateScreen> {
  final _title = TextEditingController();
  List<String> _selected = const [];
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  bool get _ready =>
      normalizeGroupTitle(_title.text) != null &&
      _selected.length >= kGroupMinInvitees;

  Future<void> _create() async {
    final title = normalizeGroupTitle(_title.text);
    if (title == null || !_ready || _busy) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await widget.api.createGroupConversation(title, _selected);
      if (!mounted) return;
      showTopBanner(context, l10n.groupsCreatedToast(title));
      Navigator.of(context).pop(id);
    } catch (e) {
      debugPrint('group create failed: ${safeErrorLabel(e)}');
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = groupErrorMessage(l10n, e,
            refused: l10n.groupsInviteRefused, fallback: l10n.groupsCreateFailed);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return DiscardGuard(
      isDirty: () => _title.text.trim().isNotEmpty || _selected.isNotEmpty,
      isBusy: () => _busy,
      child: EditorPage(
        title: l10n.groupsCreateTitle,
        save: EditorSave(
          key: const ValueKey('group-create-submit'),
          label: _busy ? l10n.groupsCreating : l10n.groupsCreateSubmit,
          busy: _busy,
          onPressed: _ready ? _create : null,
        ),
        status: _error == null
            ? null
            : Text(
                _error!,
                key: const ValueKey('group-create-error'),
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.error),
              ),
        fields: [
          TextField(
            key: const ValueKey('group-title-input'),
            controller: _title,
            enabled: !_busy,
            maxLength: kGroupTitleMax,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: l10n.groupsTitleLabel,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.groupsCreateHint,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          GroupPeoplePicker(
            api: widget.api,
            selected: _selected,
            onChanged: (ids) => setState(() => _selected = ids),
            max: groupSeatsLeft(1, 0),
            disabled: _busy,
          ),
        ],
      ),
    );
  }
}

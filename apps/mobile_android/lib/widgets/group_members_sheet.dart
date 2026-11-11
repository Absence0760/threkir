import 'package:api_client/api_client.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

import '../club_role_labels.dart';
import '../group_errors.dart';
import '../group_messages.dart';
import '../l10n/gen/app_localizations.dart';
import 'confirm_destructive.dart';
import 'group_people_picker.dart';
import 'top_banner.dart';

/// Opens a group's member sheet. [onChanged] runs after any change, so the
/// thread re-reads the roster and the title.
Future<void> showGroupMembersSheet(
  BuildContext context, {
  required ApiClient api,
  required String conversationId,
  required String title,
  required List<GroupMember> members,
  required Future<void> Function() onChanged,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.9,
        child: GroupMembersSheet(
          api: api,
          conversationId: conversationId,
          title: title,
          members: members,
          onChanged: onChanged,
        ),
      ),
    );

/// A group's members and what its owner and admins can do to them (issue
/// #1365 slice 3, group_messages.md § 2). Removal, cancelling an invitation
/// and handing over ownership cannot be taken back from here, so each is
/// confirmed; a role change is one tap back and runs at once (conventions.md
/// § Destructive actions). The server decides every action; this only hides
/// what it would refuse. Mirrors web `GroupMembersSheet.svelte`.
class GroupMembersSheet extends StatefulWidget {
  const GroupMembersSheet({
    super.key,
    required this.api,
    required this.conversationId,
    required this.title,
    required this.members,
    required this.onChanged,
  });

  final ApiClient api;
  final String conversationId;
  final String title;
  final List<GroupMember> members;
  final Future<void> Function() onChanged;

  @override
  State<GroupMembersSheet> createState() => _GroupMembersSheetState();
}

class _GroupMembersSheetState extends State<GroupMembersSheet> {
  late List<GroupMember> _members = widget.members;
  late String _title = widget.title;
  bool _busy = false;
  bool _inviting = false;
  List<String> _invitees = const [];
  bool _renaming = false;
  final _rename = TextEditingController();

  @override
  void dispose() {
    _rename.dispose();
    super.dispose();
  }

  String? get _me => widget.api.userId;

  String? get _myRole {
    for (final m in _members) {
      if (m.userId == _me && !m.invited) return m.role;
    }
    return null;
  }

  String _nameOf(AppLocalizations l10n, GroupMember m) =>
      m.name ?? l10n.profileRunnerFallback;

  Future<bool> _run(
    Future<void> Function() action,
    String success,
  ) async {
    if (_busy) return false;
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return true;
      showTopBanner(context, success);
      await widget.onChanged();
      await _reload();
      return true;
    } catch (e) {
      debugPrint('group member action failed: ${safeErrorLabel(e)}');
      if (mounted) {
        showTopBanner(
          context,
          l10n.groupsActionFailed(groupErrorMessage(l10n, e,
              fallback: l10n.authErrorGeneric)),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The roster after a change. A failure keeps what is shown, and a group
  /// the viewer is no longer active in closes the sheet.
  Future<void> _reload() async {
    try {
      final rows = await widget.api.fetchGroupMembers(widget.conversationId);
      if (mounted) setState(() => _members = rows);
    } on GroupActionRefused catch (e) {
      if (e.reason == GroupRefusal.notFound && mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      debugPrint('group members re-read failed: ${safeErrorLabel(e)}');
    }
  }

  Future<void> _sendInvites() async {
    final ids = _invitees;
    if (ids.isEmpty || _busy) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      await widget.api.inviteToGroup(widget.conversationId, ids);
      if (!mounted) return;
      showTopBanner(context, l10n.groupsInvitedToast(ids.length));
      setState(() {
        _inviting = false;
        _invitees = const [];
      });
      await widget.onChanged();
      await _reload();
    } catch (e) {
      debugPrint('group invite failed: ${safeErrorLabel(e)}');
      if (mounted) {
        showTopBanner(
          context,
          l10n.groupsActionFailed(groupErrorMessage(l10n, e,
              refused: l10n.groupsInviteRefused,
              fallback: l10n.authErrorGeneric)),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveTitle() async {
    final next = normalizeGroupTitle(_rename.text);
    if (next == null) return;
    final l10n = AppLocalizations.of(context);
    final ok = await _run(
      () => widget.api.renameGroup(widget.conversationId, next),
      l10n.groupsRenamedToast,
    );
    if (ok && mounted) {
      setState(() {
        _renaming = false;
        _title = next;
      });
    }
  }

  Future<void> _setRole(GroupMember m, String role) {
    final l10n = AppLocalizations.of(context);
    return _run(
      () => widget.api.setGroupMemberRole(widget.conversationId, m.userId, role),
      role == 'admin'
          ? l10n.groupsMadeAdminToast(_nameOf(l10n, m))
          : l10n.groupsRemovedAdminToast(_nameOf(l10n, m)),
    );
  }

  Future<void> _remove(GroupMember m) async {
    final l10n = AppLocalizations.of(context);
    final name = _nameOf(l10n, m);
    final ok = await confirmDestructive(
      context,
      title: m.invited
          ? l10n.groupsCancelInviteConfirmTitle(name)
          : l10n.groupsRemoveConfirmTitle(name),
      body: m.invited
          ? l10n.groupsCancelInviteConfirmMessage
          : l10n.groupsRemoveConfirmMessage,
      confirmLabel: m.invited ? l10n.groupsCancelInvite : l10n.groupsRemove,
    );
    if (!ok || !mounted) return;
    await _run(
      () => widget.api.removeGroupMember(widget.conversationId, m.userId),
      m.invited
          ? l10n.groupsInviteCancelledToast(name)
          : l10n.groupsRemovedToast(name),
    );
  }

  Future<void> _transfer(GroupMember m) async {
    final l10n = AppLocalizations.of(context);
    final name = _nameOf(l10n, m);
    final ok = await confirmDestructive(
      context,
      title: l10n.groupsTransferConfirmTitle(name),
      body: l10n.groupsTransferConfirmMessage,
      confirmLabel: l10n.groupsMakeOwner,
    );
    if (!ok || !mounted) return;
    await _run(
      () => widget.api.transferGroupOwnership(widget.conversationId, m.userId),
      l10n.groupsTransferredToast(name),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final myRole = _myRole;
    final active = [
      for (final m in _members)
        if (!m.invited) m,
    ];
    final pending = _members.length - active.length;
    final seats = groupSeatsLeft(active.length, pending);
    final sorted = sortGroupMembers(_members);
    final manage = canManageGroup(myRole);
    return Material(
      key: const ValueKey('group-members-sheet'),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Text(
            l10n.groupsMembersTitle(active.length),
            style: theme.textTheme.titleLarge,
          ),
          if (manage) ...[
            const SizedBox(height: 12),
            if (_renaming)
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('group-rename-input'),
                      controller: _rename,
                      autofocus: true,
                      maxLength: kGroupTitleMax,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: l10n.groupsTitleLabel,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => setState(() => _renaming = false),
                    child: Text(l10n.commonCancel),
                  ),
                  FilledButton(
                    key: const ValueKey('group-rename-save'),
                    onPressed: _busy || normalizeGroupTitle(_rename.text) == null
                        ? null
                        : _saveTitle,
                    child: Text(l10n.groupsRenameSave),
                  ),
                ],
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    key: const ValueKey('group-rename'),
                    icon: const Icon(Icons.edit_outlined),
                    label: Text(l10n.groupsRename),
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                              _rename.text = _title;
                              _renaming = true;
                            }),
                  ),
                  if (!_inviting)
                    OutlinedButton.icon(
                      key: const ValueKey('group-invite-more'),
                      icon: const Icon(Icons.person_add_alt),
                      label: Text(l10n.groupsInviteMore),
                      onPressed: seats == 0 || _busy
                          ? null
                          : () => setState(() => _inviting = true),
                    ),
                ],
              ),
            if (_inviting) ...[
              const SizedBox(height: 12),
              GroupPeoplePicker(
                key: const ValueKey('group-invite-panel'),
                api: widget.api,
                selected: _invitees,
                onChanged: (ids) => setState(() => _invitees = ids),
                exclude: {for (final m in _members) m.userId},
                max: seats,
                disabled: _busy,
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => setState(() {
                      _inviting = false;
                      _invitees = const [];
                    }),
                    child: Text(l10n.commonCancel),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const ValueKey('group-invite-send'),
                    onPressed:
                        _busy || _invitees.isEmpty ? null : _sendInvites,
                    child: Text(l10n.groupsInviteSend(_invitees.length)),
                  ),
                ],
              ),
            ],
          ],
          const SizedBox(height: 8),
          for (final m in sorted) _memberRow(l10n, m, myRole),
        ],
      ),
    );
  }

  Widget _memberRow(AppLocalizations l10n, GroupMember m, String? myRole) {
    final me = _me;
    final roleLabel = m.invited
        ? l10n.groupsRoleInvited
        : clubRoleLabel(l10n, m.role ?? 'member');
    final actions = <PopupMenuEntry<String>>[
      if (m.userId != me &&
          canChangeGroupRoles(myRole) &&
          !m.invited &&
          m.role != 'owner') ...[
        if (m.role == 'admin')
          PopupMenuItem(
            key: ValueKey('group-member-demote-${m.userId}'),
            value: 'demote',
            child: Text(l10n.groupsRemoveAdmin),
          )
        else
          PopupMenuItem(
            key: ValueKey('group-member-promote-${m.userId}'),
            value: 'promote',
            child: Text(l10n.groupsMakeAdmin),
          ),
        PopupMenuItem(
          key: ValueKey('group-member-transfer-${m.userId}'),
          value: 'transfer',
          child: Text(l10n.groupsMakeOwner),
        ),
      ],
      if (canRemoveGroupMember(myRole, me, m))
        PopupMenuItem(
          key: ValueKey('group-member-remove-${m.userId}'),
          value: 'remove',
          child: Text(m.invited ? l10n.groupsCancelInvite : l10n.groupsRemove),
        ),
    ];
    final name = _nameOf(l10n, m);
    return ListTile(
      key: ValueKey('group-member-${m.userId}'),
      contentPadding: EdgeInsets.zero,
      leading: IdentityAvatar(
        seed: m.userId,
        name: m.name,
        imageUrl: m.avatarUrl,
        size: 36,
      ),
      title: Text(
        m.userId == me ? '$name ${l10n.groupsYouSuffix}' : name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(roleLabel),
      trailing: actions.isEmpty
          ? null
          : PopupMenuButton<String>(
              key: ValueKey('group-member-menu-${m.userId}'),
              enabled: !_busy,
              tooltip: name,
              itemBuilder: (_) => actions,
              onSelected: (action) {
                switch (action) {
                  case 'promote':
                    _setRole(m, 'admin');
                  case 'demote':
                    _setRole(m, 'member');
                  case 'transfer':
                    _transfer(m);
                  case 'remove':
                    _remove(m);
                }
              },
            ),
    );
  }
}

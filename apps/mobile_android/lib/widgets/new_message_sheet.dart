import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' show UserProfileRow;
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

import '../dm_recipients.dart';
import '../l10n/gen/app_localizations.dart';
import 'error_state.dart';

/// Picks the person a new direct message goes to: the inbox's "New message"
/// (issue #1374, owner decision "Messages move to Social"). Before it the
/// inbox could only say "open a runner's profile and tap Message".
///
/// The list is the viewer's follow graph in both directions, the people the
/// `direct_messages` insert policy admits without a request
/// ([dmRecipientCandidates] says why a block is never drawn here). Resolves
/// to the person picked, or null when the sheet was closed.
Future<DmRecipient?> showNewMessageSheet(
  BuildContext context, {
  required ApiClient api,
}) {
  return showModalBottomSheet<DmRecipient>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => NewMessageSheet(api: api),
  );
}

class NewMessageSheet extends StatefulWidget {
  const NewMessageSheet({super.key, required this.api});

  final ApiClient api;

  @override
  State<NewMessageSheet> createState() => _NewMessageSheetState();
}

class _NewMessageSheetState extends State<NewMessageSheet> {
  bool _loading = true;
  Object? _error;
  List<DmRecipient> _candidates = const [];
  final _query = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final me = widget.api.userId;
    if (me == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final graph = await widget.api.fetchFollowGraph(me);
      DmCandidateProfile candidate(UserProfileRow p) => DmCandidateProfile(
            id: p.id,
            displayName: p.displayName,
            avatarUrl: p.avatarUrl,
          );
      final candidates = dmRecipientCandidates(
        graph.followers.map(candidate),
        graph.following.map(candidate),
        selfId: me,
      );
      if (!mounted) return;
      setState(() {
        _candidates = candidates;
        _loading = false;
      });
    } catch (e) {
      // "Nobody to message" and "couldn't find out who" are different
      // answers, so a failed read is never drawn as an empty list.
      debugPrint('new message sheet load failed: ${safeErrorLabel(e)}');
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  String _relation(AppLocalizations l10n, DmRelation r) => switch (r) {
        DmRelation.mutual => l10n.routeDetailSendDmRelationMutual,
        DmRelation.followsYou => l10n.routeDetailSendDmRelationFollowsYou,
        DmRelation.youFollow => l10n.routeDetailSendDmRelationYouFollow,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final shown = filterDmRecipients(_candidates, _query.text);
    final Widget body;
    if (_loading) {
      body = LoadingState.section(label: l10n.commonLoading);
    } else if (_error != null) {
      body = AppErrorState.inline(
        message: l10n.messagesNewMessageLoadFailed,
        onRetry: _load,
      );
    } else if (_candidates.isEmpty) {
      body = Padding(
        key: const ValueKey('new-message-nobody'),
        padding: const EdgeInsets.symmetric(vertical: AppSpace.smPlus),
        child: Text(l10n.messagesNewMessageNobody, style: muted),
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          AppSearchField(
            key: const ValueKey('new-message-search'),
            controller: _query,
            hint: l10n.groupsPeopleSearch,
            clearTooltip: l10n.commonClearSearch,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpace.sm),
          if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
              child: Text(l10n.groupsPeopleNoMatches, style: muted),
            )
          else
            for (final r in shown)
              ListTile(
                key: ValueKey('new-message-${r.id}'),
                contentPadding: EdgeInsets.zero,
                leading: IdentityAvatar(
                  seed: r.id,
                  name: r.displayName,
                  imageUrl: r.avatarUrl,
                  size: 36,
                ),
                title: Text(
                  r.displayName ?? l10n.profileRunnerFallback,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(_relation(l10n, r.relation)),
                onTap: () => Navigator.of(context).pop(r),
              ),
        ],
      );
    }
    return SheetScaffold(
      title: Text(l10n.messagesNewMessage),
      body: body,
    );
  }
}

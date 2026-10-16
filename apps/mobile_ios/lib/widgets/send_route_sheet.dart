import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' show UserProfileRow;
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart' show IdentityAvatar, ListSkeleton;

import '../dm_recipients.dart';
import '../dm_send_error.dart';
import '../l10n/gen/app_localizations.dart';

/// Send one route to one person as a direct message carrying the typed route
/// attachment. Mirror of web `SendRouteDialog.svelte`
/// (route_direct_share.md).
///
/// [shareUrl] is the message body: the public `/share/route/{id}` link when
/// the caller has made the route reachable, or the in-app `/routes/{id}` link
/// when [grantAccess] is set. With [grantAccess] each send first shares the
/// route with that one person (a `route_shares` grant), so it stays private.
///
/// Resolves to the person whose conversation the sender asked to open, or
/// null when the sheet was closed any other way.
Future<DmRecipient?> showSendRouteSheet(
  BuildContext context, {
  required ApiClient api,
  required String routeId,
  required String shareUrl,
  bool grantAccess = false,
}) {
  return showModalBottomSheet<DmRecipient>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => SendRouteSheet(
      api: api,
      routeId: routeId,
      shareUrl: shareUrl,
      grantAccess: grantAccess,
    ),
  );
}

class SendRouteSheet extends StatefulWidget {
  const SendRouteSheet({
    super.key,
    required this.api,
    required this.routeId,
    required this.shareUrl,
    this.grantAccess = false,
  });

  final ApiClient api;
  final String routeId;
  final String shareUrl;
  final bool grantAccess;

  @override
  State<SendRouteSheet> createState() => _SendRouteSheetState();
}

class _SendRouteSheetState extends State<SendRouteSheet> {
  bool _loading = true;
  bool _loadFailed = false;
  List<DmRecipient> _candidates = const [];
  String _query = '';
  String? _sendingTo;
  String? _sendError;
  DmRecipient? _sentTo;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final me = widget.api.userId;
    if (me == null) {
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
      return;
    }
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final pages = await Future.wait([
        widget.api.fetchFollowers(me, limit: 500),
        widget.api.fetchFollowing(me, limit: 500),
      ]);
      DmCandidateProfile candidate(UserProfileRow p) => DmCandidateProfile(
        id: p.id,
        displayName: p.displayName,
        avatarUrl: p.avatarUrl,
      );
      final candidates = dmRecipientCandidates(
        pages[0].rows.map(candidate),
        pages[1].rows.map(candidate),
        selfId: me,
      );
      if (!mounted) return;
      setState(() {
        _candidates = candidates;
        _loading = false;
      });
    } catch (e) {
      // Never an empty list: "nobody to send to" and "couldn't find out who
      // you can send to" are different answers.
      debugPrint('send route: recipient load failed: $e');
      if (!mounted) return;
      setState(() {
        _candidates = const [];
        _loadFailed = true;
        _loading = false;
      });
    }
  }

  Future<void> _send(DmRecipient recipient) async {
    if (_sendingTo != null) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _sendingTo = recipient.id;
      _sendError = null;
    });
    try {
      // Grant first: a message whose link does not open for its reader is
      // worse than no message, so a refused grant stops the send.
      if (widget.grantAccess) {
        await widget.api.addShare(
          ShareableKind.route,
          widget.routeId,
          recipient.id,
        );
      }
      await widget.api.sendDm(
        recipient.id,
        widget.shareUrl,
        routeId: widget.routeId,
      );
      if (!mounted) return;
      setState(() => _sentTo = recipient);
    } catch (e) {
      debugPrint('send route: send failed: $e');
      if (!mounted) return;
      setState(() => _sendError = dmSendErrorMessage(l10n, e));
    } finally {
      if (mounted) setState(() => _sendingTo = null);
    }
  }

  String _nameOf(AppLocalizations l10n, DmRecipient r) =>
      r.displayName ?? l10n.profileRunnerFallback;

  String _relation(AppLocalizations l10n, DmRecipient r) =>
      switch (r.relation) {
        DmRelation.mutual => l10n.routeDetailSendDmRelationMutual,
        DmRelation.followsYou => l10n.routeDetailSendDmRelationFollowsYou,
        DmRelation.youFollow => l10n.routeDetailSendDmRelationYouFollow,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final sent = _sentTo;

    final children = <Widget>[
      Semantics(
        header: true,
        child: Text(
          l10n.routeDetailSendDmTitle,
          style: theme.textTheme.titleLarge,
        ),
      ),
      const SizedBox(height: 8),
    ];

    if (sent != null) {
      children.addAll([
        Semantics(
          liveRegion: true,
          child: Text(
            l10n.routeDetailSendDmSent(_nameOf(l10n, sent)),
            key: const ValueKey('send-route-sent'),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(
              key: const ValueKey('send-route-open-thread'),
              onPressed: () => Navigator.of(context).pop(sent),
              child: Text(l10n.routeDetailSendDmOpenThread),
            ),
            OutlinedButton(
              key: const ValueKey('send-route-done'),
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.routeDetailSendDmDone),
            ),
          ],
        ),
      ]);
    } else {
      children.addAll([
        Text(l10n.routeDetailSendDmIntro),
        const SizedBox(height: 4),
        Text(
          widget.grantAccess
              ? l10n.routeDetailSendDmPrivateNote
              : l10n.routeDetailSendDmLinkNote,
          key: const ValueKey('send-route-note'),
          style: muted,
        ),
        const SizedBox(height: 12),
        if (_sendError != null) ...[
          Semantics(
            liveRegion: true,
            child: Text(
              _sendError!,
              key: const ValueKey('send-route-error'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        ..._body(l10n, muted),
      ]);
    }

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          key: const ValueKey('send-route-sheet'),
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: children,
          ),
        ),
      ),
    );
  }

  List<Widget> _body(AppLocalizations l10n, TextStyle? muted) {
    if (_loading) {
      return [ListSkeleton.section(label: l10n.commonLoading, rows: 3)];
    }
    if (_loadFailed) {
      return [
        Row(
          key: const ValueKey('send-route-load-error'),
          children: [
            Expanded(child: Text(l10n.routeDetailSendDmLoadFailed)),
            TextButton(onPressed: _load, child: Text(l10n.audienceRetry)),
          ],
        ),
      ];
    }
    if (_candidates.isEmpty) {
      return [
        Text(
          l10n.routeDetailSendDmEmpty,
          key: const ValueKey('send-route-empty'),
          style: muted,
        ),
      ];
    }
    final shown = filterDmRecipients(_candidates, _query);
    return [
      TextField(
        key: const ValueKey('send-route-search'),
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search),
          hintText: l10n.routeDetailSendDmSearchPlaceholder,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        onChanged: (v) => setState(() => _query = v),
      ),
      const SizedBox(height: 8),
      if (shown.isEmpty)
        Text(
          l10n.routeDetailSendDmNoMatches,
          key: const ValueKey('send-route-no-matches'),
          style: muted,
        )
      else
        for (final r in shown) _row(l10n, r),
    ];
  }

  Widget _row(AppLocalizations l10n, DmRecipient r) {
    final sending = _sendingTo == r.id;
    return ListTile(
      key: ValueKey('send-route-recipient-${r.id}'),
      contentPadding: EdgeInsets.zero,
      enabled: _sendingTo == null,
      leading: IdentityAvatar(
        seed: r.id,
        name: r.displayName,
        imageUrl: r.avatarUrl,
        size: 40,
      ),
      title: Text(
        _nameOf(l10n, r),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(_relation(l10n, r)),
      trailing: Text(
        sending ? l10n.routeDetailSendDmSending : l10n.routeDetailSendDmSend,
        style: TextStyle(color: Theme.of(context).colorScheme.primary),
      ),
      onTap: _sendingTo == null ? () => _send(r) : null,
    );
  }
}

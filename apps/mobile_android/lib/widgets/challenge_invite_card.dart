import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../challenge_invite_link.dart';
import '../l10n/gen/app_localizations.dart';
import '../share_ref.dart';
import '../share_sheet.dart';
import '../social_service.dart';
import '../web_base_url.dart';
import 'confirm_destructive.dart';
import 'top_banner.dart';

/// The creator's invite link on a challenge, and a public challenge's share
/// page link for anyone (decisions § 2261). The invite half waits on the
/// `challenge_invite_links` gate; the share half does not, because a public
/// challenge is already readable by anyone. Mirrors web
/// `ChallengeInviteLink.svelte`.
class ChallengeInviteCard extends StatefulWidget {
  final SocialService social;
  final String challengeId;
  final bool isPublic;
  final bool canManage;

  /// The share page link carries the creator's own ref (decisions § 2268);
  /// a club admin handing it out is not the creator, so theirs goes out bare.
  final bool isCreator;
  final String? webBaseOverride;

  const ChallengeInviteCard({
    super.key,
    required this.social,
    required this.challengeId,
    required this.isPublic,
    required this.canManage,
    this.isCreator = false,
    this.webBaseOverride,
  });

  @override
  State<ChallengeInviteCard> createState() => _ChallengeInviteCardState();
}

class _ChallengeInviteCardState extends State<ChallengeInviteCard> {
  bool _enabled = false;
  bool _loadFailed = false;
  bool _busy = false;
  String? _token;
  String? _shareRef;

  @override
  void initState() {
    super.initState();
    _load();
    _loadShareRef();
  }

  Future<void> _loadShareRef() async {
    if (!widget.isCreator || !widget.isPublic) return;
    final ref = await widget.social.myShareRef();
    if (mounted && ref != null) setState(() => _shareRef = ref);
  }

  Future<void> _load() async {
    if (!widget.canManage) return;
    try {
      final enabled = await widget.social.challengeInviteLinksEnabled();
      final token = enabled
          ? await widget.social.getChallengeInviteToken(widget.challengeId)
          : null;
      if (!mounted) return;
      setState(() {
        _enabled = enabled;
        _token = token;
        _loadFailed = false;
      });
    } catch (e) {
      debugPrint('ChallengeInviteCard._load failed: $e');
      if (mounted) setState(() => _loadFailed = true);
    }
  }

  String _url(String path) => webPageUrl(path, override: widget.webBaseOverride);

  Future<void> _copy(String url) async {
    final l10n = AppLocalizations.of(context);
    try {
      await Clipboard.setData(ClipboardData(text: url));
      if (mounted) showTopBanner(context, l10n.challengeInviteCopied);
    } catch (e) {
      debugPrint('ChallengeInviteCard._copy failed: $e');
      if (mounted) showTopBanner(context, l10n.challengeInviteCopyFailed);
    }
  }

  Future<void> _share(String url) async {
    try {
      await shareTextFrom(context, text: url);
    } catch (e) {
      debugPrint('ChallengeInviteCard._share failed: $e');
    }
  }

  Future<void> _rotate() async {
    final l10n = AppLocalizations.of(context);
    final ok = await confirmDestructive(
      context,
      title: l10n.challengeInviteRotateTitle,
      body: l10n.challengeInviteRotateBody,
      confirmLabel: l10n.challengeInviteRotate,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      final token =
          await widget.social.rotateChallengeInviteToken(widget.challengeId);
      if (mounted) setState(() => _token = token);
    } catch (e) {
      debugPrint('ChallengeInviteCard._rotate failed: $e');
      if (mounted) showTopBanner(context, l10n.challengeInviteRotateFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final token = _token;
    final showInvite = widget.canManage && _enabled && token != null;
    final showRetry = widget.canManage && _loadFailed;
    if (!showInvite && !showRetry && !widget.isPublic) {
      return const SizedBox.shrink();
    }
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.challengeInviteLinkTitle, style: theme.textTheme.titleMedium),
            if (showRetry) ...[
              const SizedBox(height: 8),
              Text(l10n.challengeInviteLinkLoadFailed,
                  style: TextStyle(color: theme.colorScheme.error)),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(onPressed: _load, child: Text(l10n.errorStateRetry)),
              ),
            ],
            if (showInvite) ...[
              const SizedBox(height: 8),
              Text(widget.isPublic
                  ? l10n.challengeInviteLinkBodyPublic
                  : l10n.challengeInviteLinkBodyPrivate),
              const SizedBox(height: 8),
              SelectableText(
                _url(challengeInvitePath(token)),
                key: const ValueKey('challenge-invite-url'),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonal(
                    onPressed: () => _share(_url(challengeInvitePath(token))),
                    child: Text(l10n.challengeInviteShare),
                  ),
                  OutlinedButton(
                    onPressed: () => _copy(_url(challengeInvitePath(token))),
                    child: Text(l10n.challengeInviteCopy),
                  ),
                  TextButton(
                    key: const ValueKey('challenge-invite-rotate'),
                    onPressed: _busy ? null : _rotate,
                    child: Text(l10n.challengeInviteRotate),
                  ),
                ],
              ),
            ],
            if (widget.isPublic) ...[
              const SizedBox(height: 8),
              Text(l10n.challengeInviteShareBody),
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: OutlinedButton(
                  key: const ValueKey('challenge-share-page'),
                  onPressed: () => _share(withShareRef(
                      _url(challengeSharePath(widget.challengeId)), _shareRef)),
                  child: Text(l10n.challengeInviteSharePage),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

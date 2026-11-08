import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/gen/app_localizations.dart';
import '../share_sheet.dart';
import '../social_service.dart';
import '../web_base_url.dart';
import 'confirm_destructive.dart';
import 'top_banner.dart';

/// The web link that joins a club by invite.
String clubInvitePath(String token) =>
    '/clubs/join/${Uri.encodeComponent(token)}';

/// The public share page for club [slug].
String clubSharePath(String slug) => '/share/club/${Uri.encodeComponent(slug)}';

/// Whether a club has a public share page worth handing out:
/// `/share/club/<slug>` renders nothing for a private or moderation-hidden
/// club. Mirrors web's `canShareClub`.
bool canShareClub(ClubView club) =>
    (club.row.isPublic ?? true) && !club.row.shadowHidden;

/// Hands [url] to the share sheet, copying it instead when the sheet cannot
/// open, so the tap is never a silent no-op.
Future<void> _shareOrCopy(
    BuildContext context, String url, String copiedMessage) async {
  try {
    await shareTextFrom(context, text: url);
    return;
  } catch (e) {
    debugPrint('club share sheet failed, copying instead: $e');
  }
  if (!context.mounted) return;
  await _copy(context, url, copiedMessage);
}

Future<void> _copy(
    BuildContext context, String url, String copiedMessage) async {
  final failed = AppLocalizations.of(context).clubInviteCopyFailed;
  try {
    await Clipboard.setData(ClipboardData(text: url));
    if (context.mounted) showTopBanner(context, copiedMessage);
  } catch (e) {
    debugPrint('club link copy failed: $e');
    if (context.mounted) showTopBanner(context, failed);
  }
}

/// App-bar action sharing a public club's page with anyone. Mirrors web's
/// "Share club" hero button.
class ClubShareButton extends StatelessWidget {
  final ClubView club;
  final String? webBaseOverride;

  const ClubShareButton({super.key, required this.club, this.webBaseOverride});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return IconButton(
      key: const ValueKey('club-share'),
      tooltip: l10n.clubShareClub,
      icon: const Icon(Icons.share_outlined),
      onPressed: () => _shareOrCopy(
        context,
        webPageUrl(clubSharePath(club.row.slug), override: webBaseOverride),
        l10n.clubShareLinkCopied,
      ),
    );
  }
}

/// App-bar action opening a club admin's invite sheet: the invite link and,
/// for a public club, the share page. An admin reaches both from one action
/// so the bar keeps room for the club's name.
class ClubInviteButton extends StatelessWidget {
  final SocialService social;
  final ClubView club;
  final String? webBaseOverride;

  const ClubInviteButton({
    super.key,
    required this.social,
    required this.club,
    this.webBaseOverride,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return IconButton(
      key: const ValueKey('club-invite'),
      tooltip: l10n.clubInviteLinkTitle,
      icon: const Icon(Icons.person_add_alt_1_outlined),
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                ClubInviteCard(
                  social: social,
                  club: club,
                  webBaseOverride: webBaseOverride,
                ),
                if (canShareClub(club))
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Builder(
                      builder: (buttonContext) => OutlinedButton.icon(
                        key: const ValueKey('club-share-page'),
                        icon: const Icon(Icons.share_outlined),
                        label: Text(l10n.clubShareClub),
                        onPressed: () => _shareOrCopy(
                          buttonContext,
                          webPageUrl(clubSharePath(club.row.slug),
                              override: webBaseOverride),
                          l10n.clubShareLinkCopied,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A club admin's invite link, whatever the join policy: an invite-only club
/// has no other way in, and on an open or request-to-join club it lets the
/// admin bring someone straight in. Mirrors the invite card on web
/// `/clubs/[slug]`.
class ClubInviteCard extends StatefulWidget {
  final SocialService social;
  final ClubView club;
  final String? webBaseOverride;

  const ClubInviteCard({
    super.key,
    required this.social,
    required this.club,
    this.webBaseOverride,
  });

  @override
  State<ClubInviteCard> createState() => _ClubInviteCardState();
}

class _ClubInviteCardState extends State<ClubInviteCard> {
  bool _loading = true;
  bool _loadFailed = false;
  bool _busy = false;
  String? _token;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final token = await widget.social.getClubInviteToken(widget.club.row.id);
      if (mounted) setState(() => _token = token);
    } catch (e) {
      debugPrint('ClubInviteCard._load failed: $e');
      if (mounted) setState(() => _loadFailed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _url(String token) =>
      webPageUrl(clubInvitePath(token), override: widget.webBaseOverride);

  Future<void> _write({required bool replacing}) async {
    final l10n = AppLocalizations.of(context);
    if (replacing) {
      final ok = await confirmDestructive(
        context,
        title: l10n.clubInviteRotateTitle,
        body: l10n.clubInviteRotateBody,
        confirmLabel: l10n.clubInviteRotate,
      );
      if (!ok || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      final token =
          await widget.social.regenerateClubInviteToken(widget.club.row.id);
      if (mounted) setState(() => _token = token);
    } catch (e) {
      debugPrint('ClubInviteCard._write failed: $e');
      if (mounted) showTopBanner(context, l10n.clubInviteRotateFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _body(AppLocalizations l10n) => switch (widget.club.joinPolicy) {
        'invite' => l10n.clubInviteBodyInvite,
        'request' => l10n.clubInviteBodyRequest,
        _ => l10n.clubInviteBodyOpen,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final token = _token;
    return Card(
      key: const ValueKey('club-invite-card'),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.clubInviteLinkTitle, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(_body(l10n), style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            if (_loading)
              const Align(
                alignment: AlignmentDirectional.centerStart,
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (_loadFailed) ...[
              Text(l10n.clubInviteLoadFailed,
                  style: TextStyle(color: theme.colorScheme.error)),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                    onPressed: _load, child: Text(l10n.errorStateRetry)),
              ),
            ] else if (token == null)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: FilledButton.tonal(
                  key: const ValueKey('club-invite-generate'),
                  onPressed: _busy ? null : () => _write(replacing: false),
                  child: Text(l10n.clubInviteGenerate),
                ),
              )
            else ...[
              SelectableText(
                _url(token),
                key: const ValueKey('club-invite-url'),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonal(
                    onPressed: () =>
                        _shareOrCopy(context, _url(token), l10n.clubInviteCopied),
                    child: Text(l10n.clubInviteShare),
                  ),
                  OutlinedButton(
                    onPressed: () =>
                        _copy(context, _url(token), l10n.clubInviteCopied),
                    child: Text(l10n.clubInviteCopy),
                  ),
                  TextButton(
                    key: const ValueKey('club-invite-rotate'),
                    onPressed: _busy ? null : () => _write(replacing: true),
                    child: Text(l10n.clubInviteRotate),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

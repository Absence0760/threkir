import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart' show AppIconSize, SheetScaffold;

import '../l10n/gen/app_localizations.dart';
import '../share_sheet.dart';
import '../web_base_url.dart';
import 'badge_grid.dart';
import 'top_banner.dart';

/// Writes a badge's visibility; the profile passes `ApiClient.setBadgeVisibility`.
typedef BadgeVisibilitySetter = Future<void> Function(String id, bool isPublic);

/// Hands a badge's share text to the OS share sheet.
typedef BadgeLinkSharer =
    Future<void> Function(BuildContext context, String text);

/// The public page a badge is shared as — web's `/share/badge/[id]`, which
/// answers "not found" while the badge is private.
Uri badgeShareUrl(String id, {String? webBase}) => Uri.parse(
  webPageUrl('/share/badge/${Uri.encodeComponent(id)}', override: webBase),
);

Future<void> _shareText(BuildContext context, String text) =>
    shareTextFrom(context, text: text);

/// The owner's sheet for one of their badges: show it on the profile and its
/// share page or hide it, and share the page while it is public. Mirrors the
/// owner controls web's `BadgeGrid.svelte` puts on each tile. [onChanged]
/// receives the badge after each visibility change that landed, so the grid
/// redraws it however the sheet is dismissed.
Future<void> showBadgeShareSheet(
  BuildContext context, {
  required AchievementRow badge,
  required BadgeVisibilitySetter setVisibility,
  required ValueChanged<AchievementRow> onChanged,
  @visibleForTesting BadgeLinkSharer? shareOverride,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _BadgeShareSheet(
      badge: badge,
      setVisibility: setVisibility,
      onChanged: onChanged,
      share: shareOverride ?? _shareText,
    ),
  );
}

class _BadgeShareSheet extends StatefulWidget {
  final AchievementRow badge;
  final BadgeVisibilitySetter setVisibility;
  final ValueChanged<AchievementRow> onChanged;
  final BadgeLinkSharer share;

  const _BadgeShareSheet({
    required this.badge,
    required this.setVisibility,
    required this.onChanged,
    required this.share,
  });

  @override
  State<_BadgeShareSheet> createState() => _BadgeShareSheetState();
}

class _BadgeShareSheetState extends State<_BadgeShareSheet> {
  late AchievementRow _badge = widget.badge;
  bool _busy = false;

  Future<void> _toggle() async {
    if (_busy) return;
    final next = !_badge.isPublic;
    setState(() => _busy = true);
    try {
      await widget.setVisibility(_badge.id, next);
      if (!mounted) return;
      setState(() => _badge = _badge.copyWith(isPublic: next));
      widget.onChanged(_badge);
    } catch (e) {
      debugPrint('badge visibility change failed: $e');
      if (mounted) {
        showTopBanner(context, AppLocalizations.of(context).badgesToggleError);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share(String label) async {
    final l10n = AppLocalizations.of(context);
    try {
      await widget.share(
        context,
        l10n.badgesShareText(label, badgeShareUrl(_badge.id).toString()),
      );
    } catch (e) {
      debugPrint('badge share failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final words = badgeWords(l10n, _badge.badgeKey, _badge.tier);
    final label = words?.label ?? _badge.badgeKey;
    final desc = words?.desc;
    final color = badgeTierColor(_badge.tier);
    return SheetScaffold(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            badgeIconData(words?.icon ?? 'military_tech'),
            size: AppIconSize.illustration,
            color: color,
          ),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (desc != null)
            Text(
              desc,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          const SizedBox(height: 4),
          Text(
            badgeTierLabel(l10n, _badge.tier).toUpperCase(),
            textAlign: TextAlign.center,
            style: theme.textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            key: const Key('badge-share'),
            onPressed: _busy || !_badge.isPublic ? null : () => _share(label),
            icon: const Icon(Icons.ios_share),
            label: Text(l10n.badgesShare),
          ),
          if (!_badge.isPublic)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                l10n.badgesPrivateShareHint,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('badge-visibility'),
            onPressed: _busy ? null : _toggle,
            icon: Icon(_badge.isPublic ? Icons.lock_outline : Icons.public),
            label: Text(
              _badge.isPublic ? l10n.badgesMakePrivate : l10n.badgesMakePublic,
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

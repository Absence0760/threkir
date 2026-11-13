import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart'
    show
        AppSpace,
        EmptyState,
        ListCard,
        ListSkeleton,
        PageHeader,
        PushedPage,
        StatGrid,
        StatTile,
        kStatLargeCellMinWidth;

import '../backend_timeout.dart';
import '../l10n/gen/app_localizations.dart';
import '../share_ref.dart';
import '../social_service.dart';
import '../widgets/error_state.dart';

/// How the creator's own share links did over the last 90 days: visits,
/// sign-ups, plan starts and challenge joins per link, and how many came
/// through their own ref (decisions § 2268). Counts only. Mirrors web
/// `/settings/shares`.
class YourSharesScreen extends StatefulWidget {
  final SocialService social;

  const YourSharesScreen({super.key, required this.social});

  @override
  State<YourSharesScreen> createState() => _YourSharesScreenState();
}

class _YourSharesScreenState extends State<YourSharesScreen> {
  List<ShareStat>? _rows;
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final rows =
          await widget.social.fetchMyShareStats().timeout(kBackendLoadTimeout);
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (e) {
      debugPrint('my_share_stats failed: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final rows = _rows ?? const <ShareStat>[];
    return PushedPage(
      title: l10n.sharesTitle,
      body: _loading
          ? ListSkeleton.section(label: l10n.commonLoading, rowHeight: 72)
          : _error
              ? AppErrorState(message: l10n.sharesLoadFailed, onRetry: _load)
              : rows.isEmpty
                  ? EmptyState(
                      icon: Icons.share_outlined,
                      title: l10n.sharesEmptyTitle,
                      body: l10n.sharesEmptyBody,
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          PageHeader(
                            title: l10n.sharesTitle,
                            subtitle: l10n.sharesTagline,
                            padding: const EdgeInsets.only(bottom: 12),
                          ),
                          for (final r in rows) _ShareCard(stat: r),
                          const SizedBox(height: 8),
                          Text(l10n.sharesFootnote,
                              style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
    );
  }
}

class _ShareCard extends StatelessWidget {
  final ShareStat stat;
  const _ShareCard({required this.stat});

  String _kind(AppLocalizations l10n) => switch (stat.kind) {
        'plan' => l10n.sharesKindPlan,
        'challenge' => l10n.sharesKindChallenge,
        'profile' => l10n.sharesKindProfile,
        'session' => l10n.sharesKindSession,
        _ => l10n.sharesKindWorkout,
      };

  Widget _stat(ThemeData theme, AppLocalizations l10n, String label, int value, int viaRef) =>
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          StatTile.large(label: label, value: '$value'),
          if (viaRef > 0)
            Text(
              l10n.sharesViaYourLink(viaRef),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
        ],
      );

  String _title(AppLocalizations l10n) {
    if (stat.kind == 'profile') return l10n.sharesYourProfile;
    final t = stat.title?.trim() ?? '';
    return t.isEmpty ? l10n.sharesUntitled : t;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return ListCard.row(
      key: ValueKey('share-${stat.kind}-${stat.entityId}'),
      title: _title(l10n),
      subtitle: _kind(l10n),
      meta: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StatGrid(
            minCellWidth: kStatLargeCellMinWidth,
            cells: [
              _stat(theme, l10n, l10n.sharesVisits, stat.visits, stat.refVisits),
              _stat(theme, l10n, l10n.sharesSignups, stat.signups, 0),
              if (stat.kind == 'plan')
                _stat(theme, l10n, l10n.sharesStarts, stat.starts, stat.refStarts),
              if (stat.kind == 'challenge')
                _stat(theme, l10n, l10n.sharesJoins, stat.joins, stat.refJoins),
            ],
          ),
          if (stat.botVisits > 0) ...[
            const SizedBox(height: AppSpace.sm),
            Text(l10n.sharesBotVisits(stat.botVisits),
                style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

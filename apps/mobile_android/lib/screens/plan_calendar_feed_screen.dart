import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:ui_kit/ui_kit.dart' show ListSkeleton;
import 'package:url_launcher/url_launcher.dart';

import '../l10n/gen/app_localizations.dart';
import '../plan_calendar_feed.dart';
import '../rate_limit_message.dart';
import '../widgets/confirm_destructive.dart';
import '../widgets/top_banner.dart';

/// Create, copy, replace and turn off the subscribable plan calendar link.
/// Mirrors web's `PlanCalendarFeedCard` (Settings → Integrations). The token
/// lives in this screen's state only between minting it and leaving: the
/// server keeps its hash and nothing can read it back.
class PlanCalendarFeedScreen extends StatefulWidget {
  final Future<Map<String, dynamic>?> Function() loadStatus;
  final Future<String> Function() rotate;
  final Future<void> Function() revoke;
  final String? supabaseUrl;

  const PlanCalendarFeedScreen({
    super.key,
    required this.loadStatus,
    required this.rotate,
    required this.revoke,
    required this.supabaseUrl,
  });

  @override
  State<PlanCalendarFeedScreen> createState() => _PlanCalendarFeedScreenState();
}

class _PlanCalendarFeedScreenState extends State<PlanCalendarFeedScreen> {
  bool _loading = true;
  bool _loadFailed = false;
  bool _busy = false;
  PlanCalendarFeedStatus? _status;
  String? _freshUrl;

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
      final row = await widget.loadStatus();
      if (!mounted) return;
      setState(() => _status = PlanCalendarFeedStatus.fromRow(row));
    } catch (e) {
      debugPrint('plan calendar feed: status failed: $e');
      if (mounted) setState(() => _loadFailed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _mint() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      final token = await widget.rotate();
      if (!mounted) return;
      setState(() {
        _freshUrl = planCalendarFeedUrl(widget.supabaseUrl, token);
        _status = PlanCalendarFeedStatus(createdAt: DateTime.now());
      });
    } catch (e) {
      debugPrint('plan calendar feed: rotate failed: $e');
      if (mounted) {
        final friendly = e is PostgrestException
            ? rateLimitErrorMessage(l10n, code: e.code, message: e.message)
            : null;
        showTopBanner(context, friendly ?? l10n.planCalendarFeedCreateFailed);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmRotate() async {
    final l10n = AppLocalizations.of(context);
    final ok = await confirmDestructive(
      context,
      title: l10n.planCalendarFeedRotateTitle,
      body: l10n.planCalendarFeedRotateMessage,
      confirmLabel: l10n.planCalendarFeedRotate,
    );
    if (ok && mounted) await _mint();
  }

  Future<void> _confirmRevoke() async {
    final l10n = AppLocalizations.of(context);
    final ok = await confirmDestructive(
      context,
      title: l10n.planCalendarFeedRevokeTitle,
      body: l10n.planCalendarFeedRevokeMessage,
      confirmLabel: l10n.planCalendarFeedRevoke,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.revoke();
      if (mounted) {
        setState(() {
          _status = null;
          _freshUrl = null;
        });
      }
    } catch (e) {
      debugPrint('plan calendar feed: revoke failed: $e');
      if (mounted) showTopBanner(context, l10n.planCalendarFeedRevokeFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copy() async {
    final url = _freshUrl;
    if (url == null) return;
    await Clipboard.setData(ClipboardData(text: url));
    if (mounted) {
      showTopBanner(context, AppLocalizations.of(context).planCalendarFeedCopied);
    }
  }

  Future<void> _subscribe(String webcal) async {
    try {
      await launchUrl(Uri.parse(webcal), mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('plan calendar feed: open calendar failed: $e');
    }
  }

  String _when(DateTime t) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    return DateFormat.yMMMd(locale).add_jm().format(t.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final status = _status;
    final fresh = _freshUrl;
    final webcal = fresh == null ? null : webcalUrl(fresh);

    final List<Widget> body;
    if (_loading) {
      body = [ListSkeleton.section(label: l10n.commonLoading, rows: 2)];
    } else if (_loadFailed) {
      body = [
        Text(
          l10n.planCalendarFeedLoadFailed,
          key: const ValueKey('plan-calendar-feed-load-error'),
          style: TextStyle(color: theme.colorScheme.error),
        ),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: _load, child: Text(l10n.planCalendarFeedRetry)),
      ];
    } else if (status == null) {
      body = [
        FilledButton(
          key: const ValueKey('plan-calendar-feed-create'),
          onPressed: _busy ? null : _mint,
          child: Text(l10n.planCalendarFeedCreate),
        ),
      ];
    } else {
      body = [
        if (fresh != null) ...[
          Text(l10n.planCalendarFeedUrlLabel, style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          SelectableText(
            fresh,
            key: const ValueKey('plan-calendar-feed-url'),
            style: theme.textTheme.bodySmall
                ?.copyWith(fontFamily: 'monospace'),
          ),
          const SizedBox(height: 4),
          Text(l10n.planCalendarFeedShownOnce, style: muted),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                key: const ValueKey('plan-calendar-feed-copy'),
                onPressed: _copy,
                icon: const Icon(Icons.copy),
                label: Text(l10n.planCalendarFeedCopy),
              ),
              if (webcal != null)
                OutlinedButton(
                  key: const ValueKey('plan-calendar-feed-subscribe'),
                  onPressed: () => _subscribe(webcal),
                  child: Text(l10n.planCalendarFeedSubscribe),
                ),
            ],
          ),
        ] else ...[
          Text(
            l10n.planCalendarFeedActiveSince(_when(status.createdAt)),
            key: const ValueKey('plan-calendar-feed-active'),
          ),
          const SizedBox(height: 4),
          Text(
            status.lastFetchedAt == null
                ? l10n.planCalendarFeedNeverRead
                : l10n.planCalendarFeedLastRead(_when(status.lastFetchedAt!)),
          ),
          const SizedBox(height: 4),
          Text(l10n.planCalendarFeedLostLink, style: muted),
        ],
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(
              key: const ValueKey('plan-calendar-feed-rotate'),
              onPressed: _busy ? null : _confirmRotate,
              child: Text(l10n.planCalendarFeedRotate),
            ),
            OutlinedButton(
              key: const ValueKey('plan-calendar-feed-revoke'),
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
              onPressed: _busy ? null : _confirmRevoke,
              child: Text(l10n.planCalendarFeedRevoke),
            ),
          ],
        ),
      ];
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.planCalendarFeedTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(l10n.planCalendarFeedDescription),
            const SizedBox(height: 16),
            ...body,
            const SizedBox(height: 16),
            Text(l10n.planCalendarFeedPrivacy, style: muted),
          ],
        ),
      ),
    );
  }
}

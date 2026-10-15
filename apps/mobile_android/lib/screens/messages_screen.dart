import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

import '../l10n/date_format.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../widgets/error_state.dart';
import '../widgets/sign_in_required_state.dart';
import 'message_thread_screen.dart';

/// How often the inbox re-reads its conversation list while on screen. No
/// Realtime channel carries this rail on any platform.
const Duration kMessagesInboxPollInterval = Duration(seconds: 30);

/// The direct-message inbox: one row per conversation, newest first, with the
/// latest message as a preview and an unread count. Mirrors the thread-list
/// pane of web's `/messages/[[id]]`.
class MessagesScreen extends StatefulWidget {
  const MessagesScreen({
    super.key,
    required this.api,
    this.pollInterval = kMessagesInboxPollInterval,
    this.threadPollInterval = kMessageThreadPollInterval,
  });

  final ApiClient api;
  final Duration pollInterval;
  final Duration threadPollInterval;

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen>
    with WidgetsBindingObserver {
  Timer? _poll;
  bool _loading = true;
  Object? _loadError;
  List<DmThread> _threads = const [];
  bool _refreshing = false;

  /// When each conversation was last opened here. A list read that started
  /// before that answers with the count from before the thread marked itself
  /// read, and assigning it as-is put the badge back on the conversation just
  /// left — the race web's `markedReadAt` closes the same way.
  final Map<String, DateTime> _openedAt = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.api.userId == null) return;
    _load();
    _poll = Timer.periodic(widget.pollInterval, (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  List<DmThread> _applyOpened(List<DmThread> rows, DateTime startedAt) => [
        for (final t in rows)
          (_openedAt[t.partnerId]?.isAfter(startedAt) ?? false)
              ? t.copyWith(unread: 0)
              : t,
      ];

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    final startedAt = DateTime.now();
    try {
      final rows = await widget.api.fetchDmThreads();
      if (!mounted) return;
      setState(() {
        _threads = _applyOpened(rows, startedAt);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e;
        _loading = false;
      });
    }
  }

  /// A poll keeps the list it has on a failure: the next tick is the retry.
  Future<void> _refresh() async {
    if (_loading || _refreshing) return;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    if (_loadError != null) return _load();
    _refreshing = true;
    final startedAt = DateTime.now();
    try {
      final rows = await widget.api.fetchDmThreads();
      if (mounted) setState(() => _threads = _applyOpened(rows, startedAt));
    } catch (e) {
      debugPrint('messages inbox poll failed: $e');
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _open(DmThread t) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MessageThreadScreen(
          api: widget.api,
          partnerId: t.partnerId,
          partnerName: t.partnerName,
          partnerAvatarUrl: t.partnerAvatarUrl,
          pollInterval: widget.threadPollInterval,
        ),
      ),
    );
    if (!mounted) return;
    _openedAt[t.partnerId] = DateTime.now();
    setState(() {
      _threads = [
        for (final x in _threads)
          x.partnerId == t.partnerId ? x.copyWith(unread: 0) : x,
      ];
    });
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.messagesTitle)),
      body: _body(l10n),
    );
  }

  Widget _body(AppLocalizations l10n) {
    if (widget.api.userId == null) return SignInRequiredState(api: widget.api);
    if (_loading && _threads.isEmpty) {
      return ListSkeleton(label: l10n.commonLoading);
    }
    if (_loadError != null && _threads.isEmpty) {
      return ErrorState(message: l10n.messagesLoadError, onRetry: _load);
    }
    if (_threads.isEmpty) {
      return EmptyState(
        icon: Icons.chat_bubble_outline,
        title: l10n.messagesEmptyTitle,
        body: l10n.messagesEmptyBody,
      );
    }
    final tag = localeToTag(Localizations.localeOf(context));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _threads.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, i) => _row(l10n, _threads[i], tag),
      ),
    );
  }

  Widget _row(AppLocalizations l10n, DmThread t, String tag) {
    final theme = Theme.of(context);
    final unread = t.unread > 0;
    final name = t.partnerName ?? l10n.profileRunnerFallback;
    return ListTile(
      key: ValueKey('dm-thread-${t.partnerId}'),
      leading: IdentityAvatar(
        seed: t.partnerId,
        name: t.partnerName,
        imageUrl: t.partnerAvatarUrl,
        size: 40,
      ),
      title: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: unread ? const TextStyle(fontWeight: FontWeight.w700) : null,
      ),
      subtitle: Text(
        t.lastFromMe ? l10n.messagesYouPrefixed(t.lastBody) : t.lastBody,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            _stamp(t.lastAt, tag),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (unread) ...[
            const SizedBox(height: 4),
            Semantics(
              label: l10n.messagesUnreadCount(t.unread),
              excludeSemantics: true,
              child: StatusPill(
                key: ValueKey('dm-unread-${t.partnerId}'),
                label: '${t.unread}',
                foreground: theme.colorScheme.onPrimary,
                fill: theme.colorScheme.primary,
                size: StatusPillSize.compact,
              ),
            ),
          ],
        ],
      ),
      onTap: () => _open(t),
    );
  }

  static String _stamp(DateTime at, String tag) {
    final local = at.toLocal();
    final now = DateTime.now();
    final today = local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    return today ? formatTime(at, tag) : formatDateShort(at, tag);
  }
}

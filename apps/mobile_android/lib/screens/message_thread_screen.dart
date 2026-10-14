import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LengthLimitingTextInputFormatter;
import 'package:ui_kit/ui_kit.dart';

import '../dm_attachment.dart';
import '../dm_send_error.dart';
import '../l10n/date_format.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../widgets/dm_route_attachment.dart';
import '../widgets/error_state.dart';
import '../widgets/sign_in_required_state.dart';
import '../widgets/top_banner.dart';
import 'profile_screen.dart';

/// `direct_messages.body` is capped at `length(btrim(body)) <= 4000` by its
/// CHECK (migration 20261026_001), the same ceiling web's composer sets.
const int kDirectMessageMaxLength = 4000;

/// How often an open conversation re-reads its newest page. There is no
/// Realtime channel on this rail on any platform, so a poll is how a reply
/// arrives while the conversation is on screen.
const Duration kMessageThreadPollInterval = Duration(seconds: 10);

/// One direct-message conversation with a composer. Mirrors the conversation
/// pane of web's `/messages/[[id]]`.
///
/// A send is optimistic: the bubble appears at once marked as sending, is
/// replaced by the stored row when the insert answers, and on a refusal is
/// withdrawn with the typed text put back in the composer and the reason
/// shown — the follow / block gate, the send throttle, offline and anything
/// else each read differently (`dm_send_error.dart`).
class MessageThreadScreen extends StatefulWidget {
  const MessageThreadScreen({
    super.key,
    required this.api,
    required this.partnerId,
    this.partnerName,
    this.partnerAvatarUrl,
    this.pollInterval = kMessageThreadPollInterval,
    this.onOpenRoute,
  });

  final ApiClient api;
  final String partnerId;
  final String? partnerName;
  final String? partnerAvatarUrl;
  final Duration pollInterval;
  final void Function(BuildContext context, String routeId)? onOpenRoute;

  @override
  State<MessageThreadScreen> createState() => _MessageThreadScreenState();
}

class _PendingMessage {
  _PendingMessage(this.localId, this.body, this.createdAt);
  final String localId;
  final String body;
  final DateTime createdAt;
}

class _MessageThreadScreenState extends State<MessageThreadScreen>
    with WidgetsBindingObserver {
  final _composer = TextEditingController();
  Timer? _poll;

  bool _loading = true;
  Object? _loadError;
  List<DirectMessageRow> _messages = const [];
  bool _hasMore = false;
  bool _loadingEarlier = false;
  bool _refreshing = false;
  int _window = 0;
  int _refreshTick = 0;

  final List<_PendingMessage> _pending = [];
  bool _sending = false;
  int _pendingSeq = 0;

  String? _partnerName;

  @override
  void initState() {
    super.initState();
    _partnerName = widget.partnerName;
    WidgetsBinding.instance.addObserver(this);
    _composer.addListener(_onComposerChanged);
    if (widget.api.userId == null) return;
    _load();
    if (_partnerName == null) _loadPartnerName();
    _poll = Timer.periodic(widget.pollInterval, (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _composer.removeListener(_onComposerChanged);
    _composer.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  void _onComposerChanged() => setState(() {});

  bool get _appInForeground {
    final s = WidgetsBinding.instance.lifecycleState;
    return s == null || s == AppLifecycleState.resumed;
  }

  Future<void> _loadPartnerName() async {
    try {
      final profile = await widget.api.fetchPublicProfile(widget.partnerId);
      if (!mounted || profile?.displayName == null) return;
      setState(() => _partnerName = profile!.displayName);
    } catch (e) {
      debugPrint('message thread partner name read failed: ${safeErrorLabel(e)}');
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final page = await widget.api.fetchDmThread(widget.partnerId);
      if (!mounted) return;
      setState(() {
        _messages = page.messages;
        _hasMore = page.hasMore;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e;
        _loading = false;
      });
      return;
    }
    await _markReadIfUnread();
  }

  /// Re-read the newest page and merge it in by id. Skipped while the first
  /// load or another refresh is in flight, while the app is in the background
  /// and while another screen covers this one. A failed poll keeps what is
  /// on screen: the next tick is the retry, and a banner every ten seconds
  /// would be noise.
  ///
  /// A page that does not reach back to the newest message on screen means
  /// more than a page arrived since the last read. Merging it would leave the
  /// messages between the two out of the list for good, since "load earlier"
  /// pages back from the oldest message shown, so the page replaces the list
  /// instead and the older history is one "load earlier" away again.
  Future<void> _refresh() async {
    if (_loading || _refreshing || _loadError != null) return;
    if (!_appInForeground) return;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    _refreshing = true;
    try {
      final page = await widget.api.fetchDmThread(widget.partnerId);
      if (!mounted) return;
      setState(() {
        _refreshTick++;
        final fresh = page.messages;
        final gap = page.hasMore &&
            fresh.isNotEmpty &&
            _messages.isNotEmpty &&
            _compareOrder(fresh.first, _messages.last) > 0;
        if (!gap) {
          _messages = _merge(_messages, fresh);
          return;
        }
        _window++;
        _messages = _merge(fresh, [
          for (final m in _messages)
            if (_compareOrder(m, fresh.last) > 0) m,
        ]);
        _hasMore = true;
      });
      await _markReadIfUnread();
    } catch (e) {
      debugPrint('message thread poll failed: ${safeErrorLabel(e)}');
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _loadEarlier() async {
    if (_loadingEarlier || _messages.isEmpty) return;
    final window = _window;
    setState(() => _loadingEarlier = true);
    try {
      final page = await widget.api
          .fetchDmThread(widget.partnerId, before: _messages.first);
      if (!mounted || window != _window) return;
      setState(() {
        _messages = _merge(_messages, page.messages);
        _hasMore = page.hasMore;
      });
    } catch (e) {
      debugPrint('message thread older page failed: ${safeErrorLabel(e)}');
      if (mounted) {
        showTopBanner(
          context,
          AppLocalizations.of(context).messagesLoadEarlierFailed,
        );
      }
    } finally {
      if (mounted) setState(() => _loadingEarlier = false);
    }
  }

  static List<DirectMessageRow> _merge(
    List<DirectMessageRow> a,
    List<DirectMessageRow> b,
  ) {
    final byId = <String, DirectMessageRow>{
      for (final m in a) m.id: m,
      for (final m in b) m.id: m,
    };
    return byId.values.toList()..sort(_compareOrder);
  }

  /// The thread's `(created_at, id)` order, the one `fetchDmThread` pages on.
  static int _compareOrder(DirectMessageRow x, DirectMessageRow y) {
    final at = x.createdAt.compareTo(y.createdAt);
    return at != 0 ? at : x.id.compareTo(y.id);
  }

  /// Opening the conversation marks it read, as does a poll that brings in a
  /// new message from the partner. Only up to the newest unread message on
  /// screen: one that arrived after the read that drew the list stays unread
  /// until a poll shows it. An auxiliary effect: a failure leaves the
  /// conversation on screen and the next poll tries again.
  Future<void> _markReadIfUnread() async {
    bool unread(DirectMessageRow m) =>
        m.senderId == widget.partnerId && m.readAt == null;
    final shown = _messages.where(unread);
    if (shown.isEmpty) return;
    final through = shown.last;
    try {
      await widget.api.markDmThreadRead(widget.partnerId, through: through);
      if (!mounted) return;
      final now = DateTime.now().toUtc();
      setState(() {
        _messages = [
          for (final m in _messages)
            unread(m) && _compareOrder(m, through) <= 0
                ? m.copyWith(readAt: now)
                : m,
        ];
      });
    } catch (e) {
      debugPrint('message thread mark-read failed: ${safeErrorLabel(e)}');
    }
  }

  Future<void> _send() async {
    final body = _composer.text.trim();
    if (_sending || body.isEmpty) return;
    final pending =
        _PendingMessage('pending-${_pendingSeq++}', body, DateTime.now());
    setState(() {
      _sending = true;
      _pending.add(pending);
    });
    _composer.clear();
    try {
      final row = await widget.api.sendDm(widget.partnerId, body);
      if (!mounted) return;
      setState(() {
        _pending.remove(pending);
        _messages = _merge(_messages, [row]);
      });
    } catch (e) {
      debugPrint('message send failed: ${safeErrorLabel(e)}');
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      setState(() => _pending.remove(pending));
      if (_composer.text.isEmpty) {
        _composer.value = TextEditingValue(
          text: body,
          selection: TextSelection.collapsed(offset: body.length),
        );
      }
      showTopBanner(
        context,
        dmSendErrorMessage(l10n, e),
        duration: kTopBannerMaxDuration,
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _openProfile() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ProfileScreen(api: widget.api, userId: widget.partnerId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final signedIn = widget.api.userId != null;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            IdentityAvatar(
              seed: widget.partnerId,
              name: _partnerName,
              imageUrl: widget.partnerAvatarUrl,
              size: 32,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _partnerName ?? l10n.profileRunnerFallback,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          if (signedIn)
            IconButton(
              tooltip: l10n.messagesViewProfile,
              icon: const Icon(Icons.person_outline),
              onPressed: _openProfile,
            ),
        ],
      ),
      body: !signedIn
          ? SignInRequiredState(api: widget.api)
          : Column(
              children: [
                Expanded(child: _body(l10n)),
                if (_loadError == null && !_loading) _composerBar(l10n),
              ],
            ),
    );
  }

  Widget _body(AppLocalizations l10n) {
    if (_loading) {
      return FullBodyLoader(
        kind: ActivityLoaderKind.run,
        label: l10n.commonLoading,
      );
    }
    if (_loadError != null) {
      return ErrorState(message: l10n.messagesThreadLoadError, onRetry: _load);
    }
    if (_messages.isEmpty && _pending.isEmpty) {
      return EmptyState(
        icon: Icons.chat_bubble_outline,
        title: l10n.messagesThreadEmpty,
      );
    }
    final tag = localeToTag(Localizations.localeOf(context));
    final me = widget.api.userId;
    // Reversed so the newest message sits at the bottom and the list opens
    // there, the way every conversation does.
    final items = <Widget>[
      for (final p in _pending.reversed)
        _Bubble(
          key: ValueKey(p.localId),
          mine: true,
          sending: true,
          body: p.body,
          time: formatTime(p.createdAt, tag),
          sendingLabel: l10n.messagesSending,
        ),
      for (final m in _messages.reversed)
        _Bubble(
          key: ValueKey(m.id),
          mine: m.senderId == me,
          body: hasDmRouteAttachment(m.routeId) &&
                  bodyRestatesAttachment(m.body, m.routeId!)
              ? null
              : m.body,
          time: _stamp(m.createdAt, tag),
          attachment: hasDmRouteAttachment(m.routeId)
              ? DmRouteAttachment(
                  api: widget.api,
                  routeId: m.routeId!,
                  refreshTick: _refreshTick,
                  onOpen: widget.onOpenRoute,
                )
              : null,
        ),
      if (_hasMore)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Center(
            child: TextButton(
              onPressed: _loadingEarlier ? null : _loadEarlier,
              child: Text(l10n.messagesLoadEarlier),
            ),
          ),
        ),
    ];
    return ListView(
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      children: items,
    );
  }

  static String _stamp(DateTime at, String tag) {
    final local = at.toLocal();
    final now = DateTime.now();
    final today = local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    return today ? formatTime(at, tag) : formatDateTime(at, tag);
  }

  Widget _composerBar(AppLocalizations l10n) {
    final theme = Theme.of(context);
    final canSend = !_sending && _composer.text.trim().isNotEmpty;
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: theme.dividerColor)),
        ),
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('message-composer'),
                controller: _composer,
                minLines: 1,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                inputFormatters: [
                  LengthLimitingTextInputFormatter(kDirectMessageMaxLength),
                ],
                decoration: InputDecoration(
                  hintText: l10n.messagesComposerHint,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              key: const ValueKey('message-send'),
              tooltip: l10n.messagesSend,
              icon: const Icon(Icons.send),
              onPressed: canSend ? _send : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    super.key,
    required this.mine,
    required this.body,
    required this.time,
    this.attachment,
    this.sending = false,
    this.sendingLabel,
  });

  final bool mine;
  final String? body;
  final String time;
  final Widget? attachment;
  final bool sending;
  final String? sendingLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fg = mine ? scheme.onPrimary : scheme.onSurface;
    final bubble = Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.78,
      ),
      decoration: BoxDecoration(
        color: mine ? scheme.primary : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (attachment != null) ...[
            attachment!,
            if (body != null) const SizedBox(height: 6),
          ],
          if (body != null)
            Text(body!, style: theme.textTheme.bodyMedium?.copyWith(color: fg)),
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (sending) ...[
                Icon(Icons.schedule,
                    size: AppIconSize.dense, color: fg.withValues(alpha: 0.7)),
                const SizedBox(width: 4),
              ],
              Text(
                time,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: fg.withValues(alpha: 0.7)),
              ),
            ],
          ),
        ],
      ),
    );
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: sending
          ? Semantics(
              label: sendingLabel,
              child: Opacity(opacity: 0.6, child: bubble),
            )
          : bubble,
    );
  }
}

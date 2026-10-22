import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' show CoachMessageRow;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

import '../ai_disclosure.dart';
import '../ai_disclosure_memo.dart';
import '../l10n/date_format.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../messages_inbox.dart';
import '../pro_sellable.dart';
import '../settings_sync.dart';
import '../training_service.dart';
import '../widgets/ai_tag.dart';
import '../widgets/error_state.dart';
import '../widgets/sign_in_required_state.dart';
import '../widgets/top_banner.dart';
import 'coach_screen.dart';
import 'message_thread_screen.dart';

/// How often the inbox re-reads its conversation list while on screen. No
/// Realtime channel carries this rail on any platform.
const Duration kMessagesInboxPollInterval = Duration(seconds: 30);

Object? _activeCoachPlacement() => activeSetting(kMessagesCoachRowKey);

/// The Coach's state as the inbox row needs it (decisions § 2227).
class _CoachRowState {
  final CoachInboxPlacement placement;

  /// The runner has accepted the Coach disclosure. False on a failed read.
  final bool consented;

  /// The newest Coach message, read only when [consented].
  final CoachMessageRow? latest;

  const _CoachRowState({
    required this.placement,
    required this.consented,
    this.latest,
  });

  _CoachRowState copyWith({
    CoachInboxPlacement? placement,
    CoachMessageRow? latest,
  }) =>
      _CoachRowState(
        placement: placement ?? this.placement,
        consented: consented,
        latest: latest ?? this.latest,
      );
}

/// The inbox: one row per conversation, newest first, with the latest message
/// as a preview and an unread count, plus the AI Coach as a conversation of
/// its own — pinned at the top unless the runner chose otherwise (decisions
/// § 2227). Mirrors the thread-list pane of web's `/messages` layout.
class MessagesScreen extends StatefulWidget {
  const MessagesScreen({
    super.key,
    required this.api,
    this.training,
    this.pollInterval = kMessagesInboxPollInterval,
    this.threadPollInterval = kMessageThreadPollInterval,
    this.loadPerks,
    this.readCoachPlacement,
    this.writeUniversal,
  });

  final ApiClient api;

  /// What the Coach row opens [CoachScreen] with. Without it there is no
  /// Coach row, as Home shows no Coach card without one.
  final TrainingService? training;
  final Duration pollInterval;
  final Duration threadPollInterval;

  /// Whether the deploy has the Coach live; the row is off unless it says so.
  /// Defaults to the capability manifest; tests inject it.
  final Future<ProPerks> Function()? loadPerks;

  /// The stored `messages_coach_row` value. Defaults to the app's settings
  /// bag; tests inject it.
  final Object? Function()? readCoachPlacement;

  /// Writes a universal setting. Defaults to the app's settings sync.
  final Future<void> Function(Map<String, dynamic>)? writeUniversal;

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

  /// Null while unknown and whenever the Coach row is off.
  _CoachRowState? _coach;
  int _coachGeneration = 0;
  bool _placing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.api.userId == null) return;
    _load();
    _loadCoach();
    _poll = Timer.periodic(widget.pollInterval, (_) => _refresh());
  }

  /// Decides the Coach row. Each step fails toward showing less: an
  /// unreachable manifest is a Coach that is off, and a failed consent read is
  /// no consent, so nothing the Coach said is read.
  Future<void> _loadCoach() async {
    if (widget.training == null) return;
    final generation = ++_coachGeneration;
    var live = false;
    try {
      live = (await (widget.loadPerks ?? fetchProPerks)()).coach;
    } catch (e) {
      debugPrint('messages inbox: capability lookup failed: $e');
    }
    if (!live) {
      if (mounted && generation == _coachGeneration) {
        setState(() => _coach = null);
      }
      return;
    }
    final placement = parseCoachInboxPlacement(
        (widget.readCoachPlacement ?? _activeCoachPlacement)());
    var consented = false;
    try {
      final record =
          aiDisclosureFromProfileRow(await widget.api.fetchAiDisclosure());
      final uid = widget.api.userId;
      if (uid != null) AiDisclosureMemo.remember(uid, record);
      consented = checkAiDisclosure(record, kAiDisclosureVersionCoach).ok;
    } catch (e) {
      debugPrint('messages inbox: AI consent read failed: $e');
    }
    CoachMessageRow? latest;
    if (consented && placement != CoachInboxPlacement.hidden) {
      try {
        latest = await widget.api.fetchLatestCoachMessage();
      } catch (e) {
        debugPrint('messages inbox: latest coach message read failed: $e');
      }
    }
    if (!mounted || generation != _coachGeneration) return;
    setState(() => _coach = _CoachRowState(
          placement: placement,
          consented: consented,
          latest: latest,
        ));
  }

  /// Re-reads the preview only; placement and consent stand until the next
  /// full load.
  Future<void> _refreshCoachPreview() async {
    final coach = _coach;
    if (coach == null ||
        !coach.consented ||
        coach.placement == CoachInboxPlacement.hidden) {
      return;
    }
    final generation = _coachGeneration;
    try {
      final latest = await widget.api.fetchLatestCoachMessage();
      if (!mounted || generation != _coachGeneration || _coach == null) return;
      setState(() => _coach = _CoachRowState(
            placement: _coach!.placement,
            consented: _coach!.consented,
            latest: latest,
          ));
    } catch (e) {
      debugPrint('messages inbox: coach preview refresh failed: $e');
    }
  }

  /// Pin or unpin, saved through the settings bag and shown at once. A
  /// refused write puts the row back where it was and says so.
  Future<void> _togglePin() async {
    final before = _coach;
    if (before == null || _placing) return;
    final next = before.placement == CoachInboxPlacement.pinned
        ? CoachInboxPlacement.listed
        : CoachInboxPlacement.pinned;
    _coachGeneration++;
    setState(() {
      _placing = true;
      _coach = before.copyWith(placement: next);
    });
    try {
      await (widget.writeUniversal ?? updateActiveUniversal)(
          {kMessagesCoachRowKey: next.name});
    } catch (e) {
      debugPrint('messages inbox: coach placement write failed: $e');
      if (!mounted) return;
      setState(() => _coach = before);
      showTopBanner(
        context,
        AppLocalizations.of(context).messagesCoachPlacementFailed,
      );
    } finally {
      if (mounted) setState(() => _placing = false);
    }
  }

  Future<void> _openCoach() async {
    final training = widget.training;
    if (training == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CoachScreen(
          api: widget.api,
          training: training,
          initialPlanId: _coach?.latest?.planId,
        ),
      ),
    );
    // Re-decide the row: the runner may have just accepted the disclosure in
    // the Coach, and has a newer message either way.
    if (mounted) _loadCoach();
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
          (_openedAt[t.threadKey]?.isAfter(startedAt) ?? false)
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
    await _refreshCoachPreview();
  }

  Future<void> _open(DmThread t) async {
    final partnerId = t.partnerId;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => partnerId == null
            ? MessageThreadScreen.deletedPartner(
                api: widget.api,
                deletedPartnerKey: t.deletedPartnerKey!,
                pollInterval: widget.threadPollInterval,
              )
            : MessageThreadScreen(
                api: widget.api,
                partnerId: partnerId,
                partnerName: t.partnerName,
                partnerAvatarUrl: t.partnerAvatarUrl,
                pollInterval: widget.threadPollInterval,
              ),
      ),
    );
    if (!mounted) return;
    _openedAt[t.threadKey] = DateTime.now();
    setState(() {
      _threads = [
        for (final x in _threads)
          x.threadKey == t.threadKey ? x.copyWith(unread: 0) : x,
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
    final coach = _coach;
    final entries = inboxEntries<DmThread>(
      _threads,
      coach == null
          ? null
          : CoachInboxRow(
              placement: coach.placement,
              lastAt: coach.latest?.createdAt,
            ),
      lastAt: (t) => t.lastAt,
    );
    final hasCoachRow = entries.any((e) => e is CoachInboxEntry<DmThread>);
    if (_loadError != null && _threads.isEmpty && !hasCoachRow) {
      return ErrorState(message: l10n.messagesLoadError, onRetry: _load);
    }
    if (entries.isEmpty) {
      return EmptyState(
        icon: Icons.chat_bubble_outline,
        title: l10n.messagesEmptyTitle,
        body: l10n.messagesEmptyBody,
      );
    }
    final tag = localeToTag(Localizations.localeOf(context));
    // With the Coach as the only row, the empty-inbox guidance still says how
    // a conversation with a person starts.
    final footer = _threads.isEmpty
        ? Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              _loadError != null
                  ? l10n.messagesLoadError
                  : l10n.messagesEmptyBody,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          )
        : null;
    return RefreshIndicator(
      onRefresh: () async {
        await Future.wait([_load(), _loadCoach()]);
      },
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: entries.length + (footer == null ? 0 : 1),
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, i) {
          if (i == entries.length) return footer!;
          return switch (entries[i]) {
            CoachInboxEntry() => _coachRow(l10n, coach!),
            DmInboxEntry(:final thread) => _row(l10n, thread, tag),
          };
        },
      ),
    );
  }

  Widget _coachRow(AppLocalizations l10n, _CoachRowState coach) {
    final theme = Theme.of(context);
    final pinned = coach.placement == CoachInboxPlacement.pinned;
    final latest = coach.latest;
    // Without consent nothing the Coach said was read, so the row describes
    // the Coach instead of quoting it.
    final preview = !coach.consented || latest == null
        ? l10n.messagesCoachRowIntro
        : latest.role == 'user'
            ? l10n.messagesYouPrefixed(coachInboxPreview(latest.content))
            : coachInboxPreview(latest.content);
    return ListTile(
      key: const ValueKey('inbox-coach-row'),
      leading: const CoachAvatar(),
      title: Row(
        children: [
          Flexible(
            child: Text(
              l10n.coachTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          const AiTag(),
        ],
      ),
      subtitle: Text(
        preview,
        key: const ValueKey('inbox-coach-preview'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: IconButton(
        key: const ValueKey('inbox-coach-pin'),
        tooltip: pinned ? l10n.messagesCoachUnpin : l10n.messagesCoachPin,
        isSelected: pinned,
        icon: const Icon(Icons.push_pin_outlined),
        selectedIcon: Icon(Icons.push_pin, color: theme.colorScheme.primary),
        onPressed: _placing ? null : _togglePin,
      ),
      onTap: _openCoach,
    );
  }

  Widget _row(AppLocalizations l10n, DmThread t, String tag) {
    final theme = Theme.of(context);
    final unread = t.unread > 0;
    final name = t.partnerId == null
        ? l10n.messagesDeletedAccount
        : t.partnerName ?? l10n.profileRunnerFallback;
    final preview = t.lastUnsent || t.lastBody == null
        ? l10n.messagesUnsentPlaceholder
        : t.lastBody!;
    return ListTile(
      key: ValueKey('dm-thread-${t.threadKey}'),
      leading: IdentityAvatar(
        seed: t.threadKey,
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
        t.lastFromMe ? l10n.messagesYouPrefixed(preview) : preview,
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
                key: ValueKey('dm-unread-${t.threadKey}'),
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

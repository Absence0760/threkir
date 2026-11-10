import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' show CoachMessageRow;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

import '../ai_disclosure.dart';
import '../ai_disclosure_memo.dart';
import '../auth_change_aware.dart';
import '../dm_pending_hides.dart';
import '../dm_search.dart';
import '../l10n/date_format.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../messages_inbox.dart';
import '../monotonic_clock.dart';
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

/// The pause in typing before a search of the viewer's messages is sent.
const Duration kMessagesSearchDebounce = Duration(milliseconds: 300);

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
    with WidgetsBindingObserver, AuthChangeAware<MessagesScreen> {
  Timer? _poll;
  bool _loading = true;
  Object? _loadError;
  List<DmThread> _threads = const [];

  /// When the read [_threads] came from started, which decides the deleted
  /// conversations it still lists ([DmPendingHides.hides]).
  Duration? _threadsReadAt;
  final DmHideReader _hideReader = DmPendingHides.instance.reader();

  /// Bumped when a delete lands or is undone. A list read started before that
  /// is the wrong answer either way, so it is dropped rather than painted.
  int _readGen = 0;

  /// The [_readGen] of the poll in flight, null when none is. A poll from an
  /// older generation does not hold off the read the removal asks for.
  int? _pollGen;

  /// When each conversation was last opened here. A list read that started
  /// before that answers with the count from before the thread marked itself
  /// read, and assigning it as-is put the badge back on the conversation just
  /// left — the race web's `markedReadAt` closes the same way.
  final Map<String, Duration> _openedAt = {};

  /// Null while unknown and whenever the Coach row is off.
  _CoachRowState? _coach;
  int _coachGeneration = 0;
  bool _placing = false;

  /// The inbox is showing its Archived list.
  bool _showingArchived = false;

  /// The inbox is showing its Requests list (message requests the runner has
  /// not answered, migration 20271115002384).
  bool _showingRequests = false;

  /// Search over the viewer's own conversations (migration 20271213121603).
  /// Only the newest query's answer is shown: [_searchSeq] drops the rest.
  final _search = TextEditingController();
  Timer? _searchTimer;
  int _searchSeq = 0;
  String? _searchQuery;
  List<DmSearchHit> _searchHits = const [];
  bool _searching = false;
  bool _searchFailed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    DmPendingHides.instance.addListener(_onPendingHidesChanged);
    if (widget.api.userId == null) return;
    _load();
    _loadCoach();
    _poll = Timer.periodic(widget.pollInterval, (_) => _refresh());
  }

  @override
  ApiClient? get authApi => widget.api;

  /// Everything held belongs to the account that left. A read still in flight
  /// for it is dropped when it lands (each read carries the user it was made
  /// for), and the list is read again for whoever is signed in now.
  @override
  void onAuthUserChanged(String? userId) {
    _readGen++;
    _coachGeneration++;
    setState(() {
      _threads = const [];
      _threadsReadAt = null;
      _openedAt.clear();
      _coach = null;
      _loadError = null;
      _showingArchived = false;
      _showingRequests = false;
    });
    _clearSearch();
    _hideReader.reset();
    if (userId == null) return;
    _load();
    _loadCoach();
    _poll ??= Timer.periodic(widget.pollInterval, (_) => _refresh());
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

  void _onSearchChanged(String text) {
    _searchTimer?.cancel();
    final q = normalizeDmSearchQuery(text);
    final seq = ++_searchSeq;
    if (q == null) {
      setState(() {
        _searchQuery = null;
        _searchHits = const [];
        _searching = false;
        _searchFailed = false;
      });
      return;
    }
    setState(() {
      _searchQuery = q;
      _searching = true;
      _searchFailed = false;
    });
    _searchTimer = Timer(kMessagesSearchDebounce, () => _runSearch(q, seq));
  }

  Future<void> _runSearch(String q, int seq) async {
    final userId = widget.api.userId;
    try {
      final hits = await widget.api.searchDms(q);
      if (!mounted || seq != _searchSeq || widget.api.userId != userId) return;
      setState(() {
        _searchHits = hits;
        _searchFailed = false;
        _searching = false;
      });
    } catch (e) {
      debugPrint('messages search failed: ${safeErrorLabel(e)}');
      if (!mounted || seq != _searchSeq) return;
      setState(() {
        _searchFailed = true;
        _searching = false;
      });
    }
  }

  void _clearSearch() {
    _searchTimer?.cancel();
    _searchSeq++;
    _search.clear();
    _searchQuery = null;
    _searchHits = const [];
    _searching = false;
    _searchFailed = false;
  }

  /// Opens the conversation a hit belongs to, through its inbox row when the
  /// list holds one so the thread gets the viewer's state with it.
  Future<void> _openHit(DmSearchHit hit) async {
    setState(_clearSearch);
    FocusScope.of(context).unfocus();
    for (final t in _threads) {
      if (t.conversationId == hit.conversationId) return _open(t);
    }
    final partnerId = hit.partnerId;
    await Navigator.of(context).push(
      MaterialPageRoute<bool>(
        builder: (_) => partnerId == null
            ? MessageThreadScreen.deletedPartner(
                api: widget.api,
                deletedPartnerKey: hit.deletedPartnerKey!,
                pollInterval: widget.threadPollInterval,
                conversationId: hit.conversationId,
              )
            : MessageThreadScreen(
                api: widget.api,
                partnerId: partnerId,
                partnerName: hit.partnerName,
                pollInterval: widget.threadPollInterval,
                conversationId: hit.conversationId,
              ),
      ),
    );
    if (mounted) _refresh();
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _search.dispose();
    _poll?.cancel();
    DmPendingHides.instance.removeListener(_onPendingHidesChanged);
    _hideReader.close();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  int _seenHideOutcomes = DmPendingHides.instance.outcomes;

  /// A conversation deleted in a thread leaves the list while its undo window
  /// is open and comes back on Undo. Once the delete lands, the list it holds
  /// still leaves it out until a read started after that replaces it; the
  /// read is the server's answer either way. The delete itself needs no read:
  /// the list already holds the row it leaves out.
  void _onPendingHidesChanged() {
    if (!mounted) return;
    setState(() {});
    final outcomes = DmPendingHides.instance.outcomes;
    if (outcomes == _seenHideOutcomes) return;
    _seenHideOutcomes = outcomes;
    _readGen++;
    _refresh();
  }

  void _hold(List<DmThread> rows, Duration startedAt) {
    _threads = _applyOpened(rows, startedAt);
    _threadsReadAt = startedAt;
    _hideReader.applied(startedAt);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  List<DmThread> _applyOpened(List<DmThread> rows, Duration startedAt) => [
        for (final t in rows)
          (_openedAt[t.threadKey] ?? Duration.zero) > startedAt
              ? t.copyWith(unread: 0)
              : t,
      ];

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    final gen = _readGen;
    final userId = widget.api.userId;
    final startedAt = monotonicNow();
    try {
      final rows = await widget.api.fetchDmThreads();
      if (!mounted || widget.api.userId != userId) return;
      if (gen != _readGen) {
        unawaited(_load());
        return;
      }
      setState(() {
        _hold(rows, startedAt);
        _loading = false;
      });
    } catch (e) {
      if (!mounted || widget.api.userId != userId) return;
      if (gen != _readGen) return _load();
      setState(() {
        _loadError = e;
        _loading = false;
      });
    }
  }

  /// A poll keeps the list it has on a failure: the next tick is the retry.
  Future<void> _refresh() async {
    if (_loading || _pollGen == _readGen) return;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    final userId = widget.api.userId;
    if (userId == null) return;
    if (_loadError != null) return _load();
    final gen = _readGen;
    _pollGen = gen;
    final startedAt = monotonicNow();
    try {
      final rows = await widget.api.fetchDmThreads();
      if (mounted && gen == _readGen && widget.api.userId == userId) {
        setState(() => _hold(rows, startedAt));
      }
    } catch (e) {
      debugPrint('messages inbox poll failed: $e');
    } finally {
      if (_pollGen == gen) _pollGen = null;
    }
    await _refreshCoachPreview();
  }

  Future<void> _open(DmThread t) async {
    final partnerId = t.partnerId;
    final markedUnread = await Navigator.of(context).push(
      MaterialPageRoute<bool>(
        builder: (_) => partnerId == null
            ? MessageThreadScreen.deletedPartner(
                api: widget.api,
                deletedPartnerKey: t.deletedPartnerKey!,
                pollInterval: widget.threadPollInterval,
                conversationId: t.conversationId,
                initialMuted: t.muted,
                initialArchived: t.archived,
                initialMarkedUnread: t.markedUnread,
              )
            : MessageThreadScreen(
                api: widget.api,
                partnerId: partnerId,
                partnerName: t.partnerName,
                partnerAvatarUrl: t.partnerAvatarUrl,
                pollInterval: widget.threadPollInterval,
                conversationId: t.conversationId,
                initialMuted: t.muted,
                initialArchived: t.archived,
                initialMarkedUnread: t.markedUnread,
                initialRequest: t.request,
              ),
      ),
    );
    if (!mounted) return;
    if (markedUnread == true) {
      // The conversation was left marked unread: no read since may zero it,
      // and one already in flight predates the mark, so it is dropped.
      _openedAt.remove(t.threadKey);
      _readGen++;
      setState(() {
        _threads = [
          for (final x in _threads)
            x.threadKey == t.threadKey
                ? x.copyWith(
                    unread: x.unread < 1 ? 1 : x.unread, markedUnread: true)
                : x,
        ];
      });
      _refresh();
      return;
    }
    _openedAt[t.threadKey] = monotonicNow();
    setState(() {
      _threads = [
        for (final x in _threads)
          x.threadKey == t.threadKey
              ? x.copyWith(unread: 0, markedUnread: false)
              : x,
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
    final subList = (_showingRequests && _threads.any((t) => t.request)) ||
        (_showingArchived && _threads.any((t) => t.archived && !t.request));
    if (subList) return _listBody(l10n);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Semantics(
            label: l10n.messagesSearchLabel,
            child: TextField(
              key: const ValueKey('inbox-search'),
              controller: _search,
              onChanged: _onSearchChanged,
              maxLength: kDmSearchMaxChars,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: l10n.messagesSearchPlaceholder,
                counterText: '',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        key: const ValueKey('inbox-search-clear'),
                        tooltip: l10n.commonClearSearch,
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(_clearSearch),
                      ),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
        ),
        Expanded(
          child: _searchQuery != null ? _searchBody(l10n) : _listBody(l10n),
        ),
      ],
    );
  }

  Widget _searchBody(AppLocalizations l10n) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    Widget note(String key, String text) => Padding(
          key: ValueKey(key),
          padding: const EdgeInsets.all(16),
          child: Text(text, style: muted),
        );
    if (_searchFailed) {
      return note('inbox-search-error', l10n.messagesSearchFailed);
    }
    if (_searchHits.isEmpty) {
      return _searching
          ? ListSkeleton(label: l10n.commonLoading, rows: 3)
          : note('inbox-search-empty', l10n.messagesSearchEmpty);
    }
    final tag = localeToTag(Localizations.localeOf(context));
    final query = _searchQuery ?? '';
    final emphasis = TextStyle(
      fontWeight: FontWeight.w700,
      backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.18),
    );
    // The own-message prefix is a whole sentence per locale, so it is split
    // around a marker rather than assumed to come first.
    final prefixed = l10n.messagesYouPrefixed('\u0000').split('\u0000');
    return ListView.separated(
      key: const ValueKey('inbox-search-results'),
      itemCount: _searchHits.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final hit = _searchHits[i];
        final snip = dmSearchSnippet(hit.body, query);
        final name = hit.partnerId == null
            ? l10n.messagesDeletedAccount
            : hit.partnerName ?? l10n.profileRunnerFallback;
        return ListTile(
          key: ValueKey('inbox-search-hit-${hit.id}'),
          title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text.rich(
            TextSpan(children: [
              if (hit.fromMe) TextSpan(text: prefixed.first),
              TextSpan(text: snip.before),
              TextSpan(text: snip.match, style: emphasis),
              TextSpan(text: snip.after),
              if (hit.fromMe && prefixed.length > 1)
                TextSpan(text: prefixed.last),
            ]),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Text(
            _stamp(hit.createdAt, tag),
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          onTap: () => _openHit(hit),
        );
      },
    );
  }

  Widget _listBody(AppLocalizations l10n) {
    if (_loading && _threads.isEmpty) {
      return ListSkeleton(label: l10n.commonLoading);
    }
    final coach = _coach;
    final hides = DmPendingHides.instance;
    final readAt = _threadsReadAt;
    // Archived conversations sit in their own list until a newer message
    // arrives (dm_threads() decides that), and message requests the runner
    // has not answered sit in Requests. The Coach row belongs to the inbox.
    final split = partitionArchived<DmThread>(
      [
        for (final t in _threads)
          if (readAt == null || !hides.hides(t.conversationId, readAt)) t,
      ],
      archived: (t) => t.archived,
      request: (t) => t.request,
    );
    final showingRequests = _showingRequests && split.requests.isNotEmpty;
    final showingArchived =
        !showingRequests && _showingArchived && split.archived.isNotEmpty;
    final entries = showingRequests
        ? [for (final t in split.requests) DmInboxEntry<DmThread>(t)]
        : showingArchived
        ? [for (final t in split.archived) DmInboxEntry<DmThread>(t)]
        : inboxEntries<DmThread>(
            split.inbox,
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
    if (entries.isEmpty && split.archived.isEmpty && split.requests.isEmpty) {
      return EmptyState(
        icon: Icons.chat_bubble_outline,
        title: l10n.messagesEmptyTitle,
        body: l10n.messagesEmptyBody,
      );
    }
    final tag = localeToTag(Localizations.localeOf(context));
    // With the Coach as the only row, the empty-inbox guidance still says how
    // a conversation with a person starts.
    final Widget? header = showingArchived || showingRequests
        ? ListTile(
            key: const ValueKey('inbox-back-to-inbox'),
            leading: const Icon(Icons.arrow_back),
            title: Text(l10n.messagesBackToInbox),
            onTap: () => setState(() {
              _showingArchived = false;
              _showingRequests = false;
            }),
          )
        : null;
    final Widget? requestsLink = !showingArchived &&
            !showingRequests &&
            split.requests.isNotEmpty
        ? ListTile(
            key: const ValueKey('inbox-show-requests'),
            leading: const Icon(Icons.person_add_alt),
            title: Text(l10n.messagesRequestsCount(split.requests.length)),
            onTap: () => setState(() => _showingRequests = true),
          )
        : null;
    final Widget? archivedLink = !showingArchived &&
            !showingRequests &&
            split.archived.isNotEmpty
        ? ListTile(
            key: const ValueKey('inbox-show-archived'),
            leading: const Icon(Icons.archive_outlined),
            title: Text(l10n.messagesArchivedCount(split.archived.length)),
            onTap: () => setState(() => _showingArchived = true),
          )
        : null;
    final footer = split.inbox.isEmpty && !showingArchived && !showingRequests
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
        itemCount: (header == null ? 0 : 1) +
            entries.length +
            (footer == null ? 0 : 1) +
            (requestsLink == null ? 0 : 1) +
            (archivedLink == null ? 0 : 1),
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, i) {
          if (header != null) {
            if (i == 0) return header;
            i -= 1;
          }
          if (i < entries.length) {
            return switch (entries[i]) {
              CoachInboxEntry() => _coachRow(l10n, coach!),
              DmInboxEntry(:final thread) => _row(l10n, thread, tag),
            };
          }
          i -= entries.length;
          if (footer != null) {
            if (i == 0) return footer;
            i -= 1;
          }
          if (requestsLink != null) {
            if (i == 0) return requestsLink;
            i -= 1;
          }
          return archivedLink!;
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
    final preview = t.lastUnsent
        ? l10n.messagesUnsentPlaceholder
        : t.lastBody ??
            (t.lastImage
                ? l10n.messagesPhotoPreview
                : l10n.messagesUnsentPlaceholder);
    return ListTile(
      key: ValueKey('dm-thread-${t.threadKey}'),
      leading: IdentityAvatar(
        seed: t.threadKey,
        name: t.partnerName,
        imageUrl: t.partnerAvatarUrl,
        size: 40,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  unread ? const TextStyle(fontWeight: FontWeight.w700) : null,
            ),
          ),
          if (t.muted) ...[
            const SizedBox(width: 6),
            Semantics(
              key: ValueKey('dm-muted-${t.threadKey}'),
              label: l10n.messagesMutedMark,
              excludeSemantics: true,
              child: Icon(
                Icons.notifications_off_outlined,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
      subtitle: _previewLine(
        t,
        t.lastFromMe ? l10n.messagesYouPrefixed(preview) : preview,
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
                foreground: t.muted
                    ? theme.colorScheme.onSecondaryContainer
                    : theme.colorScheme.onPrimary,
                fill: t.muted
                    ? theme.colorScheme.secondaryContainer
                    : theme.colorScheme.primary,
                size: StatusPillSize.compact,
              ),
            ),
          ],
        ],
      ),
      onTap: () => _open(t),
    );
  }

  /// The preview under a conversation. A shared AI Coach answer carries the
  /// AI tag before it, as it does in the thread (EU AI Act Art. 50).
  static Widget _previewLine(DmThread t, String text) {
    final line = Text(text, maxLines: 1, overflow: TextOverflow.ellipsis);
    if (t.lastKind != 'coach_share' || t.lastUnsent) return line;
    return Row(
      key: ValueKey('dm-coach-share-preview-${t.threadKey}'),
      children: [
        const AiTag(),
        const SizedBox(width: 6),
        Flexible(child: line),
      ],
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

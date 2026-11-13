import '../widgets/grisnir_moments.dart';
import '../activity_type_labels.dart';
import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart'
    show
        ActiveFilter,
        AppInsets,
        AppSpace,
        AsyncView,
        ChoiceChipOption,
        EmptyState,
        FilterBar,
        HubTabBody,
        IdentityAvatar,
        LoadingState,
        buildChoiceChip,
        showFilterSheet;

import '../adaptive_width.dart';
import '../auth_error.dart';
import '../badges.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../preferences.dart';
import '../social_service.dart';
import '../social_surface_requests.dart';
import '../widgets/badge_grid.dart';
import '../widgets/error_state.dart';
import '../widgets/run_track_preview.dart';
import '../widgets/sign_in_required_state.dart';
import 'people_screen.dart';
import 'profile_screen.dart';
import 'public_run_screen.dart';
import '../widgets/top_banner.dart';

/// Activity feed of public runs from people you follow, capped to the
/// last 14 days. Mirrors the web `/feed` route (decisions §31).
///
/// The Social hub's Feed tab: a ui_kit `HubTabBody`, so in the hub it draws
/// no app bar and pushed on its own it gets a small titled one (issue #1374).
/// The activity kinds are the quick chips; who the activity is from is in the
/// Filters sheet and shows as a removable chip while it narrows the feed.
class FeedScreen extends StatefulWidget {
  final ApiClient api;
  const FeedScreen({super.key, required this.api});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  static const _activities = <_ActivityOption>[
    _ActivityOption('all', Icons.apps),
    _ActivityOption('run', Icons.directions_run),
    _ActivityOption('walk', Icons.directions_walk),
    _ActivityOption('cycle', Icons.directions_bike),
    _ActivityOption('hike', Icons.terrain),
    _ActivityOption('lift', Icons.fitness_center),
  ];

  String _activityLabel(AppLocalizations l10n, String value) {
    switch (value) {
      case 'run':
      case 'walk':
      case 'cycle':
      case 'hike':
        return activityTypeLabelFor(l10n, value);
      case 'lift':
        return l10n.feedActivityLift;
      default:
        return l10n.feedActivityAll;
    }
  }

  bool _loading = true;
  bool _loadingMore = false;
  bool _exhausted = false;
  Object? _loadError;

  List<ActivityFeedEntry> _entries = const [];
  Map<String, EngagementSummary> _engagement = const {};
  List<UserProfileRow> _followees = const [];
  List<BadgeAwardEntry> _badgeAwards = const [];

  String _authorFilter = 'all';
  String _activityFilter = 'all';

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  // Recent badge awards from people you follow — an auxiliary feed adornment
  // (L4). A failure here must never blank the core feed, so it loads on its
  // own and degrades to no strip.
  Future<void> _loadBadgeAwards() async {
    try {
      final awards = await widget.api.fetchFollowingBadgeAwards(limit: 6);
      if (!mounted) return;
      setState(() => _badgeAwards = awards);
    } catch (_) {
      if (!mounted) return;
      setState(() => _badgeAwards = const []);
    }
  }

  // Engagement (kudos / comments) only exists for runs. Lift cards carry no
  // engagement footer.
  static List<String> _runIds(List<ActivityFeedEntry> es) =>
      es.whereType<RunFeedEntry>().map((e) => e.run.id).toList();

  /// Reads the first page. Rows already on screen stay while it runs (a pull
  /// to refresh), and stay when it fails, with a banner saying so: a failed
  /// read never blanks a feed that had loaded.
  Future<void> _loadInitial() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    _loadBadgeAwards();

    // The activity feed is the one fetch that must succeed — a failure
    // here is a genuine can't-show-a-feed error. The author filter
    // (fetchFollowing) and the per-run kudos/comment footers
    // (fetchEngagementSummaries) are adornments on the feed; isolating
    // them means one of those failing can't blank the whole feed the way
    // a single shared try/catch over all three did (issue #506).
    final List<ActivityFeedEntry> entries;
    try {
      entries = await widget.api.fetchFollowingActivityFeed(
        limit: 20,
        authorId: _authorFilter == 'all' ? null : _authorFilter,
        activityType: _activityFilter,
      );
    } catch (e) {
      debugPrint('feed load failed: $e');
      if (!mounted) return;
      final hadRows = _entries.isNotEmpty;
      setState(() {
        _loadError = e;
        _loading = false;
      });
      if (hadRows) {
        showTopBanner(context, AppLocalizations.of(context).feedLoadError);
      }
      return;
    }

    final followees = await _loadFollowees();
    final engagement = await _loadEngagement(_runIds(entries));
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _followees = followees;
      _engagement = engagement;
      _exhausted = entries.length < 20;
      _loading = false;
    });
  }

  // Following list — drives the author filter. Capped at 200 to keep the
  // payload small. A failure here degrades to no author filter (the
  // previously-loaded list is kept), never blanks the feed.
  Future<List<UserProfileRow>> _loadFollowees() async {
    if (widget.api.userId == null) return const [];
    try {
      return (await widget.api.fetchFollowing(widget.api.userId!, limit: 200))
          .rows;
    } catch (e) {
      debugPrint('feed followees load failed: $e');
      return _followees;
    }
  }

  // Per-run kudos / comment counts. Runs only (lift cards carry no
  // engagement footer). A failure degrades to no counts, never blanks
  // the feed.
  Future<Map<String, EngagementSummary>> _loadEngagement(
      List<String> runIds) async {
    if (runIds.isEmpty) return const {};
    try {
      final engagement = await widget.api.fetchEngagementSummaries(runIds);
      return {
        for (final id in engagement.keys)
          id: EngagementSummary(
            kudosCount: engagement[id]!.kudosCount,
            viewerHasKudos: engagement[id]!.viewerHasKudos,
            commentCount: engagement[id]!.commentCount,
          ),
      };
    } catch (e) {
      debugPrint('feed engagement load failed: $e');
      return const {};
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _exhausted || _entries.isEmpty) return;
    setState(() => _loadingMore = true);
    try {
      final last = _entries.last;
      final more = await widget.api.fetchFollowingActivityFeed(
        limit: 20,
        cursor: (startedAt: last.startedAt, id: last.id),
        authorId: _authorFilter == 'all' ? null : _authorFilter,
        activityType: _activityFilter,
      );
      final moreEng = await _loadEngagement(_runIds(more));
      if (!mounted) return;
      setState(() {
        _entries = [..._entries, ...more];
        _engagement = {..._engagement, ...moreEng};
        _exhausted = more.length < 20;
        _loadingMore = false;
      });
    } catch (e) {
      debugPrint('feed load more failed: $e');
      if (!mounted) return;
      setState(() => _loadingMore = false);
      showTopBanner(
          context, AppLocalizations.of(context).feedLoadMoreFailed(friendlyError(AppLocalizations.of(context), e)));
    }
  }

  /// A new filter is a different feed: the rows for the old one go, so the
  /// loading frame shows rather than the old filter's rows.
  void _refilter(VoidCallback change) {
    setState(() {
      change();
      _entries = const [];
      _engagement = const {};
    });
    _loadInitial();
  }

  void _setActivity(String value) {
    if (value == _activityFilter) return;
    _refilter(() => _activityFilter = value);
  }

  void _setAuthor(String value) {
    if (value == _authorFilter) return;
    _refilter(() => _authorFilter = value);
  }

  String _authorName(AppLocalizations l10n, String id) {
    for (final f in _followees) {
      if (f.id == id) return f.displayName ?? l10n.feedRunnerFallback;
    }
    return l10n.feedRunnerFallback;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return HubTabBody(
      title: l10n.feedTitle,
      filters: _followees.isEmpty ? null : _filterBar(l10n),
      banner: _badgeAwards.isEmpty ? null : _buildBadgeStrip(theme),
      onRefresh: _loadInitial,
      body: contentColumn(
        context,
        AsyncView<List<ActivityFeedEntry>>(
          loading: _loading,
          error: _loadError,
          data: _entries,
          isEmpty: (e) => e.isEmpty,
          loadingState: LoadingState.list(label: l10n.commonLoading, rows: 3),
          errorBuilder: (_, _) =>
              AppErrorState(message: l10n.feedLoadError, onRetry: _loadInitial),
          // A signed-out viewer's following feed is empty by definition, and
          // the "follow other runners" copy invites an action they can't
          // take. Only the EMPTY state gates — entries still render signed
          // out when there are any.
          empty: widget.api.userId == null
              ? SignInRequiredState(
                  api: widget.api,
                  message: l10n.feedSignedOutMessage,
                  onSignedIn: _loadInitial,
                )
              : _buildEmpty(l10n),
          builder: (_, entries) => _list(theme, l10n, entries),
        ),
      ),
    );
  }

  Widget _list(
      ThemeData theme, AppLocalizations l10n, List<ActivityFeedEntry> entries) {
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.pixels >= n.metrics.maxScrollExtent - 200 &&
            !_loadingMore &&
            !_exhausted) {
          _loadMore();
        }
        return false;
      },
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(AppInsets.gutter, AppSpace.sm,
            AppInsets.gutter, AppSpace.md + MediaQuery.paddingOf(context).bottom),
        // The window caption leads the list, so it scrolls away with it.
        itemCount: 1 + entries.length + (_exhausted ? 0 : 1),
        separatorBuilder: (_, i) =>
            SizedBox(height: i == 0 ? AppSpace.xs : AppSpace.sm),
        itemBuilder: (_, index) {
          if (index == 0) {
            return Text(
              l10n.feedLast14Days,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            );
          }
          final i = index - 1;
          if (i >= entries.length) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.smPlus),
                child: _loadingMore
                    ? const CircularProgressIndicator()
                    : TextButton(
                        onPressed: _loadMore,
                        child: Text(l10n.feedLoadMore),
                      ),
              ),
            );
          }
          final entry = entries[i];
          void openAuthor() => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ProfileScreen(
                    api: widget.api,
                    userId: entry.author.id,
                  ),
                ),
              );
          if (entry is LiftFeedEntry) {
            return _LiftEntryCard(
              key: ValueKey(entry.id),
              entry: entry,
              onAuthorTap: openAuthor,
            );
          }
          final run = entry as RunFeedEntry;
          return _EntryCard(
            key: ValueKey(run.run.id),
            api: widget.api,
            entry: FeedEntry(run: run.run, author: run.author),
            initialEngagement: _engagement[run.run.id],
            onAuthorTap: openAuthor,
            onCardTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PublicRunScreen(
                  api: widget.api,
                  runId: run.run.id,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBadgeStrip(ThemeData theme) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppInsets.gutter, AppSpace.sm, AppInsets.gutter, 0),
      // A scrolling Row rather than a horizontal ListView in a fixed-height
      // box: the strip is capped at six awards, and a literal lane height
      // squeezed the chips out of their 48 dp tap target at 1.0x and cropped
      // their labels outright at 2x OS text scale.
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final (i, a) in _badgeAwards.indexed) ...[
              if (i > 0) const SizedBox(width: AppSpace.sm),
              _badgeChip(l10n, a),
            ],
          ],
        ),
      ),
    );
  }

  Widget _badgeChip(AppLocalizations l10n, BadgeAwardEntry a) {
    final name = a.authorName ?? l10n.badgesARunner;
    final label = badgeLabelFor(l10n, a.badge.badgeKey, a.badge.tier);
    return ActionChip(
      avatar: Icon(
        badgeIconData(
            tierFor(a.badge.badgeKey, a.badge.tier)?.icon ?? 'military_tech'),
        size: 18,
        color: badgeTierColor(a.badge.tier),
      ),
      label: Text(
        l10n.badgesFeedEarned(name, label),
        overflow: TextOverflow.ellipsis,
      ),
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => ProfileScreen(api: widget.api, userId: a.authorId),
        ),
      ),
    );
  }

  /// The activity kinds as the quick chips (a SegmentedButton can't fit six
  /// icon+label segments on a phone), and who the activity is from in the
  /// Filters sheet, shown as a removable chip while it is on.
  FilterBar _filterBar(AppLocalizations l10n) {
    final author = _authorFilter == 'all'
        ? null
        : _authorName(l10n, _authorFilter);
    final active = [
      if (author != null)
        ActiveFilter(
          label: author,
          onRemove: () => _setAuthor('all'),
          removeTooltip: l10n.filterBarRemoveFilter(author),
        ),
    ];
    return FilterBar(
      key: const ValueKey('feed-filter-bar'),
      chips: [
        for (final a in _activities)
          buildChoiceChip<String>(
            context,
            ChoiceChipOption(
              value: a.value,
              label: _activityLabel(l10n, a.value),
              icon: a.icon,
            ),
            _activityFilter,
            _setActivity,
          ),
      ],
      activeFilters: active,
      filtersLabel: l10n.filterBarFilters,
      filtersSemanticLabel:
          active.isEmpty ? null : l10n.filterBarFiltersCount(active.length),
      activeFilterCount: active.length,
      onOpenFilters: _openFilters,
    );
  }

  Future<void> _openFilters() {
    final l10n = AppLocalizations.of(context);
    return showFilterSheet(
      context: context,
      title: l10n.filterBarFilters,
      doneLabel: l10n.filterBarDone,
      builder: (sheetContext, setSheet) {
        final theme = Theme.of(sheetContext);
        Widget choice(String value, String label) => ChoiceChip(
              label: Text(label),
              selected: _authorFilter == value,
              onSelected: (_) {
                _setAuthor(value);
                setSheet(() {});
              },
            );
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.feedFilterAuthor, style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpace.sm),
            Semantics(
              container: true,
              label: l10n.feedFilterAuthor,
              child: Wrap(
                spacing: AppSpace.sm,
                children: [
                  choice('all', l10n.feedEveryoneYouFollow),
                  for (final f in _followees)
                    choice(f.id, f.displayName ?? l10n.feedRunnerFallback),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEmpty(AppLocalizations l10n) {
    final hasFollows = _followees.isNotEmpty;
    final filtered = _activityFilter != 'all' || _authorFilter != 'all';
    return EmptyState(
      icon: Icons.groups_outlined,
      illustration: hasFollows ? null : grisnirWaitingOrNull(),
      title: !hasFollows
          ? l10n.feedEmptyTitle
          : filtered
              ? l10n.feedNoMatchesTitle
              : l10n.feedNoActivityTitle,
      body: !hasFollows
          ? l10n.feedEmptyBody
          : filtered
              ? l10n.feedNoMatchesBody
              : l10n.feedNoActivityBody,
      ctaLabel: filtered ? l10n.feedClearFilters : l10n.feedFindPeople,
      ctaIcon: filtered ? Icons.filter_alt_off : Icons.person_search,
      onCta: filtered
          ? () => _refilter(() {
                _authorFilter = 'all';
                _activityFilter = 'all';
              })
          : () => openSocialSurface(
                context,
                SocialTab.people,
                fallback: () => PeopleScreen(api: widget.api),
              ),
    );
  }
}

class _ActivityOption {
  final String value;
  final IconData icon;
  const _ActivityOption(this.value, this.icon);
}

class _EntryCard extends StatelessWidget {
  final ApiClient api;
  final FeedEntry entry;
  final EngagementSummary? initialEngagement;
  final VoidCallback onAuthorTap;
  final VoidCallback onCardTap;

  const _EntryCard({
    super.key,
    required this.api,
    required this.entry,
    required this.initialEngagement,
    required this.onAuthorTap,
    required this.onCardTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header — author row
          InkWell(
            onTap: onAuthorTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Row(
                children: [
                  IdentityAvatar(
                    seed: entry.author.id,
                    name: entry.author.displayName,
                    size: 32,
                    imageUrl: entry.author.avatarUrl,
                  ),
                  const SizedBox(width: 10),
                  // The time sits under the name rather than beside it: at
                  // 2x text on a 320 dp phone the two side by side ran 71 dp
                  // past the card (issue #1374).
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.author.displayName ??
                              AppLocalizations.of(context).feedRunnerFallback,
                          style: theme.textTheme.titleSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          fmtRelative(entry.run.startedAt,
                              localeToTag(Localizations.localeOf(context))),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          // Track thumbnail — banner-style preview of the run shape so
          // the card's most distinctive signal sits above the fold.
          // The thumbnail opens the run, as the stats row below does; the
          // stats row is the one a screen reader stops on, named by what it
          // reads, so this one is not a second unnamed "button" (#1374
          // A11Y-12).
          if (entry.run.trackUrl != null && entry.run.trackUrl!.isNotEmpty)
            ExcludeSemantics(
              key: const Key('feedCardTrackThumb'),
              child: InkWell(
                onTap: onCardTap,
                child: Container(
                  height: 120,
                  color: theme.colorScheme.surfaceContainerHighest,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: RunTrackPreview(
                    runId: entry.run.id,
                    trackUrl: entry.run.trackUrl,
                    api: api,
                    ownerUserId: entry.author.id,
                  ),
                ),
              ),
            ),
          if (entry.run.trackUrl != null && entry.run.trackUrl!.isNotEmpty)
            const Divider(height: 1),
          // Stats — distance / time / pace; tap opens PublicRunScreen.
          InkWell(
            onTap: onCardTap,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              // Expanded, not spaceAround: an intrinsically-sized cell has no
              // bound for its FittedBox to scale against, so a long value
              // overflowed the card instead of shrinking.
              child: Row(
                children: [
                  Expanded(
                    child: _Stat(
                      label: AppLocalizations.of(context).runStatDistance,
                      value: formatDistanceForPref(entry.run.distanceM),
                    ),
                  ),
                  Expanded(
                    child: _Stat(
                      label: AppLocalizations.of(context).runStatTime,
                      value:
                          _fmtDuration(Duration(seconds: entry.run.durationS)),
                    ),
                  ),
                  Expanded(
                    child: _Stat(
                      label: AppLocalizations.of(context).runStatPace,
                      value: _fmtPace(entry.run.distanceM, entry.run.durationS),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          // Kudos / comment chips. Stateful so toggling kudos rebuilds
          // only this footer instead of the parent FeedScreen and every
          // other visible card.
          _EngagementFooter(
            api: api,
            runId: entry.run.id,
            initialEngagement: initialEngagement,
            onCommentTap: onAuthorTap,
          ),
        ],
      ),
    );
  }

  static String _fmtDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m ${s}s';
  }

  static String _fmtPace(double metres, int durationS) {
    if (metres <= 0 || durationS <= 0) return '—';
    return formatPaceForPref(durationS / (metres / 1000));
  }

}

class _EngagementFooter extends StatefulWidget {
  final ApiClient api;
  final String runId;
  final EngagementSummary? initialEngagement;
  final VoidCallback? onCommentTap;

  const _EngagementFooter({
    required this.api,
    required this.runId,
    required this.initialEngagement,
    this.onCommentTap,
  });

  @override
  State<_EngagementFooter> createState() => _EngagementFooterState();
}

class _EngagementFooterState extends State<_EngagementFooter> {
  static const _empty = EngagementSummary(
    kudosCount: 0,
    viewerHasKudos: false,
    commentCount: 0,
  );

  late EngagementSummary _eng;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _eng = widget.initialEngagement ?? _empty;
  }

  @override
  void didUpdateWidget(_EngagementFooter old) {
    super.didUpdateWidget(old);
    // Pick up a fresher engagement value pushed by the parent (e.g. when
    // the feed reloads) — but only if the user hasn't toggled locally
    // since, in which case our optimistic state is the truth.
    final fresh = widget.initialEngagement;
    if (!_busy && fresh != null && fresh != old.initialEngagement) {
      _eng = fresh;
    }
  }

  Future<void> _toggle() async {
    if (_busy) return;
    final prev = _eng;
    setState(() {
      _busy = true;
      _eng = EngagementSummary(
        kudosCount: prev.viewerHasKudos
            ? (prev.kudosCount - 1).clamp(0, 1 << 30)
            : prev.kudosCount + 1,
        viewerHasKudos: !prev.viewerHasKudos,
        commentCount: prev.commentCount,
      );
    });
    try {
      final changed = prev.viewerHasKudos
          ? await widget.api.rescindKudos(widget.runId)
          : await widget.api.giveKudos(widget.runId);
      // A no-op (the server already matched the new state — kudos given
      // / removed from another tab against a stale local flag) means the
      // optimistic +/-1 was wrong: the flag is right but the count drifted.
      // Undo the count delta while keeping the corrected flag.
      if (!changed && mounted) {
        setState(() => _eng = EngagementSummary(
              kudosCount: prev.kudosCount,
              viewerHasKudos: !prev.viewerHasKudos,
              commentCount: prev.commentCount,
            ));
      }
    } catch (e) {
      debugPrint('feed kudos update failed: $e');
      if (!mounted) return;
      setState(() => _eng = prev);
      showTopBanner(
          context, AppLocalizations.of(context).feedKudosUpdateFailed(friendlyError(AppLocalizations.of(context), e)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: _eng.viewerHasKudos
                ? AppLocalizations.of(context).kudosRemoveLabel
                : AppLocalizations.of(context).kudosGiveLabel,
            child: TextButton.icon(
              onPressed: _busy ? null : _toggle,
              icon: Icon(
                _eng.viewerHasKudos
                    ? Icons.favorite
                    : Icons.favorite_border,
                color: _eng.viewerHasKudos
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
                size: 18,
              ),
              label: Text(
                '${_eng.kudosCount}',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ),
          Semantics(
            button: true,
            label: AppLocalizations.of(context).kudosViewCommentsLabel,
            child: TextButton.icon(
              onPressed: widget.onCommentTap,
              icon: Icon(
                Icons.chat_bubble_outline,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              label: Text(
                '${_eng.commentCount}',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A public gym workout rendered as a "lift card" — title + set count +
/// total volume, distinct from a run card. Mirrors web's lift-card branch
/// in SocialFeed. No kudos / comments footer (engagement is run-only).
class _LiftEntryCard extends StatelessWidget {
  final LiftFeedEntry entry;
  final VoidCallback onAuthorTap;

  const _LiftEntryCard({
    super.key,
    required this.entry,
    required this.onAuthorTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final title = entry.title?.trim();
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onAuthorTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Row(
                children: [
                  IdentityAvatar(
                    seed: entry.author.id,
                    name: entry.author.displayName,
                    size: 32,
                    imageUrl: entry.author.avatarUrl,
                  ),
                  const SizedBox(width: 10),
                  // Stacked for the same reason as the run card's header.
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.author.displayName ?? l10n.feedRunnerFallback,
                          style: theme.textTheme.titleSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          fmtRelative(entry.startedAt,
                              localeToTag(Localizations.localeOf(context))),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.fitness_center,
                        size: 18, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        (title == null || title.isEmpty)
                            ? l10n.feedLiftUntitled
                            : title,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _Stat(
                      label: l10n.feedLiftSetsLabel,
                      value: '${entry.setCount}',
                    ),
                    if (entry.volumeKg > 0) ...[
                      const SizedBox(width: 32),
                      _Stat(
                        label: l10n.feedLiftVolume,
                        value: WeightFormat.format(
                            entry.volumeKg, activeWeightUnit),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // An ultra's value ("104:32:11", "386.24") is far wider than a 5K's,
        // so scale it down to the cell rather than overflow the card.
        // Mirrors _StatBig on run_detail_screen.
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
        ),
        const SizedBox(height: 2),
        Text(
          label.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            letterSpacing: 0.6,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}


import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart'
    show AppInsets, AppSearchField, AppSpace, AsyncView, EmptyState, FilterBar, HubTabBody, ListCard, LoadingState, PrimaryAction, SectionHeader;

import '../catalogue_browse.dart' show fold;
import '../challenge_list.dart';
import '../fab_clearance.dart';
import '../l10n/gen/app_localizations.dart';
import '../social_service.dart';
import '../widgets/challenge_form_sheet.dart';
import '../widgets/challenge_progress_bar.dart';
import '../widgets/error_state.dart';
import '../widgets/official_badge.dart';
import '../widgets/top_banner.dart';
import 'challenge_detail_screen.dart';

/// The Social hub's Challenges tab: the challenges the runner joined, with
/// their progress, and the public ones to join. A ui_kit `HubTabBody`, so in
/// the hub "Create challenge" is the hub's FAB and pushed on its own it gets
/// a small titled app bar and the FAB itself (issue #1374).
class ChallengesScreen extends StatefulWidget {
  final SocialService social;
  const ChallengesScreen({super.key, required this.social});

  @override
  State<ChallengesScreen> createState() => _ChallengesScreenState();
}

class _ChallengesScreenState extends State<ChallengesScreen> {
  List<ChallengeView>? _all;
  bool _failed = false;

  /// Stamped when the list lands so every row grades its window against one
  /// instant, instead of each rebuild sampling a slightly different clock.
  DateTime _loadedAt = DateTime.now();

  /// Narrows both sections by title, over the challenges already loaded.
  final _searchCtl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  bool _matches(ChallengeView c) {
    final q = fold(_query.trim());
    return q.isEmpty || fold(c.title).contains(q);
  }

  void _clearSearch() => setState(() {
        _searchCtl.clear();
        _query = '';
      });

  /// The list can grow (every public challenge plus the runner's own), so
  /// the tab has a search like the other Social tabs (issue #1374).
  FilterBar _filterBar(AppLocalizations l10n) => FilterBar(
        key: const ValueKey('challenges-filter-bar'),
        search: AppSearchField(
          controller: _searchCtl,
          hint: l10n.challengesSearchHint,
          clearTooltip: l10n.commonClearSearch,
          onChanged: (v) => setState(() => _query = v),
        ),
      );

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await widget.social.fetchChallenges();
      if (!mounted) return;
      setState(() {
        _all = rows;
        _failed = false;
        _loadedAt = DateTime.now();
      });
    } catch (_) {
      if (!mounted) return;
      // A failed reload keeps the list on screen and says so; only a list
      // that never loaded is replaced by the error state.
      final hadRows = _all?.isNotEmpty ?? false;
      setState(() {
        _all ??= const [];
        _failed = true;
      });
      if (hadRows) {
        showTopBanner(
            context, AppLocalizations.of(context).challengesLoadFailed);
      }
    }
  }

  Future<void> _open(ChallengeView c) => _openById(c.id);

  Future<void> _openById(String id) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChallengeDetailScreen(social: widget.social, challengeId: id),
    ));
    if (!mounted) return;
    _load();
  }

  Future<void> _create() async {
    final id = await showChallengeFormSheet(context, social: widget.social);
    if (id == null || !mounted) return;
    await _openById(id);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final create = PrimaryAction(
      label: l10n.challengesCreate,
      icon: Icons.add,
      onPressed: _create,
    );
    final listed = _all?.where((c) => c.joined || c.isPublic).toList();
    return HubTabBody(
      title: l10n.challengesTitle,
      primary: create,
      filters: (listed?.isNotEmpty ?? false) ? _filterBar(l10n) : null,
      onRefresh: _load,
      body: AsyncView<List<ChallengeView>>(
        loading: _all == null,
        error: _failed ? l10n.challengesLoadFailed : null,
        data: _all,
        isEmpty: (all) => !all.any((c) => c.joined || c.isPublic),
        loadingState: LoadingState.list(label: l10n.commonLoading),
        errorBuilder: (_, _) =>
            AppErrorState(message: l10n.challengesLoadFailed, onRetry: _load),
        empty: EmptyState(
          icon: Icons.emoji_events_outlined,
          title: l10n.challengesEmpty,
          body: l10n.challengesBrowseEmpty,
          ctaLabel: create.label,
          onCta: _create,
        ),
        builder: (context, all) {
          final shown = all.where(_matches);
          if (!shown.any((c) => c.joined || c.isPublic)) {
            return EmptyState(
              key: const ValueKey('challenges-no-match'),
              icon: Icons.search_off,
              title: l10n.challengesNoMatch,
              ctaLabel: l10n.commonClearSearch,
              ctaIcon: Icons.clear,
              onCta: _clearSearch,
            );
          }
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(AppInsets.gutter, AppSpace.smPlus,
                AppInsets.gutter, fabScrollClearance(context)),
            children: [
              _section(
                context,
                l10n.challengesMyChallenges,
                shown.where((c) => c.joined).toList(),
                l10n.challengesEmpty,
                showProgress: true,
              ),
              const SizedBox(height: AppInsets.sectionGap),
              _section(
                context,
                l10n.challengesBrowse,
                shown.where((c) => !c.joined && c.isPublic).toList(),
                l10n.challengesBrowseEmpty,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _section(BuildContext context, String title, List<ChallengeView> rows, String emptyMsg,
      {bool showProgress = false}) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(label: title),
        const SizedBox(height: AppSpace.sm),
        if (rows.isEmpty)
          // One section of two is empty while the other has rows, so this
          // is a line under its heading, not a whole-surface empty state.
          Text(
            emptyMsg,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          )
        else
          ...rows.map((c) => ListCard.row(
                title: c.title,
                badge: c.isOfficial ? const OfficialBadge() : null,
                subtitle:
                    '${challengeMetricLabel(l10n, c.metric)} · ${l10n.challengesParticipants(c.participantCount)}',
                meta: showProgress ? _progress(context, c) : null,
                chevron: true,
                onTap: () => _open(c),
              )),
      ],
    );
  }

  /// A joined row's own progress. The value is whatever
  /// `my_active_challenges` reported; a challenge outside that RPC's
  /// live-plus-7-day window has no value at all, and says so — drawing an empty
  /// bar there would state a zero nobody measured.
  Widget _progress(BuildContext context, ChallengeView c) {
    final l10n = AppLocalizations.of(context);
    final hint = TextStyle(color: Theme.of(context).hintColor);
    final progress = myProgressView(
      myValue: c.myValue,
      startsAt: c.startsAt,
      now: _loadedAt,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (progress.state == MyProgressState.unknown)
          Text(l10n.challengesProgressUnavailable, style: hint)
        else
          ChallengeProgressBar(
            metric: c.metric,
            value: progress.value,
            goal: c.goalValue,
            startsAt: c.startsAt,
            endsAt: c.endsAt,
          ),
        if (c.myRank != null || c.completedAt != null) ...[
          const SizedBox(height: AppSpace.sm),
          Wrap(
            spacing: AppSpace.smPlus,
            children: [
              if (c.myRank != null)
                Text(l10n.challengesLeaderboardRank(c.myRank!),
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w600)),
              if (c.completedAt != null)
                Text(l10n.challengesBadgeEarned,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.primary)),
            ],
          ),
        ],
      ],
    );
  }
}

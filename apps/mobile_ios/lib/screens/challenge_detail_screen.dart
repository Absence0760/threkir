import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

import '../challenge_list.dart';
import '../l10n/gen/app_localizations.dart';
import '../leaderboard_standing.dart';
import '../social_service.dart';
import '../widgets/challenge_invite_card.dart';
import '../widgets/challenge_progress_bar.dart';
import '../widgets/confirm_destructive.dart';
import '../widgets/error_state.dart';
import '../widgets/official_badge.dart';
import '../widgets/sign_in_required_state.dart';
import '../widgets/top_banner.dart';
import '../widgets/loading_skeletons.dart';

class ChallengeDetailScreen extends StatefulWidget {
  final SocialService social;
  final String challengeId;

  /// The creator's `ref` the share link that opened this carried; a join
  /// made here is attributed to it (decisions § 2268).
  final String? shareRef;
  const ChallengeDetailScreen(
      {super.key, required this.social, required this.challengeId, this.shareRef});

  @override
  State<ChallengeDetailScreen> createState() => _ChallengeDetailScreenState();
}

class _ChallengeDetailScreenState extends State<ChallengeDetailScreen> {
  ChallengeView? _challenge;
  List<ChallengeLeaderboardEntry> _board = const [];
  Map<String, String> _clubNames = const {};
  bool _loaded = false;
  bool _notFound = false;
  bool _loadError = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final c = await widget.social.fetchChallengeById(widget.challengeId);
      if (c == null) {
        if (!mounted) return;
        setState(() {
          _notFound = true;
          _loadError = false;
          _loaded = true;
        });
        return;
      }
      final byTeam = c.scope == 'club_vs_club';
      final board = await widget.social
          .fetchChallengeLeaderboard(widget.challengeId, byTeam: byTeam);
      var clubNames = const <String, String>{};
      if (byTeam) {
        final clubs = await widget.social.fetchMyClubs();
        clubNames = {for (final cl in clubs) cl.row.id: cl.row.name};
      }
      if (!mounted) return;
      setState(() {
        _challenge = c;
        _board = board;
        _clubNames = clubNames;
        _loaded = true;
        _notFound = false;
        _loadError = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadError = true;
        _notFound = false;
        _loaded = true;
      });
    }
  }

  Future<void> _join() async {
    if (_busy) return;
    if (!await ensureSignedIn(context,
        viewerId: widget.social.currentUserId, onSignedIn: _load)) {
      return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      await widget.social.joinChallenge(widget.challengeId);
      await widget.social.attributeChallengeJoin(widget.challengeId, widget.shareRef);
      await _load();
    } catch (_) {
      if (mounted) showTopBanner(context, AppLocalizations.of(context).challengesJoinFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leave() async {
    final l10n = AppLocalizations.of(context);
    final ok = await confirmDestructive(
      context,
      title: l10n.challengesLeaveConfirmTitle,
      body: l10n.challengesLeaveConfirm,
      confirmLabel: l10n.challengesLeave,
      cancelLabel: l10n.checkpointCancel,
    );
    if (!ok || _busy) return;
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      await widget.social.leaveChallenge(widget.challengeId);
      await _load();
    } catch (_) {
      if (mounted) showTopBanner(context, l10n.challengesLeaveFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final l10n = AppLocalizations.of(context);
    final ok = await confirmDestructive(
      context,
      title: l10n.challengesDeleteConfirmTitle,
      body: l10n.challengesDeleteConfirm,
      confirmLabel: l10n.challengesDelete,
      cancelLabel: l10n.checkpointCancel,
    );
    if (!ok) return;
    try {
      await widget.social.deleteChallenge(widget.challengeId);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) showTopBanner(context, l10n.challengesDeleteFailed);
    }
  }

  String _windowLabel(AppLocalizations l10n, ChallengeView c) {
    final now = DateTime.now();
    if (now.isAfter(c.endsAt)) return l10n.challengesEnded;
    // Whole days left, rounded up as web's challenge_labels does: under a
    // day is "today", 25 hours is 2 days.
    final minutes = c.endsAt.difference(now).inMinutes;
    return l10n.challengesEndsIn(minutes <= 0 ? 1 : (minutes / 1440).ceil());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = _challenge;
    final isCreator = c != null && c.creatorId != null && c.creatorId == widget.social.currentUserId;
    return DetailPage(
      title: c?.title ?? l10n.challengesTitle,
      moreTooltip: l10n.commonMore,
      actions: [
        if (isCreator)
          AppBarAction(
            icon: const Icon(Icons.delete_outline),
            label: l10n.challengesDeleteChallenge,
            onPressed: _delete,
            destructive: true,
          ),
      ],
      body: !_loaded
          ? SectionedDetailSkeleton(
              label: l10n.commonLoading,
              statCells: 2,
              hasAction: true,
              rows: 5,
              hasLeading: true,
            )
          : _loadError
              ? AppErrorState(message: l10n.challengesLoadFailed, onRetry: _load)
              : _notFound || c == null
              ? EmptyState(
                  icon: Icons.emoji_events,
                  title: l10n.challengesNotFound,
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    DetailHero(
                      title: c.title,
                      padding: const EdgeInsets.only(top: 16),
                      badges: [
                        if (c.isOfficial) const OfficialBadge(size: 16),
                      ],
                      meta: [
                        DetailMeta(
                          icon: Icons.schedule,
                          text: _windowLabel(l10n, c),
                        ),
                      ],
                      description: (c.description ?? '').isNotEmpty
                          ? Text(c.description!)
                          : null,
                      children: [
                        if (c.metric == 'park_courses' &&
                            c.parkRegionCode != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            l10n.challengesParkRegion(c.parkRegionCode!),
                            key: const Key('challenge-park-region'),
                          ),
                        ],
                        if (c.joined && c.scope != 'club_vs_club') ...[
                          const SizedBox(height: 16),
                          _progress(context, c),
                        ],
                      ],
                      cta: c.joined
                          ? HeroCta(
                              label: l10n.challengesLeave,
                              outlined: true,
                              onPressed: _leave,
                              busy: _busy,
                            )
                          : HeroCta(
                              label: l10n.challengesJoin,
                              onPressed: _join,
                              busy: _busy,
                            ),
                    ),
                    const SizedBox(height: 24),
                    SectionHeader.title(label: l10n.challengesLeaderboard),
                    const SizedBox(height: 8),
                    _leaderboard(context, c),
                    const SizedBox(height: 16),
                    ChallengeInviteCard(
                      social: widget.social,
                      challengeId: c.id,
                      isPublic: c.isPublic,
                      canManage: isCreator && c.scope != 'club_vs_club',
                      isCreator: isCreator,
                    ),
                  ],
                ),
    );
  }

  /// The caller's own value comes off the board the page already holds — the
  /// `challenges` read carries no per-caller value, so without this the bar
  /// stated a confident zero for everyone (web reads it the same way).
  Widget _progress(BuildContext context, ChallengeView c) {
    final l10n = AppLocalizations.of(context);
    final me = widget.social.currentUserId;
    ChallengeLeaderboardEntry? myRow;
    for (final e in _board) {
      if (me != null && e.userId == me) {
        myRow = e;
        break;
      }
    }
    final value = myRow?.value ?? c.myValue ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ChallengeProgressBar(
          metric: c.metric,
          value: value,
          goal: c.goalValue,
          startsAt: c.startsAt,
          endsAt: c.endsAt,
        ),
        if (c.completedAt != null) ...[
          const SizedBox(height: 8),
          Text(l10n.challengesBadgeEarned,
              style: TextStyle(color: Theme.of(context).colorScheme.primary)),
        ],
      ],
    );
  }

  String _entrantName(ChallengeLeaderboardEntry e, bool byTeam) {
    if (!byTeam) return e.displayName ?? '—';
    final l10n = AppLocalizations.of(context);
    final label = teamLabel(e.teamClubId, _clubNames);
    return switch (label.kind) {
      TeamLabelKind.named => label.name!,
      TeamLabelKind.noClub => l10n.challengesTeamNoClub,
      TeamLabelKind.unresolved => l10n.challengesTeamPrivateClub,
    };
  }

  Widget _standing(BuildContext context, ChallengeView c, bool byTeam) {
    if (_board.length < 2) return const SizedBox.shrink();
    final s = standingFor(
      _board,
      byTeam ? c.myTeamClubId : widget.social.currentUserId,
    );
    if (s == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final lines = <Widget>[
      Text(byTeam ? l10n.challengesStandingTitleTeam : l10n.challengesStandingTitle,
          style: const TextStyle(fontWeight: FontWeight.w700)),
      Text(l10n.challengesStandingRank(s.rank, s.total),
          style: TextStyle(fontWeight: FontWeight.w700, color: scheme.onPrimaryContainer)),
      if (s.tiedWith > 0)
        Text(
          l10n.challengesStandingTied(s.tiedWith),
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
      if (s.chasing != null)
        Text(
          l10n.challengesStandingBehind(
            challengeValueLabel(l10n, c.metric, s.chasing!.delta),
            _entrantName(s.chasing!.entry, byTeam),
          ),
          style: TextStyle(color: scheme.onSurfaceVariant),
        )
      else if (s.tiedWith == 0)
        Text(l10n.challengesStandingLeading,
            style: TextStyle(color: scheme.tertiary, fontWeight: FontWeight.w600)),
      if (s.chasedBy != null)
        Text(
          l10n.challengesStandingAhead(
            challengeValueLabel(l10n, c.metric, s.chasedBy!.delta),
            _entrantName(s.chasedBy!.entry, byTeam),
          ),
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
    ];
    return Container(
      key: const Key('challenge-standing'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Wrap(spacing: 12, runSpacing: 4, children: lines),
    );
  }

  Widget _leaderboard(BuildContext context, ChallengeView c) {
    final l10n = AppLocalizations.of(context);
    if (_board.isEmpty) {
      return Text(l10n.challengesLeaderboardEmpty, style: TextStyle(color: Theme.of(context).hintColor));
    }
    final byTeam = c.scope == 'club_vs_club';
    final meId = widget.social.currentUserId;
    return Column(
      children: [
        _standing(context, c, byTeam),
        ..._board.map((e) {
          final me = !byTeam && meId != null && e.userId == meId;
          final name = _entrantName(e, byTeam);
          return Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: me
                  ? Theme.of(context).colorScheme.primaryContainer
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                TextLane(
                  width: 36,
                  child: Text(l10n.challengesLeaderboardRank(e.rank),
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                Expanded(child: Text(name, overflow: TextOverflow.ellipsis)),
                Text(challengeValueLabel(l10n, c.metric, e.value),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
          );
        }),
      ],
    );
  }
}

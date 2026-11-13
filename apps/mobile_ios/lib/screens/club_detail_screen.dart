import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:core_models/core_models.dart' as cm;
import 'package:core_models/core_models.dart' hide Route;

import 'package:api_client/api_client.dart';

import '../club_role_labels.dart';
import '../column_limits.dart';
import '../auth_error.dart';
import '../l10n/date_format.dart';
import '../l10n/gen/app_localizations.dart';
import '../race_service.dart';
import '../l10n/locale_support.dart';
import '../local_gym_store.dart';
import '../local_route_store.dart';
import '../local_routine_store.dart';
import '../plan_overlap.dart';
import '../preferences.dart';
import '../runner_handle.dart';
import '../settings_destination.dart';
import '../social_service.dart';
import '../training.dart' show toIsoDate;
import '../training_service.dart';
import '../backend_timeout.dart';
import '../widgets/activity_waiver_dialog.dart';
import '../widgets/club_form_sheet.dart';
import '../widgets/club_invite_card.dart';
import '../widgets/club_verification_status_card.dart';
import '../widgets/club_photos.dart';
import '../widgets/official_badge.dart';
import '../widgets/collapsing_tab_host.dart';
import '../widgets/confirm_destructive.dart';
import '../widgets/error_state.dart';
import '../widgets/event_form_sheet.dart';
import '../widgets/plan_overlap_dialog.dart';
import '../widgets/report_sheet.dart';
import '../widgets/route_track_preview.dart';
import '../widgets/verified_badge.dart';
import 'event_detail_screen.dart';
import 'plan_detail_screen.dart';
import 'profile_screen.dart';
import 'routine_detail_screen.dart';
import 'session_detail_screen.dart';
import 'public_route_screen.dart';
import 'route_builder_screen.dart';
import '../widgets/sign_in_required_state.dart';
import '../widgets/stale_refresh_banner.dart';
import '../widgets/top_banner.dart';
import '../widgets/loading_skeletons.dart';

class ClubDetailScreen extends StatefulWidget {
  final SocialService social;
  final TrainingService training;
  /// Optional — when both are supplied, the Routes tab grows an admin-
  /// only "Build route" CTA that pushes `RouteBuilderScreen` pre-bound
  /// to this club. Mirrors web's `/routes/new?club=<id>` deep link.
  /// Old callers (e.g. `ClubInviteScreen`) can omit them; the CTA
  /// simply doesn't render in that case.
  final ApiClient? apiClient;
  final LocalRouteStore? routeStore;
  final String slug;
  const ClubDetailScreen({
    super.key,
    required this.social,
    required this.training,
    this.apiClient,
    this.routeStore,
    required this.slug,
  });

  @override
  State<ClubDetailScreen> createState() => _ClubDetailScreenState();
}

class _ClubDetailScreenState extends State<ClubDetailScreen>
    with SingleTickerProviderStateMixin {
  ClubView? _club;
  List<EventView> _upcoming = const [];
  List<ClubPostView> _posts = const [];
  List<ClubMemberView> _pending = const [];
  final Set<String> _pendingBusy = {};
  List<ClubMemberView> _members = const [];
  /// Whether the signed-in member has no display name, so the Members tab
  /// can tell them how others see them (decisions § 2365).
  bool _viewerUnnamed = false;
  List<Object?>? _membersNext;
  bool _membersLoading = true;
  bool _membersLoadingMore = false;
  bool _membersFailed = false;
  final Set<String> _memberBusy = {};
  final Set<String> _replyBusy = {};
  List<TrainingPlanRow> _templates = const [];
  List<SessionPlanRow> _sessionTemplates = const [];
  String? _adoptingSessionId;
  String? _adoptingPlanId;
  List<GymRoutineRow> _gymRoutineTemplates = const [];
  Set<String> _officialGymRoutineIds = const {};
  String? _adoptingRoutineId;
  List<cm.Route> _routes = const [];
  bool _loading = true;
  bool _busy = false;
  bool _templatesLoaded = false;
  bool _routesLoaded = false;
  // A failed read is an error with Retry, never the empty state, and leaves
  // the tab unloaded so the next visit tries again (issue #1374 FS-3).
  Object? _templatesError;
  Object? _routesError;
  String? _error;
  bool _timedOut = false;
  late final TabController _tabs;
  final _postCtrl = TextEditingController();
  final Map<String, List<ClubPostView>> _threads = {};
  final Map<String, TextEditingController> _replyCtrls = {};

  RealtimeChannel? _channel;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 6, vsync: this);
    _tabs.addListener(_onTabChanged);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _timedOut = false;
    });
    try {
      final club = await widget.social
          .fetchClubBySlug(widget.slug)
          .timeout(kBackendLoadTimeout);
      if (club == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final results = await Future.wait<dynamic>([
        widget.social.fetchUpcomingEvents(club.row.id),
        widget.social.fetchClubPosts(club.row.id),
        // Pending requests only meaningful when the viewer is admin.
        // RLS will return [] for non-admins; keep the call simple.
        club.isAdmin
            ? widget.social.fetchPendingRequests(club.row.id)
            : Future.value(const <ClubMemberView>[]),
      ]).timeout(kBackendLoadTimeout);
      if (!mounted) return;
      setState(() {
        _club = club;
        _upcoming = results[0] as List<EventView>;
        _posts = results[1] as List<ClubPostView>;
        _pending = results[2] as List<ClubMemberView>;
        _loading = false;
      });
      unawaited(_loadMembers());
      if (club.isMember) unawaited(_checkViewerName());
      if (_channel == null) {
        _channel = widget.social.subscribeToClub(club.row.id, _onRealtimeChange);
      }
    } on TimeoutException catch (e) {
      debugPrint('ClubDetailScreen._load timed out: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _timedOut = true;
        });
      }
    } catch (e, s) {
      debugPrint('ClubDetailScreen._load failed: $e\n$s');
      if (mounted) {
        setState(() {
          _error = friendlyError(AppLocalizations.of(context), e);
          _loading = false;
        });
      }
    }
  }

  /// The roster's first page. Its own load and its own failure, so a roster
  /// read that fails leaves the rest of the club readable.
  Future<void> _loadMembers() async {
    final c = _club;
    if (c == null) return;
    setState(() {
      _membersLoading = true;
      _membersFailed = false;
    });
    try {
      final page = await widget.social
          .fetchClubMembers(c.row.id)
          .timeout(kBackendLoadTimeout);
      if (!mounted) return;
      setState(() {
        _members = page.rows;
        _membersNext = page.next;
        _membersLoading = false;
      });
    } catch (e) {
      debugPrint('ClubDetailScreen._loadMembers failed: $e');
      if (mounted) {
        setState(() {
          _membersLoading = false;
          _membersFailed = true;
        });
      }
    }
  }

  Future<void> _loadMoreMembers() async {
    final c = _club;
    final after = _membersNext;
    if (c == null || after == null || _membersLoadingMore) return;
    setState(() => _membersLoadingMore = true);
    try {
      final page = await widget.social
          .fetchClubMembers(c.row.id, after: after)
          .timeout(kBackendLoadTimeout);
      if (!mounted) return;
      setState(() {
        _members = appendPage(_members, page.rows, (m) => m.userId);
        _membersNext = page.next;
      });
    } catch (e) {
      debugPrint('ClubDetailScreen._loadMoreMembers failed: $e');
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        showTopBanner(context, l10n.clubDetailMembersLoadFailed);
      }
    } finally {
      if (mounted) setState(() => _membersLoadingMore = false);
    }
  }

  Future<void> _changeRole(ClubMemberView m, String role) async {
    final c = _club;
    if (c == null || role == m.role || _memberBusy.contains(m.userId)) return;
    setState(() => _memberBusy.add(m.userId));
    try {
      await widget.social.setMemberRole(
        clubId: c.row.id,
        userId: m.userId,
        role: role,
      );
      if (mounted) {
        setState(() => _members = [
              for (final x in _members)
                x.userId == m.userId ? x.withRole(role) : x,
            ]);
      }
    } catch (e) {
      debugPrint('club detail role change failed: $e');
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      showTopBanner(
          context, l10n.clubDetailRoleChangeFailed(friendlyError(l10n, e)));
    } finally {
      if (mounted) setState(() => _memberBusy.remove(m.userId));
    }
  }

  Future<void> _removeMember(ClubMemberView m) async {
    final c = _club;
    if (c == null || _memberBusy.contains(m.userId)) return;
    final l10n = AppLocalizations.of(context);
    final ok = await confirmDestructive(
      context,
      title: l10n.clubDetailRemoveMemberTitle,
      body: l10n.clubDetailRemoveMemberBody(
        _shownName(l10n, m.displayName, m.userId),
        c.row.name,
      ),
      confirmLabel: l10n.clubDetailRemoveMemberConfirm,
    );
    if (!ok || !mounted || _memberBusy.contains(m.userId)) return;
    setState(() => _memberBusy.add(m.userId));
    try {
      await widget.social.removeMember(clubId: c.row.id, userId: m.userId);
      if (mounted) {
        setState(() =>
            _members = _members.where((x) => x.userId != m.userId).toList());
      }
    } catch (e) {
      debugPrint('club detail remove member failed: $e');
      if (!mounted) return;
      showTopBanner(
          context, l10n.clubDetailRemoveMemberFailed(friendlyError(l10n, e)));
    } finally {
      if (mounted) setState(() => _memberBusy.remove(m.userId));
    }
  }

  void _openMemberProfile(String userId) {
    final api = widget.apiClient;
    if (api == null) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ProfileScreen(api: api, userId: userId),
    ));
  }

  Future<void> _join() async {
    final c = _club;
    if (c == null || _busy) return;
    if (!await ensureSignedIn(context,
        viewerId: widget.apiClient?.userId,
        api: widget.apiClient,
        onSignedIn: _load)) {
      return;
    }
    if (!mounted) return;
    final needsWaiver = c.row.requiresActivityWaiver;
    if (needsWaiver && !await confirmActivityWaiver(context)) return;
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      final status = await widget.social.joinClub(
        c.row.id,
        c.joinPolicy,
        ackWaiver: needsWaiver,
      );
      if (status == 'pending' && mounted) {
        showTopBanner(
            context, AppLocalizations.of(context).clubDetailRequestSent);
      }
      await _load();
    } catch (e) {
      debugPrint('ClubDetailScreen._join failed: $e');
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        showTopBanner(
          context,
          friendlyError(l10n, e),
          duration: const Duration(seconds: 6),
          actionLabel: l10n.errorStateRetry,
          onAction: _join,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leave() async {
    final c = _club;
    if (c == null || _busy) return;
    final l10n = AppLocalizations.of(context);
    final ok = await confirmDestructive(
      context,
      title: l10n.clubDetailLeaveTitle(c.row.name),
      confirmLabel: l10n.clubDetailLeave,
      cancelLabel: l10n.clubDetailCancel,
    );
    if (!ok) return;
    await _doLeave();
  }

  Future<void> _doLeave() async {
    final c = _club;
    if (c == null || _busy) return;
    setState(() => _busy = true);
    try {
      await widget.social.leaveClub(c.row.id);
      await _load();
    } catch (e) {
      debugPrint('ClubDetailScreen._leave failed: $e');
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        showTopBanner(
          context,
          friendlyError(l10n, e),
          duration: const Duration(seconds: 6),
          actionLabel: l10n.errorStateRetry,
          onAction: _doLeave,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitPost() async {
    final c = _club;
    if (c == null || _busy) return;
    final body = _postCtrl.text.trim();
    if (body.isEmpty) return;
    setState(() => _busy = true);
    try {
      await widget.social.createPost(clubId: c.row.id, body: body);
      _postCtrl.clear();
      await _load();
    } catch (e) {
      debugPrint('ClubDetailScreen._submitPost failed: $e');
      // The controller text survives (cleared only on success), so a
      // retry re-submits exactly what the user typed.
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        showTopBanner(
          context,
          friendlyError(l10n, e),
          duration: const Duration(seconds: 6),
          actionLabel: l10n.errorStateRetry,
          onAction: _submitPost,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleReplies(String postId) async {
    if (_threads[postId] != null) {
      setState(() => _threads.remove(postId));
      return;
    }
    final replies = await widget.social.fetchPostReplies(postId);
    if (!mounted) return;
    setState(() {
      _threads[postId] = replies;
      _replyCtrls.putIfAbsent(postId, () => TextEditingController());
    });
  }

  Future<void> _sendReply(String postId) async {
    final c = _club;
    if (c == null || _replyBusy.contains(postId)) return;
    final ctrl = _replyCtrls[postId];
    final body = ctrl?.text.trim();
    if (body == null || body.isEmpty) return;
    setState(() => _replyBusy.add(postId));
    try {
      await widget.social.createPost(
        clubId: c.row.id,
        parentPostId: postId,
        body: body,
      );
      ctrl?.clear();
      final replies = await widget.social.fetchPostReplies(postId);
      if (!mounted) return;
      setState(() => _threads[postId] = replies);
      _load();
    } catch (e) {
      debugPrint('club detail reply failed: $e');
      // Without this catch, a network error / RLS rejection on
      // reply post would propagate as an uncaught Future error —
      // Flutter logs it to console but the user sees no feedback
      // and the reply text just sits in the box. Surface a banner
      // so the user knows to retry; the controller text stays
      // because the `ctrl?.clear()` above only fires on success.
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      showTopBanner(
        context,
        l10n.clubDetailReplyFailed(friendlyError(l10n, e)),
        duration: const Duration(seconds: 6),
        actionLabel: l10n.errorStateRetry,
        onAction: () => _sendReply(postId),
      );
    } finally {
      if (mounted) setState(() => _replyBusy.remove(postId));
    }
  }

  void _onRealtimeChange() {
    // Coalesce bursts so a multi-row change (e.g. cascading delete) triggers
    // one reload, not several.
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    final channel = _channel;
    if (channel != null) {
      widget.social.unsubscribe(channel);
    }
    _tabs.dispose();
    _postCtrl.dispose();
    for (final c in _replyCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return DetailPage.placeholder(
        child: TabbedDetailSkeleton(
          label: AppLocalizations.of(context).commonLoading,
        ),
      );
    }
    final c = _club;
    if (c == null) {
      return DetailPage.placeholder(
        child: AppErrorState(
          icon: Icons.help_outline,
          message: _timedOut
              ? AppLocalizations.of(context).clubDetailTimeoutError
              : _error ?? AppLocalizations.of(context).clubDetailLoadFailedBody,
          onRetry: _load,
        ),
      );
    }
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return DetailPage(
      title: c.row.name,
      moreTooltip: l10n.commonMore,
      pinned: [
        if (c.isAdmin)
          ClubInviteButton(social: widget.social, club: c)
        else if (canShareClub(c))
          ClubShareButton(club: c),
      ],
      actions: [
        if (c.isAdmin)
          AppBarAction(
            icon: const Icon(Icons.edit_outlined),
            label: l10n.clubDetailEditClub,
            onPressed: () => _openEdit(c),
          ),
        AppBarAction(
          icon: const Icon(Icons.flag_outlined),
          label: l10n.clubDetailReportClub,
          destructive: true,
          onPressed: () => showReportSheet(
            context,
            api: ApiClient(),
            targetKind: 'club',
            targetId: c.row.id,
            organiserClubs: (c.row.isPublic ?? true)
                ? () => RaceService().fetchMyOrganiserClubs()
                : null,
            targetClubId: c.row.id,
          ),
        ),
      ],
      body: CollapsingTabHost(
        controller: _tabs,
        labels: [
          AppLocalizations.of(context).clubDetailTabFeed,
          AppLocalizations.of(context).clubDetailTabEvents,
          AppLocalizations.of(context).clubDetailTabMembers,
          AppLocalizations.of(context).clubDetailTabRoutes,
          AppLocalizations.of(context).clubDetailTabTemplates,
          AppLocalizations.of(context).clubDetailTabPhotos,
        ],
        header: [
          _buildHero(theme, c),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.onErrorContainer),
                ),
              ),
            ),
        ],
        tabs: [
          _buildFeedTab(theme, c),
          _buildEventsTab(theme, c),
          _buildMembersTab(theme, c),
          _buildRoutesTab(theme, c),
          _buildTemplatesTab(theme, c),
          _buildPhotosTab(c),
        ],
      ),
    );
  }

  Widget _buildHero(ThemeData theme, ClubView c) {
    final l10n = AppLocalizations.of(context);
    final description = c.row.description;
    final location = c.row.locationLabel;
    return DetailHero(
      title: c.row.name,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      leading: IdentityAvatar(
          seed: c.row.id, name: c.row.name, size: 56, fontSize: 24),
      // The verified-official badge disambiguates the authentic operator
      // from squatter or fan clubs holding the same name.
      badges: [if (c.row.isVerified) const VerifiedBadge(size: 18)],
      meta: [
        if (location != null && location.isNotEmpty)
          DetailMeta(icon: Icons.place, text: location),
        DetailMeta(
          icon: Icons.groups_outlined,
          text: l10n.clubsMemberCount(c.memberCount),
        ),
      ],
      description: description != null && description.isNotEmpty
          ? _ClubDescription(description: description, clubName: c.row.name)
          : null,
      children: [_clubLinks(context, c)],
      status: _statusFor(theme, l10n, c),
      cta: _ctaFor(l10n, c),
    );
  }

  /// Where the viewer stands when there is nothing for them to press: a
  /// request awaiting approval, an invite-only club, or their own club.
  Widget? _statusFor(ThemeData theme, AppLocalizations l10n, ClubView c) {
    final label = c.viewerStatus == 'pending'
        ? l10n.clubDetailRequestPending
        : !c.isMember && c.joinPolicy == 'invite'
            ? l10n.clubDetailInviteOnly
            : c.isMember && c.viewerRole == 'owner'
                ? l10n.clubDetailOwner
                : null;
    if (label == null) return null;
    return StatusPill(
      key: const Key('club-detail-status'),
      label: label,
      foreground: theme.colorScheme.onSurfaceVariant,
      fill: theme.colorScheme.surfaceContainerHighest,
    );
  }

  /// The viewer's one action on the club: Join or Request, else Leave.
  HeroCta? _ctaFor(AppLocalizations l10n, ClubView c) {
    if (c.viewerStatus == 'pending') return null;
    if (!c.isMember) {
      if (c.joinPolicy == 'invite') return null;
      return HeroCta(
        label: c.joinPolicy == 'request'
            ? l10n.clubDetailRequest
            : l10n.clubDetailJoin,
        onPressed: _join,
        busy: _busy,
      );
    }
    if (c.viewerRole == 'owner') return null;
    return HeroCta(
      label: l10n.clubDetailLeave,
      outlined: true,
      onPressed: _leave,
      busy: _busy,
    );
  }

  Future<void> _openEdit(ClubView c) async {
    final saved = await showClubFormSheet(
      context,
      social: widget.social,
      existing: c.row,
    );
    if (saved != null) await _load();
  }

  Widget _clubLinks(BuildContext context, ClubView c) {
    final l10n = AppLocalizations.of(context);
    final links = <Widget>[];
    void launch(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

    if (c.row.websiteUrl != null && c.row.websiteUrl!.isNotEmpty) {
      links.add(TextButton.icon(
        onPressed: () => launch(c.row.websiteUrl!),
        icon: const Icon(Icons.language, size: 18),
        label: Text(l10n.clubDetailVisitWebsite),
      ));
    }
    void social(String? url, IconData icon, String label) {
      if (url == null || url.isEmpty) return;
      links.add(IconButton(
        tooltip: label,
        icon: Icon(icon, size: 20),
        onPressed: () => launch(url),
      ));
    }

    social(c.row.instagramUrl, Icons.photo_camera, 'Instagram');
    social(c.row.stravaUrl, Icons.directions_run, 'Strava');
    social(c.row.facebookUrl, Icons.thumb_up, 'Facebook');

    if (links.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(spacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: links),
    );
  }

  Widget _buildFeedTab(ThemeData theme, ClubView c) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        children: [
          if (_upcoming.isNotEmpty) _buildNextEventCard(theme, c, _upcoming.first),
          if (c.isMember)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildPostComposer(theme),
            ),
          if (_posts.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                  c.isMember
                      ? AppLocalizations.of(context).clubDetailNoPostsMember
                      : AppLocalizations.of(context).clubDetailNoPosts,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          for (final p in _posts) _buildPostCard(theme, c, p),
        ],
      ),
    );
  }

  Widget _buildNextEventCard(ThemeData theme, ClubView c, EventView e) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => EventDetailScreen(
              social: widget.social,
              clubSlug: c.row.slug,
              eventId: e.row.id,
            ),
          ),
        );
        _load();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.colorScheme.primaryContainer,
              theme.colorScheme.surfaceContainerHighest,
            ],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.dividerColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppLocalizations.of(context).clubDetailNextEvent,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              e.row.title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            // A Wrap: at 2x on a 320 dp phone the date and the count side by
            // side ran 38 dp past the card.
            Wrap(
              spacing: AppSpace.smPlus,
              runSpacing: AppSpace.xxs,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.calendar_today, size: 14,
                        color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        fmtEventDate(e.nextInstanceStart,
                            localeToTag(Localizations.localeOf(context))),
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.group, size: 14,
                        color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        AppLocalizations.of(context)
                            .clubDetailGoingCount(e.attendeeCount),
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPostComposer(ThemeData theme) {
    return ListCard(
      margin: EdgeInsets.zero,
      dense: true,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Column(
        children: [
          TextField(
            controller: _postCtrl,
            maxLines: 3,
            maxLength: columnLength('club_posts.body'),
            decoration: InputDecoration(
              border: InputBorder.none,
              hintText: AppLocalizations.of(context).clubDetailShareUpdateHint,
              counterText: '',
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: _busy ? null : _submitPost,
              child: Text(AppLocalizations.of(context).clubDetailPost),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPostCard(ThemeData theme, ClubView c, ClubPostView p) {
    final l10n = AppLocalizations.of(context);
    final replies = _threads[p.row.id];
    return ListCard(
      dense: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IdentityAvatar(
                  seed: p.row.authorId,
                  name: _shownName(l10n, p.authorName, p.row.authorId),
                  imageUrl: p.authorAvatarUrl,
                  size: 32,
                  fontSize: 14),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _shownName(l10n, p.authorName, p.row.authorId),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      fmtRelative(p.row.createdAt ?? DateTime.now(),
                          localeToTag(Localizations.localeOf(context))),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (Supabase.instance.client.auth.currentUser != null &&
                  Supabase.instance.client.auth.currentUser!.id !=
                      p.row.authorId)
                IconButton(
                  tooltip: l10n.clubDetailReportPost,
                  icon: const Icon(Icons.flag_outlined, size: 18),
                  constraints:
                      const BoxConstraints(minWidth: 48, minHeight: 48),
                  onPressed: () => showReportSheet(
                    context,
                    api: ApiClient(),
                    targetKind: 'club_post',
                    targetId: p.row.id,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(p.row.body, style: theme.textTheme.bodyMedium),
          if (c.isMember) ...[
            const SizedBox(height: 6),
            TextButton.icon(
              onPressed: () => _toggleReplies(p.row.id),
              icon: const Icon(Icons.chat_bubble_outline, size: 16),
              label: Text(
                p.replyCount == 0
                    ? l10n.clubDetailReply
                    : replies != null
                        ? l10n.clubDetailHideReplies(p.replyCount)
                        : l10n.clubDetailShowReplies(p.replyCount),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                minimumSize: const Size(0, 32),
              ),
            ),
            if (replies != null)
              Padding(
                padding: const EdgeInsets.only(left: 8, top: 4),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(color: theme.dividerColor, width: 2),
                    ),
                  ),
                  padding: const EdgeInsets.only(left: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final r in replies)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.clubDetailReplyAuthorLine(
                                    _shownName(l10n, r.authorName, r.row.authorId),
                                    fmtRelative(
                                        r.row.createdAt ?? DateTime.now(),
                                        localeToTag(Localizations.localeOf(context)))),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              Text(r.row.body, style: theme.textTheme.bodyMedium),
                            ],
                          ),
                        ),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _replyCtrls.putIfAbsent(
                                p.row.id, () => TextEditingController()),
                              decoration: InputDecoration(
                                hintText: l10n.clubDetailWriteReplyHint,
                                isDense: true,
                                filled: true,
                                fillColor: theme.colorScheme.surface,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          FilledButton(
                            onPressed: _replyBusy.contains(p.row.id)
                                ? null
                                : () => _sendReply(p.row.id),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(0, 40),
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                            ),
                            child: Text(l10n.clubDetailSend),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _createEvent(ClubView c) async {
    final ok = await showEventFormSheet(
      context,
      social: widget.social,
      clubId: c.row.id,
      clubIsPublic: c.row.isPublic ?? true,
    );
    if (ok == null) return;
    // Anything but 'ok' is the form's message for a follow-up write (the
    // price, the session plan) that failed after the event was created.
    if (ok != 'ok' && mounted) showTopBanner(context, ok);
    _load();
  }

  Widget _buildEventsTab(ThemeData theme, ClubView c) {
    // event_organiser is exactly the role that exists to run events: the
    // server's is_event_organiser RLS admits it and web's canManageEvents
    // matches, so gating on isAdmin locked the role out on mobile only.
    final showCreate = c.isEventOrganiser;
    if (_upcoming.isEmpty) {
      return EmptyState(
        icon: Icons.event,
        title: showCreate
            ? AppLocalizations.of(context).clubDetailNoEventsAdmin
            : AppLocalizations.of(context).clubDetailNoEvents,
        ctaLabel: showCreate
            ? AppLocalizations.of(context).clubDetailCreateEvent
            : null,
        onCta: showCreate ? () => _createEvent(c) : null,
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: _upcoming.length + (showCreate ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (ctx, i) {
          if (showCreate && i == 0) {
            return Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => _createEvent(c),
                icon: const Icon(Icons.add),
                label: Text(AppLocalizations.of(context).clubDetailCreateEvent),
              ),
            );
          }
          final e = _upcoming[showCreate ? i - 1 : i];
          final tag = localeToTag(Localizations.localeOf(context));
          return ListCard.row(
            margin: EdgeInsets.zero,
            dense: true,
            onTap: () async {
              await Navigator.of(ctx).push(
                MaterialPageRoute<void>(
                  builder: (_) => EventDetailScreen(
                    social: widget.social,
                    clubSlug: c.row.slug,
                    eventId: e.row.id,
                  ),
                ),
              );
              _load();
            },
            title: e.row.title,
            badge: e.viewerRsvp == 'going'
                ? StatusPill(
                    label: AppLocalizations.of(context).clubDetailGoing,
                    foreground: theme.colorScheme.onPrimaryContainer,
                    fill: theme.colorScheme.primaryContainer,
                    size: StatusPillSize.compact,
                  )
                : null,
            subtitle: e.row.meetLabel,
            subtitleMaxLines: 1,
            // The date is a lane in the meta line rather than the row's
            // leading: at 2x a leading lane wide enough for "28 de mar."
            // left the title no room, and in a Wrap it drops to its own line.
            meta: Wrap(
              spacing: AppSpace.smPlus,
              runSpacing: AppSpace.xxs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextLane(
                  width: 56,
                  child: Text(
                    formatDateShort(e.nextInstanceStart, tag),
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  formatTime(e.nextInstanceStart, tag),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  AppLocalizations.of(context)
                      .clubDetailGoingCount(e.attendeeCount),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _approve(String userId) async {
    final c = _club;
    if (c == null || _pendingBusy.contains(userId)) return;
    setState(() => _pendingBusy.add(userId));
    try {
      await widget.social.approveJoinRequest(
        clubId: c.row.id,
        userId: userId,
      );
      if (mounted) {
        setState(() => _pending =
            _pending.where((m) => m.userId != userId).toList());
        unawaited(_loadMembers());
      }
    } catch (e) {
      debugPrint('club detail approve failed: $e');
      if (!mounted) return;
      showTopBanner(
          context, AppLocalizations.of(context).clubDetailApproveFailed(friendlyError(AppLocalizations.of(context), e)));
    } finally {
      if (mounted) setState(() => _pendingBusy.remove(userId));
    }
  }

  Future<void> _deny(String userId) async {
    final c = _club;
    if (c == null || _pendingBusy.contains(userId)) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context).clubDetailDenyTitle),
        content: Text(AppLocalizations.of(context).clubDetailDenyMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppLocalizations.of(context).clubDetailCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(AppLocalizations.of(context).clubDetailDeny),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (!mounted || _pendingBusy.contains(userId)) return;
    setState(() => _pendingBusy.add(userId));
    try {
      await widget.social.denyJoinRequest(
        clubId: c.row.id,
        userId: userId,
      );
      if (mounted) {
        setState(() => _pending =
            _pending.where((m) => m.userId != userId).toList());
      }
    } catch (e) {
      debugPrint('club detail deny failed: $e');
      if (!mounted) return;
      showTopBanner(
          context, AppLocalizations.of(context).clubDetailDenyFailed(friendlyError(AppLocalizations.of(context), e)));
    } finally {
      if (mounted) setState(() => _pendingBusy.remove(userId));
    }
  }

  /// L4: a failed profile read only leaves the hint hidden.
  Future<void> _checkViewerName() async {
    final api = widget.apiClient;
    if (api == null) return;
    try {
      final profile = await api.fetchMyProfile();
      if (!mounted) return;
      setState(() => _viewerUnnamed =
          profile != null && namedOrNull(profile.displayName) == null);
    } catch (e) {
      debugPrint('ClubDetailScreen._checkViewerName failed: $e');
    }
  }

  Widget _buildMembersTab(ThemeData theme, ClubView c) {
    final l10n = AppLocalizations.of(context);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          if (c.isMember && _viewerUnnamed) ...[
            ListCard.row(
              key: const Key('club-name-hint'),
              leading: const Icon(Icons.info_outline),
              title: l10n.clubDetailNameHint(
                  _shownName(l10n, null, widget.social.currentUserId ?? '')),
              subtitle: l10n.clubDetailNameHintAction,
              chevron: true,
              onTap: () => openSettings(SettingsDestination.account),
            ),
            const SizedBox(height: 12),
          ],
          if (c.isAdmin) ...[
            ClubVerificationStatusCard(
              social: widget.social,
              clubId: c.row.id,
              isVerified: c.row.isVerified,
            ),
            const SizedBox(height: 12),
          ],
          if (c.isAdmin && _pending.isNotEmpty) ...[
            Text(
              l10n.clubDetailPendingRequests(_pending.length),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            for (final m in _pending)
              ListCard.row(
                dense: true,
                leading: IdentityAvatar(
                  seed: m.userId,
                  name: _shownName(l10n, m.displayName, m.userId),
                  imageUrl: m.avatarUrl,
                  size: 32,
                  fontSize: 14,
                ),
                title: _shownName(l10n, m.displayName, m.userId),
                titleMaxLines: 1,
                actions: [
                  TextButton(
                    onPressed: _pendingBusy.contains(m.userId)
                        ? null
                        : () => _deny(m.userId),
                    child: Text(l10n.clubDetailDeny),
                  ),
                  FilledButton(
                    onPressed: _pendingBusy.contains(m.userId)
                        ? null
                        : () => _approve(m.userId),
                    child: Text(l10n.clubDetailApprove),
                  ),
                ],
              ),
            const SizedBox(height: 24),
          ],
          Text(
            l10n.clubDetailMemberCountLine(c.memberCount),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          ..._rosterBody(theme, l10n, c),
        ],
      ),
    );
  }

  List<Widget> _rosterBody(
      ThemeData theme, AppLocalizations l10n, ClubView c) {
    if (_membersLoading && _members.isEmpty) {
      return [ListSkeleton.section(label: l10n.commonLoading)];
    }
    if (_membersFailed && _members.isEmpty) {
      return [
        AppErrorState(
          message: l10n.clubDetailMembersLoadFailed,
          onRetry: _loadMembers,
        ),
      ];
    }
    if (_members.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            children: [
              Text(l10n.clubDetailMembersEmptyTitle,
                  style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                l10n.clubDetailMembersEmptyBody,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ];
    }
    return [
      for (final m in _members) _memberTile(theme, l10n, c, m),
      if (_membersNext != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Center(
            child: OutlinedButton(
              onPressed: _membersLoadingMore ? null : _loadMoreMembers,
              child: _membersLoadingMore
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l10n.clubDetailMembersLoadMore),
            ),
          ),
        ),
    ];
  }

  Widget _memberTile(
    ThemeData theme,
    AppLocalizations l10n,
    ClubView c,
    ClubMemberView m,
  ) {
    final isOwner = m.role == 'owner' || m.userId == c.row.ownerId;
    // Same rule as web: an admin manages everyone but the owner, and the
    // role menu stands in for the badge on the rows it can change.
    final manageable = c.isAdmin && !isOwner;
    final showBadge = m.role != 'member' && !manageable;
    final busy = _memberBusy.contains(m.userId);
    return ListTile(
      key: ValueKey('club-member-${m.userId}'),
      contentPadding: EdgeInsets.zero,
      onTap: widget.apiClient == null
          ? null
          : () => _openMemberProfile(m.userId),
      leading: IdentityAvatar(
        seed: m.userId,
        name: _shownName(l10n, m.displayName, m.userId),
        imageUrl: m.avatarUrl,
        size: 36,
        fontSize: 15,
      ),
      title: Text(
        _shownName(l10n, m.displayName, m.userId),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: showBadge || manageable
          ? Text(clubRoleLabel(l10n, m.role))
          : null,
      trailing: !manageable
          ? null
          : PopupMenuButton<String>(
              enabled: !busy,
              tooltip: l10n.clubDetailMemberActions,
              icon: const Icon(Icons.more_vert),
              onSelected: (v) {
                if (v == _removeAction) {
                  _removeMember(m);
                } else {
                  _changeRole(m, v);
                }
              },
              itemBuilder: (_) => [
                for (final r in assignableClubRoles)
                  CheckedPopupMenuItem<String>(
                    value: r,
                    checked: r == m.role,
                    child: Text(clubRoleLabel(l10n, r)),
                  ),
                if (m.userId != widget.social.currentUserId) ...[
                  const PopupMenuDivider(),
                  PopupMenuItem<String>(
                    value: _removeAction,
                    child: Text(
                      l10n.clubDetailRemoveFromClub,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  static const _removeAction = '__remove__';

  void _onTabChanged() {
    if (_tabs.indexIsChanging) return;
    if (_tabs.index == 3 && !_routesLoaded) {
      _loadRoutes();
    }
    if (_tabs.index == 4 && !_templatesLoaded) {
      _loadTemplates();
    }
  }

  Future<void> _loadRoutes() async {
    final c = _club;
    if (c == null) return;
    try {
      final list = await widget.social.fetchClubRoutes(c.row.id);
      if (!mounted) return;
      setState(() {
        _routes = list;
        _routesLoaded = true;
        _routesError = null;
      });
    } catch (e) {
      debugPrint('ClubDetail._loadRoutes failed: $e');
      if (!mounted) return;
      if (_routesLoaded) {
        showStaleRefreshBanner(context, e);
      } else {
        setState(() => _routesError = e);
      }
    }
  }

  void _retryRoutes() {
    setState(() => _routesError = null);
    _loadRoutes();
  }

  void _retryTemplates() {
    setState(() => _templatesError = null);
    _loadTemplates();
  }

  Future<void> _buildClubRoute(ClubView c) async {
    // Admin-only entry point. Pushes the route builder with the club
    // pre-bound — `SaveRouteDialog`'s "Save to" picker opens with this
    // club already selected. The user can still flip to Personal in
    // the picker if they change their mind mid-save (matches web's
    // `?club=<id>` deep link, which lets the user pick `null` to
    // unbind).
    final api = widget.apiClient;
    final routeStore = widget.routeStore;
    if (api == null || routeStore == null) return;
    final created = await Navigator.of(context).push<cm.Route>(
      MaterialPageRoute<cm.Route>(
        builder: (_) => RouteBuilderScreen(
          apiClient: api,
          routeStore: routeStore,
          social: widget.social,
          initialClubId: c.row.id,
        ),
      ),
    );
    if (created == null || !mounted) return;
    showTopBanner(
        context, AppLocalizations.of(context).clubDetailRouteSaved(created.name));
    // Reload the club's routes so the new one appears immediately
    // (the realtime channel doesn't subscribe to `routes`).
    await _loadRoutes();
  }

  Future<void> _loadTemplates() async {
    final c = _club;
    if (c == null) return;
    try {
      final list = await widget.training.fetchClubTemplates(c.row.id);
      final sessions = await widget.apiClient?.fetchClubSessionTemplates(c.row.id) ??
          const <SessionPlanRow>[];
      final routines =
          await widget.apiClient?.fetchClubGymRoutineTemplates(c.row.id) ??
              const <GymRoutineRow>[];
      final officialRoutines = await widget.apiClient
              ?.fetchOfficialGymRoutineIds([for (final r in routines) r.id]) ??
          const <String>{};
      if (!mounted) return;
      setState(() {
        _templates = list;
        _sessionTemplates = sessions;
        _gymRoutineTemplates = routines;
        _officialGymRoutineIds = officialRoutines;
        _templatesLoaded = true;
        _templatesError = null;
      });
    } catch (e) {
      debugPrint('ClubDetail._loadTemplates failed: $e');
      if (!mounted) return;
      if (_templatesLoaded) {
        showStaleRefreshBanner(context, e);
      } else {
        setState(() => _templatesError = e);
      }
    }
  }

  Future<void> _adoptGymRoutineTemplate(GymRoutineRow g) async {
    final api = widget.apiClient;
    if (api == null || _adoptingRoutineId != null) return;
    setState(() => _adoptingRoutineId = g.id);
    try {
      final newId = await api.cloneGymRoutineTemplate(g.id);
      if (!mounted) return;
      showTopBanner(
          context, AppLocalizations.of(context).clubDetailGymRoutineAdopted);
      // The clone lands as a personal routine server-side; a throwaway
      // store hydrates the user's routines (including the new one) so the
      // detail screen renders it offline-first, mirroring how the gym
      // screen owns its own LocalRoutineStore.
      final store = LocalRoutineStore();
      await store.init();
      await store.syncWithServer(api);
      final detail = await api.fetchGymRoutineDetail(newId);
      if (detail != null) {
        await store.upsertFromServer(
          detail.routine.toJson(),
          [
            for (final e in detail.exercises)
              StoredRoutineExercise(
                exerciseName: e.exercise.exerciseName,
                exerciseKey: e.exercise.exerciseKey,
                supersetGroup: e.exercise.supersetGroup,
                supersetOrder: e.exercise.supersetOrder,
                modality: e.exercise.modality,
                progression: e.exercise.progression,
                progressionParams: e.exercise.progressionParams is Map
                    ? Map<String, dynamic>.from(
                        e.exercise.progressionParams as Map)
                    : const <String, dynamic>{},
                sets: [
                  for (final s in e.sets)
                    StoredRoutineSet(
                      setType: s.setType,
                      targetRepsMin: s.targetRepsMin,
                      targetRepsMax: s.targetRepsMax,
                      targetWeightKg: s.targetWeightKg,
                      targetRpe: s.targetRpe,
                      restS: s.restS,
                      targetDurationS: s.targetDurationS,
                      targetDistanceM: s.targetDistanceM,
                    ),
                ],
              ),
          ],
        );
      }
      if (!mounted) return;
      final gymStore = LocalGymStore();
      await gymStore.init();
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => RoutineDetailScreen(
            api: api,
            store: store,
            gymStore: gymStore,
            routineId: newId,
          ),
        ),
      );
    } catch (e) {
      debugPrint('club detail adopt failed: $e');
      if (!mounted) return;
      showTopBanner(
          context, AppLocalizations.of(context).clubDetailAdoptFailed(friendlyError(AppLocalizations.of(context), e)));
    } finally {
      if (mounted) setState(() => _adoptingRoutineId = null);
    }
  }

  Future<void> _adoptSessionTemplate(SessionPlanRow s) async {
    final api = widget.apiClient;
    if (api == null || _adoptingSessionId != null) return;
    setState(() => _adoptingSessionId = s.id);
    try {
      final newId = await api.cloneSessionTemplate(s.id);
      if (!mounted) return;
      showTopBanner(context, AppLocalizations.of(context).clubDetailSessionAdopted);
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => SessionDetailScreen(
            api: api,
            planId: newId,
            titleHint: s.title,
          ),
        ),
      );
    } catch (e) {
      debugPrint('club detail adopt failed: $e');
      if (!mounted) return;
      showTopBanner(
          context, AppLocalizations.of(context).clubDetailAdoptFailed(friendlyError(AppLocalizations.of(context), e)));
    } finally {
      if (mounted) setState(() => _adoptingSessionId = null);
    }
  }

  Future<void> _adoptTemplate(TrainingPlanRow t) async {
    if (_adoptingPlanId != null) return;
    final today = DateTime.now();
    final startIso = toIsoDate(today);
    final endIso = clonedPlanEndIso(t, startIso,
        start: planRowStartIso, end: planRowEndIso);
    // Held across the overlap lookup too: it is a network read, and a second
    // tap inside it would otherwise clone the template twice.
    setState(() => _adoptingPlanId = t.id);
    final action = await confirmPlanOverlap(context, widget.training,
        startIso: startIso, endIso: endIso);
    if (!mounted) return;
    if (action == null) {
      setState(() => _adoptingPlanId = null);
      return;
    }
    try {
      final newId = await widget.training
          .clonePlanTemplate(templateId: t.id, startDate: today, onOverlap: action)
          .timeout(kBackendLoadTimeout);
      if (!mounted) return;
      showTopBanner(
          context, AppLocalizations.of(context).clubDetailTemplateAdded);
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => PlanDetailScreen(
            training: widget.training,
            planId: newId,
          ),
        ),
      );
    } catch (e) {
      debugPrint('club detail adopt failed: $e');
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      showTopBanner(
          context,
          planOverlapErrorText(context, e) ??
              l10n.clubDetailAdoptFailed(friendlyError(l10n, e)));
    } finally {
      if (mounted) setState(() => _adoptingPlanId = null);
    }
  }

  Widget _buildRoutesTab(ThemeData theme, ClubView c) {
    // Admin-only CTA — mirrors web's `Routes` tab "New route" + "Transfer
    // from My routes" actions strip on `/clubs/[slug]`. We only render
    // "Build route" today because the mobile transfer flow lives on
    // `route_detail_screen` (per the empty-state copy below); the new
    // CTA covers the create path that the old empty-state pointed
    // users to. Only visible when `apiClient` + `routeStore` were
    // threaded in — the `ClubInviteScreen` redemption path omits both,
    // so the CTA disappears there but the rest of the tab still works.
    final canBuild = c.isAdmin &&
        widget.apiClient != null &&
        widget.routeStore != null;
    return AsyncView<List<cm.Route>>(
      loading: !_routesLoaded && _routesError == null,
      error: _routesError,
      data: _routesLoaded ? _routes : null,
      isEmpty: (r) => r.isEmpty,
      onRefresh: _loadRoutes,
      loadingState: LoadingState.list(
        label: AppLocalizations.of(context).commonLoading,
        rows: 4,
      ),
      errorBuilder: (_, _) => AppErrorState(
        message: AppLocalizations.of(context).clubDetailRoutesLoadFailed,
        onRetry: _retryRoutes,
      ),
      empty: EmptyState(
        icon: Icons.route,
        title: canBuild
            ? AppLocalizations.of(context).clubDetailRoutesEmptyBuild
            : c.isAdmin
                ? AppLocalizations.of(context).clubDetailRoutesEmptyAdmin
                : AppLocalizations.of(context).clubDetailRoutesEmpty,
        ctaLabel:
            canBuild ? AppLocalizations.of(context).clubDetailBuildRoute : null,
        onCta: canBuild ? () => _buildClubRoute(c) : null,
        ctaIcon: Icons.add_road,
      ),
      builder: (_, routes) => ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: routes.length + (canBuild ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, index) {
          if (canBuild && index == 0) {
            return SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('club-detail-build-route'),
                onPressed: () => _buildClubRoute(c),
                icon: const Icon(Icons.add_road),
                label: Text(AppLocalizations.of(context).clubDetailBuildRoute),
              ),
            );
          }
          final i = index - (canBuild ? 1 : 0);
          final r = routes[i];
          return ListCard.row(
                   margin: EdgeInsets.zero,
                   dense: true,
                   leadingWidth: 72,
                   leading: r.waypoints.length >= 2
                       ? SizedBox(
                           width: 72,
                           height: 40,
                           // Club routes are owned by other admins / members.
                           // Non-owner thumbnails route through
                           // clip_route_for_viewer (decisions §33).
                           child: RouteTrackPreview(
                             routeId: r.id,
                             waypoints: r.waypoints,
                             ownerUserId: r.userId,
                             api: ApiClient(),
                           ),
                         )
                       : CircleAvatar(
                           backgroundColor: theme.colorScheme.secondaryContainer,
                           child: Icon(Icons.route, color: theme.colorScheme.secondary),
                         ),
                   title: r.name,
                   subtitle: '${formatDistanceForPref(r.distanceMetres)}'
                       '  •  ${formatElevationForPref(r.elevationGainMetres)} ↑',
                   chevron: true,
                   onTap: () => Navigator.push(
                     context,
                     MaterialPageRoute<void>(
                       builder: (_) => PublicRouteScreen(
                         api: ApiClient(),
                         routeId: r.id,
                       ),
                     ),
                   ),
                 );
        },
      ),
    );
  }

  Widget _buildTemplatesTab(ThemeData theme, ClubView c) {
    final l10n = AppLocalizations.of(context);
    return AsyncView<bool>(
      loading: !_templatesLoaded && _templatesError == null,
      error: _templatesError,
      data: _templatesLoaded ? true : null,
      isEmpty: (_) =>
          _templates.isEmpty &&
          _sessionTemplates.isEmpty &&
          _gymRoutineTemplates.isEmpty,
      onRefresh: _loadTemplates,
      loadingState: LoadingState.list(
        label: l10n.commonLoading,
        rows: 4,
        hasLeading: false,
      ),
      errorBuilder: (_, _) => AppErrorState(
        message: l10n.clubDetailTemplatesLoadFailed,
        onRetry: _retryTemplates,
      ),
      empty: EmptyState(
        icon: Icons.assignment_outlined,
        title: c.isAdmin
            ? l10n.clubDetailNoTemplatesAdmin
            : l10n.clubDetailNoTemplates,
      ),
      builder: (_, _) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          for (final t in _templates) ...[
            ListCard.row(
              dense: true,
              title: t.name,
              subtitle: (t.notes?.isNotEmpty ?? false) ? t.notes : null,
              subtitleMaxLines: 3,
              actions: [
                FilledButton(
                  onPressed: _adoptingPlanId == t.id ? null : () => _adoptTemplate(t),
                  child: Text(l10n.clubDetailAdopt),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          if (_sessionTemplates.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 8),
              child: Text(l10n.clubDetailSessionTemplatesTitle,
                  style: theme.textTheme.titleMedium),
            ),
            for (final s in _sessionTemplates) ...[
              ListCard.row(
                dense: true,
                title: s.title,
                subtitle: (s.discipline?.isNotEmpty ?? false) ? s.discipline : null,
                actions: [
                  FilledButton(
                    onPressed: _adoptingSessionId == s.id
                        ? null
                        : () => _adoptSessionTemplate(s),
                    child: Text(l10n.clubDetailAdopt),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ],
          if (_gymRoutineTemplates.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              child: Text(l10n.clubDetailGymRoutineTemplatesTitle,
                  style: theme.textTheme.titleMedium),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                l10n.clubDetailGymRoutineTemplatesHint,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            for (final g in _gymRoutineTemplates) ...[
              ListCard.row(
                dense: true,
                title: g.title,
                badge: _officialGymRoutineIds.contains(g.id)
                    ? const OfficialBadge()
                    : null,
                subtitle: l10n.clubDetailRoutineExerciseCount(g.exerciseCount),
                actions: [
                  if (c.isMember)
                    FilledButton(
                      onPressed: _adoptingRoutineId == g.id
                          ? null
                          : () => _adoptGymRoutineTemplate(g),
                      child: Text(l10n.clubDetailAdopt),
                    ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildPhotosTab(ClubView c) {
    // The ClubInviteScreen redemption path omits apiClient; the gallery
    // needs a client to fetch / upload, so fall back to a quiet message.
    final api = widget.apiClient;
    if (api == null) {
      return EmptyState(
        icon: Icons.photo_library_outlined,
        title: AppLocalizations.of(context).clubPhotosEmpty,
      );
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        ClubPhotos(
          api: api,
          clubId: c.row.id,
          canUpload: c.isMember,
          canModerate: c.isAdmin,
        ),
      ],
    );
  }
}

/// Lines of club description the hero shows before offering the rest in a
/// sheet.
///
/// The hero scrolls away since § 545, so an over-long description can no longer
/// overflow — but at rest it still takes the tab bodies' height, and at the
/// composer's cap the paragraph measured 440 dp against real Roboto on a 360 dp
/// phone, leaving the six tabs 32 dp (decisions § 537). Clamping the band's one
/// unbounded child is what keeps the tabs on screen without a scroll.
const int kClubDescriptionMaxLines = 3;

/// The hero's club description: clamped to [kClubDescriptionMaxLines] with the
/// whole text one tap away in a scrollable sheet, so the clamp hides nothing.
class _ClubDescription extends StatelessWidget {
  const _ClubDescription({required this.description, required this.clubName});

  final String description;
  final String clubName;

  void _openFull(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => SheetScaffold(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        title: Text(clubName),
        body: Text(description),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final style = theme.textTheme.bodyMedium;
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: description, style: style),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: kClubDescriptionMaxLines,
        )..layout(maxWidth: constraints.maxWidth);
        final clamped = painter.didExceedMaxLines;
        painter.dispose();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              description,
              style: style,
              maxLines: kClubDescriptionMaxLines,
              overflow: TextOverflow.ellipsis,
            ),
            if (clamped)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: () => _openFull(context),
                  child: Text(l10n.clubDetailReadMore),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// A member with no display name is shown as their runner handle rather than
/// an indistinguishable "Member" (decisions § 2365). Twin of the web club
/// pages' `shownName`.
String _shownName(AppLocalizations l10n, String? displayName, String userId) =>
    namedOrNull(displayName) ??
    runnerHandle(
      userId,
      handle: (slug) => l10n.liveRunnerHandle(slug),
      anonymous: l10n.liveRunnerAnonymous,
    );

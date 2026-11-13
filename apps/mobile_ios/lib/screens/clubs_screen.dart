import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart'
    show StravaClub, stravaClubSetup;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:ui_kit/ui_kit.dart';

import '../l10n/gen/app_localizations.dart';
import '../fab_clearance.dart';
import '../local_route_store.dart';
import '../social_service.dart';
import '../strava.dart' show isStravaConfigured;
import '../training_service.dart';
import '../backend_timeout.dart';
import '../widgets/club_form_sheet.dart';
import '../widgets/error_state.dart';
import '../widgets/strava_clubs_section.dart';
import '../widgets/top_banner.dart';
import '../widgets/verified_badge.dart';
import 'club_detail_screen.dart';
import 'club_invite_screen.dart';
import 'help_screen.dart';

/// The Social hub's Clubs tab: browse public clubs and the runner's own
/// memberships. A ui_kit `HubTabBody`, so in the hub it draws no app bar and
/// hands "New club" to the hub's FAB; pushed on its own it gets a small
/// titled app bar and the FAB itself (issue #1374).
class ClubsScreen extends StatefulWidget {
  final SocialService social;
  final TrainingService training;
  /// Optional — when provided alongside [routeStore], threaded into
  /// `ClubDetailScreen` so the Routes tab can host the "Build route"
  /// CTA (admin-only) that opens `RouteBuilderScreen` pre-bound to
  /// the club. Mirrors web's `/routes/new?club=<id>` deep link.
  final ApiClient? apiClient;
  final LocalRouteStore? routeStore;

  /// Whether this build carries a Strava client id. "Your Strava clubs" is
  /// inert without one, as on web (decisions § 1959); tests pass their own.
  final bool Function() stravaConfigured;
  const ClubsScreen({
    super.key,
    required this.social,
    required this.training,
    this.apiClient,
    this.routeStore,
    this.stravaConfigured = isStravaConfigured,
  });

  @override
  State<ClubsScreen> createState() => _ClubsScreenState();
}

class _ClubsScreenState extends State<ClubsScreen> {
  // Default to "My clubs" — returning users want to see the clubs they're
  // already in first. Fresh users with no memberships get an empty state
  // that points them at Browse.
  int _tab = 1; // 0 = Browse, 1 = My clubs
  bool _loading = true;
  _ClubsLoadError? _error;
  List<ClubView> _browse = const [];
  List<ClubView> _mine = const [];
  final _searchCtrl = TextEditingController();

  /// Null when the build has no Strava client id or no api client; then the
  /// section is never built and Strava is never asked.
  StravaClubsController? _strava;

  @override
  void initState() {
    super.initState();
    widget.social.addListener(_onChange);
    _load();
    final api = widget.apiClient;
    if (api != null && widget.stravaConfigured()) {
      _strava = StravaClubsController(api)..load();
    }
  }

  void _onChange() {
    if (mounted) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Region-aware Browse: when the user typed a query, route through
      // `searchClubs` so "Virginia" → ~470 km radius around the bbox
      // centroid expands beyond a raw ILIKE on the location label.
      // Empty queries fall through `searchClubs` → `browseClubs()` for
      // the default ranking.
      final mapTilerKey = dotenv.env['MAPTILER_KEY'] ?? '';
      final term = _searchCtrl.text.trim();
      final browseFut = term.isEmpty
          ? widget.social.browseClubs()
          : widget.social.searchClubs(term, mapTilerKey: mapTilerKey);
      final results = await Future.wait([
        browseFut,
        widget.social.fetchMyClubs(),
      ]).timeout(kBackendLoadTimeout);
      if (!mounted) return;
      setState(() {
        _browse = results[0];
        _mine = results[1];
        _loading = false;
      });
    } on TimeoutException catch (e) {
      debugPrint('ClubsScreen._load timed out after ${kBackendLoadTimeout.inSeconds}s: $e');
      _failed(_ClubsLoadError.timeout);
    } catch (e, s) {
      debugPrint('ClubsScreen._load failed: $e\n$s');
      _failed(_ClubsLoadError.generic);
    }
  }

  /// A failed reload keeps the clubs already on screen and says so in a
  /// banner; only a list that never loaded is replaced by the error state.
  void _failed(_ClubsLoadError error) {
    if (!mounted) return;
    final hadRows = (_tab == 0 ? _browse : _mine).isNotEmpty;
    setState(() {
      _loading = false;
      _error = error;
    });
    if (hadRows) {
      final l10n = AppLocalizations.of(context);
      showTopBanner(
        context,
        error == _ClubsLoadError.timeout
            ? l10n.clubsTimeoutError
            : l10n.clubsLoadError,
      );
    }
  }

  @override
  void dispose() {
    widget.social.removeListener(_onChange);
    _searchCtrl.dispose();
    _strava?.dispose();
    super.dispose();
  }

  Future<void> _createClub({
    String? initialName,
    String? initialLocation,
    int? stravaClubId,
  }) async {
    final api = widget.apiClient;
    final slug = await showClubFormSheet(
      context,
      social: widget.social,
      initialName: initialName,
      initialLocation: initialLocation,
      stravaClubId: stravaClubId,
      linkStravaClub: stravaClubId == null || api == null
          ? null
          : api.linkStravaClub,
    );
    if (slug == null || !mounted) return;
    if (stravaClubId != null) _strava?.load();
    await _openClub(slug);
  }

  void _setUpFromStrava(StravaClub club) {
    final setup = stravaClubSetup(club);
    _createClub(
      initialName: setup.name,
      initialLocation: setup.location,
      stravaClubId: setup.stravaClubId,
    );
  }

  Future<void> _openClub(String slug) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ClubDetailScreen(
          social: widget.social,
          training: widget.training,
          apiClient: widget.apiClient,
          routeStore: widget.routeStore,
          slug: slug,
        ),
      ),
    );
    _load();
  }

  Widget? _stravaSection() {
    final strava = _strava;
    if (strava == null || _tab != 1) return null;
    return StravaClubsSection(
      controller: strava,
      adminClubs: [
        for (final v in _mine)
          if (v.viewerRole == 'owner' || v.viewerRole == 'admin') v.row,
      ],
      onSetUp: _setUpFromStrava,
      onOpenClub: (slug) {
        _openClub(slug);
      },
    );
  }

  /// A new query is a different list, so the old results go and the loading
  /// frame shows until the new ones arrive.
  void _searchBrowse() {
    setState(() => _browse = const []);
    _load();
  }

  void _joinWithCode() {
    // Mobile mirror of web /clubs/join/[token], for a runner who tapped an
    // invite link that the browser redeemed elsewhere and can paste the code.
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ClubInviteScreen(
          social: widget.social,
          training: widget.training,
        ),
      ),
    );
  }

  /// Browse / My clubs as the quick chips, the Browse search, and Join with
  /// code as the row's one secondary action. Three stacked control rows
  /// before (chips, a full-width button, the search), now at most two.
  FilterBar _filterBar(AppLocalizations l10n) => FilterBar(
        key: const ValueKey('clubs-filter-bar'),
        search: _tab == 0
            ? AppSearchField(
                  controller: _searchCtrl,
                  hint: l10n.clubsSearchHint,
                  clearTooltip: l10n.commonClearSearch,
                  onSubmitted: (_) => _searchBrowse(),
                  // Clearing goes back to the default ranking at once; a
                  // typed query is sent on submit, since a place name is
                  // geocoded and each keystroke would spend a lookup.
                  onChanged: (v) {
                    if (v.isEmpty) _searchBrowse();
                  },
                )
            : null,
        trailing: [
          IconButton(
            key: const ValueKey('clubs-join-with-code'),
            tooltip: l10n.clubsJoinWithCode,
            icon: const Icon(Icons.qr_code),
            onPressed: _joinWithCode,
          ),
        ],
        chips: [
          for (final option in [
            ChoiceChipOption(value: 0, label: l10n.clubsTabBrowse),
            ChoiceChipOption(value: 1, label: l10n.clubsTabMine),
          ])
            buildChoiceChip<int>(
              context,
              option,
              _tab,
              (v) => setState(() => _tab = v),
            ),
        ],
      );

  Widget _empty(AppLocalizations l10n) => _tab == 0
      ? EmptyState(
          icon: Icons.groups_outlined,
          title: l10n.clubsEmptyBrowseTitle,
          body: l10n.clubsMissingClubBody,
          ctaLabel: l10n.clubsSetUpYourClub,
          onCta: () => _createClub(initialName: _searchCtrl.text.trim()),
          footer: TextButton.icon(
            onPressed: () => openGuide(context, 'create-a-club'),
            icon: const Icon(Icons.help_outline),
            label: Text(l10n.clubsHowToCreateClub),
          ),
        )
      : EmptyState(
          icon: Icons.person_add_alt_1,
          title: l10n.clubsEmptyMineTitle,
          body: l10n.clubsEmptyMineBody,
          ctaLabel: l10n.clubsTabBrowse,
          ctaIcon: Icons.travel_explore,
          onCta: () => setState(() => _tab = 0),
          footer: TextButton.icon(
            onPressed: _joinWithCode,
            icon: const Icon(Icons.qr_code),
            label: Text(l10n.clubsJoinWithCode),
          ),
        );

  Widget _buildList(AppLocalizations l10n, List<ClubView> list) {
    final strava = _stravaSection();
    final empty = _empty(l10n);
    final bottom = fabScrollClearance(context);
    return AsyncView<List<ClubView>>(
      loading: _loading,
      error: _error,
      data: list,
      isEmpty: (l) => l.isEmpty,
      loadingState: LoadingState.list(label: l10n.commonLoading),
      errorBuilder: (_, error) => AppErrorState(
        message: error == _ClubsLoadError.timeout
            ? l10n.clubsTimeoutError
            : l10n.clubsLoadError,
        onRetry: _load,
      ),
      empty: strava == null
          ? empty
          : ListView(
              padding: EdgeInsets.fromLTRB(
                  AppInsets.gutter, 0, AppInsets.gutter, bottom),
              children: [empty, strava],
            ),
      builder: (ctx, list) => ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
            AppInsets.gutter, AppSpace.sm, AppInsets.gutter, bottom),
        itemCount: list.length + (strava == null ? 0 : 1),
        separatorBuilder: (_, _) => const SizedBox(height: AppInsets.itemGap),
        itemBuilder: (ctx, i) => i == list.length
            ? strava!
            : _ClubTile(
                view: list[i],
                onTap: () => _openClub(list[i].row.slug),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return HubTabBody(
      title: l10n.clubsTitle,
      filters: _filterBar(l10n),
      primary: PrimaryAction(
        label: l10n.clubsNewClub,
        icon: Icons.add,
        onPressed: _createClub,
      ),
      onRefresh: _load,
      body: _buildList(l10n, _tab == 0 ? _browse : _mine),
    );
  }
}

class _ClubTile extends StatelessWidget {
  final ClubView view;
  final VoidCallback onTap;
  const _ClubTile({required this.view, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = view.row;
    return ListCard.row(
      margin: EdgeInsets.zero,
      dense: true,
      onTap: onTap,
      chevron: true,
      leading: IdentityAvatar(seed: c.id, name: c.name, size: 44),
      title: c.name,
      // The order stays name, verified, private for a screen reader.
      badge: c.isVerified || !(c.isPublic ?? true)
          ? Wrap(
              spacing: AppSpace.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // Verified-official badge — differentiates an authentic
                // operator (e.g. the Richmond Marathon) from a fan or
                // squatter holding the same name on a sibling slug.
                // clubs.name is intentionally NOT unique; the badge is the
                // disambiguator.
                if (c.isVerified) const VerifiedBadge(),
                if (!(c.isPublic ?? true))
                  StatusPill(
                    label: AppLocalizations.of(context).clubsBadgePrivate,
                    foreground: theme.colorScheme.onSurfaceVariant,
                    fill: theme.colorScheme.surface,
                    outline: theme.dividerColor,
                    icon: Icons.lock_outline,
                    size: StatusPillSize.compact,
                  ),
              ],
            )
          : null,
      // Wraps: the place, the count and the role pill side by side ran 271 dp
      // past the tile at 2x on a 320 dp phone (issue #1374).
      meta: Wrap(
        spacing: 10,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (c.locationLabel case final place? when place.isNotEmpty)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.place, size: 14, color: theme.colorScheme.outline),
                const SizedBox(width: AppSpace.xs),
                Flexible(
                  child: Text(
                    place,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.group, size: 14, color: theme.colorScheme.outline),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  AppLocalizations.of(context)
                      .clubsMemberCount(view.memberCount),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          if (view.viewerRole != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                view.viewerRole!,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

enum _ClubsLoadError { timeout, generic }


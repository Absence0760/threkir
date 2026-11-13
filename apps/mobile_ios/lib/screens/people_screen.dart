import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart'
    show
        AppInsets,
        AppSearchField,
        AppSpace,
        EmptyState,
        FilterBar,
        HubTabBody,
        IdentityAvatar,
        LoadingState,
        SectionHeader;

import '../auth_error.dart';
import '../l10n/gen/app_localizations.dart';
import '../nearby.dart';
import '../nearby_flag.dart';
import '../preferences.dart' show formatDistanceForPref;
import '../settings_destination.dart';
import '../widgets/error_state.dart';
import '../widgets/sign_in_required_state.dart';
import '../widgets/top_banner.dart';
import 'profile_screen.dart';

/// People discovery — name search + "suggested" people pulled from the
/// viewer's clubs. Mirrors `apps/web/src/lib/components/SocialPeople.svelte`
/// + the People tab on web's `/social` hub. The **People** tab of
/// `social_screen.dart`, built as a ui_kit `HubTabBody`: its search is the
/// tab's `FilterBar`, and pushed on its own (the Feed's "Find people" where
/// no shell is listening) it gets a small titled app bar (issue #1374).
///
/// Also hosts the opt-in coarse-location "runners nearby" list (issue #466),
/// which renders only while the default-off `ENABLE_NEARBY_RUNNERS` deploy gate
/// is on. With the gate off the surface is wholly inert: no heading, no empty
/// state, and no `discoverable_runners_near` call.
class PeopleScreen extends StatefulWidget {
  final ApiClient api;

  const PeopleScreen({super.key, required this.api});

  @override
  State<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends State<PeopleScreen> {
  final _searchCtl = TextEditingController();
  Timer? _debounce;
  int _searchGen = 0;

  bool _loadingSuggestions = true;
  bool _searching = false;
  bool _searchError = false;
  bool _suggestionsError = false;
  bool _signedOut = false;
  List<PeopleSuggestion> _suggestions = const [];
  List<PeopleSuggestion> _results = const [];
  List<NearbyRunner> _nearby = const [];
  bool _loadingNearby = false;
  bool _nearbyError = false;
  String _query = '';

  /// Read once per mount rather than per build so a mid-session env mutation
  /// can't leave the surface half-rendered against a half-loaded list.
  final bool _nearbyGate = nearbyRunnersGate;

  final Set<String> _rowBusy = <String>{};

  @override
  void initState() {
    super.initState();
    if (widget.api.userId != null) {
      _loadSuggestions();
      if (_nearbyGate) _loadNearby();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtl.dispose();
    super.dispose();
  }

  Future<void> _loadSuggestions() async {
    try {
      final s = await widget.api.fetchSuggestedPeople(limit: 12);
      if (!mounted) return;
      setState(() {
        _suggestions = s;
        _loadingSuggestions = false;
        _suggestionsError = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (isSignedOutError(e)) {
          _signedOut = true;
        } else {
          _suggestionsError = true;
        }
        _loadingSuggestions = false;
      });
    }
  }

  void _retrySuggestions() {
    setState(() {
      _loadingSuggestions = true;
      _suggestionsError = false;
    });
    _loadSuggestions();
  }

  /// Only ever called behind [_nearbyGate] — the RPC must not be reached at
  /// all while the sign-off gate is off.
  Future<void> _loadNearby() async {
    setState(() {
      _loadingNearby = true;
      _nearbyError = false;
    });
    try {
      final rows = await widget.api.fetchNearbyRunners();
      if (!mounted) return;
      setState(() {
        _nearby = rows;
        _loadingNearby = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (isSignedOutError(e)) {
          _signedOut = true;
        } else {
          _nearbyError = true;
        }
        _loadingNearby = false;
      });
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    final trimmed = value.trim();
    setState(() {
      _query = trimmed;
      _searchError = false;
    });
    if (trimmed.isEmpty) {
      _searchGen++;
      setState(() {
        _results = const [];
        _searching = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), _runSearch);
  }

  Future<void> _runSearch() async {
    final term = _query;
    final gen = ++_searchGen;
    if (term.isEmpty) return;
    setState(() {
      _searching = true;
      _searchError = false;
    });
    try {
      final next = await widget.api.searchPeople(term, limit: 20);
      if (!mounted || gen != _searchGen) return;
      setState(() {
        _results = next;
        _searching = false;
      });
    } catch (e) {
      // Surface the failure with a retry affordance instead of silently
      // falling through to the "no matches" empty state — a failed search
      // is not the same as an empty result. Mirrors the sibling Discover
      // tab's ErrorState pattern (and web's search-failed toast). An auth
      // rejection is different again: search_user_profiles is revoked from
      // anon by design, so a retry can never succeed — route it into the
      // sign-in state instead (issue #224).
      if (!mounted || gen != _searchGen) return;
      setState(() {
        if (isSignedOutError(e)) {
          _signedOut = true;
        } else {
          _searchError = true;
        }
        _searching = false;
      });
    }
  }

  void _clearSearch() {
    _searchCtl.clear();
    _onSearchChanged('');
  }

  Future<void> _toggleFollow(String id, bool wasFollowing) async {
    if (_rowBusy.contains(id)) return;
    setState(() {
      _rowBusy.add(id);
      _flipFollow(id, !wasFollowing);
    });
    try {
      if (wasFollowing) {
        await widget.api.unfollowUser(id);
      } else if (await widget.api.followUser(id) == FollowOutcome.requested) {
        // A private profile: a request went out, nothing is followed yet.
        if (!mounted) return;
        setState(() => _flipFollow(id, false));
        showTopBanner(
            context, AppLocalizations.of(context).profileRequestSent);
      }
    } catch (e) {
      debugPrint('[PeopleScreen] follow failed: $e');
      if (!mounted) return;
      final signedOut = isSignedOutError(e);
      setState(() {
        _flipFollow(id, wasFollowing);
        if (signedOut) _signedOut = true;
      });
      if (!signedOut) {
        showTopBanner(
          context,
          AppLocalizations.of(context).peopleFollowFailedBanner(
              friendlyError(AppLocalizations.of(context), e)));
      }
    } finally {
      if (mounted) setState(() => _rowBusy.remove(id));
    }
  }

  void _flipFollow(String id, bool viewerFollows) {
    _results = _results
        .map((p) => p.id == id ? _withFollow(p, viewerFollows) : p)
        .toList();
    _suggestions = _suggestions
        .map((p) => p.id == id ? _withFollow(p, viewerFollows) : p)
        .toList();
    _nearby = _nearby
        .map((p) => p.id == id ? _withFollowNearby(p, viewerFollows) : p)
        .toList();
  }

  static PeopleSuggestion _withFollow(PeopleSuggestion p, bool follows) =>
      PeopleSuggestion(
        id: p.id,
        displayName: p.displayName,
        avatarUrl: p.avatarUrl,
        publicRunsCount: p.publicRunsCount,
        sharedClubs: p.sharedClubs,
        viewerFollows: follows,
      );

  static NearbyRunner _withFollowNearby(NearbyRunner p, bool follows) =>
      NearbyRunner(
        id: p.id,
        displayName: p.displayName,
        avatarUrl: p.avatarUrl,
        bucket: p.bucket,
        viewerFollows: follows,
      );

  /// The coarse bucket as a label. Only ever the bucket's upper BOUND, formatted
  /// in the runner's own unit — never the exact distance, which the RPC
  /// deliberately never sends.
  static String _bucketLabel(AppLocalizations l10n, int bucket) {
    final bound = nearbyBucketUpperBoundM(bucket);
    return bound == null
        ? l10n.peopleNearbyBeyond(
            formatDistanceForPref(kNearbyBucketBoundsM.last.toDouble()))
        : l10n.peopleNearbyWithin(formatDistanceForPref(bound.toDouble()));
  }

  void _handleSignedIn() {
    if (!mounted) return;
    setState(() {
      _signedOut = false;
      _loadingSuggestions = true;
      _suggestionsError = false;
      _searchError = false;
    });
    _loadSuggestions();
    if (_nearbyGate) _loadNearby();
    if (_query.isNotEmpty) _runSearch();
  }

  Future<void> _refresh() => Future.wait([
        _loadSuggestions(),
        if (_nearbyGate) _loadNearby(),
        if (_query.isNotEmpty) _runSearch(),
      ]);

  Widget _sectionHeader(String label, {String? subtitle}) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppInsets.gutter, AppSpace.md, AppInsets.gutter, AppSpace.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(label: label),
          if (subtitle != null) ...[
            const SizedBox(height: AppSpace.xs),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // search_user_profiles is granted to authenticated only (privacy
    // opt-out lives in owner-only user_settings), so a signed-out search
    // can only fail — render the sign-in state instead of a search field
    // whose every query dead-ends in a retry loop (issue #224).
    if (widget.api.userId == null || _signedOut) {
      return HubTabBody(
        title: l10n.socialTabPeople,
        body: SignInRequiredState(
          api: widget.api,
          message: l10n.peopleSignedOutMessage,
          onSignedIn: _handleSignedIn,
        ),
      );
    }
    final hasQuery = _query.isNotEmpty;
    final visible = hasQuery ? _results : _suggestions;
    Widget box(Widget child) => SliverToBoxAdapter(child: child);
    final loading = box(LoadingState.section(
      label: l10n.commonLoading,
      padding: const EdgeInsets.symmetric(
          horizontal: AppInsets.gutter, vertical: AppSpace.sm),
    ));
    return HubTabBody(
      title: l10n.socialTabPeople,
      filters: FilterBar(
        key: const ValueKey('people-filter-bar'),
        search: Semantics(
          textField: true,
          label: l10n.peopleSearchHint,
          child: AppSearchField(
            controller: _searchCtl,
            hint: l10n.peopleSearchHint,
            clearTooltip: l10n.peopleClearSearchTooltip,
            onChanged: _onSearchChanged,
          ),
        ),
      ),
      onRefresh: _refresh,
      body: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          box(_sectionHeader(hasQuery
              ? l10n.peopleSearchResultsHeader
              : l10n.peopleSuggestedHeader)),
          if (hasQuery && _searching)
            loading
          else if (hasQuery && _searchError)
            box(AppErrorState.inline(
              message: l10n.exploreRoutesSearchFailed,
              onRetry: _runSearch,
            ))
          else if (hasQuery && _results.isEmpty)
            box(EmptyState(
              icon: Icons.search_off,
              title: l10n.peopleEmptySearchTitle(_query),
              body: l10n.peopleEmptySearchBody,
              ctaLabel: l10n.peopleClearSearchTooltip,
              ctaIcon: Icons.close,
              onCta: _clearSearch,
            ))
          else if (!hasQuery && _loadingSuggestions)
            loading
          else if (!hasQuery && _suggestionsError)
            box(AppErrorState.inline(
              message: l10n.peopleSuggestionsLoadFailed,
              onRetry: _retrySuggestions,
            ))
          else if (!hasQuery && _suggestions.isEmpty)
            box(EmptyState(
              icon: Icons.groups_outlined,
              title: l10n.peopleEmptySuggestionsTitle,
              body: l10n.peopleEmptySuggestionsBody,
            ))
          else
            SliverList.separated(
              itemBuilder: (_, i) => _PersonRow(
                person: visible[i],
                busy: _rowBusy.contains(visible[i].id),
                onToggleFollow: () =>
                    _toggleFollow(visible[i].id, visible[i].viewerFollows),
                onOpenProfile: () => _openProfile(visible[i].id),
              ),
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemCount: visible.length,
            ),
          // Opt-in coarse-location discovery. Suppressed while a search is
          // active (mirrors SocialPeople.svelte) and entirely absent while the
          // deploy gate is off.
          if (_nearbyGate && !hasQuery) ...[
            box(_sectionHeader(
              l10n.peopleNearbyHeader,
              subtitle: l10n.peopleNearbySubtitle,
            )),
            if (_loadingNearby)
              loading
            else if (_nearbyError)
              box(AppErrorState.inline(
                message: l10n.peopleNearbyLoadFailed,
                onRetry: _loadNearby,
              ))
            else if (_nearby.isEmpty)
              box(EmptyState(
                icon: Icons.near_me,
                title: l10n.peopleNearbyEmptyTitle,
                body: l10n.peopleNearbyEmptyBody,
                // The opt-in and the area setter both live on the
                // Preferences screen, which needs a Preferences and a
                // SettingsSyncService this tab was never handed. Name the
                // destination and let the shell open it (decisions § 710) —
                // web's empty card links to the privacy page here.
                ctaLabel: l10n.peopleNearbyEmptyAction,
                ctaIcon: Icons.settings,
                onCta: () => openSettings(SettingsDestination.privacy),
              ))
            else
              SliverList.separated(
                itemBuilder: (_, i) => _NearbyRow(
                  person: _nearby[i],
                  bucketLabel: _bucketLabel(l10n, _nearby[i].bucket),
                  busy: _rowBusy.contains(_nearby[i].id),
                  onToggleFollow: () => _toggleFollow(
                      _nearby[i].id, _nearby[i].viewerFollows),
                  onOpenProfile: () => _openProfile(_nearby[i].id),
                ),
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemCount: _nearby.length,
              ),
          ],
          SliverToBoxAdapter(
            child: SizedBox(height: MediaQuery.paddingOf(context).bottom),
          ),
        ],
      ),
    );
  }

  void _openProfile(String id) => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ProfileScreen(api: widget.api, userId: id),
        ),
      );
}

class _PersonRow extends StatelessWidget {
  final PeopleSuggestion person;
  final bool busy;
  final VoidCallback onToggleFollow;
  final VoidCallback onOpenProfile;

  const _PersonRow({
    required this.person,
    required this.busy,
    required this.onToggleFollow,
    required this.onOpenProfile,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final metaParts = <String>[
      l10n.peoplePublicRunCount(person.publicRunsCount),
      if (person.sharedClubs > 0) l10n.peopleSharedClubsCount(person.sharedClubs),
    ];
    final handle = person.handle;
    final hasHandle = handle != null && handle.isNotEmpty;
    final subtitle = hasHandle
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '@$handle',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              Text(metaParts.join(' · ')),
            ],
          )
        : Text(metaParts.join(' · '));
    return ListTile(
      isThreeLine: hasHandle,
      leading: IdentityAvatar(
        seed: person.id,
        name: person.displayName,
        size: 40,
        imageUrl: person.avatarUrl,
      ),
      title: Text(person.displayName ?? l10n.peopleFallbackDisplayName),
      subtitle: subtitle,
      trailing: FilledButton.tonal(
        onPressed: busy ? null : onToggleFollow,
        style: FilledButton.styleFrom(
          visualDensity: VisualDensity.compact,
        ),
        child: Text(person.viewerFollows
            ? l10n.peopleFollowingButton
            : l10n.peopleFollowButton),
      ),
      onTap: onOpenProfile,
    );
  }
}

/// A nearby runner's row. Deliberately NOT the same widget as [_PersonRow]:
/// the only thing known about this person's location is a coarse bucket, so the
/// row has no place to put a run count, a shared-club count, or anything a map
/// could pin.
class _NearbyRow extends StatelessWidget {
  final NearbyRunner person;
  final String bucketLabel;
  final bool busy;
  final VoidCallback onToggleFollow;
  final VoidCallback onOpenProfile;

  const _NearbyRow({
    required this.person,
    required this.bucketLabel,
    required this.busy,
    required this.onToggleFollow,
    required this.onOpenProfile,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListTile(
      leading: IdentityAvatar(
        seed: person.id,
        name: person.displayName,
        size: 40,
        imageUrl: person.avatarUrl,
      ),
      title: Text(person.displayName ?? l10n.peopleFallbackDisplayName),
      subtitle: Text(bucketLabel),
      trailing: FilledButton.tonal(
        onPressed: busy ? null : onToggleFollow,
        style: FilledButton.styleFrom(
          visualDensity: VisualDensity.compact,
        ),
        child: Text(person.viewerFollows
            ? l10n.peopleFollowingButton
            : l10n.peopleFollowButton),
      ),
      onTap: onOpenProfile,
    );
  }
}

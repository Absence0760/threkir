import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

import '../fab_clearance.dart';
import '../l10n/gen/app_localizations.dart';
import '../local_route_store.dart';
import '../social_service.dart';
import '../training_service.dart';
import '../unread_messages.dart';
import '../widgets/notification_bell.dart';
import '../widgets/sign_in_required_state.dart';
import 'challenges_screen.dart';
import 'clubs_screen.dart';
import 'discover_screen.dart';
import 'feed_screen.dart';
import 'messages_screen.dart';
import 'people_screen.dart';

/// The Social hub's sub-tabs, in strip order.
///
/// A named, ordered enum rather than the raw int this was, per § 490: the same
/// seam on `ProfileScreen` shipped a live bug where a stale `initialTab: 3`
/// literal stayed IN RANGE after the tab set changed, so the notification bell
/// silently opened the wrong tab. An int carries no way to notice; the label
/// row, the view row, the FAB and any deep link all read this order.
///
/// `Feed · Clubs · Events · Challenges · People` (issue #1374, owner
/// decision "Social tabs"): Events is the cross-club activity search that was
/// called Discover, named for what it lists, and People goes last, since it
/// is a directory also reached from every avatar. Web's `/social` has the
/// same five in the same order.
enum SocialTab {
  feed,
  clubs,
  events,
  challenges,
  people;

  String label(AppLocalizations l10n) => switch (this) {
        SocialTab.feed => l10n.socialTabFeed,
        SocialTab.clubs => l10n.socialTabClubs,
        SocialTab.events => l10n.socialTabEvents,
        SocialTab.challenges => l10n.challengesTitle,
        SocialTab.people => l10n.socialTabPeople,
      };
}

/// The Social tab, mirroring the web `/social` hub (decisions § 54). Five
/// sub-tabs:
///   - Feed: 14-day activity feed of public runs from people you follow.
///   - Clubs: browse public clubs + the user's own memberships.
///   - Events: cross-club activity search over `search_public_events`
///     (public clubs only; category/cadence/weekday/time/price filters,
///     decisions § 147).
///   - Challenges: the joinable-challenge board + the user's own entries.
///   - People: name search + suggested-from-clubs discovery.
///
/// The hub owns the only app bar and the one FAB, as the Fitness hub does:
/// the bar carries the hub's title, Messages (with the unread count) and the
/// notifications bell, over the tab strip; every tab body is a ui_kit
/// `HubTabBody`, which inside the hub's [HubTabScope] draws no app bar of its
/// own, keeps its secondary actions in its control row and hands its primary
/// action to the hub's FAB (issue #1374). Messages and the bell moved here
/// from You and Home, so a message is answered from the hub where people are.
///
/// Every tab is kept alive: a `TabBarView` page is disposed once it scrolls
/// out of view, and without the wrapper each swipe dropped a tab's search and
/// filters and refetched it behind a skeleton (#1374 NS-4).
///
/// A link to one of these tabs from elsewhere selects it through
/// `social_surface_requests.dart` and the host's [selectedTab] rather than
/// pushing a second copy.
class SocialScreen extends StatefulWidget {
  /// Nullable like every other tab's client — null means Supabase never
  /// initialised (env missing / init failed). The tab then fails closed
  /// into the shared unavailable state instead of manufacturing a
  /// default ApiClient whose every method throws (issue #238).
  final ApiClient? api;
  final SocialService social;
  final TrainingService training;

  /// `ClubsScreen` takes it to surface club-owned routes.
  final LocalRouteStore routeStore;

  /// The tab to open on when no [selectedTab] is given. Defaults to Feed:
  /// fresh follower activity is the likeliest reason to open Social.
  final SocialTab initialTab;

  /// Which tab is showing, held by the host so a link can select a tab
  /// before this lazy page has been built, and written back on every tap
  /// and swipe. Null in standalone mounts and tests, where the hub owns one.
  final ValueNotifier<SocialTab>? selectedTab;

  /// The count the Messages button shows. Defaults to the app's one source,
  /// which this hub binds to [api].
  final UnreadMessages? unreadMessages;

  const SocialScreen({
    super.key,
    required this.api,
    required this.social,
    required this.training,
    required this.routeStore,
    this.initialTab = SocialTab.feed,
    this.selectedTab,
    this.unreadMessages,
  });

  @override
  State<SocialScreen> createState() => _SocialScreenState();
}

class _SocialScreenState extends State<SocialScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _controller;
  final _actions = HubPrimaryActions();

  late final ValueNotifier<SocialTab> _tab =
      widget.selectedTab ?? ValueNotifier(widget.initialTab);
  late final bool _ownsTab = widget.selectedTab == null;

  late final UnreadMessages _unread =
      widget.unreadMessages ?? UnreadMessages.instance;

  @override
  void initState() {
    super.initState();
    _controller = TabController(
      length: SocialTab.values.length,
      vsync: this,
      initialIndex: _tab.value.index,
    );
    _controller.addListener(_publishTab);
    _tab.addListener(_adoptTab);
    _unread.bind(widget.api);
  }

  /// Mid-animation the index has not committed yet; publishing then would
  /// come straight back through [_adoptTab] and snap the transition.
  void _publishTab() {
    if (_controller.indexIsChanging) return;
    _tab.value = SocialTab.values[_controller.index];
  }

  void _adoptTab() {
    final index = _tab.value.index;
    if (index != _controller.index) _controller.index = index;
  }

  @override
  void dispose() {
    _tab.removeListener(_adoptTab);
    _controller
      ..removeListener(_publishTab)
      ..dispose();
    if (_ownsTab) _tab.dispose();
    _actions.dispose();
    super.dispose();
  }

  /// The inbox reads the count again as it closes, so this badge needs no
  /// read of its own on the way back.
  void _openMessages(ApiClient api) =>
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => MessagesScreen(api: api, training: widget.training),
      ));

  Widget _messagesButton(AppLocalizations l10n, ApiClient api) =>
      ValueListenableBuilder<int>(
        valueListenable: _unread,
        builder: (context, unread, _) => MergeSemantics(
          // Merged so the count is announced on the button itself, not as a
          // separate node after it.
          child: Semantics(
            value: unread > 0 ? l10n.messagesUnreadCount(unread) : null,
            child: IconButton(
              key: const ValueKey('social-messages'),
              tooltip: l10n.messagesTitle,
              onPressed: () => _openMessages(api),
              icon: ExcludeSemantics(
                child: Badge.count(
                  count: unread,
                  isLabelVisible: unread > 0,
                  child: const Icon(Icons.chat_bubble_outline),
                ),
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final api = widget.api;
    if (api == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.navSocial)),
        body: const SignInRequiredState(api: null),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.navSocial),
        actions: [
          _messagesButton(l10n, api),
          if (api.userId != null) NotificationBell(api: api),
          const SizedBox(width: AppSpace.xs),
        ],
        bottom: AppTabBar(
          controller: _controller,
          labels: [
            for (final t in SocialTab.values) t.label(l10n),
          ],
        ),
      ),
      body: TabBarView(
        controller: _controller,
        children: [
          for (final t in SocialTab.values)
            HubTabScope(
              tab: t,
              actions: _actions,
              child: _KeepAliveTab(child: _body(t, api)),
            ),
        ],
      ),
      floatingActionButtonLocation: pageFabLocation(context),
      floatingActionButton: ValueListenableBuilder<SocialTab>(
        valueListenable: _tab,
        builder: (_, tab, _) => HubFab(actions: _actions, tab: tab),
      ),
    );
  }

  Widget _body(SocialTab tab, ApiClient api) => switch (tab) {
        SocialTab.feed => FeedScreen(
            key: const PageStorageKey('social-feed'),
            api: api,
          ),
        SocialTab.clubs => ClubsScreen(
            key: const PageStorageKey('social-clubs'),
            social: widget.social,
            training: widget.training,
            apiClient: api,
            routeStore: widget.routeStore,
          ),
        SocialTab.events => DiscoverScreen(
            key: const PageStorageKey('social-events'),
            api: api,
            social: widget.social,
          ),
        SocialTab.challenges => ChallengesScreen(
            key: const PageStorageKey('social-challenges'),
            social: widget.social,
          ),
        SocialTab.people => PeopleScreen(
            key: const PageStorageKey('social-people'),
            api: api,
          ),
      };
}

class _KeepAliveTab extends StatefulWidget {
  final Widget child;

  const _KeepAliveTab({required this.child});

  @override
  State<_KeepAliveTab> createState() => _KeepAliveTabState();
}

class _KeepAliveTabState extends State<_KeepAliveTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

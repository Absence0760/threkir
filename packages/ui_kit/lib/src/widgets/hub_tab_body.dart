import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;

import 'filter_bar.dart';
import 'pushed_page.dart';

/// A page's one primary action, as a value its page template places: the
/// hub's extended FAB on a hub tab, the extended FAB on a pushed page. A
/// template takes at most one, which is what makes "one primary action per
/// page" a rule the type enforces rather than one each screen follows.
@immutable
class PrimaryAction {
  const PrimaryAction({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.fabKey,
  });

  final String label;
  final IconData icon;

  /// Null draws the action disabled.
  final VoidCallback? onPressed;
  final String? tooltip;

  /// The rendered button's key, for a test or a tour to find it by.
  final Key? fabKey;

  /// Whether [other] draws the same button; a new [onPressed] closure alone
  /// does not change what is on screen.
  bool looksLike(PrimaryAction? other) =>
      other != null &&
      other.label == label &&
      other.icon == icon &&
      other.tooltip == tooltip &&
      other.fabKey == fabKey &&
      (other.onPressed == null) == (onPressed == null);

  /// This action as an extended FAB. [onPressed] defaults to the action's own.
  /// With [extended] false only the icon shows, and the label becomes the
  /// tooltip, so the button keeps its name.
  Widget toFab({
    Object? heroTag,
    VoidCallback? onPressed,
    bool extended = true,
  }) =>
      FloatingActionButton.extended(
        key: fabKey,
        heroTag: heroTag,
        isExtended: extended,
        onPressed: this.onPressed == null ? null : (onPressed ?? this.onPressed),
        tooltip: tooltip ?? (extended ? null : label),
        icon: Icon(icon),
        label: Text(label),
      );
}

/// One entry in a tab's overflow menu: an action people take now and then,
/// which would otherwise hold the FAB or a slot in the control row.
@immutable
class HubMenuItem {
  const HubMenuItem({
    required this.label,
    required this.icon,
    required this.onSelected,
    this.itemKey,
  });

  final String label;
  final IconData icon;
  final VoidCallback onSelected;

  /// The rendered entry's key, for a test to find it by.
  final Key? itemKey;

  bool looksLike(HubMenuItem other) =>
      other.label == label && other.icon == icon && other.itemKey == itemKey;
}

bool _menusLookAlike(List<HubMenuItem>? a, List<HubMenuItem>? b) {
  if (a == null || b == null) return a == b;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (!a[i].looksLike(b[i])) return false;
  }
  return true;
}

/// A ⋮ button opening the entries [read] returns. It reads them again when
/// the menu opens and when an entry is picked, so a hub calls the newest
/// closures a body has published, not the ones it had when it last built.
Widget _menuButton(
  BuildContext context,
  List<HubMenuItem> Function() read, {
  String? tooltip,
}) =>
    PopupMenuButton<int>(
      key: const Key('hub-menu'),
      icon: const Icon(Icons.more_vert),
      tooltip: tooltip ?? MaterialLocalizations.of(context).showMenuTooltip,
      onSelected: (i) {
        final now = read();
        if (i < now.length) now[i].onSelected();
      },
      itemBuilder: (_) {
        final items = read();
        return [
          for (var i = 0; i < items.length; i++)
            PopupMenuItem<int>(
              key: items[i].itemKey,
              value: i,
              child: ListTile(
                leading: Icon(items[i].icon),
                title: Text(items[i].label),
                contentPadding: EdgeInsets.zero,
              ),
            ),
        ];
      },
    );

/// The primary actions a hub's tab bodies have published, by tab. The hub
/// listens and renders the active tab's as its one FAB.
class HubPrimaryActions extends ChangeNotifier {
  final Map<Object, PrimaryAction> _actions = {};

  /// A body withdraws after the frame it was disposed in, which can be after
  /// the hub that owns this store has gone too.
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  PrimaryAction? of(Object tab) => _actions[tab];

  final Map<Object, List<HubMenuItem>> _menus = {};

  /// The overflow menu [tab]'s body has published, empty when it has none.
  List<HubMenuItem> menuOf(Object tab) => _menus[tab] ?? const [];

  /// Stores [menu] for [tab], notifying only when the entries would look
  /// different, as [publish] does for the primary action.
  void publishMenu(Object tab, List<HubMenuItem> menu) {
    if (_disposed) return;
    final before = _menus[tab];
    if (menu.isEmpty) {
      if (_menus.remove(tab) != null) notifyListeners();
      return;
    }
    _menus[tab] = menu;
    if (!_menusLookAlike(menu, before)) notifyListeners();
  }

  /// Tabs whose list is scrolling down, whose FAB shows its icon only.
  final Set<Object> _collapsed = {};

  /// Whether [tab]'s FAB is collapsed to its icon.
  bool isCollapsed(Object tab) => _collapsed.contains(tab);

  /// Collapses [tab]'s FAB while its list scrolls down and extends it again
  /// when the list scrolls up or comes to rest at either end. An extended FAB
  /// at 2x text spans most of a narrow phone, so over a list on the move it
  /// covered the trailing control of every card it passed (issue #1374,
  /// Routes → Mine: Build over the stars).
  void setCollapsed(Object tab, bool collapsed) {
    if (_disposed) return;
    final changed = collapsed ? _collapsed.add(tab) : _collapsed.remove(tab);
    if (changed) notifyListeners();
  }

  /// Back handlers by tab, each keyed by the body that registered it, so a
  /// tab with several bodies (Routes' views) never has one clear another's.
  final Map<Object, Map<Object, VoidCallback>> _back = {};

  /// Registers (or with null, withdraws) [owner]'s Back handler for [tab]. A
  /// body registers one while it has something Back should undo first, such
  /// as a selection.
  void registerBack(Object tab, Object owner, VoidCallback? onBack) {
    if (onBack == null) {
      final forTab = _back[tab];
      forTab?.remove(owner);
      if (forTab != null && forTab.isEmpty) _back.remove(tab);
      return;
    }
    (_back[tab] ??= {})[owner] = onBack;
  }

  /// Gives Back to [tab]'s body, if it has something to undo. True when it
  /// was used, so the hub's host must not also navigate (issue #1374 NS-2,
  /// NS-3: Back in select mode cleared the selection AND left the tab).
  bool consumeBack(Object tab) {
    final handlers = _back[tab];
    if (handlers == null || handlers.isEmpty) return false;
    handlers.values.last();
    return true;
  }

  /// Stores [action] for [tab]. Notifies only when the button would look
  /// different, so a body that rebuilds with a fresh closure every frame does
  /// not rebuild the hub every frame; the stored action is still the latest,
  /// and [HubFab] calls it through [of].
  void publish(Object tab, PrimaryAction? action) {
    if (_disposed) return;
    final before = _actions[tab];
    if (action == null) {
      if (_actions.remove(tab) != null) notifyListeners();
      return;
    }
    _actions[tab] = action;
    if (!action.looksLike(before)) notifyListeners();
  }
}

/// Marks a hub's tab page so the [HubTabBody] inside it knows it is hosted:
/// it then draws no app bar of its own and hands its primary action to
/// [actions] under [tab].
class HubTabScope extends InheritedWidget {
  const HubTabScope({
    super.key,
    required this.tab,
    required this.actions,
    required super.child,
  });

  final Object tab;
  final HubPrimaryActions actions;

  static HubTabScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HubTabScope>();

  @override
  bool updateShouldNotify(HubTabScope oldWidget) =>
      oldWidget.tab != tab || oldWidget.actions != actions;
}

/// The hub's FAB: the primary action [actions] holds for [tab], or nothing.
/// The hub's own `Scaffold` places it, so it sits where every page's FAB
/// sits.
class HubFab extends StatelessWidget {
  const HubFab({super.key, required this.actions, required this.tab});

  final HubPrimaryActions actions;
  final Object tab;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: actions,
        builder: (context, _) {
          final action = actions.of(tab);
          if (action == null) return const SizedBox.shrink();
          return action.toFab(
            heroTag: ValueKey(('hub-fab', tab)),
            onPressed: () => actions.of(tab)?.onPressed?.call(),
            extended: !actions.isCollapsed(tab),
          );
        },
      );
}

/// The hub's ⋮: the overflow menu [actions] holds for [tab], or nothing. The
/// hub puts it at the end of its title row, where a pushed page's app bar
/// keeps its own.
class HubMenu extends StatelessWidget {
  const HubMenu({
    super.key,
    required this.actions,
    required this.tab,
    this.tooltip,
  });

  final HubPrimaryActions actions;
  final Object tab;

  /// The button's name, so it can match the ⋮ another root page keeps in the
  /// same place. Defaults to Material's "Show menu".
  final String? tooltip;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: actions,
        builder: (context, _) {
          if (actions.menuOf(tab).isEmpty) return const SizedBox.shrink();
          return _menuButton(
            context,
            () => actions.menuOf(tab),
            tooltip: tooltip,
          );
        },
      );
}

/// The bar that replaces a list's controls while rows are selected: close,
/// the count, and the actions on the selection.
@immutable
class HubSelection {
  const HubSelection({
    required this.title,
    required this.onClose,
    required this.closeTooltip,
    this.actions = const [],
  });

  final String title;

  /// Null disables close (a delete in flight).
  final VoidCallback? onClose;
  final String closeTooltip;
  final List<Widget> actions;
}

/// The body of a hub tab: its control row, an optional banner, and its
/// content, with no app bar and no title, because the hub's tab strip already
/// names it (issue #1374; the Social hub's contract since decisions § 54).
///
/// Inside a hub ([HubTabScope]) it hands [primary] to the hub, which shows it
/// as its one FAB, hands [menu] to the hub's ⋮ ([HubMenu]), puts [actions] at
/// the end of the control row, and wraps [body] in a pull-to-refresh when
/// [onRefresh] is given. Mounted on its own (pushed where no hub is
/// listening, or in a test) it builds the page a pushed screen is: [title]
/// said in a heading above the controls, a small app bar that repeats it once
/// the heading has scrolled away and holds [menu] as its ⋮, and [primary] as
/// its FAB.
class HubTabBody extends StatefulWidget {
  const HubTabBody({
    super.key,
    required this.title,
    required this.body,
    this.filters,
    this.actions = const [],
    this.primary,
    this.menu = const [],
    this.banner,
    this.selection,
    this.onRefresh,
  });

  /// Shown only when mounted outside a hub.
  final String title;

  /// The content. Should scroll, so a pull can refresh it.
  final Widget body;

  /// The control row, usually a [FilterBar]. Pinned above [body].
  final Widget? filters;

  /// Secondary actions (sort, import, sync). At most two or three icons.
  final List<Widget> actions;

  final PrimaryAction? primary;

  /// Actions taken now and then: the hub's ⋮ at the end of its title row
  /// while this tab shows, or the app bar's ⋮ when mounted on its own.
  final List<HubMenuItem> menu;

  /// One line between the controls and the content: an offline notice, a
  /// stale-data warning, a summary.
  final Widget? banner;

  /// While set, replaces the control row (or, on its own, the app bar).
  final HubSelection? selection;

  final Future<void> Function()? onRefresh;

  @override
  State<HubTabBody> createState() => _HubTabBodyState();
}

class _HubTabBodyState extends State<HubTabBody> {
  HubTabScope? _scope;

  /// What this body last handed the hub, so a withdrawal never removes an
  /// action a newer body for the same tab has published since.
  PrimaryAction? _published;

  /// The menu this body last handed the hub, for the same reason.
  List<HubMenuItem>? _publishedMenu;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = HubTabScope.maybeOf(context);
    if (!identical(scope, _scope) &&
        _scope != null &&
        (scope?.tab != _scope!.tab || scope?.actions != _scope!.actions)) {
      _withdraw(_scope!);
      _scope!.actions.registerBack(_scope!.tab, this, null);
    }
    _scope = scope;
    if (scope != null) _registerBack(scope);
    _publish();
  }

  @override
  void didUpdateWidget(HubTabBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_scope case final scope?) _registerBack(scope);
    _publish();
  }

  @override
  void dispose() {
    if (_scope case final scope?) {
      _withdraw(scope);
      scope.actions.registerBack(scope.tab, this, null);
    }
    super.dispose();
  }

  /// While rows are selected, Back closes the selection (or, while a delete
  /// on it is in flight and close is off, does nothing) instead of leaving
  /// the tab. The hub's host asks through [HubPrimaryActions.consumeBack], so
  /// a body never needs a `PopScope` of its own, and a hidden tab's selection
  /// never answers a Back pressed somewhere else.
  void _registerBack(HubTabScope scope) {
    final selection = widget.selection;
    scope.actions.registerBack(
      scope.tab,
      this,
      selection == null ? null : () => widget.selection?.onClose?.call(),
    );
  }

  void _withdraw(HubTabScope scope) {
    final menu = _publishedMenu;
    if (menu != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (identical(scope.actions.menuOf(scope.tab), menu)) {
          scope.actions.publishMenu(scope.tab, const []);
        }
      });
    }
    final mine = _published;
    if (mine == null) return;
    // After the frame: a hub listening to the store must not be marked
    // dirty while it is itself being built or torn down.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (identical(scope.actions.of(scope.tab), mine)) {
        scope.actions.publish(scope.tab, null);
      }
    });
  }

  void _publish() {
    final scope = _scope;
    if (scope == null) return;
    _publishMenu(scope);
    final action = widget.selection == null ? widget.primary : null;
    final current = scope.actions.of(scope.tab);
    if (action != null && action.looksLike(current)) {
      // Same button: keep the newest closure without a rebuild.
      scope.actions.publish(scope.tab, _published = action);
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(_scope, scope)) return;
      final next = widget.selection == null ? widget.primary : null;
      if (next == null && !identical(scope.actions.of(scope.tab), _published)) {
        return;
      }
      scope.actions.publish(scope.tab, _published = next);
    });
  }

  /// The menu hides while rows are selected, as the primary action does.
  void _publishMenu(HubTabScope scope) {
    final menu = widget.selection == null ? widget.menu : const <HubMenuItem>[];
    if (_menusLookAlike(menu, scope.actions.menuOf(scope.tab))) {
      // Same entries: keep the newest closures without a rebuild.
      if (menu.isNotEmpty) {
        scope.actions.publishMenu(scope.tab, _publishedMenu = menu);
      }
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(_scope, scope)) return;
      final next = widget.selection == null
          ? widget.menu
          : const <HubMenuItem>[];
      if (next.isEmpty &&
          !identical(scope.actions.menuOf(scope.tab), _publishedMenu)) {
        return;
      }
      scope.actions.publishMenu(scope.tab, next);
      _publishedMenu = next.isEmpty ? null : next;
    });
  }

  Widget _selectionRow(HubSelection s) => Material(
        color: Theme.of(context).colorScheme.secondaryContainer,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(4, 4, 4, 4),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: s.closeTooltip,
                onPressed: s.onClose,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  s.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              ...s.actions,
            ],
          ),
        ),
      );

  Widget? _controls() {
    final filters = widget.filters;
    final actions = widget.actions;
    if (filters is FilterBar) return filters.withTrailing(actions);
    if (filters != null && actions.isEmpty) return filters;
    if (filters != null) {
      return Row(children: [Expanded(child: filters), ...actions]);
    }
    if (actions.isEmpty) return null;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: actions,
      ),
    );
  }

  /// Always the same tree, refreshable or not, so a tab that turns its
  /// refresh on and off (a view switch) keeps the state under it.
  Widget _content() {
    final onRefresh = widget.onRefresh;
    return NotificationListener<UserScrollNotification>(
      onNotification: _onUserScroll,
      child: RefreshIndicator(
        onRefresh: onRefresh ?? () async {},
        notificationPredicate: onRefresh == null
            ? (_) => false
            : defaultScrollNotificationPredicate,
        child: widget.body,
      ),
    );
  }

  /// Hosted, tells the hub which way the list is moving, so its FAB shows
  /// its icon only while the list scrolls down ([HubPrimaryActions.setCollapsed]).
  bool _onUserScroll(UserScrollNotification n) {
    final scope = _scope;
    if (scope == null || n.metrics.axis != Axis.vertical) return false;
    switch (n.direction) {
      case ScrollDirection.reverse:
        scope.actions.setCollapsed(scope.tab, true);
      case ScrollDirection.forward:
        scope.actions.setCollapsed(scope.tab, false);
      case ScrollDirection.idle:
        if (n.metrics.atEdge) scope.actions.setCollapsed(scope.tab, false);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final selection = widget.selection;
    if (_scope != null) {
      final controls =
          selection != null ? _selectionRow(selection) : _controls();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ?controls,
          ?widget.banner,
          Expanded(child: _content()),
        ],
      );
    }
    // On its own: the same controls and content under a heading and a small
    // app bar, so a tab reads the same pushed as hosted. While selecting, the app bar becomes
    // the selection bar, as a pushed list's does, and Back closes it first.
    return PopScope(
      canPop: selection == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) widget.selection?.onClose?.call();
      },
      // Pushed, the page says its title above its controls, where it wraps
      // (TO-12). The heading, the controls and the banner scroll away with
      // the list, so at large text they never leave it without room (or run
      // past the bottom of a small phone); the bar repeats the title once the
      // heading has gone.
      child: PageTitleScope(
        child: Scaffold(
          appBar: selection != null
              ? AppBar(
                  leading: IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: selection.closeTooltip,
                    onPressed: selection.onClose,
                  ),
                  title: Text(selection.title),
                  actions: selection.actions,
                )
              : AppBar(
                  title: PageBarTitle(widget.title),
                  actions: [
                    if (widget.menu.isNotEmpty)
                      _menuButton(context, () => widget.menu),
                  ],
                ),
          body: PageBody(
            child: NestedScrollView(
              headerSliverBuilder: (context, _) => [
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      PageHeader(title: widget.title),
                      if (selection == null) ?_controls(),
                      ?widget.banner,
                    ],
                  ),
                ),
              ],
              body: _content(),
            ),
          ),
          floatingActionButton:
              selection == null ? widget.primary?.toFab() : null,
        ),
      ),
    );
  }
}

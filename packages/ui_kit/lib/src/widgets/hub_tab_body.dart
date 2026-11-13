import 'package:flutter/material.dart';

import 'filter_bar.dart';

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
  Widget toFab({Object? heroTag, VoidCallback? onPressed}) =>
      FloatingActionButton.extended(
        key: fabKey,
        heroTag: heroTag,
        onPressed: this.onPressed == null ? null : (onPressed ?? this.onPressed),
        tooltip: tooltip,
        icon: Icon(icon),
        label: Text(label),
      );
}

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
/// as its one FAB, puts [actions] at the end of the control row, and wraps
/// [body] in a pull-to-refresh when [onRefresh] is given. Mounted on its own
/// (pushed where no hub is listening, or in a test) it builds the page a
/// pushed screen is: a small app bar titled [title] carrying [actions], and
/// [primary] as its FAB.
class HubTabBody extends StatefulWidget {
  const HubTabBody({
    super.key,
    required this.title,
    required this.body,
    this.filters,
    this.actions = const [],
    this.primary,
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
    return RefreshIndicator(
      onRefresh: onRefresh ?? () async {},
      notificationPredicate: onRefresh == null
          ? (_) => false
          : defaultScrollNotificationPredicate,
      child: widget.body,
    );
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
    // On its own: the same column under a small titled app bar, so a tab
    // reads the same pushed as hosted. While selecting, the app bar becomes
    // the selection bar, as a pushed list's does, and Back closes it first.
    return PopScope(
      canPop: selection == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) widget.selection?.onClose?.call();
      },
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
            : AppBar(title: Text(widget.title)),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (selection == null) ?_controls(),
            ?widget.banner,
            Expanded(child: _content()),
          ],
        ),
        floatingActionButton:
            selection == null ? widget.primary?.toFab() : null,
      ),
    );
  }
}

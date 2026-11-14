import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../motion.dart';
import '../theme/spacing.dart';
import 'toolbar_actions.dart';

/// Every page has a title (issue #1374): a large one in the body on a root
/// page ([PageHeader] at the top of Today and You), and on a pushed page a
/// small app bar whose title is never cut.
///
/// A toolbar leaves a title little room: 72 dp before it and 48 per action,
/// so on a 320 dp phone at 2x text a title with a back button and two actions
/// gets about seven characters before it is ellipsized ("Calendrier du plan
/// d'entraî…", TO-12). So a pushed page's title lives in its body, as a
/// [PageHeader] or a [DetailHero] that wraps, and the bar shows the same
/// words only once that heading has scrolled under it; by then they have
/// been read in full, and the bar is a reminder, not the only place the name
/// is said. A page with no heading in its body shows the title in the bar
/// from the start, which the worst-case harness fails once it is cut.
///
/// [PushedPage] is that page: the title rule, the toolbar budget
/// ([ToolbarActions], three slots counting the overflow, destructive and
/// Report actions only in the overflow), the bottom system inset, and a
/// [PushedPage.placeholder] form for loading and failed reads. [DetailPage]
/// is the same scaffold for an entity's page (a run, a route, a club), whose
/// body opens with a [DetailHero].
class PushedPage extends StatelessWidget {
  const PushedPage({
    super.key,
    required this.title,
    required Widget this.body,
    this.actions = const [],
    this.pinned = const [],
    this.moreTooltip,
    this.moreKey,
    this.busyLabel,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.bottomBar,
    this.safeBottom = true,
    this.resizeToAvoidBottomInset,
  }) : placeholder = null;

  /// The page while it has nothing to show yet: a skeleton, a failed read
  /// with its retry, a not-found state. [title] may be empty while the
  /// entity's name is unknown.
  const PushedPage.placeholder({
    super.key,
    this.title = '',
    required Widget child,
    this.actions = const [],
    this.pinned = const [],
    this.moreTooltip,
  })  : placeholder = child,
        moreKey = null,
        body = null,
        busyLabel = null,
        floatingActionButton = null,
        floatingActionButtonLocation = null,
        bottomBar = null,
        safeBottom = true,
        resizeToAvoidBottomInset = null;

  /// The page's name. The body says it in full; the bar repeats it once the
  /// body's heading has scrolled away.
  final String title;

  /// The page's content. It should hold one [PageHeader] or [DetailHero]
  /// near the top: that heading is what keeps the bar title off until it is
  /// needed.
  final Widget? body;

  final Widget? placeholder;

  /// Toolbar actions, most used first. At most two show beside the overflow
  /// (three when every action fits without one); a destructive action is
  /// always in the overflow.
  final List<AppBarAction> actions;

  /// Toolbar widgets that cannot fold into a menu (a share menu of its own).
  /// They count against the budget.
  final List<Widget> pinned;

  final String? moreTooltip;

  /// The overflow button's key, for a test to open the menu by.
  final Key? moreKey;

  /// While set, the overflow button is a spinner announced with this label.
  final String? busyLabel;

  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;

  /// A bar pinned under the body, which then owns the bottom inset.
  final Widget? bottomBar;

  /// Clear the system navigation bar under the body. A page whose body ends
  /// in a map or a pinned bar that handles the inset itself passes false.
  final bool safeBottom;

  final bool? resizeToAvoidBottomInset;

  @override
  Widget build(BuildContext context) {
    final placeholder = this.placeholder;
    final hasActions = actions.isNotEmpty || pinned.isNotEmpty;
    return PageTitleScope(
      child: Builder(
        builder: (context) => Scaffold(
          resizeToAvoidBottomInset: resizeToAvoidBottomInset,
          appBar: AppBar(
            title: PageBarTitle(title),
            actions: hasActions
                ? [
                    ToolbarActions(
                      actions: actions,
                      pinned: pinned,
                      moreTooltip: moreTooltip,
                      moreKey: moreKey,
                      busyLabel: busyLabel,
                    ),
                  ]
                : null,
          ),
          floatingActionButton: floatingActionButton,
          floatingActionButtonLocation: floatingActionButtonLocation,
          bottomNavigationBar: bottomBar,
          body: PageBody(
            child: SafeArea(
              top: false,
              bottom: placeholder != null || (safeBottom && bottomBar == null),
              child: placeholder ?? body!,
            ),
          ),
        ),
      ),
    );
  }
}

/// The page for one entity: a run, a route, a race, a park, a course, a club,
/// an event, a challenge, a profile, a plan.
///
/// The anatomy (issue #1374 report 5 § 5.5 C): a small app bar with at most
/// Share and Edit beside the overflow, Report and anything destructive inside
/// it; the body opens with an optional full-bleed map or image, then a
/// [DetailHero] (the name, a parent chip, the meta row and the one primary
/// action as its [HeroCta]); the rest are sections under `SectionHeader`s.
/// Only a club and a profile have tabs, through `CollapsingTabHost` with the
/// hero as its header.
///
/// A [PushedPage] in every other respect.
class DetailPage extends PushedPage {
  const DetailPage({
    super.key,
    required super.title,
    required super.body,
    super.actions,
    super.pinned,
    super.moreTooltip,
    super.moreKey,
    super.busyLabel,
    super.floatingActionButton,
    super.floatingActionButtonLocation,
    super.bottomBar,
    super.safeBottom,
    super.resizeToAvoidBottomInset,
  });

  const DetailPage.placeholder({
    super.key,
    super.title,
    required super.child,
    super.actions,
    super.pinned,
    super.moreTooltip,
  }) : super.placeholder();
}

/// The large title at the top of a page's body: a root page's name (Today,
/// You), or a pushed page's name above its content.
///
/// The title wraps rather than being cut, and is announced as a heading.
/// [actions] sit at its end (a root page's notification bell and overflow);
/// [leading] before it (an avatar).
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.actions = const [],
    this.padding = const EdgeInsets.fromLTRB(
      AppInsets.gutter,
      AppSpace.md,
      AppInsets.gutter,
      AppSpace.sm,
    ),
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> actions;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = this.subtitle;
    final leading = this.leading;
    return Padding(
      padding: padding,
      child: Row(
        children: [
          if (leading != null) ...[
            leading,
            const SizedBox(width: AppSpace.smPlus),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                PageHeading(title),
                if (subtitle != null) ...[
                  const SizedBox(height: AppSpace.xs),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

/// A page's name in its body: `headlineSmall`, wrapping, a heading to a
/// screen reader. Inside a [PushedPage] it is the heading whose scrolling
/// away brings the bar title in. [PageHeader] and [DetailHero] use it; a
/// page with a header of its own shape (a map's caption) can too.
class PageHeading extends StatefulWidget {
  const PageHeading(this.text, {super.key, this.style, this.maxLines});

  final String text;

  /// Defaults to `headlineSmall`.
  final TextStyle? style;

  /// Only for a name a person typed with no length limit (a display name),
  /// whose whole text a screen reader still gets. A localized title never
  /// sets it: those wrap in full.
  final int? maxLines;

  @override
  State<PageHeading> createState() => _PageHeadingState();
}

class _PageHeadingState extends State<PageHeading> {
  _PageTitleScopeState? _scope;
  GlobalKey? _key;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = PageTitleScope._of(context);
    if (!identical(scope, _scope)) {
      _scope?._release(this);
      _scope = scope;
      _key = scope?._claim(this);
    }
  }

  @override
  void dispose() {
    _scope?._release(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Text(
        key: _key,
        widget.text,
        maxLines: widget.maxLines,
        overflow: widget.maxLines == null ? null : TextOverflow.ellipsis,
        style: widget.style ?? Theme.of(context).textTheme.headlineSmall,
      ),
    );
  }
}

/// Tracks whether a page's in-body heading ([PageHeading]) is still in view,
/// for its bar title. [PushedPage] puts one around itself; a page that cannot
/// be a [PushedPage] yet can wrap its own `Scaffold` in one and use
/// [PageBarTitle] as the app bar title.
///
/// It listens to the scroll notifications that bubble out of the body, so
/// any scroll view works: a list, a `CustomScrollView`, a
/// `NestedScrollView` under tabs.
///
/// A page whose bar appears by a rule of its own passes [barTitleShown], and
/// the bar title follows that instead: a root page's header knows when its
/// heading has gone under its compact bar, which the heading's position
/// against the body's top edge cannot tell (`RootPage`).
class PageTitleScope extends StatefulWidget {
  const PageTitleScope({super.key, required this.child, this.barTitleShown});

  final Widget child;

  final ValueListenable<bool>? barTitleShown;

  static _PageTitleScopeState? _of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_PageTitleInherited>()
      ?.state;

  /// Whether the page around [context] says its title in the body, so a cut
  /// bar title is only a reminder of words already read in full. The
  /// worst-case layout harness reads it.
  static bool hasInBodyTitle(BuildContext context) =>
      context
          .getInheritedWidgetOfExactType<_PageTitleInherited>()
          ?.state
          ._everClaimed ??
      false;

  @override
  State<PageTitleScope> createState() => _PageTitleScopeState();
}

class _PageTitleScopeState extends State<PageTitleScope> {
  final GlobalKey _headingKey = GlobalKey(debugLabel: 'page heading');
  final GlobalKey _bodyKey = GlobalKey(debugLabel: 'page body');

  /// Whether the bar shows the title. Off until the first frame has had the
  /// chance to lay out a heading, so a page that has one never flashes its
  /// title in the bar on open.
  final ValueNotifier<bool> _showBarTitle = ValueNotifier(false);

  _PageHeadingState? _owner;
  bool _everClaimed = false;
  bool _scrolled = false;
  bool _queued = false;

  @override
  void initState() {
    super.initState();
    _queueMeasure();
  }

  @override
  void dispose() {
    _showBarTitle.dispose();
    super.dispose();
  }

  GlobalKey? _claim(_PageHeadingState heading) {
    // One heading per page; a second (a hero inside a tab) keeps its text
    // but is not the one measured.
    if (_owner != null && !identical(_owner, heading)) return null;
    _owner = heading;
    _everClaimed = true;
    _queueMeasure();
    return _headingKey;
  }

  void _release(_PageHeadingState heading) {
    if (identical(_owner, heading)) {
      _owner = null;
      _queueMeasure();
    }
  }

  // After the frame: a scroll notification arrives before the list has laid
  // out at its new offset, so measuring then would read the last frame.
  void _queueMeasure() {
    if (_queued) return;
    _queued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _queued = false;
      if (mounted) _measure();
    });
  }

  ValueListenable<bool> get _barTitle =>
      widget.barTitleShown ?? _showBarTitle;

  void _measure() {
    if (widget.barTitleShown != null) return;
    final heading = _headingKey.currentContext?.findRenderObject();
    final body = _bodyKey.currentContext?.findRenderObject();
    final bool show;
    if (!_everClaimed) {
      show = true;
    } else if (heading is RenderBox &&
        heading.attached &&
        heading.hasSize &&
        body is RenderBox &&
        body.attached) {
      final bottom =
          heading.localToGlobal(Offset(0, heading.size.height)).dy;
      show = bottom <= body.localToGlobal(Offset.zero).dy + 0.5;
    } else {
      // A lazy list has disposed a heading that scrolled far above the bar.
      show = _scrolled;
    }
    _showBarTitle.value = show;
  }

  bool _onScroll(ScrollNotification n) {
    if (n.metrics.axis == Axis.vertical) {
      _scrolled = n.metrics.pixels > n.metrics.minScrollExtent + 0.5;
      _queueMeasure();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return _PageTitleInherited(
      state: this,
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: widget.child,
      ),
    );
  }
}

class _PageTitleInherited extends InheritedWidget {
  const _PageTitleInherited({required this.state, required super.child});

  final _PageTitleScopeState state;

  @override
  bool updateShouldNotify(_PageTitleInherited old) => old.state != state;
}

/// Marks where the body starts, the edge a heading scrolls under. A page
/// that wraps its own `Scaffold` in a [PageTitleScope] puts its body in one.
class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scope = PageTitleScope._of(context);
    return KeyedSubtree(key: scope?._bodyKey, child: child);
  }
}

/// The app-bar title of a page inside a [PageTitleScope]: hidden (and silent
/// to a screen reader, which reads the heading instead) while the body's
/// heading is in view, faded in once it has scrolled under the bar.
class PageBarTitle extends StatelessWidget {
  const PageBarTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scope = PageTitleScope._of(context);
    if (scope == null) return Text(text);
    return ValueListenableBuilder<bool>(
      valueListenable: scope._barTitle,
      builder: (context, show, child) => ExcludeSemantics(
        excluding: !show,
        child: AnimatedOpacity(
          opacity: show ? 1 : 0,
          duration: motionDuration(context, AppMotion.brief),
          child: child,
        ),
      ),
      child: Text(text),
    );
  }
}

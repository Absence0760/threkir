import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../motion.dart';
import '../theme/spacing.dart';
import 'app_tab_bar.dart';
import 'pushed_page.dart';

/// A bottom-nav root page (Today, the Fitness hub, Social, You): every one
/// has a title, and it behaves the same on all four (issue #1374).
///
/// At rest the page says its name in a large, wrapping [PageHeader] directly
/// under the status bar, with the page's [actions] (Social's Messages and
/// bell, Today's overflow) at the end of that row, centred on it. There is no
/// bar above the title: an empty toolbar row there read as a gap
/// (decisions § 2517). As the content scrolls the heading goes up, the
/// actions travel with it until they reach the top band, and once the
/// heading has gone under that band a compact bar appears there saying the
/// same name ([PageBarTitle]), so the name is never lost and never cut while
/// it is the only place it is said. The actions are one set of widgets that
/// move, never two copies, so a screen reader meets them once and a stateful
/// action (the bell's unread count) is built once.
///
/// The header is a sliver in the page's scroll: it shrinks by exactly what
/// the content scrolls until it reaches the compact bar's height, then stays.
/// Nothing above the content changes height on its own, so the content never
/// jumps when the bar appears.
///
/// [RootPage.tabbed] is a hub: the header, then the tab strip, then the
/// tabs. The title scrolls away with the first scroll of any tab and the
/// strip pins under the compact bar, as a pushed `HubTabBody` does with its
/// controls. The collapse is shared by the tabs, so switching tab never moves
/// the strip, and each tab keeps its own scroll position. The bar title's
/// fade follows reduce-motion (`motionDuration`).
///
/// [RootPage.new] is a root whose body is one scroll view of its own (Today,
/// You), under the header. The body does not say the title again.
class RootPage extends StatefulWidget {
  const RootPage({
    super.key,
    required this.title,
    required Widget this.body,
    this.actions = const [],
    this.floatingActionButton,
    this.floatingActionButtonLocation,
  }) : controller = null,
       labels = const [],
       children = const [];

  const RootPage.tabbed({
    super.key,
    required this.title,
    required TabController this.controller,
    required this.labels,
    required this.children,
    this.actions = const [],
    this.floatingActionButton,
    this.floatingActionButtonLocation,
  }) : body = null;

  /// The bottom-nav label of this destination, said in full in the header.
  final String title;

  /// The page's actions: at the end of the title row at rest, in the compact
  /// bar once the title has scrolled away.
  final List<Widget> actions;

  /// The page's own scroll view, under the header.
  final Widget? body;

  final TabController? controller;

  /// Resolved tab labels, one per entry in [children].
  final List<String> labels;

  /// The tab bodies, in strip order.
  final List<Widget> children;

  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;

  @override
  State<RootPage> createState() => _RootPageState();
}

class _RootPageState extends State<RootPage> {
  /// Where the pinned header ends: the tab strip on a hub, the top of the
  /// body otherwise.
  final _edge = GlobalKey();

  /// Whether the compact bar is showing, as the header last laid out.
  final _barShown = ValueNotifier(false);

  @override
  void dispose() {
    _barShown.dispose();
    super.dispose();
  }

  void _onBarShown(bool shown) {
    if (mounted) _barShown.value = shown;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final barTheme = theme.appBarTheme;
    final controller = widget.controller;
    final title = widget.title;
    final actions = widget.actions;
    final restColor = _barColor(theme, scrolled: false);
    final barColor = _barColor(theme, scrolled: true);
    final toolbarHeight = barTheme.toolbarHeight ?? kToolbarHeight;
    final overlay = _overlayStyle(theme, restColor);
    final padding = EdgeInsets.fromLTRB(
      AppInsets.gutter,
      AppSpace.md,
      actions.isEmpty ? AppInsets.gutter : AppSpace.xs,
      AppSpace.sm,
    );

    final header = _RootHeader(
      padding: padding,
      collapsedExtent: toolbarHeight,
      textDirection: Directionality.of(context),
      onBarShown: _onBarShown,
      expanded: PageHeader(title: title, padding: padding),
      surface: Material(
        color: barColor,
        elevation: barTheme.scrolledUnderElevation ?? 3,
        shadowColor: barTheme.shadowColor,
        surfaceTintColor: Colors.transparent,
      ),
      bar: AppBar(
        primary: false,
        automaticallyImplyLeading: false,
        toolbarHeight: toolbarHeight,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        notificationPredicate: (_) => false,
        systemOverlayStyle: overlay,
        title: PageBarTitle(title),
      ),
      actions: Row(mainAxisSize: MainAxisSize.min, children: actions),
    );

    final Widget nestedBody;
    if (controller == null) {
      nestedBody = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(key: _edge),
          Expanded(child: widget.body!),
        ],
      );
    } else {
      nestedBody = Column(
        children: [
          KeyedSubtree(
            key: _edge,
            child: AppTabBar(controller: controller, labels: widget.labels),
          ),
          Expanded(
            // The key keeps the strip's page apart from the header's scroll
            // offset in PageStorage: with no key between them the two share
            // an identifier, and the pager restored the header's 0.0 as its
            // page, opening on the first tab whatever the controller said.
            child: KeyedSubtree(
              key: const PageStorageKey<String>('root-page-tabs'),
              child: TabBarView(
                controller: controller,
                children: widget.children,
              ),
            ),
          ),
        ],
      );
    }

    return PageTitleScope(
      barTitleShown: _barShown,
      child: Scaffold(
        floatingActionButton: widget.floatingActionButton,
        floatingActionButtonLocation: widget.floatingActionButtonLocation,
        body: AnnotatedRegion<SystemUiOverlayStyle>(
          value: overlay,
          child: Builder(
            builder: (context) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // The status bar keeps the colour of whatever is under it:
                // the page at rest, the compact bar once it shows.
                ValueListenableBuilder<bool>(
                  valueListenable: _barShown,
                  builder: (context, shown, _) => AnimatedContainer(
                    duration: motionDuration(context, AppMotion.brief),
                    height: MediaQuery.paddingOf(context).top,
                    color: shown ? barColor : restColor,
                  ),
                ),
                Expanded(
                  child: MediaQuery.removePadding(
                    context: context,
                    removeTop: true,
                    child: PinnedHeaderScope(
                      headerKey: _edge,
                      child: NestedScrollView(
                        headerSliverBuilder: (context, _) => [header],
                        body: nestedBody,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Color _barColor(ThemeData theme, {required bool scrolled}) {
  final color = theme.appBarTheme.backgroundColor;
  if (color == null) {
    return scrolled
        ? theme.colorScheme.surfaceContainer
        : theme.colorScheme.surface;
  }
  return WidgetStateProperty.resolveAs<Color>(
    color,
    {if (scrolled) WidgetState.scrolledUnder},
  );
}

/// What `AppBar` gives the status bar for a bar of [color].
SystemUiOverlayStyle _overlayStyle(ThemeData theme, Color color) {
  final themed = theme.appBarTheme.systemOverlayStyle;
  if (themed != null) return themed;
  final style = ThemeData.estimateBrightnessForColor(color) == Brightness.dark
      ? SystemUiOverlayStyle.light
      : SystemUiOverlayStyle.dark;
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarBrightness: style.statusBarBrightness,
    statusBarIconBrightness: style.statusBarIconBrightness,
    systemStatusBarContrastEnforced: style.systemStatusBarContrastEnforced,
  );
}

enum _Slot { expanded, surface, bar, actions }

/// The root page's header sliver: the title row at rest, shrinking with the
/// scroll to the compact bar's height. It measures the title row as it lays
/// out, so a title that wraps at a large text size still collapses by
/// exactly its own height.
class _RootHeader extends SlottedMultiChildRenderObjectWidget<_Slot, RenderBox> {
  const _RootHeader({
    required this.padding,
    required this.collapsedExtent,
    required this.textDirection,
    required this.onBarShown,
    required this.expanded,
    required this.surface,
    required this.bar,
    required this.actions,
  });

  /// The [PageHeader]'s padding, whose top and bottom frame the title row.
  final EdgeInsets padding;
  final double collapsedExtent;
  final TextDirection textDirection;
  final ValueChanged<bool> onBarShown;
  final Widget expanded;
  final Widget surface;
  final Widget bar;
  final Widget actions;

  @override
  Iterable<_Slot> get slots => _Slot.values;

  @override
  Widget childForSlot(_Slot slot) => switch (slot) {
        _Slot.expanded => expanded,
        _Slot.surface => surface,
        _Slot.bar => bar,
        _Slot.actions => actions,
      };

  @override
  _RenderRootHeader createRenderObject(BuildContext context) =>
      _RenderRootHeader(
        padding: padding,
        collapsedExtent: collapsedExtent,
        textDirection: textDirection,
        onBarShown: onBarShown,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderRootHeader renderObject,
  ) {
    renderObject
      ..padding = padding
      ..collapsedExtent = collapsedExtent
      ..textDirection = textDirection
      ..onBarShown = onBarShown;
  }
}

class _RenderRootHeader extends RenderSliver
    with SlottedContainerRenderObjectMixin<_Slot, RenderBox> {
  _RenderRootHeader({
    required EdgeInsets padding,
    required double collapsedExtent,
    required TextDirection textDirection,
    required this.onBarShown,
  })  : _padding = padding,
        _collapsedExtent = collapsedExtent,
        _textDirection = textDirection;

  EdgeInsets get padding => _padding;
  EdgeInsets _padding;
  set padding(EdgeInsets value) {
    if (value == _padding) return;
    _padding = value;
    markNeedsLayout();
  }

  double get collapsedExtent => _collapsedExtent;
  double _collapsedExtent;
  set collapsedExtent(double value) {
    if (value == _collapsedExtent) return;
    _collapsedExtent = value;
    markNeedsLayout();
  }

  TextDirection get textDirection => _textDirection;
  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (value == _textDirection) return;
    _textDirection = value;
    markNeedsLayout();
  }

  ValueChanged<bool> onBarShown;

  bool _barShown = false;

  RenderBox get _expanded => childForSlot(_Slot.expanded)!;
  RenderBox get _surface => childForSlot(_Slot.surface)!;
  RenderBox get _bar => childForSlot(_Slot.bar)!;
  RenderBox get _actions => childForSlot(_Slot.actions)!;

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! BoxParentData) {
      child.parentData = BoxParentData();
    }
  }

  static Offset _offsetOf(RenderBox child) =>
      (child.parentData! as BoxParentData).offset;

  static void _place(RenderBox child, Offset offset) =>
      (child.parentData! as BoxParentData).offset = offset;

  @override
  void performLayout() {
    final constraints = this.constraints;
    assert(constraints.axisDirection == AxisDirection.down);
    final width = constraints.crossAxisExtent;
    final rtl = textDirection == TextDirection.rtl;

    _actions.layout(BoxConstraints(maxWidth: width), parentUsesSize: true);
    final actionsSize = _actions.size;
    final side = math.max(0.0, width - actionsSize.width);
    _expanded.layout(BoxConstraints.tightFor(width: side), parentUsesSize: true);
    final heading = math.max(
      0.0,
      _expanded.size.height - padding.top - padding.bottom,
    );
    final row = math.max(heading, actionsSize.height);
    final full = padding.top + row + padding.bottom;
    final collapsed = math.min(collapsedExtent, full);
    final maxShrink = full - collapsed;
    final shrink = clampDouble(constraints.scrollOffset, 0, maxShrink);
    final extent = full - shrink;

    // The compact bar comes in once the heading has gone under its band, so
    // the name is never in both places, nor in neither.
    final headingTop = padding.top + (row - heading) / 2 - shrink;
    final barShown = maxShrink > 0 &&
        headingTop < 0 &&
        headingTop + heading <= collapsed + precisionErrorTolerance;

    final barSize = Size(width, collapsedExtent);
    _surface.layout(BoxConstraints.tight(barSize));
    _bar.layout(
      BoxConstraints.tight(Size(side, collapsedExtent)),
      parentUsesSize: true,
    );

    final lead = rtl ? actionsSize.width : 0.0;
    _place(_expanded, Offset(lead, (row - heading) / 2 - shrink));
    _place(_surface, Offset.zero);
    _place(_bar, Offset(lead, 0));
    final actionsCentre = math.max(
      collapsed / 2,
      padding.top + row / 2 - shrink,
    );
    _place(
      _actions,
      Offset(
        rtl ? 0 : width - actionsSize.width,
        actionsCentre - actionsSize.height / 2,
      ),
    );

    final paintExtent = math.min(extent, constraints.remainingPaintExtent);
    geometry = SliverGeometry(
      scrollExtent: maxShrink,
      paintExtent: paintExtent,
      layoutExtent: paintExtent,
      maxPaintExtent: full,
      maxScrollObstructionExtent: collapsed,
      cacheExtent: math.min(extent, constraints.remainingCacheExtent),
      hasVisualOverflow: true,
    );

    if (barShown != _barShown) {
      _barShown = barShown;
      markNeedsSemanticsUpdate();
      final notify = onBarShown;
      SchedulerBinding.instance.addPostFrameCallback((_) => notify(barShown));
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (!geometry!.visible) return;
    void paintChild(RenderBox child) =>
        context.paintChild(child, offset + _offsetOf(child));
    paintChild(_expanded);
    if (_barShown) {
      paintChild(_surface);
      paintChild(_bar);
    }
    paintChild(_actions);
  }

  @override
  bool hitTestChildren(
    SliverHitTestResult result, {
    required double mainAxisPosition,
    required double crossAxisPosition,
  }) {
    final boxResult = BoxHitTestResult.wrap(result);
    final position = Offset(crossAxisPosition, mainAxisPosition);
    bool hit(RenderBox child) => boxResult.addWithPaintOffset(
          offset: _offsetOf(child),
          position: position,
          hitTest: (result, local) => child.hitTest(result, position: local),
        );
    if (hit(_actions)) return true;
    if (_barShown) return hit(_bar) || hit(_surface);
    return hit(_expanded);
  }

  @override
  double childMainAxisPosition(covariant RenderBox child) => _offsetOf(child).dy;

  @override
  double childCrossAxisPosition(covariant RenderBox child) => _offsetOf(child).dx;

  @override
  void applyPaintTransform(covariant RenderBox child, Matrix4 transform) {
    final offset = _offsetOf(child);
    transform.translateByDouble(offset.dx, offset.dy, 0, 1);
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    if (_barShown) {
      visitor(_bar);
    } else {
      visitor(_expanded);
    }
    visitor(_actions);
  }
}

/// Where a page's pinned header ends, for an overlay that must not cover it.
///
/// A root page's title row, and a hub's tab strip under it, are not an app
/// bar, so an overlay that measured app bars alone covered them (issue
/// #1374). [RootPage] marks the widget whose bottom edge is the bottom of its
/// header with this; the app's top banner finds every one that is on screen
/// and starts below it. The four roots stay alive side by side in the shell,
/// so the banner measures only a header that is painted, never a hidden
/// root's.
class PinnedHeaderScope extends StatelessWidget {
  const PinnedHeaderScope({
    super.key,
    required this.headerKey,
    required this.child,
  });

  /// The widget whose bottom edge is the bottom of the pinned header.
  final GlobalKey headerKey;

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

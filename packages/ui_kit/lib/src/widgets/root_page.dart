import 'package:flutter/material.dart';

import 'app_tab_bar.dart';
import 'pushed_page.dart';

/// A bottom-nav root page (Today, the Fitness hub, Social, You): every one
/// has a title, and it behaves the same on all four (issue #1374).
///
/// At rest the page says its name in a large, wrapping [PageHeader] at the
/// top of its scroll. As the content scrolls the heading goes up under a slim
/// app bar, which then shows the same name ([PageBarTitle]), so the name is
/// never lost and never cut while it is the only place it is said. The bar
/// holds the page's [actions] (Social's Messages and bell, Today's bell and
/// overflow) at every scroll position, so they stay one tap away.
///
/// [RootPage.tabbed] is a hub: the large title, then the tab strip, then the
/// tabs. The title scrolls away with the first scroll of any tab and the
/// strip pins under the bar, as a pushed `HubTabBody` does with its
/// controls. The collapse is shared by the tabs, so switching tab never moves
/// the strip, and each tab keeps its own scroll position. The bar title's
/// fade follows reduce-motion (`motionDuration`).
///
/// [RootPage.new] is a root whose body is one scroll view of its own (Today,
/// You): the body opens with the [PageHeader] itself, under this bar.
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

  /// The bottom-nav label of this destination, said in full in the body.
  final String title;

  /// The page's actions, in the bar at every scroll position.
  final List<Widget> actions;

  /// The page's own scroll view, which opens with a [PageHeader] of [title].
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
  /// The tab strip, which is where a hub's pinned header ends.
  final _strip = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final title = widget.title;
    final actions = widget.actions;
    final body = widget.body;
    final labels = widget.labels;
    final children = widget.children;
    return PageTitleScope(
      child: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: PageBarTitle(title),
            actions: actions.isEmpty ? null : actions,
          ),
          floatingActionButton: widget.floatingActionButton,
          floatingActionButtonLocation: widget.floatingActionButtonLocation,
          body: PageBody(
            child: controller == null
                ? body!
                : PinnedHeaderScope(
                    headerKey: _strip,
                    child: NestedScrollView(
                      headerSliverBuilder: (context, _) => [
                        SliverToBoxAdapter(child: PageHeader(title: title)),
                      ],
                      body: Column(
                        children: [
                          KeyedSubtree(
                            key: _strip,
                            child: AppTabBar(
                              controller: controller,
                              labels: labels,
                            ),
                          ),
                          Expanded(
                            // The key keeps the strip's page apart from the
                            // header's scroll offset in PageStorage: with no
                            // key between them the two share an identifier,
                            // and the pager restored the header's 0.0 as its
                            // page, opening on the first tab whatever the
                            // controller said.
                            child: KeyedSubtree(
                              key: const PageStorageKey<String>(
                                'root-page-tabs',
                              ),
                              child: TabBarView(
                                controller: controller,
                                children: children,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// Where a page's pinned header ends, for an overlay that must not cover it.
///
/// A hub's tab strip sits under the large title and then pins under the app
/// bar, so it is not part of the app bar an overlay measures. A top banner
/// placed under the bar alone covered the strip at 2x text (issue #1374).
/// [RootPage.tabbed] puts the strip under this scope; the app's top banner
/// reads [headerKeyOf] from the calling context and starts below the strip
/// wherever it is when the banner is shown.
class PinnedHeaderScope extends InheritedWidget {
  const PinnedHeaderScope({
    super.key,
    required this.headerKey,
    required super.child,
  });

  /// The widget whose bottom edge is the bottom of the pinned header.
  final GlobalKey headerKey;

  /// The pinned header's key for [context], or null on a page without one.
  /// Reads without depending: a banner measures once, when it is shown.
  static GlobalKey? headerKeyOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<PinnedHeaderScope>()?.headerKey;

  @override
  bool updateShouldNotify(PinnedHeaderScope oldWidget) =>
      headerKey != oldWidget.headerKey;
}

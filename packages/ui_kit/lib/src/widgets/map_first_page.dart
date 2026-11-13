import 'package:flutter/material.dart';

import '../theme/corner_radii.dart';
import '../theme/spacing.dart';
import 'sheet_scaffold.dart' show systemBottomInset;

/// The draggable sheet of a [MapFirstPage]: a list over the bottom of the
/// map, from a peek of [minSize] up to [maxSize] of the map's height.
///
/// [slivers] are the sheet's content. The page puts a drag handle above them
/// and the system inset below them, and keeps each one clear of a side nav
/// bar or cutout, so a sliver only lays out its own rows.
@immutable
class MapFirstSheet {
  const MapFirstSheet({
    required this.slivers,
    this.controller,
    this.initialSize = 0.4,
    this.minSize = 0.15,
    this.maxSize = 0.85,
    this.snapSizes,
    this.onScroll,
  }) : assert(minSize <= initialSize && initialSize <= maxSize),
       // The map keeps a band at the top even with the sheet raised, where
       // its credit and the page's top overlays stay readable.
       assert(maxSize < 1);

  final List<Widget> slivers;
  final DraggableScrollableController? controller;
  final double initialSize;
  final double minSize;
  final double maxSize;

  /// Resting sizes between [minSize] and [maxSize]; the sheet snaps to the
  /// nearest when released. Null lets it rest anywhere.
  final List<double>? snapSizes;

  /// Every scroll notification from the sheet's list, for a page that loads
  /// more as the list nears its end.
  final bool Function(ScrollNotification notification)? onScroll;
}

/// The map-first page (issue #1374 report 5, archetype F): a full-bleed map
/// with controls floating over it, and either a pinned panel below it or a
/// draggable sheet over its bottom.
///
/// The page owns every inset, so no screen places bottom content by hand
/// (decisions § 2485 for sheets): the floating column stands on the system
/// nav bar when nothing is below the map, on the [panel] when there is one,
/// and rides the [sheet]'s top edge as it is dragged. The [panel] and the
/// sheet's content end above the 3-button bar, and everything but the map
/// stays clear of a side nav bar or cutout in landscape (IK-10), while the
/// map itself runs edge to edge. A screen that hand-placed a
/// `Positioned(bottom: 0)` drew its stats under the bar (IK-5), and a
/// Scaffold FAB over a page with a footer covered the footer's button
/// (IK-3); here a map control can only go in [controls], which sits above
/// whatever the bottom holds.
///
/// With an [appBar] it is a pushed page with its own `Scaffold`. Without one
/// it is hosted (a hub tab's view), draws no `Scaffold` of its own, and the
/// host passes what of the bottom it covers as [bottomClearance] (the shell's
/// docked centre button). Inside a horizontally swiping host the map keeps
/// the drags that start on it, and the host swipes from everywhere else: the
/// map widget claims them (flutter_map's own horizontal drag recogniser, a
/// leaf of the hit test, wins the arena before the host's page view does).
class MapFirstPage extends StatefulWidget {
  const MapFirstPage({
    super.key,
    required this.map,
    this.appBar,
    this.header,
    this.overlays = const [],
    this.controls = const [],
    this.footer,
    this.attribution,
    this.panel,
    this.panelColor,
    this.sheet,
    this.bottomClearance = 0,
    this.maxPanelFraction = 0.6,
  }) : assert(panel == null || sheet == null,
           'a map-first page has a pinned panel or a sheet, not both');

  /// The map, edge to edge under everything else.
  final Widget map;

  /// A pushed page's app bar. Null when hosted.
  final PreferredSizeWidget? appBar;

  /// Solid controls above the map (a hint, a search field, a slider).
  /// Scrolls when it outgrows its share of the page, as [panel] does.
  final Widget? header;

  /// Laid over the top of the map, full width, later ones on top: a status
  /// pill, a search-results dropdown. Each brings its own padding.
  final List<Widget> overlays;

  /// The map's own buttons (Locate me, layers), stacked at the end edge
  /// above [footer].
  final List<Widget> controls;

  /// A full-width row floating at the map's bottom, under [controls]: a mode
  /// selector, a results pill, a selected item's card.
  final Widget? footer;

  /// The map's credit, closing the floating column so nothing covers it.
  final Widget? attribution;

  /// Pinned below the map, never over it: live stats, a count and its
  /// action. Scrolls when it outgrows its share of the page.
  final Widget? panel;

  /// The panel's surface. Defaults to `surfaceContainerHighest`.
  final Color? panelColor;

  final MapFirstSheet? sheet;

  /// Height the host covers at the bottom of a hosted page.
  final double bottomClearance;

  /// The most of the page the [header] and the [panel] take together, so the
  /// map keeps the rest at any text size. With both, each gets half.
  final double maxPanelFraction;

  @override
  State<MapFirstPage> createState() => _MapFirstPageState();
}

/// Above this share of the map, the sheet has the page and the floating
/// controls step aside rather than ride into the top band.
const double _kControlsRideLimit = 0.6;

class _MapFirstPageState extends State<MapFirstPage> {
  late final ValueNotifier<double> _extent =
      ValueNotifier(widget.sheet?.initialSize ?? 0);

  @override
  void didUpdateWidget(MapFirstPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sheet == null && widget.sheet != null) {
      _extent.value = widget.sheet!.initialSize;
    }
  }

  @override
  void dispose() {
    _extent.dispose();
    super.dispose();
  }

  static Widget _sides(Widget child) =>
      SafeArea(top: false, bottom: false, child: child);

  Widget _floating({required bool showControls}) {
    final controls = widget.controls;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (controls.isNotEmpty)
          IgnorePointer(
            ignoring: !showControls,
            child: AnimatedOpacity(
              opacity: showControls ? 1 : 0,
              duration: const Duration(milliseconds: 150),
              child: Padding(
                padding: const EdgeInsetsDirectional.only(
                    end: AppInsets.gutter, bottom: AppSpace.sm),
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Column(
                    key: const ValueKey('map-first-controls'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < controls.length; i++) ...[
                        if (i > 0) const SizedBox(height: AppSpace.sm),
                        controls[i],
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        if (widget.footer case final footer?)
          IgnorePointer(
            ignoring: !showControls,
            child: AnimatedOpacity(
              opacity: showControls ? 1 : 0,
              duration: const Duration(milliseconds: 150),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppInsets.gutter, 0, AppInsets.gutter, AppSpace.sm),
                child: footer,
              ),
            ),
          ),
        ?widget.attribution,
      ],
    );
  }

  Widget _mapArea(BuildContext context) {
    final sheet = widget.sheet;
    final standsOnSystemBar = widget.panel == null && sheet == null;
    return LayoutBuilder(builder: (context, box) {
      final height = box.maxHeight;
      return Stack(
        fit: StackFit.expand,
        children: [
          widget.map,
          if (sheet == null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                top: false,
                bottom: standsOnSystemBar,
                child: Padding(
                  padding: EdgeInsets.only(
                      bottom: standsOnSystemBar ? widget.bottomClearance : 0),
                  child: _floating(showControls: true),
                ),
              ),
            )
          else
            ValueListenableBuilder<double>(
              valueListenable: _extent,
              builder: (context, extent, child) => Positioned(
                left: 0,
                right: 0,
                bottom: extent * height,
                child: _sides(
                    _floating(showControls: extent <= _kControlsRideLimit)),
              ),
            ),
          for (final overlay in widget.overlays)
            Positioned(top: 0, left: 0, right: 0, child: _sides(overlay)),
          if (sheet != null) _sheet(context, sheet),
        ],
      );
    });
  }

  Widget _sheet(BuildContext context, MapFirstSheet sheet) {
    final theme = Theme.of(context);
    final sheetTheme = theme.bottomSheetTheme;
    final bottom = systemBottomInset(context) + widget.bottomClearance;
    return NotificationListener<DraggableScrollableNotification>(
      onNotification: (n) {
        _extent.value = n.extent;
        return false;
      },
      child: DraggableScrollableSheet(
        key: const ValueKey('map-first-sheet'),
        controller: sheet.controller,
        initialChildSize: sheet.initialSize,
        minChildSize: sheet.minSize,
        maxChildSize: sheet.maxSize,
        snap: sheet.snapSizes != null,
        snapSizes: sheet.snapSizes,
        builder: (context, scroll) => Material(
          color: sheetTheme.backgroundColor ?? theme.colorScheme.surface,
          elevation: 3,
          shape: sheetTheme.shape ??
              const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(
                      top: Radius.circular(AppRadius.xl))),
          clipBehavior: Clip.antiAlias,
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) => sheet.onScroll?.call(n) ?? false,
            child: CustomScrollView(
              controller: scroll,
              slivers: [
                SliverToBoxAdapter(
                  child: ExcludeSemantics(
                    child: Center(
                      child: Container(
                        width: 32,
                        height: 4,
                        margin: const EdgeInsets.symmetric(
                            vertical: AppSpace.smPlus),
                        decoration: BoxDecoration(
                          color: sheetTheme.dragHandleColor ??
                              theme.colorScheme.outline,
                          borderRadius:
                              BorderRadius.circular(AppRadius.pill),
                        ),
                      ),
                    ),
                  ),
                ),
                for (final sliver in sheet.slivers)
                  SliverSafeArea(
                      top: false, bottom: false, sliver: sliver),
                SliverToBoxAdapter(child: SizedBox(height: bottom)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  double _bandMax(double pageHeight) =>
      pageHeight *
      widget.maxPanelFraction /
      (widget.header != null && widget.panel != null ? 2 : 1);

  Widget _header(Widget header, double pageHeight) => ConstrainedBox(
        key: const ValueKey('map-first-header'),
        constraints: BoxConstraints(maxHeight: _bandMax(pageHeight)),
        child: SingleChildScrollView(child: _sides(header)),
      );

  Widget _panel(BuildContext context, double pageHeight) {
    final theme = Theme.of(context);
    return Material(
      key: const ValueKey('map-first-panel'),
      color: widget.panelColor ?? theme.colorScheme.surfaceContainerHighest,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: _bandMax(pageHeight)),
        child: SingleChildScrollView(
          child: SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.only(bottom: widget.bottomClearance),
              child: widget.panel,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = LayoutBuilder(
      builder: (context, box) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.header case final header?)
            _header(header, box.maxHeight),
          Expanded(child: _mapArea(context)),
          if (widget.panel != null) _panel(context, box.maxHeight),
        ],
      ),
    );
    final appBar = widget.appBar;
    if (appBar == null) return body;
    return Scaffold(appBar: appBar, body: body);
  }
}

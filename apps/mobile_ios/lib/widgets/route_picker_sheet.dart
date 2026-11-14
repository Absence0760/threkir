import 'package:core_models/core_models.dart' as cm;
import 'package:core_models/core_models.dart' show DistanceUnit;
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart'
    show AppSearchField, AppSemanticColors, SectionHeader, SheetScaffold;

import '../l10n/gen/app_localizations.dart';
import '../preferences.dart';

/// The runner's answer from [pickRoute]. "No route" is an answer of its own,
/// so a caller can clear its selection on it and leave the selection alone on
/// a cancel, which [pickRoute] reports as `null`.
sealed class RoutePick {
  const RoutePick();
}

final class RoutePicked extends RoutePick {
  final cm.Route route;
  const RoutePicked(this.route);
}

final class NoRoutePicked extends RoutePick {
  const NoRoutePicked();
}

/// Opens the route picker sheet, the one picker every "choose a route" opens
/// (the Run tab's options, the runner menu's All routes, a past run's route).
/// [selected] is marked the way the Guided run sheet marks its choice.
/// [offerNoRoute] is false where clearing has nothing to clear: the runner
/// menu opens it only to start a run on a route.
///
/// Resolves the runner's [RoutePick], or `null` when they close the sheet
/// without choosing.
Future<RoutePick?> pickRoute(
  BuildContext context, {
  required List<cm.Route> routes,
  required DistanceUnit unit,
  cm.Route? selected,
  bool offerNoRoute = true,
}) {
  return showModalBottomSheet<RoutePick>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => RoutePickerSheet(
      routes: routes,
      unit: unit,
      selected: selected,
      offerNoRoute: offerNoRoute,
    ),
  );
}

class RoutePickerSheet extends StatefulWidget {
  final List<cm.Route> routes;
  final DistanceUnit unit;
  final cm.Route? selected;
  final bool offerNoRoute;

  const RoutePickerSheet({
    super.key,
    required this.routes,
    required this.unit,
    this.selected,
    this.offerNoRoute = true,
  });

  @override
  State<RoutePickerSheet> createState() => _RoutePickerSheetState();
}

/// The radio value of the "No route" row; a route id is never empty.
const _noRoute = '';

class _RoutePickerSheetState extends State<RoutePickerSheet> {
  final _searchCtl = TextEditingController();

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  /// Starred first, then by name, case-insensitively; filtered by a name
  /// substring while searching.
  List<cm.Route> _filteredAndSorted(String term) {
    final filtered = term.isEmpty
        ? List<cm.Route>.from(widget.routes)
        : widget.routes
              .where((r) => r.name.toLowerCase().contains(term))
              .toList();
    filtered.sort((a, b) {
      if (a.isStarred != b.isStarred) return a.isStarred ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return filtered;
  }

  void _choose(String? value) {
    if (value == null) return;
    if (value == _noRoute) {
      Navigator.pop<RoutePick>(context, const NoRoutePicked());
      return;
    }
    final route = widget.routes.firstWhere((r) => r.id == value);
    Navigator.pop<RoutePick>(context, RoutePicked(route));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final query = _searchCtl.text.trim();
    final routes = _filteredAndSorted(query.toLowerCase());
    final sectioned = query.isEmpty && routes.any((r) => r.isStarred);
    final starred = [if (sectioned) ...routes.where((r) => r.isStarred)];
    final rest = [...routes.where((r) => !sectioned || !r.isStarred)];
    final selectedId =
        widget.selected?.id ?? (widget.offerNoRoute ? _noRoute : null);

    Widget header(IconData icon, String label, {Color? color}) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: SectionHeader(icon: icon, label: label, iconColor: color),
    );

    return RadioGroup<String>(
      groupValue: selectedId,
      onChanged: _choose,
      child: SheetScaffold.expanding(
        padding: EdgeInsets.zero,
        title: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(l10n.routePickerTitle),
        ),
        pinned: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: AppSearchField(
            key: const ValueKey('route-picker-search'),
            controller: _searchCtl,
            hint: l10n.routePickerSearchHint,
            clearTooltip: l10n.commonClearSearch,
            onChanged: (_) => setState(() {}),
          ),
        ),
        slivers: [
          SliverList.list(
            children: [
              if (widget.offerNoRoute)
                RadioListTile<String>(
                  key: const ValueKey('route-picker-no-route'),
                  value: _noRoute,
                  title: Text(l10n.routePickerNoRoute),
                ),
              if (sectioned)
                header(
                  Icons.star,
                  l10n.routePickerStarredHeader,
                  color: AppSemanticColors.of(context).crown,
                ),
              for (final r in starred) _RouteTile(route: r, unit: widget.unit),
              if (sectioned && rest.isNotEmpty)
                header(Icons.route, l10n.routePickerAllRoutesHeader),
              for (final r in rest) _RouteTile(route: r, unit: widget.unit),
            ],
          ),
          if (routes.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Text(
                    query.isEmpty
                        ? l10n.routePickerEmptyNoRoutes
                        : l10n.routePickerEmptyNoMatch(query),
                    key: const ValueKey('route-picker-empty'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RouteTile extends StatelessWidget {
  final cm.Route route;
  final DistanceUnit unit;
  const _RouteTile({required this.route, required this.unit});

  @override
  Widget build(BuildContext context) {
    return RadioListTile<String>(
      key: ValueKey('route-picker-route-${route.id}'),
      value: route.id,
      title: Text(route.name, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(UnitFormat.distance(route.distanceMetres, unit)),
      secondary: route.isStarred
          ? Icon(Icons.star, color: AppSemanticColors.of(context).crown)
          : null,
    );
  }
}

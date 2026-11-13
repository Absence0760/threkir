import 'package:flutter/material.dart';

import '../theme/spacing.dart';
import 'sheet_scaffold.dart';

/// The one search field: a search glyph, the hint, and a clear button while
/// there is text. Every list's search is this widget, so clear is always
/// there and always in the same place (issue #1374: 11 of 20 hand-built
/// search fields had none).
///
/// Strings come from the caller because ui_kit has no catalogue.
class AppSearchField extends StatefulWidget {
  const AppSearchField({
    super.key,
    required this.controller,
    required this.hint,
    required this.clearTooltip,
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String hint;

  /// The clear button's tooltip and screen-reader label.
  final String clearTooltip;

  /// Also called with `''` when the clear button empties the field.
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  State<AppSearchField> createState() => _AppSearchFieldState();
}

class _AppSearchFieldState extends State<AppSearchField> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onText);
  }

  @override
  void didUpdateWidget(AppSearchField old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onText);
      widget.controller.addListener(_onText);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onText);
    super.dispose();
  }

  void _onText() {
    if (mounted) setState(() {});
  }

  void _clear() {
    widget.controller.clear();
    widget.onChanged?.call('');
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      textInputAction: TextInputAction.search,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search),
        hintText: widget.hint,
        isDense: true,
        suffixIcon: widget.controller.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close),
                tooltip: widget.clearTooltip,
                onPressed: _clear,
              ),
      ),
    );
  }
}

/// A filter that is on, shown as a removable chip in [FilterBar]'s line so
/// clearing it is one tap.
@immutable
class ActiveFilter {
  const ActiveFilter({
    required this.label,
    required this.onRemove,
    required this.removeTooltip,
  });

  final String label;
  final VoidCallback onRemove;

  /// The delete button's tooltip, e.g. "Remove filter: 5K".
  final String removeTooltip;
}

/// The control row of a list: at most one search field, at most one line of
/// quick chips that scrolls sideways and never wraps, and a Filters button
/// with the active count that opens the sheet holding everything else, whose
/// active filters show as removable chips on the same line.
///
/// The chips only filter; a chip that opened another screen would look like
/// a filter and navigate (issue #1374 report 2, rule 4).
///
/// The Filters button sits beside the search when there is one, and
/// otherwise leads the chip line inside its scroll.
class FilterBar extends StatelessWidget {
  const FilterBar({
    super.key,
    this.search,
    this.trailing = const [],
    this.chips = const [],
    this.chipsLabel,
    this.activeFilters = const [],
    this.filtersLabel,
    this.filtersSemanticLabel,
    this.activeFilterCount = 0,
    this.onOpenFilters,
    this.padding = const EdgeInsets.fromLTRB(
        AppInsets.gutter, AppSpace.sm, AppInsets.gutter, AppSpace.xs),
  }) : assert((filtersLabel == null) == (onOpenFilters == null),
            'filtersLabel and onOpenFilters must be provided together');

  /// Usually an [AppSearchField].
  final Widget? search;

  /// Actions at the end of the bar's first row, after the search: a sort
  /// menu, a labelled secondary action, the tab's overflow. Always a row of
  /// their own rather than the chip line's end, where a labelled button at 2x
  /// text left the chips no room.
  final List<Widget> trailing;

  /// Names the chip line as a group for a screen reader, e.g. "Filter plans
  /// by status".
  final String? chipsLabel;

  /// The screen's most-used filter, as chips. [buildChoiceChip] lays a
  /// single-select set out the way `ChoiceChipRow` does.
  final List<Widget> chips;

  final List<ActiveFilter> activeFilters;

  /// The Filters button's text, shown with a badge carrying
  /// [activeFilterCount].
  final String? filtersLabel;

  /// What a screen reader hears for the Filters button, e.g. "Filters, 2
  /// active". Falls back to [filtersLabel].
  final String? filtersSemanticLabel;
  final int activeFilterCount;
  final VoidCallback? onOpenFilters;
  final EdgeInsets padding;

  /// This bar with [extra] appended to its [trailing], for a host that adds
  /// its own actions to the row.
  FilterBar withTrailing(List<Widget> extra) => extra.isEmpty
      ? this
      : FilterBar(
          key: key,
          search: search,
          trailing: [...trailing, ...extra],
          chips: chips,
          chipsLabel: chipsLabel,
          activeFilters: activeFilters,
          filtersLabel: filtersLabel,
          filtersSemanticLabel: filtersSemanticLabel,
          activeFilterCount: activeFilterCount,
          onOpenFilters: onOpenFilters,
          padding: padding,
        );

  /// An icon button carrying the count as a badge, named by its tooltip and
  /// its semantics label. Icon-only so it never squeezes the search: as a
  /// labelled button it took 177 dp at 1.3x text and pushed the row past a
  /// 360 dp screen.
  Widget _filtersButton() => Semantics(
        button: true,
        label: filtersSemanticLabel ?? filtersLabel,
        excludeSemantics: true,
        child: IconButton(
          key: const Key('filter-bar-filters'),
          tooltip: filtersLabel,
          onPressed: onOpenFilters,
          isSelected: activeFilterCount > 0,
          icon: Badge(
            isLabelVisible: activeFilterCount > 0,
            label: Text('$activeFilterCount'),
            child: const Icon(Icons.tune),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final hasFilters = onOpenFilters != null;
    final filtersBesideSearch = hasFilters && search != null;
    final hasLine = (hasFilters && !filtersBesideSearch) ||
        chips.isNotEmpty ||
        activeFilters.isNotEmpty;
    final hasTop = search != null || trailing.isNotEmpty;
    Widget spaced(Widget child) => Padding(
          padding: const EdgeInsetsDirectional.only(end: AppSpace.sm),
          child: child,
        );
    final line = SingleChildScrollView(
      key: const Key('filter-bar-chips'),
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          if (hasFilters && !filtersBesideSearch) spaced(_filtersButton()),
          for (final chip in chips) spaced(chip),
          for (final f in activeFilters)
            spaced(InputChip(
              label: Text(f.label),
              selected: true,
              showCheckmark: false,
              onPressed: onOpenFilters,
              onDeleted: f.onRemove,
              deleteButtonTooltipMessage: f.removeTooltip,
              materialTapTargetSize: MaterialTapTargetSize.padded,
            )),
        ],
      ),
    );
    final labelledLine = chipsLabel == null
        ? line
        // semantics-children: a group name, read once before the controls inside it
        : Semantics(container: true, label: chipsLabel, child: line);
    final rows = <Widget>[
      if (hasTop)
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (search case final search?) Expanded(child: search),
            if (filtersBesideSearch) _filtersButton(),
            ...trailing,
          ],
        ),
      if (hasLine) labelledLine,
    ];
    if (rows.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpace.sm),
            rows[i],
          ],
        ],
      ),
    );
  }
}

/// Opens the sheet behind [FilterBar]'s Filters button: a title, the filter
/// controls (which may wrap here, unlike the bar's line), and Done pinned
/// below them, with an optional Reset beside it. Built on [SheetScaffold], so
/// Done clears the keyboard and the nav bar.
///
/// [builder] gets a setter that rebuilds the sheet; changes are meant to
/// apply at once, so the list behind it is already right when it closes.
Future<void> showFilterSheet({
  required BuildContext context,
  required String title,
  required String doneLabel,
  required Widget Function(BuildContext context, StateSetter setSheet) builder,
  String? resetLabel,
  VoidCallback? onReset,
}) {
  assert((resetLabel == null) == (onReset == null),
      'resetLabel and onReset must be provided together');
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (sheetContext, setSheet) => SheetScaffold(
        title: Text(title),
        actions: Row(
          children: [
            if (onReset != null)
              TextButton(
                onPressed: () {
                  onReset();
                  setSheet(() {});
                },
                child: Text(resetLabel!),
              ),
            const Spacer(),
            FilledButton(
              key: const Key('filter-sheet-done'),
              onPressed: () => Navigator.of(sheetContext).pop(),
              child: Text(doneLabel),
            ),
          ],
        ),
        body: builder(sheetContext, setSheet),
      ),
    ),
  );
}
